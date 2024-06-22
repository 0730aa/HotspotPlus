#!/system/bin/sh
MODDIR=${0%/*}

# 指定日志文件路径
LOG_FILE="/data/adb/modules/autofrp/log/service.log"

log_to_file() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_to_file "service starting"

# 等待系统初始化完成
until [ "$(getprop sys.boot_completed)" -eq 1 ] ; do
    sleep 5
done
log_to_file "系统初始化完成"

sleep 20
log_to_file "等待系统拉起进程"

pkill -9 -x busybox crond
log_to_file "终止 crond 进程"

chmod -R 777 /data/adb/modules/autofrp
log_to_file "获取满权限到子文件夹"

# 确保权限设置生效
sleep 5

/data/adb/magisk/busybox crond -c /data/adb/modules/autofrp/RunAuto/crontabs
log_to_file "计划任务守护进程"

sleep 5

# 执行 cron_update.sh 并记录输出
log_to_file "开始执行定时规则"
CRON_UPDATE_OUTPUT=$(/data/adb/modules/autofrp/RunAuto/sh/cron_update.sh 2>&1)
CRON_UPDATE_EXIT_CODE=$?
log_to_file "定时规则配置输出日志: $CRON_UPDATE_OUTPUT"
log_to_file "定时规则错误日志: $CRON_UPDATE_EXIT_CODE"

sleep 5

log_to_file "运行 additional 文件"
/data/adb/modules/autofrp/RunAuto/sh/additional.sh

sleep 5

# 开机首次启动 frpc
log_to_file "首次启动 frpc"
/data/adb/modules/autofrp/frp/一键启动.sh

log_to_file "模块所有服务启动完毕"