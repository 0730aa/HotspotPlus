package com.hotspotplus;

import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;

/**
 * HotspotCtl —— 通过 app_process 以 root 运行，调用系统自身的
 * tethering / softap API 来开关"带网络共享的真热点"，尽量做到跨版本通用。
 *
 * 用法(由 open_hotspot.sh 调起):
 *   app_process -Djava.class.path=hotspotctl.dex /system/bin com.hotspotplus.HotspotCtl on
 *   app_process -Djava.class.path=hotspotctl.dex /system/bin com.hotspotplus.HotspotCtl off
 *
 * 说明:
 *  - "on" 打开的是用户在系统设置里已配置好的热点(SSID/密码/加密沿用系统设置)，
 *    这是系统"个人热点"开关走的同一条路，兼容性最好。
 *  - 真正是否成功由外层脚本用 ifconfig 查 ap0 判定；本程序只负责发起调用并打日志。
 */
public final class HotspotCtl {

    private static final int TETHERING_WIFI = 0;

    private static void log(String msg) {
        System.out.println("[hotspotctl] " + msg);
    }

    public static void main(String[] args) {
        String action = (args != null && args.length > 0) ? args[0] : "on";
        log("start action=" + action + " sdk=" + getSdkInt());

        Object ctx = getSystemContext();
        if (ctx == null) {
            log("FATAL 无法获取 system context，退出");
            System.exit(2);
            return;
        }
        ensureLooper();

        boolean issued;
        if ("off".equalsIgnoreCase(action)) {
            issued = stopTethering(ctx);
        } else {
            issued = startTethering(ctx);
        }
        log("done issued=" + issued + " (最终是否成功以 ap0 检测为准)");
        // 给异步回调一点点时间打印，但不阻塞太久
        sleep(800);
        System.exit(issued ? 0 : 1);
    }

    // ---------------------------------------------------------------
    // 打开热点：按 API 从新到旧依次尝试
    // ---------------------------------------------------------------
    private static boolean startTethering(Object ctx) {
        boolean ok = false;
        // 1) Android 11+ : TetheringManager.startTethering(request, executor, callback)
        if (tryTetheringManagerStart(ctx)) ok = true;
        // 2) Android 7~10 : ConnectivityManager.startTethering(type, showUi, callback)
        if (!ok && tryConnectivityManagerStart(ctx)) ok = true;
        // 3) 老机型兜底 : WifiManager.setWifiApEnabled(null, true)
        if (!ok && tryLegacyWifiApEnable(ctx, true)) ok = true;
        return ok;
    }

    private static boolean stopTethering(Object ctx) {
        boolean ok = false;
        if (tryTetheringManagerStop(ctx)) ok = true;
        if (!ok && tryConnectivityManagerStop(ctx)) ok = true;
        if (!ok && tryLegacyWifiApEnable(ctx, false)) ok = true;
        return ok;
    }

    // ---- 1) TetheringManager (API 30+) ----
    private static boolean tryTetheringManagerStart(Object ctx) {
        try {
            Object tm = getSystemService(ctx, "tethering");
            if (tm == null) { log("TetheringManager: 服务为 null，跳过"); return false; }

            Class<?> reqCls = Class.forName("android.net.TetheringManager$TetheringRequest");
            Class<?> builderCls = Class.forName("android.net.TetheringManager$TetheringRequest$Builder");
            Constructor<?> bctor = builderCls.getConstructor(int.class);
            Object builder = bctor.newInstance(TETHERING_WIFI);
            Object request = builderCls.getMethod("build").invoke(builder);

            Class<?> cbCls = Class.forName("android.net.TetheringManager$StartTetheringCallback");
            Object cb = Proxy.newProxyInstance(cbCls.getClassLoader(),
                    new Class[]{cbCls}, new CbHandler("TetheringManager"));

            java.util.concurrent.Executor exec = new java.util.concurrent.Executor() {
                public void execute(Runnable r) { r.run(); }
            };

            Method start = tm.getClass().getMethod("startTethering",
                    reqCls, java.util.concurrent.Executor.class, cbCls);
            start.invoke(tm, request, exec, cb);
            log("TetheringManager.startTethering 已发起");
            return true;
        } catch (Throwable t) {
            log("TetheringManager 失败: " + t);
            return false;
        }
    }

    private static boolean tryTetheringManagerStop(Object ctx) {
        try {
            Object tm = getSystemService(ctx, "tethering");
            if (tm == null) return false;
            Method stop = tm.getClass().getMethod("stopTethering", int.class);
            stop.invoke(tm, TETHERING_WIFI);
            log("TetheringManager.stopTethering 已发起");
            return true;
        } catch (Throwable t) {
            log("TetheringManager.stop 失败: " + t);
            return false;
        }
    }

