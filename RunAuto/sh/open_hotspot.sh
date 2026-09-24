#!/system/bin/sh
# ============================================================================
# open_hotspot.sh —— 通用开热点入口（分层回退 + 热点校验 + 重试 + 日志）
#   用法: open_hotspot.sh [on|off]   缺省 on
#   层级:
#     1) app_process 跑 hotspotctl.dex，调系统 tethering API（真热点，最通用）
#        热点名称/密码 = 系统设置 -> 个人热点 里保存的
#     2) cmd wifi start-softap（Android 11+ 本地热点，名称/密码取 config 的 ap_mode2）
#     3) uiautomator 找到设置里的热点开关再点（只点关着的热点开关，找不到就不点）
#   任一层成功（ap_up 认出热点）即停止。每进下一层前都先问一次系统，
#   热点其实已经开了就不再往下走(否则层2 会和已开的热点冲突、层3 会去点屏幕)
# ============================================================================

MODDIR="/data/adb/modules/HotspotPlus"
DEX="$MODDIR/bin/hotspotctl.dex"
CONFIG_FILE="$MODDIR/config.json"
LOG_FILE="$MODDIR/log/open_hotspot.log"
ACTION="${1:-on}"

mkdir -p "$MODDIR/log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
: > "$LOG_FILE"

# 公共函数: cfg 读配置 / ap_up 检测热点 / ap_sys_info 问系统 / ap_no_timeout 关闭空闲超时
. "$MODDIR/RunAuto/sh/lib.sh"

# 打开后等待热点起来，最多 wait 秒。循环里只做快速检测，快速检测说开了再用 ap_up 确认
# (快速检测在系统答不上来时是按网卡名猜的)；最后再问一次系统，顺带更新 AP_SYS_STATE
wait_ap() {
  w="${1:-6}"
  i=0
  while [ "$i" -lt "$w" ]; do
    if ap_up_fast && ap_up; then return 0; fi
    sleep 1
    i=$((i + 1))
  done
  ap_up
}

# 记下热点名称，方便确认连的是哪套名称/密码
#   log_ssid cfg   层2 开的，用的是 config.json 的 ap_mode2
#   log_ssid       其余情况，用的是系统设置里保存的
log_ssid() {
  if [ "$1" = "cfg" ]; then
    log "热点名称: $AP_SSID (config.json 里 ap_mode2 的名称/密码)"
    return
  fi
  # 系统保存的名称脚本运行期间不会变，前面问过就不再起一次 app_process
  [ -n "$AP_SYS_SSID" ] || ap_sys_info
  if [ -n "$AP_SYS_SSID" ]; then
    log "热点名称: $AP_SYS_SSID (系统设置 -> 个人热点 里的名称/密码)"
  fi
}

