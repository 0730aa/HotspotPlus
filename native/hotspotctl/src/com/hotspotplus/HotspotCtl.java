package com.hotspotplus;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

/**
 * HotspotCtl —— 经 ServiceManager 直连系统服务的 binder，开关"带网络共享的真热点"，
 * 不创建 Context / 不走 ActivityThread.systemMain（规避 MIUI 等 ROM 的 Resources 崩溃）。
 *
 *   Android 11+ (API 30+): tethering 服务 ITetheringConnector.startTethering(TetheringRequestParcel,...)
 *   Android 7~10 (API 24~29): connectivity 服务 IConnectivityManager.startTethering(...)
 *
 * 用法: CLASSPATH=hotspotctl.dex app_process /system/bin com.hotspotplus.HotspotCtl on|off
 * 是否真的成功由外层脚本用接口检测(ap_up)判定。
 */
public final class HotspotCtl {

    private static final int TETHERING_WIFI = 0;
    private static final String[] PKG_CANDIDATES = { "com.android.shell", "android", null };

    private static void log(String m) { System.out.println("[hotspotctl] " + m); }

    public static void main(String[] args) {
        String action = (args != null && args.length > 0) ? args[0] : "on";
        int sdk = getSdkInt();
        log("start action=" + action + " sdk=" + sdk);
        boolean on = !"off".equalsIgnoreCase(action);

        boolean ok = false;
        // Android 11+ 优先走 tethering 服务
        if (sdk >= 30) {
            ok = tetheringConnectorBinder(on);
            if (!ok) log("tethering 服务路径未成功，回退尝试 connectivity 服务");
        }
        // Android 7~10（以及 11+ 的回退）
        if (!ok) ok = connectivityBinder(on);

        log("done issued=" + ok + " (最终是否成功以接口检测为准)");
        sleep(600);
        System.exit(ok ? 0 : 1);
    }

    // ========================= Android 11+ : ITetheringConnector =========================
    private static boolean tetheringConnectorBinder(boolean on) {
        try {
            Object binder = getService("tethering");
            if (binder == null) { log("tethering 服务 binder=null"); return false; }
            Class<?> ibinder = Class.forName("android.os.IBinder");
            Class<?> stub = Class.forName("android.net.ITetheringConnector$Stub");
            Object conn = stub.getMethod("asInterface", ibinder).invoke(null, binder);
            Class<?> connCls = Class.forName("android.net.ITetheringConnector");

            Object request = on ? buildTetheringRequest() : null;
            Object listener = newIntResultListener();

            String name = on ? "startTethering" : "stopTethering";
            Method m = findLongest(connCls, name);
            if (m == null) { log("ITetheringConnector 未找到 " + name); return false; }
            Class<?>[] pt = m.getParameterTypes();
            log("ITetheringConnector." + name + " 签名 " + typeNames(pt));

            for (int i = 0; i < PKG_CANDIDATES.length; i++) {
                String pkg = PKG_CANDIDATES[i];
                Object[] a = buildTetheringArgs(pt, on, request, listener, pkg);
                if (a == null) { log("  该签名含未知参数类型，放弃 tethering 路径"); return false; }
                try {
                    m.invoke(conn, a);
                    log("ITetheringConnector." + name + " 已发起 (pkg=" + pkg + ")");
                    return true;
                } catch (Throwable t) {
                    log("  " + name + "(pkg=" + pkg + ") 失败: " + rootMsg(t));
                }
            }
            return false;
        } catch (Throwable t) {
            log("tethering binder 路径异常: " + rootMsg(t));
            return false;
        }
    }

    private static Object buildTetheringRequest() {
        try {
            Class<?> reqCls = Class.forName("android.net.TetheringRequestParcel");
            Object req = reqCls.getConstructor().newInstance();
            setInt(req, "tetheringType", TETHERING_WIFI);
            setBool(req, "showProvisioningUi", false);
            setBool(req, "exemptFromEntitlementCheck", false);
            // localIPv4Address / staticClientAddress 保持 null，沿用系统默认配置
            log("TetheringRequestParcel 构造完成");
            return req;
        } catch (Throwable t) {
            log("构造 TetheringRequestParcel 失败: " + rootMsg(t));
            return null;
        }
    }

    private static Object newIntResultListener() {
        try { return new IntResultListener(); }
        catch (Throwable t) { log("构造 IIntResultListener 失败: " + rootMsg(t)); return null; }
    }

    // 参数按类型填充：TetheringRequestParcel->request, IIntResultListener->listener,
    //                String->callerPkg/attributionTag, int->WIFI, boolean->false
    private static Object[] buildTetheringArgs(Class<?>[] pt, boolean on, Object req, Object listener, String pkg) {
        Object[] a = new Object[pt.length];
        for (int i = 0; i < pt.length; i++) {
            String n = pt[i].getName();
            if (pt[i] == int.class) a[i] = Integer.valueOf(TETHERING_WIFI);
            else if (pt[i] == boolean.class) a[i] = Boolean.FALSE;
            else if (pt[i] == String.class) a[i] = pkg;
            else if ("android.net.TetheringRequestParcel".equals(n)) { if (req == null) return null; a[i] = req; }
            else if ("android.net.IIntResultListener".equals(n)) a[i] = listener; // 允许 null
            else return null;
        }
        return a;
    }

