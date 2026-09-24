#!/system/bin/sh
# ============================================================================
# lib.sh —— 模块公共函数，供各脚本 source 使用
#   (由原来的 lib_cfg.sh + lib_ap.sh 合并而来)
#
# 一、读配置
#   cfg <路径> [默认值]    取一个值。取不到就用默认值(键不存在、值为 null、
#                          config.json 写错、jq 不在)，例:
#                            PORT=$(cfg .ftp_setting.port 21)
#                            PASS=$(cfg .ftp_setting.password)   # 不给默认值就是空
#   cfg_raw <jq表达式>     直接跑 jq，数组、筛选这类复杂查询用
#
#   cfg 故意不用 jq 的 // 运算符，因为 jq 把 false 也当成空值:
#     jq '.x // true'   在 x 为 false 时会错误地返回 true
#
# 二、热点
#   ap_up                  热点已开返回 0，否则返回 1。准，判断顺序:
#                            网络共享服务 -> WifiManager(dex) -> 都答不上来才按网卡名猜
#   ap_up_fast             只问网络共享服务(答不上来才猜)，不起 app_process，适合循环里等热点；
#                          结果是"猜"出来的时候不够准，要用 ap_up 再确认
#   ap_sys_info            问系统热点状态和系统设置里保存的热点名称，
#                          结果放在 AP_SYS_STATE(13=已开启) / AP_SYS_SSID
#   ap_no_timeout          关掉系统"无设备连接自动关闭热点"的超时
# ============================================================================

CONFIG_FILE="${CONFIG_FILE:-/data/adb/modules/HotspotPlus/config.json}"
JQ="${JQ:-/data/adb/modules/HotspotPlus/bin/jq}"

cfg() {
  _cfg_v=$("$JQ" -r "if $1 == null then \"\" else $1 | tostring end" "$CONFIG_FILE" 2>/dev/null)
  [ -z "$_cfg_v" ] && _cfg_v="$2"
  printf '%s' "$_cfg_v"
}

cfg_raw() {
  "$JQ" -r "$1" "$CONFIG_FILE"
}

# ---------------------------------------------------------------------------
# 热点接口检测
# 不同芯片/ROM 的热点网卡命名不同:
#   联发科(天玑) ap0 ; 高通(骁龙) wlan1 / wlan2(vivo/iQOO) / softap0 / swlan0 ;
#   其他 uap0 / ap_br0 等
# 名单永远列不全，而且高通机型开了"双 WLAN 加速"时 wlan1 可能是第二个 Wi-Fi
# 连接而不是热点。所以先问系统的网络共享服务，系统答得上来就以它为准，
# 答不上来(老系统/改过的 ROM)才用下面的网卡名单和网关地址猜
# ---------------------------------------------------------------------------
AP_IFACE_RE='^(ap0|wlan1|softap0|swlan0|uap0|ap_br0)'
HOTSPOTCTL_DEX="/data/adb/modules/HotspotPlus/bin/hotspotctl.dex"

# 系统网络共享服务里有没有处于"已共享"的 Wi-Fi 网卡(热点)。
# 返回 0=有  1=没有  2=拿不到(dumpsys 没有 Tether state 段)
# dumpsys 的 Tether state 段形如 "wlan2 - TetheredState - lastError = 0"，
# USB(rndis0/ncm0)、蓝牙(bt-pan) 共享也会出现在这里，所以只认无线网卡，
# 另外排除 WLAN 直连(p2p-*)
_ap_tethered() {
  # 安卓 11 起网络共享是独立的 tethering 服务；10 及以下在 connectivity 里
  if [ "$(getprop ro.build.version.sdk 2>/dev/null)" -ge 30 ] 2>/dev/null; then
    _dump=$(dumpsys tethering 2>/dev/null)
  else
    _dump=$(dumpsys connectivity tethering 2>/dev/null)
  fi
  case "$_dump" in *"Tether state"*) ;; *) return 2 ;; esac
  for _if in $(echo "$_dump" | grep -E ' - (TetheredState|LocalHotspotState)' \
                 | sed 's/^[[:space:]]*//; s/ - .*//'); do
    case "$_if" in p2p*) continue ;; esac
    if [ -e "/sys/class/net/$_if/phy80211" ] || [ -d "/sys/class/net/$_if/wireless" ]; then
      return 0
    fi
    if echo "$_if" | grep -qE '^(wlan|ap|softap|swlan|uap|wifi)'; then
      return 0
    fi
  done
  return 1
}