# 层1/层2 没认出热点时，再看系统是不是还在"开启中"，是就多等一会。
# 返回 0 表示热点其实已经开了
ap_settled() {
  [ "$AP_SYS_STATE" = "12" ] || return 1
  log "系统报告热点正在开启中，再等 10 秒"
  wait_ap 10
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
# 先关掉系统的"空闲无设备连接自动关闭热点"。
# 放在"热点已开就退出"之前，是因为热点已经开着时同样需要改掉这个配置，
# 否则它还是会在没人连的时候把热点关掉
if [ "$(cfg .ap_keep_alive true)" = "true" ]; then
  log "关闭系统的热点空闲自动关闭:"
  ap_no_timeout 2>&1 | while read -r l; do log "  $l"; done
fi

if ap_up; then
  log "热点已开启，无需操作"
  [ -n "$AP_SYS_SSID" ] || ap_sys_info
  [ -n "$AP_SYS_SSID" ] && log "系统设置里保存的热点名称: $AP_SYS_SSID (如果热点是本模块层2 开的，则是 ap_mode2 里的名称)"
  exit 0
fi

# 层 1: dex + app_process 调系统 API
if [ -f "$DEX" ]; then
  log "层1: app_process 调系统 tethering API"
  CLASSPATH="$DEX" app_process /system/bin com.hotspotplus.HotspotCtl on 2>&1 | while read -r l; do log "  dex> $l"; done
  if wait_ap 10 || ap_settled; then log "层1 成功: 热点已开"; log_ssid; exit 0; fi
  log "层1 未生效(系统热点状态=${AP_SYS_STATE:-未知})，进入层2"
else
  log "层1 跳过: 未找到 $DEX"
fi

# 层 2: cmd wifi start-softap（Android 11+ 才有该命令；≤10 直接跳过）
SDK=$(getprop ro.build.version.sdk 2>/dev/null)
if command -v cmd >/dev/null 2>&1 && [ "${SDK:-0}" -ge 30 ] 2>/dev/null; then
  AP_SSID=$(cfg .ap_mode2.ap_ssid Hotspotplus)
  OPEN=$(cfg .ap_mode2.open false)
  ENC=$(cfg .ap_mode2.encryption wpa2)
  PWD_=$(cfg .ap_mode2.password 88888888)
  BAND=$(cfg .ap_mode2.band 2)
  # 参数逐个加引号传，热点名称里有空格也不会被拆开；日志里不写明文密码
  if [ "$OPEN" = "true" ]; then
    set -- open
    log "层2: cmd wifi start-softap \"$AP_SSID\" open -b$BAND"
  else
    set -- "$ENC" "$PWD_"
    log "层2: cmd wifi start-softap \"$AP_SSID\" $ENC ******** -b$BAND"
  fi
  cmd wifi start-softap "$AP_SSID" "$@" "-b$BAND" 2>&1 | while read -r l; do log "  cmd> $l"; done
  if wait_ap 6 || ap_settled; then log "层2 成功: 热点已开"; log_ssid cfg; exit 0; fi
  log "层2 未生效(系统热点状态=${AP_SYS_STATE:-未知})，进入层3"
else
  log "层2 跳过: 无 cmd 或 Android<11(SDK=${SDK:-?})"
fi

# 层 3: uiautomator 找到设置里的热点开关再点
# 会亮屏并弹出设置界面，不想要可以在 config.json 里把 ap_ui_fallback 设为 false
if [ "$(cfg .ap_ui_fallback true)" != "true" ]; then
  log "层3 跳过: config.json 里 ap_ui_fallback=false(不弹出设置界面)"
  log "热点未能开启，请查看日志排查"
  exit 1
fi
log "层3: UI 自动化开热点"

# 屏幕状态: on / off / unknown。mWakefulness(安卓 12+ 叫 mWakefulnessRaw)各版本都有，
# 老写法 mHoldingDisplaySuspendBlocker 兜底
screen_state() {
  _p=$(dumpsys power 2>/dev/null)
  if echo "$_p" | grep -qE 'mWakefulness(Raw)?=Awake|Display Power: state=ON|mHoldingDisplaySuspendBlocker=true'; then
    echo on
  elif echo "$_p" | grep -qE 'mWakefulness(Raw)?=(Asleep|Dozing|Dreaming)|Display Power: state=(OFF|DOZE)'; then
    echo off
  else
    echo unknown
  fi
}

keyguard_showing() {
  dumpsys activity activities 2>/dev/null | grep -q 'mKeyguardShowing=true' && return 0
  dumpsys window 2>/dev/null | grep -qE 'mShowingLockscreen=true|mDreamingLockscreen=true'
}

# 亮屏 + 解锁(只能解无密码的锁屏；有密码时后面发现不在设置界面就什么都不点)。
# 用 WAKEUP(224) 而不是电源键(26): 屏幕本来就亮着时电源键会把它关掉
WOKE=0
case "$(screen_state)" in
  on) ;;
  off) input keyevent 224; WOKE=1; sleep 1 ;;
  *) input keyevent 224; sleep 1 ;;
