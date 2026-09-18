#!/system/bin/sh
# ============================================================================
# open_hotspot.sh —— 通用开热点入口（分层回退 + ap0 校验 + 重试 + 日志）
#   用法: open_hotspot.sh [on|off]   缺省 on
#   层级:
#     1) app_process 跑 hotspotctl.dex，调系统 tethering API（真热点，最通用）
#     2) cmd wifi start-softap（Android 11+ 本地热点，参数取 config 的 ap_mode2）
#     3) uiautomator 精确点击设置里的热点开关（不依赖分辨率/语言的 UI 兜底）
#   任一层成功（ap0 出现）即停止。
# ============================================================================

MODDIR="/data/adb/modules/HotspotPlus"
JQ="$MODDIR/bin/jq"
DEX="$MODDIR/bin/hotspotctl.dex"
CONFIG_FILE="$MODDIR/config.json"
LOG_FILE="$MODDIR/log/open_hotspot.log"
ACTION="${1:-on}"

mkdir -p "$MODDIR/log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
: > "$LOG_FILE"

ap_up() { ifconfig 2>/dev/null | grep -q "^ap0"; }

# 打开后等待 ap0 出现，最多 wait 秒
wait_ap() {
  w="${1:-6}"
  i=0
  while [ "$i" -lt "$w" ]; do
    if ap_up; then return 0; fi
    sleep 1
    i=$((i + 1))
  done
  ap_up
}

# ---------------- off ----------------
if [ "$ACTION" = "off" ]; then
  log "请求关闭热点"
  if [ -f "$DEX" ]; then
    CLASSPATH="$DEX" app_process /system/bin com.hotspotplus.HotspotCtl off 2>&1 | while read -r l; do log "  dex> $l"; done
  fi
  cmd wifi stop-softap 2>/dev/null
  log "关闭指令已发出"
  exit 0
fi

# ---------------- on ----------------
if ap_up; then
  log "热点已开启(ap0 存在)，无需操作"
  exit 0
fi

# 层 1: dex + app_process 调系统 API
if [ -f "$DEX" ]; then
  log "层1: app_process 调系统 tethering API"
  CLASSPATH="$DEX" app_process /system/bin com.hotspotplus.HotspotCtl on 2>&1 | while read -r l; do log "  dex> $l"; done
  if wait_ap 6; then log "层1 成功: 热点已开(ap0)"; exit 0; fi
  log "层1 未生效，进入层2"
else
  log "层1 跳过: 未找到 $DEX"
fi

# 层 2: cmd wifi start-softap（参数取 ap_mode2）
if command -v cmd >/dev/null 2>&1; then
  AP_SSID=$("$JQ" -r '.ap_mode2.ap_ssid // "Hotspotplus"' "$CONFIG_FILE" 2>/dev/null)
  OPEN=$("$JQ" -r '.ap_mode2.open // false' "$CONFIG_FILE" 2>/dev/null)
  ENC=$("$JQ" -r '.ap_mode2.encryption // "wpa2"' "$CONFIG_FILE" 2>/dev/null)
  PWD_=$("$JQ" -r '.ap_mode2.password // "88888888"' "$CONFIG_FILE" 2>/dev/null)
  BAND=$("$JQ" -r '.ap_mode2.band // 2' "$CONFIG_FILE" 2>/dev/null)
  if [ "$OPEN" = "true" ]; then
    CMD="cmd wifi start-softap $AP_SSID open -b$BAND"
  else
    CMD="cmd wifi start-softap $AP_SSID $ENC $PWD_ -b$BAND"
  fi
  log "层2: $CMD"
  $CMD 2>&1 | while read -r l; do log "  cmd> $l"; done
  if wait_ap 6; then log "层2 成功: 热点已开(ap0)"; exit 0; fi
  log "层2 未生效，进入层3"
else
  log "层2 跳过: 无 cmd"
fi

# 层 3: uiautomator 精确点击设置里的热点开关
log "层3: UI 自动化开热点"
# 唤醒并解锁
SCREEN=$(dumpsys power 2>/dev/null | grep 'mHoldingDisplaySuspendBlocker' | awk -F= '{print $2}')
if [ "$SCREEN" != "true" ]; then
  input keyevent 26; sleep 1
fi
input swipe 300 1500 300 400 300; sleep 2
am start -n com.android.settings/.TetherSettings -f 0x00000400 2>/dev/null; sleep 3

DUMP="$MODDIR/log/ui_dump.xml"
try_tap_switch() {
  uiautomator dump "$DUMP" >/dev/null 2>&1 || return 1
  # 找一个 class 含 Switch 的节点，取其 bounds 中心点击
  line=$(tr '>' '>\n' < "$DUMP" | grep -iE 'class="[^"]*Switch"' | grep -iE 'checkable="true"' | head -1)
  [ -z "$line" ] && line=$(tr '>' '>\n' < "$DUMP" | grep -iE 'class="[^"]*Switch"' | head -1)
  [ -z "$line" ] && return 1
  bounds=$(echo "$line" | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | head -1)
  [ -z "$bounds" ] && return 1
  set -- $(echo "$bounds" | grep -oE '[0-9]+')
  x1=$1; y1=$2; x2=$3; y2=$4
  cx=$(((x1 + x2) / 2)); cy=$(((y1 + y2) / 2))
  log "  层3 点击开关中心: ($cx,$cy) bounds=$bounds"
  input tap "$cx" "$cy"
  return 0
}

for attempt in 1 2 3; do
  log "  层3 第 $attempt 次尝试"
  if ap_up; then break; fi
  if try_tap_switch; then
    if wait_ap 4; then log "层3 成功: 热点已开(ap0)"; input keyevent HOME; exit 0; fi
  else
    log "  层3 未找到开关控件"
  fi
  sleep 2
done

input keyevent HOME
if ap_up; then
  log "热点最终已开启"
  exit 0
else
  log "三层全部尝试后热点仍未开启，请查看日志排查"
  exit 1
fi
