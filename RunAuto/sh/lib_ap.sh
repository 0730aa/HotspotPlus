#!/system/bin/sh
# ============================================================================
# lib_ap.sh —— 通用 softap(热点) 接口检测，供各脚本 source 使用。
# 不同芯片/ROM 的热点网卡命名不同：
#   联发科(天玑) ap0 ；高通(骁龙) wlan1 / softap0 / swlan0 ；其他 uap0 / ap_br0 等
# 判定 ap_up(): 热点已开返回 0，否则返回 1。
# ============================================================================

# 已知 softap 接口名（词首匹配，兼容 ap0 / wlan1 / wlan1_1 等）
AP_IFACE_RE='^(ap0|wlan1|softap0|swlan0|uap0|ap_br0)'

ap_up() {
  # 1) busybox/toybox ifconfig 默认只列 UP 接口：命中已知名即认为热点开启
  if ifconfig 2>/dev/null | grep -qE "$AP_IFACE_RE"; then
    return 0
  fi
  # 2) ip 兜底：UP 的接口名命中已知名
  if command -v ip >/dev/null 2>&1; then
    if ip -o link show up 2>/dev/null | sed 's/^[0-9]*: //' | grep -qE "$AP_IFACE_RE"; then
      return 0
    fi
    # 3) 网关地址法（适配未知命名）：某个非 STA(wlan0) 接口拿到 192.168.x.1 网关
    #    (热点网关通常是 .1；USB 共享是 192.168.42.129，不会误判)
    if ip -o -4 addr show 2>/dev/null \
         | grep -vE '\b(wlan0|lo|rmnet[0-9]*|dummy[0-9]*|eth0|clat[0-9]*)\b' \
         | grep -qE 'inet 192\.168\.[0-9]+\.1/'; then
      return 0
    fi
  fi
  return 1
}
