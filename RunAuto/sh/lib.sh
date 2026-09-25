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
#
# 三、界面
#   screen_state / keyguard_showing / top_pkg   屏幕、锁屏、前台包名
#   ap_page_open           打开热点设置页；ui_leave 退出设置页
#   ui_pick <dump.xml>     看界面决定怎么点热点开关(只判断，不点)
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
HOTSPOTCTL_DEX="${HOTSPOTCTL_DEX:-/data/adb/modules/HotspotPlus/bin/hotspotctl.dex}"

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

# ---------------------------------------------------------------------------
# 三、界面(open_hotspot.sh 的层3 和 diag.sh 共用)
# ---------------------------------------------------------------------------
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

# 前台窗口所属的包名(mCurrentFocus)，拿不到(锁屏、切换中等)输出空
top_pkg() {
  _f=$(dumpsys window windows 2>/dev/null | grep 'mCurrentFocus=' | head -1)
  # 个别版本 "windows" 子项里没有这一行，退回完整的 dumpsys window
  [ -n "$_f" ] || _f=$(dumpsys window 2>/dev/null | grep 'mCurrentFocus=' | head -1)
  echo "$_f" | grep -oE '[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+' | head -1 | cut -d/ -f1
}

# 打开热点设置页，按顺序试:
#   1) 系统的"WLAN 热点设置"入口(安卓 11+)。各家 ROM 会把它指到自家的热点页，
#      也就是下拉快捷开关里长按"热点"进去的那一页，页面上直接就有热点总开关
#   2) 原生的 TetherSettings(热点和网络共享)。安卓 10 及以下，或者 1) 打不开时用。
#      vivo 等 ROM 平时不显示这一页，所以看起来和设置里的热点界面不一样
# 0x10008000 = NEW_TASK|CLEAR_TASK，每次都从这一页的开头进，不接着上次停留的子页面。
AP_PAGE_1="-a com.android.settings.WIFI_TETHER_SETTINGS"
AP_PAGE_2="-n com.android.settings/.TetherSettings"

# 打开一个页面，打不开返回 1
ap_page_start() {
  _out=$(am start $1 -f 0x10008000 2>&1)
  case "$_out" in *Error*|*Exception*) return 1 ;; esac
  return 0
}

# 按顺序试两个入口，输出打开成功的 am start 参数；都打不开返回 1
ap_page_open() {
  for _pg in "$AP_PAGE_1" "$AP_PAGE_2"; do
    if ap_page_start "$_pg"; then echo "$_pg"; return 0; fi
  done
  return 1
}

# 退出刚打开的设置页，输出做了什么:
#   1) 前台还是设置就按返回键(最多 4 次)。页面是 CLEAR_TASK 新开的，一层层退完这个任务就结束了，
#      不会留在最近任务里；屏幕本来亮着的话会回到之前正在用的 App
#   2) 返回键退不掉(被页面拦住)或者判断不了前台 → 按 HOME 回桌面；HOME 键被 ROM 拦掉再用 HOME intent
ui_leave() {
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
  echo "$_how"
}

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
