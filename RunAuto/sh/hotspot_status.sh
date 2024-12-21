#!/system/bin/sh
CONFIG_FILE="/data/adb/modules/HotspotPlus/config.json"
CLEANED_JSON=$(sed 's/\/\/.*$//' "$CONFIG_FILE" | sed '/^[ \t]*$/d')
LOG_FILE="/data/adb/modules/HotspotPlus/log/hotspot_status.log"
CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")
# 读取配置
START_AP=$(echo "$CLEANED_JSON" | /data/adb/modules/HotspotPlus/bin/jq -r '.start_ap')
AIRMODE=$(echo "$CLEANED_JSON" | /data/adb/modules/HotspotPlus/bin/jq -r '.airmode')
SCREEN_STATUS=$(dumpsys power | grep 'mHoldingDisplaySuspendBlocker' | awk -F= '{print $2}')
# 检测热点状态
hotspot_status=$(ifconfig | grep "ap0")

# 如果热点关闭，开启飞行模式
if [ -z "$hotspot_status" ]; then
  if [ "$AIRMODE" = "true" ]; then
    echo "$CURRENT_TIME - 热点已关闭, 打开飞行模式" | tee "$LOG_FILE"
    settings put global airplane_mode_on 1
    am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true
  
    echo "$CURRENT_TIME - Airplane Mode enabled" | tee "$LOG_FILE"
  
    sleep 5

# 关闭飞行模式  
    settings put global airplane_mode_on 0
    am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false
  else
    sleep 5
  fi
  
# 开启热点，模式读取 config 文件里面
    if [ "$START_AP" = "mode2" ]; then
        AP_SSID=$(echo "$CLEANED_JSON" | /data/adb/modules/HotspotPlus/bin/jq -r '.ap_mode2.ap_ssid')
        OPEN=$(echo "$CLEANED_JSON" | /data/adb/modules/HotspotPlus/bin/jq -r '.ap_mode2.open')
        ENCRYPTION=$(echo "$CLEANED_JSON" | /data/adb/modules/HotspotPlus/bin/jq -r '.ap_mode2.encryption')
        PASSWORD=$(echo "$CLEANED_JSON" | /data/adb/modules/HotspotPlus/bin/jq -r '.ap_mode2.password')
        BAND=$(echo "$CLEANED_JSON" | /data/adb/modules/HotspotPlus/bin/jq -r '.ap_mode2.band')
    
        if [ "$OPEN" = "true" ]; then
            CMD="cmd wifi start-softap $AP_SSID open -b$BAND"
        else
            CMD="cmd wifi start-softap $AP_SSID $ENCRYPTION $PASSWORD -b$BAND"
        fi
        echo "Executing: $CMD"
        $CMD
        echo "热点通过模式2打开了: $CMD"
        echo "$CURRENT_TIME - 热点已打开(模式2打开)" | tee "$LOG_FILE"
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
        echo "热点通过模式1打开了"
        echo "$CURRENT_TIME - 热点已打开(模式1打开)" | tee "$LOG_FILE"
    fi
  
else
    echo "热点已打开，无需任何操作"
    echo "$CURRENT_TIME - 热点已打开，无需任何操作" | tee "$LOG_FILE"
fi
