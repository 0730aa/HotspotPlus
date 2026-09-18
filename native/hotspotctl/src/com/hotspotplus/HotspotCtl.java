package com.hotspotplus;

import java.lang.reflect.Constructor;
import java.lang.reflect.Method;

/**
 * HotspotCtl —— 通过 app_process 以 root 运行，直接经 ServiceManager 拿到系统
 * connectivity 服务的 binder，调用 IConnectivityManager.startTethering / stopTethering
 * 来开关"带网络共享的真热点"。不创建 Context、不走 ActivityThread.systemMain，
 * 以规避 MIUI 等 ROM 在 Resources.getSystem() 阶段的崩溃。
 *
 * 适用: Android 7~10(API 24~29) 的 connectivity.startTethering；部分 11 也可尝试。
 * 用法(由 open_hotspot.sh 调起):
 *   CLASSPATH=hotspotctl.dex app_process /system/bin com.hotspotplus.HotspotCtl on|off
 * 是否真的成功由外层脚本用 ifconfig 查 ap0 判定。
 */
public final class HotspotCtl {

    private static final int TETHERING_WIFI = 0;
    private static final String[] PKG_CANDIDATES = { "com.android.shell", "android", null };

    private static void log(String m) { System.out.println("[hotspotctl] " + m); }

    public static void main(String[] args) {
        String action = (args != null && args.length > 0) ? args[0] : "on";
        int sdk = getSdkInt();
        log("start action=" + action + " sdk=" + sdk);

        boolean ok;
        if ("off".equalsIgnoreCase(action)) {
            ok = connectivityBinder(false);
        } else {
            ok = connectivityBinder(true);
        }
        log("done issued=" + ok + " (最终是否成功以 ap0 检测为准)");
        sleep(600);
        System.exit(ok ? 0 : 1);
    }

    // 直连 connectivity 服务的 binder 调 start/stopTethering
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
            if (m == null) { log("未找到方法 " + name); return false; }
            Class<?>[] pt = m.getParameterTypes();
            log(name + " 签名参数数=" + pt.length + " -> " + typeNames(pt));

            Object rr = on ? newResultReceiver() : null;
            for (int i = 0; i < PKG_CANDIDATES.length; i++) {
                String pkg = PKG_CANDIDATES[i];
                Object[] a = buildArgs(pt, on, rr, pkg);
                if (a == null) { log("  该签名含未知参数类型，跳过"); break; }
                try {
                    m.invoke(icm, a);
                    log(name + " 已发起 (pkg=" + pkg + ")");
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

    // 按参数类型填充: int->TETHERING_WIFI, boolean->false, String->pkg, ResultReceiver->rr
    private static Object[] buildArgs(Class<?>[] pt, boolean on, Object rr, String pkg) {
        Object[] a = new Object[pt.length];
        for (int i = 0; i < pt.length; i++) {
            Class<?> c = pt[i];
            if (c == int.class) a[i] = Integer.valueOf(TETHERING_WIFI);
            else if (c == boolean.class) a[i] = Boolean.FALSE;
            else if (c == String.class) a[i] = pkg;
            else if ("android.os.ResultReceiver".equals(c.getName())) {
                if (rr == null) return null;
                a[i] = rr;
            } else {
                return null; // 未知类型
            }
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

    private static Object getService(String svc) {
        try {
            Class<?> sm = Class.forName("android.os.ServiceManager");
            return sm.getMethod("getService", String.class).invoke(null, svc);
        } catch (Throwable t) {
            log("getService(" + svc + ") 失败: " + rootMsg(t));
            return null;
        }
    }

    private static Method findLongest(Class<?> c, String name) {
        Method best = null;
        Method[] ms = c.getMethods();
        for (int i = 0; i < ms.length; i++) {
            if (ms[i].getName().equals(name)) {
                if (best == null || ms[i].getParameterTypes().length > best.getParameterTypes().length) {
                    best = ms[i];
                }
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
}
