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
#   ap_up                  热点已开返回 0，否则返回 1
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
#   联发科(天玑) ap0 ; 高通(骁龙) wlan1 / softap0 / swlan0 ; 其他 uap0 / ap_br0 等
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 关掉系统的"热点空闲自动关闭"
# 安卓自带一个策略: 热点开着但一段时间(通常 5/10 分钟)没有设备连接就自动关闭。
# 这就是"热点没人连就自己关了，热点检测也救不回来"的根源——检测脚本刚把它打开，
# 系统又把它关掉。soft_ap_timeout_enabled 置 0 即可关掉这个超时。
# (安卓 11+ 该值已迁移到 SoftApConfiguration，能不能生效取决于 ROM，所以两边都试)
# ---------------------------------------------------------------------------
ap_no_timeout() {
  settings put global soft_ap_timeout_enabled 0 2>/dev/null
  cmd wifi set-soft-ap-auto-shutdown disabled 2>/dev/null
  return 0
}
