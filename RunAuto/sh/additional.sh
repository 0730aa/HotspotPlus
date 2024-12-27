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

if [ -z "$hotspot_status" ]; then
  if [ "$START_AP" = "mode1" ]; then
    # 检查屏幕状态
    SCREEN_STATUS=$(dumpsys power | grep 'mHoldingDisplaySuspendBlocker' | awk -F= '{print $2}')
    
    if [ "$SCREEN_STATUS" = "true" ]; then
      echo "屏幕已亮，无需唤醒"
      # 保险起见，尝试上滑解锁
      input swipe 300 1000 300 500
    else
      echo "屏幕未亮，唤醒屏幕"
      input keyevent 26  # 唤醒屏幕
      sleep 1 
      input swipe 300 1000 300 500 # 上滑解锁屏幕
      sleep 3
    fi
    # 进入热点设置，打开热点
    am start -n com.android.settings/.TetherSettings
    input keyevent 20
    input keyevent 66
    
    echo "热点已打开（模式一）"
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