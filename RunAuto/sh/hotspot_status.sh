#!/system/bin/sh

LOG_FILE="/data/adb/modules/HotspotPlus/log/hotspot_status.log"
CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")

# 读取配置
. /data/adb/modules/HotspotPlus/RunAuto/sh/lib_cfg.sh
START_AP=$(cfg .start_ap false)
AIRMODE=$(cfg .airmode false)
SCREEN_STATUS=$(dumpsys power | grep 'mHoldingDisplaySuspendBlocker' | awk -F= '{print $2}')

# 检测热点状态（通用接口识别）
. /data/adb/modules/HotspotPlus/RunAuto/sh/lib_ap.sh
if ap_up; then hotspot_status="up"; else hotspot_status=""; fi

# 如果热点关闭，开启飞行模式
if [ -z "$hotspot_status" ]; then
  if [ "$AIRMODE" = "true" ]; then
    echo "$CURRENT_TIME - 热点已关闭, 打开飞行模式" | tee -a "$LOG_FILE"
    settings put global airplane_mode_on 1
    am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true
  
    echo "$CURRENT_TIME - Airplane Mode enabled" | tee -a "$LOG_FILE"
    sleep 5

    # 关闭飞行模式  
    settings put global airplane_mode_on 0
    am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false
  else
    sleep 5
  fi
  
  # 开启热点，模式读取 config 文件里面
  if [ "$START_AP" = "api" ]; then
    echo "$CURRENT_TIME - 通用模式(api)重新打开热点" | tee -a "$LOG_FILE"
    /data/adb/modules/HotspotPlus/RunAuto/sh/open_hotspot.sh on
  elif [ "$START_AP" = "mode2" ]; then
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
    echo "$CURRENT_TIME - 热点通过模式2打开了: $CMD" | tee -a "$LOG_FILE"
  elif [ "$START_AP" = "mode1" ]; then
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
    echo "$CURRENT_TIME - 热点通过模式1打开了" | tee "$LOG_FILE"
  fi
else
  echo "$CURRENT_TIME - 热点已打开，无需任何操作" | tee "$LOG_FILE"
fi