    // ========================= Android 7~10 : IConnectivityManager =========================
    private static boolean connectivityBinder(boolean on) {
        try {
            Object binder = getService("connectivity");
            if (binder == null) { log("connectivity 服务 binder=null"); return false; }
            Class<?> ibinder = Class.forName("android.os.IBinder");
            Class<?> stub = Class.forName("android.net.IConnectivityManager$Stub");
            Object icm = stub.getMethod("asInterface", ibinder).invoke(null, binder);
            Class<?> icmCls = Class.forName("android.net.IConnectivityManager");

            String name = on ? "startTethering" : "stopTethering";
            Method m = findLongest(icmCls, name);
            if (m == null) { log("IConnectivityManager 未找到 " + name); return false; }
            Class<?>[] pt = m.getParameterTypes();
            log("IConnectivityManager." + name + " 签名 " + typeNames(pt));

            Object rr = on ? newResultReceiver() : null;
            for (int i = 0; i < PKG_CANDIDATES.length; i++) {
                String pkg = PKG_CANDIDATES[i];
                Object[] a = buildConnArgs(pt, rr, pkg);
                if (a == null) { log("  该签名含未知参数类型，放弃 connectivity 路径"); return false; }
                try {
                    m.invoke(icm, a);
                    log("IConnectivityManager." + name + " 已发起 (pkg=" + pkg + ")");
                    return true;
                } catch (Throwable t) {
                    log("  " + name + "(pkg=" + pkg + ") 失败: " + rootMsg(t));
                }
            }
            return false;
        } catch (Throwable t) {
            log("connectivity binder 路径异常: " + rootMsg(t));
            return false;
        }
    }

    private static Object[] buildConnArgs(Class<?>[] pt, Object rr, String pkg) {
        Object[] a = new Object[pt.length];
        for (int i = 0; i < pt.length; i++) {
            Class<?> c = pt[i];
            if (c == int.class) a[i] = Integer.valueOf(TETHERING_WIFI);
            else if (c == boolean.class) a[i] = Boolean.FALSE;
            else if (c == String.class) a[i] = pkg;
            else if ("android.os.ResultReceiver".equals(c.getName())) { if (rr == null) return null; a[i] = rr; }
            else return null;
        }
        return a;
    }

    private static Object newResultReceiver() {
        try {
            Class<?> rrCls = Class.forName("android.os.ResultReceiver");
            Class<?> handler = Class.forName("android.os.Handler");
            Constructor<?> ctor = rrCls.getConstructor(handler);
            return ctor.newInstance(new Object[]{ null });
        } catch (Throwable t) {
            log("构造 ResultReceiver 失败: " + rootMsg(t));
            return null;
        }
    }

    // ========================= 反射/工具 =========================
    private static Object getService(String svc) {
        try {
            Class<?> sm = Class.forName("android.os.ServiceManager");
            return sm.getMethod("getService", String.class).invoke(null, svc);
        } catch (Throwable t) { log("getService(" + svc + ") 失败: " + rootMsg(t)); return null; }
    }

    private static void setInt(Object o, String f, int v) {
        try { Field fd = o.getClass().getField(f); fd.setInt(o, v); } catch (Throwable ignored) {}
    }
    private static void setBool(Object o, String f, boolean v) {
        try { Field fd = o.getClass().getField(f); fd.setBoolean(o, v); } catch (Throwable ignored) {}
    }

    private static Method findLongest(Class<?> c, String name) {
        Method best = null;
        Method[] ms = c.getMethods();
        for (int i = 0; i < ms.length; i++) {
            if (ms[i].getName().equals(name)) {
                if (best == null || ms[i].getParameterTypes().length > best.getParameterTypes().length) best = ms[i];
            }
        }
        return best;
    }

    private static String typeNames(Class<?>[] pt) {
        StringBuilder sb = new StringBuilder("(");
        for (int i = 0; i < pt.length; i++) { if (i > 0) sb.append(","); sb.append(pt[i].getSimpleName()); }
        return sb.append(")").toString();
    }

    private static int getSdkInt() {
        try { return Class.forName("android.os.Build$VERSION").getField("SDK_INT").getInt(null); }
        catch (Throwable t) { return -1; }
    }
    private static void sleep(long ms) { try { Thread.sleep(ms); } catch (InterruptedException ignored) {} }
    private static String rootMsg(Throwable t) {
        Throwable c = t;
        while (c.getCause() != null && c.getCause() != c) c = c.getCause();
        return c.toString();
    }

    // IIntResultListener.Stub 子类（编译期用桩，运行时为真实 framework 类）
    static final class IntResultListener extends android.net.IIntResultListener.Stub {
        public void onResult(int resultCode) { log("ITetheringConnector 回调 onResult=" + resultCode); }
    }
}
