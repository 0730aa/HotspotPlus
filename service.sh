#!/system/bin/sh
MODDIR=${0%/*}

# 指定日志文件路径
LOG_FILE="/data/adb/modules/HotspotPlus/log/service.log"

log_to_file() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}
> "$LOG_FILE"
log_to_file "service starting"

# 等待系统初始化完成
until [ "$(getprop sys.boot_completed)" -eq 1 ] ; do
    sleep 5
done
log_to_file "系统初始化完成"

sleep 10
log_to_file "等待系统拉起进程"

pkill -9 -x busybox crond
log_to_file "终止 crond 进程"

chmod -R 777 /data/adb/modules/HotspotPlus
chmod -R 777 /data/data/com.android.providers.telephony
log_to_file "获取满权限到子文件夹"

sleep 4
Code_1=0
Code_2=0
while true
do
    if [ -f ${0%/*}/disable ] ;then
        if [ $Code_1 -eq 0 ] ;then
            /data/adb/modules/HotspotPlus/RunAuto/sh/一键关闭所有服务.sh
            Code_1=1
        fi
        Code_2=0
    else
        if [ $Code_2 -eq 0 ] ;then
            /data/adb/modules/HotspotPlus/RunAuto/sh/一键打开所有服务.sh
            Code_2=1
        fi
        Code_1=0
    fi
    sleep 5
done