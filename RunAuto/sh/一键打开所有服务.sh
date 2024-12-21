#!/system/bin/sh
# 此文件执行后将打开所有服务
LOG_FILE="/data/adb/modules/HotspotPlus/log/service.log"

log_to_file() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}
sleep 1
log_to_file "开始执行定时规则"
CRON_UPDATE_OUTPUT=$(/data/adb/modules/HotspotPlus/RunAuto/sh/cron_update.sh 2>&1)
CRON_UPDATE_EXIT_CODE=$?
log_to_file "定时规则配置输出日志: $CRON_UPDATE_OUTPUT"
log_to_file "定时规则错误日志: $CRON_UPDATE_EXIT_CODE"
/data/adb/magisk/busybox crond -c /data/adb/modules/HotspotPlus/RunAuto/crontabs
sleep 2
log_to_file "运行 additional 文件"
ADDITIONAL_OUTPUT=$(/data/adb/modules/HotspotPlus/RunAuto/sh/additional.sh)
log_to_file "additional: $ADDITIONAL_OUTPUT"

sleep 1
nohup /data/adb/modules/HotspotPlus/RunAuto/sh/sms.sh &

sleep 1
FRPC_OUTPUT=$(/data/adb/modules/HotspotPlus/frp/一键启动.sh 2>&1)
FRPC_EXIT_CODE=$?
log_to_file "FRPC输出日志: $FRPC_OUTPUT"
log_to_file "FRPC错误日志: $FRPC_EXIT_CODE"