esac
# 屏幕本来亮着且没锁屏时什么都不做，免得在用户正在用的 App 里乱滑
if [ "$WOKE" = 1 ] || keyguard_showing; then
  wm dismiss-keyguard >/dev/null 2>&1; sleep 1
  # 解不开(或判断不了)再上滑一次
  if keyguard_showing || [ "$WOKE" = 1 ]; then
    SIZE=$(wm size 2>/dev/null | tail -1 | grep -oE '[0-9]+x[0-9]+')
    SW=${SIZE%x*}; SH=${SIZE#*x}
    case "$SW$SH" in ''|*[!0-9]*) SW=1080; SH=2400 ;; esac
    input swipe $((SW / 2)) $((SH * 4 / 5)) $((SW / 2)) $((SH / 5)) 300; sleep 2
  fi
  # 还在锁屏说明设了密码/图案/指纹，模块解不开。这时不打开设置页:
  # 打开了也会压在锁屏后面点不到，锁屏上 HOME 键也不管用，用户解锁后反而会看到这个页面
  if keyguard_showing; then
    input keyevent 4                          # 收起可能弹出来的密码输入界面
    [ "$WOKE" = 1 ] && input keyevent 223     # 原来是灭屏的就灭回去
    log "层3 跳过: 锁屏设了密码，模块解不开，不打开设置页"
    log "热点未能开启，请查看日志排查"
    exit 1
  fi
fi

# 前台窗口所属的包名(mCurrentFocus)，拿不到(锁屏、切换中等)输出空
top_pkg() {
  _f=$(dumpsys window windows 2>/dev/null | grep 'mCurrentFocus=' | head -1)
  # 个别版本 "windows" 子项里没有这一行，退回完整的 dumpsys window
  [ -n "$_f" ] || _f=$(dumpsys window 2>/dev/null | grep 'mCurrentFocus=' | head -1)
  echo "$_f" | grep -oE '[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+' | head -1 | cut -d/ -f1
}

# 收尾: 把层3 打开的设置页退掉，不留在屏幕上
#   1) 前台还是设置就按返回键(最多 4 次)。页面是 CLEAR_TASK 新开的，一层层退完这个任务就结束了，
#      不会留在最近任务里；屏幕本来亮着的话会回到之前正在用的 App
#   2) 返回键退不掉(被页面拦住)或者判断不了前台 → 按 HOME 回桌面；HOME 键被 ROM 拦掉再用 HOME intent
#   3) 屏幕本来是灭的就灭回去(SLEEP=223)
# 只做一次；脚本意外退出时由下面的 trap 兜底
UI_DONE=0
ui_done() {
  [ "$UI_DONE" = 1 ] && return 0
  UI_DONE=1
  _n=0
  while [ "$_n" -lt 4 ]; do
    case "$(top_pkg)" in
      *[Ss]ettings*) input keyevent 4; sleep 1; _n=$((_n + 1)) ;;
      *) break ;;
    esac
  done
  _how="按返回键 $_n 次"
  case "$(top_pkg)" in
    ''|*[Ss]ettings*)
      input keyevent 3; sleep 1
      _how="$_how，再按 HOME"
      case "$(top_pkg)" in
        *[Ss]ettings*)
          am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null 2>&1
          _how="$_how，HOME 键无效改用 HOME intent"
          ;;
      esac
      ;;
  esac
  [ "$WOKE" = 1 ] && { input keyevent 223; _how="$_how，灭屏"; }
  log "  层3 已退出设置页($_how)"
}

# 打开热点设置页，按顺序试:
#   1) 系统的"WLAN 热点设置"入口(安卓 11+)。各家 ROM 会把它指到自家的热点页，
#      也就是下拉快捷开关里长按"热点"进去的那一页，页面上直接就有热点总开关
#   2) 原生的 TetherSettings(热点和网络共享)。安卓 10 及以下，或者 1) 打不开时用。
#      vivo 等 ROM 平时不显示这一页，所以看起来和设置里的热点界面不一样
# 0x10008000 = NEW_TASK|CLEAR_TASK，每次都从这一页的开头进，不接着上次停留的子页面
for page in "-a com.android.settings.WIFI_TETHER_SETTINGS" "-n com.android.settings/.TetherSettings"; do
  out=$(am start $page -f 0x10008000 2>&1)
  case "$out" in
    *Error*|*Exception*) log "  打不开: am start $page" ;;
    *) log "  打开热点设置页: am start $page"; break ;;
  esac
