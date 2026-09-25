#!/system/bin/sh
# ============================================================================
# diag.sh —— 热点诊断，收集排查问题要用的信息。root 或 adb shell(无 root)都能跑
#   用法: sh diag.sh [--no-ui] [--on]
#     默认     机型信息 + 热点检测每一步 + 打开热点设置页抓界面、跑层3 的判断，然后退出设置页。
#              只读: 不点开关，不开关热点
#     --no-ui  不打开设置页
#     --on     额外用层1(系统接口)真的开一次热点，看能不能开、开了之后检测和界面判断对不对，
#              最后把热点关回去。部分机型开热点会断开 WLAN，远程真机平台慎用
#   结果: report.txt 和界面 dump(ui_*.xml)。在模块里跑放 log/diag/，否则放脚本同目录的 diag_out/
#   依赖: lib.sh 和 hotspotctl.dex，放在同一个目录，或者保持模块原来的目录结构
# ============================================================================

HERE=$(cd "$(dirname "$0")" && pwd)
if [ -f "$HERE/hotspotctl.dex" ]; then
  HOTSPOTCTL_DEX="$HERE/hotspotctl.dex"
elif [ -f "$HERE/../../bin/hotspotctl.dex" ]; then
  HOTSPOTCTL_DEX="$HERE/../../bin/hotspotctl.dex"
fi
. "$HERE/lib.sh"

DO_UI=1
DO_ON=0
for a in "$@"; do
  case "$a" in
    --no-ui) DO_UI=0 ;;
    --on) DO_ON=1 ;;
    *) echo "用法: sh diag.sh [--no-ui] [--on]"; exit 1 ;;
  esac
done

if [ -f "$HERE/../../module.prop" ]; then
  OUT="$HERE/../../log/diag"
else
  OUT="$HERE/diag_out"
fi
mkdir -p "$OUT"
rm -f "$OUT"/report.txt "$OUT"/ui_*.xml
REPORT="$OUT/report.txt"

r() { printf '%s\n' "$*" | tee -a "$REPORT"; }

state_name() {
  case "$1" in
    10) echo 关闭中 ;; 11) echo 已关闭 ;; 12) echo 开启中 ;; 13) echo 已开启 ;; 14) echo 失败 ;;
    *) echo 未知 ;;
  esac
}

# 热点检测每一步的结果，最后一行是模块的结论，AP_NOW=1 表示已开启
check_ap() {
  _ap_tethered
  case $? in
    0) r "  网络共享服务: 有 Wi-Fi 网卡在共享" ;;
    1) r "  网络共享服务: 没有 Wi-Fi 网卡在共享" ;;
    *) r "  网络共享服务: 拿不到(dumpsys 里没有 Tether state)" ;;
  esac
  echo "$_dump" | sed -n '/Tether state/,/Upstream/p' | head -20 | while read -r l; do r "    | $l"; done

  if [ -f "$HOTSPOTCTL_DEX" ]; then
    CLASSPATH="$HOTSPOTCTL_DEX" app_process /system/bin com.hotspotplus.HotspotCtl state 2>&1 \
      | while read -r l; do r "    dex> $l"; done
  else
    r "    找不到 hotspotctl.dex，跳过 WifiManager 查询"
  fi
  if ap_sys_info; then
    r "  WifiManager: 热点状态 $AP_SYS_STATE($(state_name "$AP_SYS_STATE"))，系统热点名称: ${AP_SYS_SSID:-拿不到}"
  else
    r "  WifiManager: 拿不到"
  fi

  if _ap_guess; then r "  按网卡名猜: 像是开着"; else r "  按网卡名猜: 像是没开"; fi

  if ap_up; then AP_NOW=1; r "  => 模块判断: 热点已开启"; else AP_NOW=0; r "  => 模块判断: 热点未开启"; fi
}

# 打开热点设置页抓界面、跑层3 的判断(只判断不点)，再退出。$1 是文件名里的标记
check_ui() {
  _ss=$(screen_state)
  if [ "$_ss" = off ] || keyguard_showing; then
    r "  屏幕没亮或停在锁屏(屏幕: $_ss)，跳过。请先亮屏解锁再跑"
    return
  fi
  _i=0
  for _pg in "$AP_PAGE_1" "$AP_PAGE_2"; do
    _i=$((_i + 1))
    if ! ap_page_start "$_pg"; then
      r "  [$_i] am start $_pg: 打不开"
      continue
    fi
    sleep 3
    _f="$OUT/ui_$1_$_i.xml"
    if uiautomator dump "$_f" >/dev/null 2>&1 && [ -s "$_f" ]; then
      r "  [$_i] am start $_pg"
      r "      前台: $(top_pkg)"
      r "      层3 判断: $(ui_pick "$_f")"
      r "      界面: $_f"
    else
      r "  [$_i] am start $_pg: 打开了，但 uiautomator dump 失败"
    fi
    r "      退出: $(ui_leave)"
  done
}

r "===== HotspotPlus 诊断 $(date '+%Y-%m-%d %H:%M:%S')"
if [ "$(id -u)" = 0 ]; then r "运行身份: root"; else r "运行身份: $(id -u)(非 root)"; fi
for p in ro.product.brand ro.product.model ro.product.marketname ro.vivo.market.name \
         ro.build.version.release ro.build.version.sdk ro.build.version.security_patch \
         ro.build.display.id ro.vivo.os.build.display.id ro.vivo.os.version \
         ro.board.platform ro.soc.model ro.hardware; do
  v=$(getprop "$p")
  [ -n "$v" ] && r "  $p=$v"
done

r ""
r "===== 网卡"
for d in /sys/class/net/*; do
  [ -e "$d" ] || continue
  w=""
  if [ -e "$d/phy80211" ] || [ -d "$d/wireless" ]; then w=" (无线)"; fi
  r "  ${d##*/}: $(cat "$d/operstate" 2>/dev/null)$w"
done
ip -o -4 addr show 2>/dev/null | while read -r l; do r "  | $l"; done

r ""
r "===== 热点检测"
check_ap

if [ "$DO_UI" = 1 ]; then
  r ""
  r "===== 界面(层3 的判断，只判断不点击)"
  check_ui off
fi

if [ "$DO_ON" = 1 ]; then
  r ""
  r "===== 层1 实测(--on)"
  if [ "$AP_NOW" = 1 ]; then
    r "  热点本来就开着，跳过"
  elif [ ! -f "$HOTSPOTCTL_DEX" ]; then
    r "  找不到 hotspotctl.dex，跳过"
  else
    CLASSPATH="$HOTSPOTCTL_DEX" app_process /system/bin com.hotspotplus.HotspotCtl on 2>&1 \
      | while read -r l; do r "    dex> $l"; done
    i=0
    while [ "$i" -lt 15 ]; do
      if ap_up_fast && ap_up; then break; fi
      sleep 1
      i=$((i + 1))
    done
    r "  开热点后 ${i} 秒的检测:"
    check_ap
    if [ "$AP_NOW" = 1 ] && [ "$DO_UI" = 1 ]; then
      r "  开着热点时的界面判断(应为 ON):"
      check_ui on
    fi
    r "  恢复: 关闭热点"
    CLASSPATH="$HOTSPOTCTL_DEX" app_process /system/bin com.hotspotplus.HotspotCtl off 2>&1 \
      | while read -r l; do r "    dex> $l"; done
  fi
fi

r ""
r "===== 完成，结果在 $OUT"
