#!/system/bin/sh
# ============================================================================
# check.sh —— 定时检测，由 crond 调用
#   (由原来的 hotspot_status.sh + rndis_status.sh + keepfrpc.sh 合并而来)
#
#   用法: check.sh ap     热点掉了就重新打开
#         check.sh usb    USB 网络共享掉了就重新打开
#         check.sh frpc   frpc 进程没了就重新拉起
#
# 每一项都会先看 config.json 里对应的总开关，开关是关的就什么都不做直接退出。
# (以前热点检测不看 start_ap，用户把 start_ap 设成 false 只想用 frp，
#  检测脚本照样去切飞行模式、甚至把热点开起来，这里修掉)
# ============================================================================

MODDIR="/data/adb/modules/HotspotPlus"
. "$MODDIR/RunAuto/sh/lib.sh"

WHAT="$1"
LOG_FILE="$MODDIR/log/check_${WHAT}.log"
mkdir -p "$MODDIR/log"
: > "$LOG_FILE"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

case "$WHAT" in

  # ------------------------------------------------------------------ 热点
  ap)
    START_AP=$(cfg .start_ap false)
    # 总开关关掉时绝不碰热点，也不碰飞行模式
    case "$START_AP" in
      api|mode1|mode2) ;;
      *) log "热点功能已关闭(start_ap=$START_AP)，不做任何操作"; exit 0 ;;
    esac

    if ap_up; then
      log "热点已打开，无需任何操作"
      exit 0
    fi

    log "热点已关闭，准备重新打开"

    # 先把系统的"空闲自动关闭热点"关掉，否则刚开起来过一会儿又被系统关了
    if [ "$(cfg .ap_keep_alive true)" = "true" ]; then
      ap_no_timeout
      log "已关闭系统的热点空闲自动关闭"
    fi

    if [ "$(cfg .airmode false)" = "true" ]; then
      log "先切一次飞行模式"
      settings put global airplane_mode_on 1
      am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true >/dev/null 2>&1
      sleep 5
      settings put global airplane_mode_on 0
      am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false >/dev/null 2>&1
      sleep 5
    else
      sleep 2
    fi

    # 统一走 open_hotspot.sh，它内部按 api -> cmd -> UI 分层回退
    "$MODDIR/RunAuto/sh/open_hotspot.sh" on >/dev/null 2>&1

    if ap_up; then
      log "热点已重新打开"
    else
      log "热点打开失败，详情见 log/open_hotspot.log"
    fi
    ;;

  # -------------------------------------------------------------- USB 共享
  usb)
    if [ "$(cfg .start_rndis false)" != "true" ]; then
      log "USB 网络共享功能已关闭(start_rndis=false)，不做任何操作"
      exit 0
    fi

    if ifconfig 2>/dev/null | grep -q "rndis"; then
      log "USB 网络共享已打开"
      exit 0
    fi

    log "USB 网络共享已关闭，重新打开"
    svc usb setFunctions rndis
    sleep 5
    if ifconfig 2>/dev/null | grep -q "rndis"; then
      log "USB 网络共享已打开"
    else
      log "USB 网络共享打开失败，请检查 USB 是否已连接"
    fi
    ;;

  # ------------------------------------------------------------------ frpc
  frpc)
    if pgrep -x frpc > /dev/null 2>&1; then
      log "frpc 已在运行，无需任何操作"
      exit 0
    fi

    log "frpc 未运行，重新启动"
    "$MODDIR/RunAuto/sh/frpc.sh"
    sleep 5
    if pgrep -x frpc > /dev/null 2>&1; then
      log "frpc 已启动"
    else
      log "frpc 启动失败，请检查 frp/frpc.toml 配置"
    fi
    ;;

  *)
    echo "用法: check.sh ap|usb|frpc"
    exit 1
    ;;
esac
