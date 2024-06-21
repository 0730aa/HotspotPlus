#!/system/bin/sh

# 日志文件路径
LOG_FILE="/data/adb/modules/autofrp/log/hotspot_status.log"
CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")
# 检测热点状态
hotspot_status=$(ifconfig | grep "ap0")

# 如果热点关闭，开启飞行模式
if [ -z "$hotspot_status" ]; then
  echo "$CURRENT_TIME - 热点已关闭, 打开飞行模式" | tee -a "$LOG_FILE"
  settings put global airplane_mode_on 1
  am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true
  
  echo "$CURRENT_TIME - Airplane Mode enabled" | tee -a "$LOG_FILE"
else
  echo "$CURRENT_TIME - 热点已经打开" | tee -a "$LOG_FILE"
fi

