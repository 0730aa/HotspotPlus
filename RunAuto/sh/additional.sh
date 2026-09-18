#!/system/bin/sh

CONFIG_FILE="/data/adb/modules/HotspotPlus/config.json"

# 获取配置文件的值
START_ADB=$(/data/adb/modules/HotspotPlus/bin/jq -r '.start_adb // false' "$CONFIG_FILE")
ADB_PORT=$(/data/adb/modules/HotspotPlus/bin/jq -r '.adb_port' "$CONFIG_FILE")
START_TELNET=$(/data/adb/modules/HotspotPlus/bin/jq -r '.start_telnet // false' "$CONFIG_FILE")
START_FTP=$(/data/adb/modules/HotspotPlus/bin/jq -r '.start_ftp // false' "$CONFIG_FILE")
START_AP=$(/data/adb/modules/HotspotPlus/bin/jq -r '.start_ap' "$CONFIG_FILE")
START_RNDIS=$(/data/adb/modules/HotspotPlus/bin/jq -r '.start_rndis // false' "$CONFIG_FILE")

hotspot_status=$(ifconfig | grep "ap0")

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
  /data/adb/magisk/busybox tcpsvd -vE 0.0.0.0 21 /data/adb/magisk/busybox ftpd -wA / &> /dev/null &
  echo "FTP 已开启"
else
  echo "FTP 未开启"
fi

if [ "$START_AP" = "mode2" ]; then
  AP_SSID=$(/data/adb/modules/HotspotPlus/bin/jq -r '.ap_mode2.ap_ssid' "$CONFIG_FILE")
  OPEN=$(/data/adb/modules/HotspotPlus/bin/jq -r '.ap_mode2.open' "$CONFIG_FILE")
  ENCRYPTION=$(/data/adb/modules/HotspotPlus/bin/jq -r '.ap_mode2.encryption' "$CONFIG_FILE")
  PASSWORD=$(/data/adb/modules/HotspotPlus/bin/jq -r '.ap_mode2.password' "$CONFIG_FILE")
  BAND=$(/data/adb/modules/HotspotPlus/bin/jq -r '.ap_mode2.band' "$CONFIG_FILE")

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