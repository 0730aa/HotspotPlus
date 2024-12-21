#!/system/bin/sh

LOG_FILE="/data/adb/modules/HotspotPlus/log/keepfrpc.log"

> "$LOG_FILE"

if ! pgrep -x "frpc" > /dev/null
then
    echo "$(date '+%F %T') | frpc 未运行，即将开始启动" | tee -a "$LOG_FILE"
    
    sleep 2
    
    echo "$(date '+%F %T') | 开始执行 frpc.sh" | tee -a "$LOG_FILE"
    /data/adb/modules/HotspotPlus/RunAuto/sh/frpc.sh
    
    sleep 5
    
    if pgrep -x "frpc" > /dev/null
    then
        echo "$(date '+%F %T') | 执行完毕！frpc 已启动" | tee -a "$LOG_FILE"
    else
        echo "$(date '+%F %T') | frpc 启动失败" | tee -a "$LOG_FILE"
    fi
    
else
    echo "$(date '+%F %T') | frpc 已启动。无需任何操作" | tee "$LOG_FILE"
fi