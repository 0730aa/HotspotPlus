#!/system/bin/sh

# 日志文件路径
LOG_FILE="/data/adb/modules/HotspotPlus/log/rndis_status.log"
TIME=$(date "+%Y-%m-%d %H:%M:%S")

> "$LOG_FILE"

# 检测 USB 共享网络状态
rndis_status() {
    ifconfig | grep -q "rndis"
    return $?
}

if ! rndis_status; then
  echo "$TIME - USB共享网络已关闭，即将重新打开" | tee -a "$LOG_FILE"
  echo "$TIME：$(svc usb setFunctions rndis 2>&1)" | tee -a "$LOG_FILE"
  
  sleep 5
  if ! rndis_status; then
    echo "$TIME - USB共享网络打开失败，请检测USB是否已连接" | tee -a "$LOG_FILE"
  else 
    echo "$TIME - USB共享网络已打开" | tee -a "$LOG_FILE"
  
  fi

else 
    echo "$TIME - USB共享网络已打开" | tee -a "$LOG_FILE"

fi  