done
# 从这里起不管怎么退出(包括被打断)，都要把设置页退掉
trap ui_done EXIT
trap 'exit 1' HUP INT TERM
sleep 3

# 读 uiautomator 的界面 dump，决定下一步，输出一行 "动作 x y 说明":
#   ON     热点开关已经是开的，不要再点(再点就关了)
#   TAP    点这个热点开关
#   ENTER  这一页只有"WLAN 热点"入口、没有开关(vivo/OriginOS 等)，点进去再找
#   NONE   没找到，什么都不点
# 宁可不点也不乱点: 不在设置里不点；USB/蓝牙/以太网共享那几行的开关永远不碰
ui_pick() {
  tr '<' '\n' < "$1" | awk '
    function attr(s, name,   i, r) {
      i = index(s, " " name "=\"")
      if (i == 0) return ""
      r = substr(s, i + length(name) + 3)
      return substr(r, 1, index(r, "\"") - 1)
    }
    # 热点那一行的标题: 以"热点/hotspot"结尾的短文字(WLAN 热点、个人热点、Wi-Fi hotspot…)，
    # 排除"无设备连接时自动关闭热点"这类子选项
    function is_ap(t,   l) {
      l = tolower(t)
      if (l == "" || length(l) > 48) return 0
      if (l ~ /(自动|自動|关闭|關閉|auto|turn off|timeout|超时|兼容|compat)/) return 0
      return (l ~ /(热点|熱點|hotspot)$/)
    }
    # 主开关旁边常见的中性文字
    function is_neutral(t,   l) {
      l = tolower(t)
      return (l ~ /^(开|关|开启|关闭|打开|已开启|已关闭|已打开|開|關|開啟|關閉|已開啟|已關閉|on|off|use|使用)$/)
    }
    function is_other(t,   l) {
      l = tolower(t)
      return (l ~ /(usb|蓝牙|藍牙|bluetooth|以太网|乙太網路|ethernet)/)
    }
    /^node / {
      n++
      txt[n] = attr($0, "text")
      if (txt[n] == "") txt[n] = attr($0, "content-desc")
      if (n == 1) pkg = attr($0, "package")
      cls = attr($0, "class")
      en[n] = (attr($0, "enabled") == "true")
      clk[n] = (attr($0, "clickable") == "true")
      on[n] = (attr($0, "checked") == "true")
      tog[n] = (attr($0, "checkable") == "true" || cls ~ /(Switch|SlidingButton|BoolButton|CheckBox|ToggleButton)/)
      b = attr($0, "bounds"); gsub(/[^0-9]+/, ",", b); sub(/^,/, "", b); split(b, a, ",")
      x1[n] = a[1] + 0; y1[n] = a[2] + 0; x2[n] = a[3] + 0; y2[n] = a[4] + 0
      if (y2[n] > H) H = y2[n]
      if (is_ap(txt[n])) apPage = 1
    }
    END {
      if (n == 0) { print "NONE 0 0 界面为空"; exit }
      # 只在系统设置里动手，防止没打开设置(锁屏/别的 App)时乱点
      if (tolower(pkg) !~ /settings/) { print "NONE 0 0 当前界面不是系统设置(" pkg ")"; exit }

      # 1) 标题是"xx热点"的那一行上的开关；有多个取最上面的(主开关)
      # 2) 找不到时，页面是热点页的话，取最上面一个旁边只有"开启/关闭"之类文字的开关
      kwT = 0; neT = 0
      for (t = 1; t <= n; t++) {
        if (!tog[t] || !en[t]) continue
        kw = 0; bad = 0; other = 0; row = ""
        for (k = 1; k <= n; k++) {
          if (k == t || txt[k] == "") continue
          cy = (y1[k] + y2[k]) / 2
          if (cy < y1[t] || cy > y2[t]) continue
          if (is_other(txt[k])) other = 1
          if (is_ap(txt[k])) { kw = 1; row = txt[k] }
          else if (!is_neutral(txt[k])) bad = 1
        }
        if (other) continue
        if (kw && (kwT == 0 || y1[t] < y1[kwT])) { kwT = t; kwRow = row }
        if (!kw && !bad && (neT == 0 || y1[t] < y1[neT])) neT = t
      }
      t = kwT; row = kwRow
      if (t == 0 && apPage) { t = neT; row = "热点页主开关" }
      if (t > 0) {
        print (on[t] ? "ON" : "TAP"), int((x1[t] + x2[t]) / 2), int((y1[t] + y2[t]) / 2), row
        exit
      }

      # 3) 这一页只有热点入口(整行可点、没有开关)，点进去
      for (k = 1; k <= n; k++) {
        if (!is_ap(txt[k])) continue
        c = 0
        for (j = 1; j <= n; j++) {
          if (!clk[j] || !en[j] || tog[j]) continue
          if (x1[j] > x1[k] || y1[j] > y1[k] || x2[j] < x2[k] || y2[j] < y2[k]) continue
          if ((y2[j] - y1[j]) * 4 > H) continue
          if (c == 0 || (y2[j] - y1[j]) < (y2[c] - y1[c])) c = j
        }
        if (c > 0) {
          print "ENTER", int((x1[c] + x2[c]) / 2), int((y1[c] + y2[c]) / 2), txt[k]
          exit
        }
      }
      print "NONE 0 0 页面上没有热点开关"
    }'
}

