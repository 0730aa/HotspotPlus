#!/system/bin/sh
# ============================================================================
# lib_cfg.sh —— 读取 config.json 的小工具，供各脚本 source 使用
#
#   cfg <路径> [默认值]    取一个值。取不到就用默认值(键不存在、值为 null、
#                          config.json 写错、jq 不在)，例:
#                            PORT=$(cfg .ftp_setting.port 21)
#                            DIR=$(cfg .ftp_setting.dir /sdcard)
#                            PASS=$(cfg .ftp_setting.password)        # 不给默认值就是空
#
#   cfg_raw <jq表达式>     直接跑 jq，数组、筛选这类复杂查询用，例:
#                            cfg_raw '.cron_jobs[] | select(.enabled == true) | .command'
#
# cfg 故意不用 jq 的 // 运算符，因为 jq 把 false 也当成空值:
#   jq '.x // true'   在 x 为 false 时会错误地返回 true
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
