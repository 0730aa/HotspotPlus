#!/system/bin/sh

. /data/adb/modules/HotspotPlus/RunAuto/sh/lib.sh

# 获取配置文件的值
START_ADB=$(cfg .start_adb false)
ADB_PORT=$(cfg .adb_port 5555)
START_TELNET=$(cfg .start_telnet false)
START_FTP=$(cfg .start_ftp false)
FTP_PORT=$(cfg .ftp_setting.port 21)
FTP_DIR=$(cfg .ftp_setting.dir /sdcard)
FTP_UPLOAD=$(cfg .ftp_setting.allow_upload true)
FTP_PASS=$(cfg .ftp_setting.password)
START_AP=$(cfg .start_ap false)
START_RNDIS=$(cfg .start_rndis false)

if ap_up; then hotspot_status="up"; else hotspot_status=""; fi

START_ADB=$([ "$START_ADB" = "true" ] && echo 1 || echo 0)
START_TELNET=$([ "$START_TELNET" = "true" ] && echo 1 || echo 0)
START_FTP=$([ "$START_FTP" = "true" ] && echo 1 || echo 0)
START_RNDIS=$([ "$START_RNDIS" = "true" ] && echo 1 || echo 0)

if [ $START_ADB -eq 1 ]; then
  stop adbd
  setprop service.adb.tcp.port $ADB_PORT
  start adbd
  echo "ADB 已开启，端口号: $ADB_PORT"
else
  echo "ADB 已关闭"
  stop adbd
fi

if [ $START_TELNET -eq 1 ]; then
  /data/adb/magisk/busybox telnetd -l /system/bin/sh
  echo "telnet 已开启，端口号为 23"
else
  echo "telnet 未开启"
fi

if [ $START_FTP -eq 1 ]; then
  # 端口不是纯数字时回落到默认的 21
  case "$FTP_PORT" in
    ''|*[!0-9]*) FTP_PORT=21 ;;
  esac

  if [ ! -d "$FTP_DIR" ]; then
    echo "FTP 未开启: 共享目录 $FTP_DIR 不存在，请检查 config.json 里的 ftp_setting.dir"
  else
    if [ "$FTP_DIR" = "/" ]; then
      echo "警告: FTP 共享目录为根目录 /，局域网内的设备可以看到整个系统，建议改成 /sdcard"
    fi

    if [ "$FTP_UPLOAD" = "true" ]; then
      FTP_MODE="可上传"
    else
      FTP_MODE="只读"
    fi

    if [ -n "$FTP_PASS" ]; then
      FTP_AUTH="需账号密码登录"
    else
      FTP_AUTH="免登录"
    fi

    # 连接先交给 ftp_login.sh 处理 UTF-8 协商和账号密码，再转给 ftpd。
    # ftpd 的 -A 是免登录(校验已经在前面做完)，共享目录会被 chroot 成 FTP 的根目录，出不去
    /data/adb/magisk/busybox tcpsvd -vE 0.0.0.0 "$FTP_PORT" /data/adb/modules/HotspotPlus/RunAuto/sh/ftp_login.sh "$FTP_DIR" "$FTP_UPLOAD" >/dev/null 2>&1 &
    echo "FTP 已开启，端口号: $FTP_PORT，共享目录: $FTP_DIR，$FTP_MODE，$FTP_AUTH"
  fi
else
  echo "FTP 未开启"
fi

# 热点总开关关掉时，本模块不碰热点(也不切飞行模式)
case "$START_AP" in
  api|mode1|mode2)
    # 关掉系统"无设备连接就自动关闭热点"的超时，否则开起来过一会儿又被系统关了
    if [ "$(cfg .ap_keep_alive true)" = "true" ]; then
      ap_no_timeout
      echo "已关闭系统的热点空闲自动关闭"
    fi
    ;;
  *)
    echo "热点功能已关闭(start_ap=$START_AP)，本模块不会去开热点"
    ;;
esac

if [ "$START_AP" = "mode2" ]; then
  AP_SSID=$(cfg .ap_mode2.ap_ssid Hotspotplus)
  OPEN=$(cfg .ap_mode2.open false)
  ENCRYPTION=$(cfg .ap_mode2.encryption wpa2)
  PASSWORD=$(cfg .ap_mode2.password)
  BAND=$(cfg .ap_mode2.band 2)

  if [ "$OPEN" = "true" ]; then
    CMD="cmd wifi start-softap $AP_SSID open -b$BAND"
  else
    CMD="cmd wifi start-softap $AP_SSID $ENCRYPTION $PASSWORD -b$BAND"
  fi
  echo "Executing: $CMD"
  $CMD
  echo "热点已打开（模式二）: $CMD"
fi

# 通用模式(api): 调系统 tethering API 开真热点，失败自动回退 cmd/UI
if [ "$START_AP" = "api" ]; then
  echo "使用通用模式(api)开启热点"
  /data/adb/modules/HotspotPlus/RunAuto/sh/open_hotspot.sh on
fi

if [ -z "$hotspot_status" ]; then
  if [ "$START_AP" = "mode1" ]; then

    LOG_DIR="/data/adb/modules/HotspotPlus/log"
    LOG_FILE="$LOG_DIR/hotspot.log"
    mkdir -p $LOG_DIR

    log() {
      echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"
    }

    log "开始启动 mode1 热点"

    # 检查屏幕状态
    SCREEN_STATUS=$(dumpsys power | grep 'mHoldingDisplaySuspendBlocker' | awk -F= '{print $2}')
    
    if [ "$SCREEN_STATUS" = "true" ]; then
      log "屏幕已亮，无需唤醒"
      
      input swipe 300 2200 300 100 300
    else
      log "屏幕未亮，唤醒屏幕"
      input keyevent 26
      sleep 1
      input swipe 300 2200 300 100 300
      sleep 3
    fi

    am start -n com.android.settings/.TetherSettings -f 0x00000400
    sleep 2

    success=0
    # 尝试 4 次 TAB + ENTER
    for i in 1 2 3 4; do
      log "第 $i 次尝试开启热点"
      
      input keyevent TAB
      sleep 0.3
      input keyevent ENTER
      sleep 1.3

      # 检测热点
      if ifconfig | grep -q "^ap0"; then
        log "第 $i 次成功开启热点"
        success=1
        break
      fi
    done

    if [ $success -eq 1 ]; then
      input keyevent HOME
      log "热点开启成功，已返回桌面"
      echo "热点已打开（模式一）"
    else
      log "四次尝试均失败，热点未开启"
      ifconfig >> "$LOG_FILE"
      input keyevent HOME
      echo "热点开启失败（模式一）"
    fi

  fi
else
  echo "热点已经打开"
fi

if [ $START_RNDIS -eq 1 ]; then
  svc usb setFunctions rndis
  echo "USB网络共享已打开"
else
  echo "USB网络共享已关闭"
fi