DUMP="$MODDIR/log/ui_dump.xml"
last_enter=""
for attempt in 1 2 3 4; do
  log "  层3 第 $attempt 次尝试"
  if ap_up_fast && ap_up; then break; fi
  # 优先 dump 到模块日志目录，失败再退到 /sdcard
  if ! uiautomator dump "$DUMP" >/dev/null 2>&1; then
    DUMP="/sdcard/hotspotplus_ui.xml"
    if ! uiautomator dump "$DUMP" >/dev/null 2>&1; then
      log "  uiautomator dump 失败"; sleep 2; continue
    fi
  fi
  set -f; set -- $(ui_pick "$DUMP"); set +f
  act="$1"; x="$2"; y="$3"; shift 3 2>/dev/null; desc="$*"
  case "$act" in
    ON)
      log "  层3 热点开关已经是开的[$desc]，不再点击(再点会关掉)，等热点起来"
      if wait_ap 8; then log "层3 成功: 热点已开"; ui_done; log_ssid; exit 0; fi
      break
      ;;
    TAP)
      log "  层3 点击热点开关: ($x,$y) [$desc]"
      input tap "$x" "$y"
      if wait_ap 6; then log "层3 成功: 热点已开"; ui_done; log_ssid; exit 0; fi
      ;;
    ENTER)
      # 同一个入口点过一次页面还是没变，多半是这一行本身就是开关(控件没报成开关)，
      # 再点一次会把刚开起来的热点又关掉
      if [ "$x,$y" = "$last_enter" ]; then
        log "  层3 热点入口点过一次页面没变，不再重复点击，等热点起来"
        if wait_ap 6; then log "层3 成功: 热点已开"; ui_done; log_ssid; exit 0; fi
        break
      fi
      last_enter="$x,$y"
      log "  层3 本页没有热点开关，点进热点入口: ($x,$y) [$desc]"
      input tap "$x" "$y"
      # 有的 ROM 点这一行就直接开热点了，顺便等一下
      if wait_ap 4; then log "层3 成功: 热点已开"; ui_done; log_ssid; exit 0; fi
      ;;
    *)
      log "  层3 不点击: ${desc:-未找到热点开关}"
      sleep 2
      ;;
  esac
done

ui_done
if ap_up; then
  log "热点最终已开启"
  log_ssid
  exit 0
else
  log "三层全部尝试后热点仍未开启，请查看日志排查"
  exit 1
fi
