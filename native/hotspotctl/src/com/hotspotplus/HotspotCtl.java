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
 * 用法: CLASSPATH=hotspotctl.dex app_process /system/bin com.hotspotplus.HotspotCtl on|off|noautooff|state
 * 是否真的成功由外层脚本用接口检测(ap_up)判定。
 *
 *   state: 问 WifiManager 当前热点状态和系统设置里保存的热点名称，输出
 *            [hotspotctl] apState=13
 *            [hotspotctl] ssid=<名称>
 *          退出码 0=热点已开启 1=未开启 2=查不到
 */
public final class HotspotCtl {

    private static final int TETHERING_WIFI = 0;
    private static final int WIFI_AP_STATE_ENABLED = 13;
    private static final String[] PKG_CANDIDATES = { "com.android.shell", "android", null };

    private static void log(String m) { System.out.println("[hotspotctl] " + m); }

    public static void main(String[] args) {
        String action = (args != null && args.length > 0) ? args[0] : "on";
        int sdk = getSdkInt();
        log("start action=" + action + " sdk=" + sdk);

        // 关掉"热点空闲无设备连接自动关闭"，不开关热点
        if ("noautooff".equalsIgnoreCase(action)) {
            boolean done = disableApAutoShutdown();
            log("noautooff done=" + done);
            sleep(300);
            System.exit(done ? 0 : 1);
        }

        // 查询热点状态 + 系统保存的热点名称，不开关热点
        if ("state".equalsIgnoreCase(action)) {
            int st = printApState();
            System.exit(st == WIFI_AP_STATE_ENABLED ? 0 : (st < 0 ? 2 : 1));
        }

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

    // ============== 关闭"热点空闲自动关闭" (Android 11+ 的正确做法) ==============
    // 安卓 11 起这个开关已经从 Settings.Global.soft_ap_timeout_enabled 挪进了
    // SoftApConfiguration，再写 settings 不会有任何效果(系统设置里的开关也纹丝不动)，
    // 必须 getSoftApConfiguration -> Builder.setAutoShutdownEnabled(false) -> setSoftApConfiguration
    private static boolean disableApAutoShutdown() {
        try {
            Object wifi = getWifiManager();
            if (wifi == null) return false;
            Class<?> wifiCls = Class.forName("android.net.wifi.IWifiManager");

            Object cfg = getSoftApConfig(wifi, wifiCls);
            if (cfg == null) { log("拿不到 SoftApConfiguration(可能是 Android 10 及以下)"); return false; }
            log("当前 autoShutdownEnabled=" + readAutoShutdown(cfg));

            Class<?> sacCls = Class.forName("android.net.wifi.SoftApConfiguration");
            Class<?> bCls = Class.forName("android.net.wifi.SoftApConfiguration$Builder");
            Object b = bCls.getConstructor(sacCls).newInstance(cfg);
            Method setAuto;
            try {
                setAuto = bCls.getMethod("setAutoShutdownEnabled", boolean.class);
            } catch (Throwable t) {
                log("SoftApConfiguration.Builder 没有 setAutoShutdownEnabled: " + rootMsg(t));
                return false;
            }
            setAuto.invoke(b, Boolean.FALSE);
            Object ncfg = bCls.getMethod("build").invoke(b);

            Method set = findLongest(wifiCls, "setSoftApConfiguration");
            if (set == null) { log("IWifiManager 没有 setSoftApConfiguration"); return false; }
            Class<?>[] pt = set.getParameterTypes();
            log("IWifiManager.setSoftApConfiguration 签名 " + typeNames(pt));

            for (int i = 0; i < PKG_CANDIDATES.length; i++) {
                Object[] a = new Object[pt.length];
                boolean known = true;
                for (int j = 0; j < pt.length; j++) {
                    if (pt[j].isAssignableFrom(sacCls)) a[j] = ncfg;
                    else if (pt[j] == String.class) a[j] = PKG_CANDIDATES[i];
                    else if (pt[j] == boolean.class) a[j] = Boolean.FALSE;
                    else if (pt[j] == int.class) a[j] = Integer.valueOf(0);
                    else { known = false; break; }
                }
                if (!known) { log("  setSoftApConfiguration 含未知参数类型，放弃"); return false; }
                try {
                    Object r = set.invoke(wifi, a);
                    log("  setSoftApConfiguration(pkg=" + PKG_CANDIDATES[i] + ") 返回 " + r);
                    if (r instanceof Boolean && !((Boolean) r).booleanValue()) continue;
                    // 回读确认，真正生效才算成功
                    Object back = getSoftApConfig(wifi, wifiCls);
                    Boolean now = (back == null) ? null : readAutoShutdown(back);
                    log("  回读 autoShutdownEnabled=" + now);
                    if (now != null && !now.booleanValue()) return true;
                } catch (Throwable t) {
                    log("  setSoftApConfiguration(pkg=" + PKG_CANDIDATES[i] + ") 失败: " + rootMsg(t));
                }
            }
            return false;
        } catch (Throwable t) {
            log("关闭热点自动关闭异常: " + rootMsg(t));
            return false;
        }
    }

    private static Object getSoftApConfig(Object wifi, Class<?> wifiCls) {
        return callSimple(wifi, findShortest(wifiCls, "getSoftApConfiguration"));
    }

    private static Boolean readAutoShutdown(Object cfg) {
        try {
            return (Boolean) cfg.getClass().getMethod("isAutoShutdownEnabled").invoke(cfg);
        } catch (Throwable t) { return null; }
    }

    // ============== 查询热点状态 + 系统设置里保存的热点名称 ==============
    // apState: 10 关闭中 / 11 已关闭 / 12 开启中 / 13 已开启 / 14 失败，查不到返回 -1。
    // 名称取的是"系统设置 -> 个人热点"里保存的配置(api 方式开的就是这个)，
    // 不是 cmd wifi start-softap 临时指定的名称
    private static int printApState() {
        int st = -1;
        try {
            Object wifi = getWifiManager();
            if (wifi == null) return -1;
            Class<?> wifiCls = Class.forName("android.net.wifi.IWifiManager");

            Object r = callSimple(wifi, findShortest(wifiCls, "getWifiApEnabledState"));
            if (r instanceof Integer) st = ((Integer) r).intValue();
            log("apState=" + st);

            String ssid = null;
            // Android 11+: SoftApConfiguration；Android 10 及以下: WifiConfiguration.SSID
            Object cfg = getSoftApConfig(wifi, wifiCls);
            if (cfg != null) {
                ssid = (String) callNoArg(cfg, "getSsid");
                if (ssid == null) {
                    Object ws = callNoArg(cfg, "getWifiSsid");
                    if (ws != null) ssid = ws.toString();
                }
            } else {
                Object wc = callSimple(wifi, findShortest(wifiCls, "getWifiApConfiguration"));
                if (wc != null) {
                    try { ssid = (String) wc.getClass().getField("SSID").get(wc); } catch (Throwable ignored) {}
                }
            }
            if (ssid != null) log("ssid=" + ssid);
        } catch (Throwable t) {
            log("查询热点状态异常: " + rootMsg(t));
        }
        return st;
    }

    // ========================= 反射/工具 =========================
    private static Object getWifiManager() {
        try {
            Object binder = getService("wifi");
            if (binder == null) { log("wifi 服务 binder=null"); return null; }
            Class<?> ibinder = Class.forName("android.os.IBinder");
            Class<?> stub = Class.forName("android.net.wifi.IWifiManager$Stub");
            return stub.getMethod("asInterface", ibinder).invoke(null, binder);
        } catch (Throwable t) {
            log("拿 IWifiManager 失败: " + rootMsg(t));
            return null;
        }
    }

    // 调只有 String(包名)/boolean/int 参数的 binder 方法，逐个候选包名重试，返回第一个非 null 结果
    private static Object callSimple(Object target, Method m) {
        if (m == null) return null;
        Class<?>[] pt = m.getParameterTypes();
        for (int i = 0; i < PKG_CANDIDATES.length; i++) {
            Object[] a = new Object[pt.length];
            for (int j = 0; j < pt.length; j++) {
                if (pt[j] == String.class) a[j] = PKG_CANDIDATES[i];
                else if (pt[j] == boolean.class) a[j] = Boolean.FALSE;
                else if (pt[j] == int.class) a[j] = Integer.valueOf(0);
                else return null;
            }
            try {
                Object r = m.invoke(target, a);
                if (r != null) return r;
            } catch (Throwable t) {
                log("  " + m.getName() + "(pkg=" + PKG_CANDIDATES[i] + ") 失败: " + rootMsg(t));
            }
            if (pt.length == 0) break;
        }
        return null;
    }

    private static Object callNoArg(Object o, String name) {
        try { return o.getClass().getMethod(name).invoke(o); } catch (Throwable t) { return null; }
    }

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

    private static Method findShortest(Class<?> c, String name) {
        Method best = null;
        Method[] ms = c.getMethods();
        for (int i = 0; i < ms.length; i++) {
            if (ms[i].getName().equals(name)) {
                if (best == null || ms[i].getParameterTypes().length < best.getParameterTypes().length) best = ms[i];
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