    // ---- 2) ConnectivityManager (API 24~29) ----
    private static boolean tryConnectivityManagerStart(Object ctx) {
        try {
            Object cm = getSystemService(ctx, "connectivity");
            if (cm == null) { log("ConnectivityManager: 服务为 null，跳过"); return false; }
            Class<?> cbCls = Class.forName("android.net.ConnectivityManager$OnStartTetheringCallback");
            Object cb = new StartCb();
            Method start = cm.getClass().getMethod("startTethering", int.class, boolean.class, cbCls);
            start.invoke(cm, TETHERING_WIFI, false, cb);
            log("ConnectivityManager.startTethering 已发起");
            return true;
        } catch (Throwable t) {
            log("ConnectivityManager 失败: " + t);
            return false;
        }
    }

    private static boolean tryConnectivityManagerStop(Object ctx) {
        try {
            Object cm = getSystemService(ctx, "connectivity");
            if (cm == null) return false;
            Method stop = cm.getClass().getMethod("stopTethering", int.class);
            stop.invoke(cm, TETHERING_WIFI);
            log("ConnectivityManager.stopTethering 已发起");
            return true;
        } catch (Throwable t) {
            log("ConnectivityManager.stop 失败: " + t);
            return false;
        }
    }

    // ---- 3) 老机型 WifiManager.setWifiApEnabled (API <= 25) ----
    private static boolean tryLegacyWifiApEnable(Object ctx, boolean enable) {
        try {
            Object wm = getSystemService(ctx, "wifi");
            if (wm == null) return false;
            Class<?> wcCls = Class.forName("android.net.wifi.WifiConfiguration");
            Method m = wm.getClass().getMethod("setWifiApEnabled", wcCls, boolean.class);
            Object ret = m.invoke(wm, null, enable);
            log("WifiManager.setWifiApEnabled(" + enable + ") 返回 " + ret);
            return Boolean.TRUE.equals(ret);
        } catch (Throwable t) {
            log("Legacy setWifiApEnabled 失败: " + t);
            return false;
        }
    }

    // ---------------------------------------------------------------
    // 反射工具
    // ---------------------------------------------------------------
    private static Object getSystemContext() {
        try {
            Class<?> at = Class.forName("android.app.ActivityThread");
            Object thread = at.getMethod("systemMain").invoke(null);
            Object ctx = at.getMethod("getSystemContext").invoke(thread);
            log("获取 system context: " + (ctx != null));
            return ctx;
        } catch (Throwable t) {
            log("getSystemContext 失败: " + t);
            return null;
        }
    }

    private static Object getSystemService(Object ctx, String name) {
        try {
            Method m = ctx.getClass().getMethod("getSystemService", String.class);
            return m.invoke(ctx, name);
        } catch (Throwable t) {
            log("getSystemService(" + name + ") 失败: " + t);
            return null;
        }
    }

    private static void ensureLooper() {
        try {
            Class<?> looper = Class.forName("android.os.Looper");
            Object cur = looper.getMethod("myLooper").invoke(null);
            if (cur == null) {
                try { looper.getMethod("prepareMainLooper").invoke(null); }
                catch (Throwable e) { looper.getMethod("prepare").invoke(null); }
                log("已准备 Looper");
            }
        } catch (Throwable t) {
            log("ensureLooper 忽略: " + t);
        }
    }

    private static int getSdkInt() {
        try {
            Class<?> b = Class.forName("android.os.Build$VERSION");
            return b.getField("SDK_INT").getInt(null);
        } catch (Throwable t) { return -1; }
    }

    private static void sleep(long ms) {
        try { Thread.sleep(ms); } catch (InterruptedException ignored) {}
    }

    // TetheringManager.StartTetheringCallback 是接口 -> 用 Proxy 实现
    private static final class CbHandler implements InvocationHandler {
        private final String tag;
        CbHandler(String tag) { this.tag = tag; }
        public Object invoke(Object proxy, Method method, Object[] args) {
            log(tag + " 回调: " + method.getName()
                    + (args != null && args.length > 0 ? (" arg=" + args[0]) : ""));
            Class<?> rt = method.getReturnType();
            if (rt == boolean.class) return Boolean.FALSE;
            if (rt == int.class) return 0;
            return null;
        }
    }

    // ConnectivityManager.OnStartTetheringCallback 是抽象类 -> 编译期用桩子类
    private static final class StartCb extends android.net.ConnectivityManager.OnStartTetheringCallback {
        public void onTetheringStarted() { log("ConnectivityManager 回调: onTetheringStarted"); }
        public void onTetheringFailed() { log("ConnectivityManager 回调: onTetheringFailed"); }
    }
}