ap_up_fast() {
  # 问系统网络共享服务，不认网卡名；系统答得上来就以它为准，答不上来才猜
  _ap_tethered
  _r=$?
  [ "$_r" -eq 2 ] || return "$_r"
  _ap_guess
}

# 按网卡名和网关地址猜。系统两种问法都答不上来时才用，
# 高通"双 WLAN 加速"开着时 wlan1 会被误认成热点
_ap_guess() {
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

# 问 WifiManager: 热点状态(10 关闭中/11 已关闭/12 开启中/13 已开启/14 失败)
# 和"系统设置 -> 个人热点"里保存的名称。查不到时两个变量为空
ap_sys_info() {
  AP_SYS_STATE=""
  AP_SYS_SSID=""
  [ -f "$HOTSPOTCTL_DEX" ] || return 1
  _info=$(CLASSPATH="$HOTSPOTCTL_DEX" app_process /system/bin com.hotspotplus.HotspotCtl state 2>/dev/null)
  AP_SYS_STATE=$(echo "$_info" | sed -n 's/^\[hotspotctl\] apState=\([0-9]*\).*/\1/p' | head -1)
  AP_SYS_SSID=$(echo "$_info" | sed -n 's/^\[hotspotctl\] ssid=//p' | head -1)
  [ -n "$AP_SYS_STATE" ]
}

# 准确判断热点是否已开:
#   1) 网络共享服务说有 -> 开着
#   2) 问 WifiManager(要起一次 app_process，约 1 秒)，它答得上来就以它为准。
#      网络共享服务说没有时也要问，防止热点不走网络共享服务的 ROM 被当成没开，
#      接着去重复开热点、切飞行模式、点屏幕
#   3) 两个都答不上来才按网卡名猜
ap_up() {
  _ap_tethered
  _r=$?
  [ "$_r" -eq 0 ] && return 0
  if ap_sys_info; then
    [ "$AP_SYS_STATE" = "13" ]
    return $?
  fi
  [ "$_r" -eq 1 ] && return 1
  _ap_guess
}

# ---------------------------------------------------------------------------
# 关掉系统的"热点空闲自动关闭"
# 安卓自带一个策略: 热点开着但一段时间(通常 5/10 分钟)没有设备连接就自动关闭，
# 这就是"热点没人连就自己关了，热点检测也救不回来"的根源。
#
# 安卓 10 及以下: 该开关存在 Settings.Global.soft_ap_timeout_enabled
# 安卓 11 及以上: 已经挪进 SoftApConfiguration.isAutoShutdownEnabled，
#                 再写 settings 没有任何效果(系统设置里的开关也不会变)，
#                 必须走 hotspotctl.dex 改 SoftAp 配置
#
# 注意: 改的是热点配置，对"下一次开启热点"生效。如果热点当前正开着，
#       要等它重开一次(或手动关一次再开)才会真正不再自动关闭。
# ---------------------------------------------------------------------------
ap_no_timeout() {
  _sdk=$(getprop ro.build.version.sdk 2>/dev/null)
  _dex="$HOTSPOTCTL_DEX"

  if [ "${_sdk:-0}" -ge 30 ] 2>/dev/null && [ -f "$_dex" ]; then
    CLASSPATH="$_dex" app_process /system/bin com.hotspotplus.HotspotCtl noautooff 2>&1
    return $?
  fi

  # 安卓 10 及以下走老设置项
  settings put global soft_ap_timeout_enabled 0 2>/dev/null
  return 0
}
