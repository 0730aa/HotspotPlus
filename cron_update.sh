#!/system/bin/sh
# 改完 config.json 的 cron_jobs 后执行本文件，定时规则立即生效
MODDIR="/data/adb/modules/HotspotPlus"

pkill -9 -x busybox crond
echo "正在重新启动 crond，请稍等"
sleep 2
/data/adb/magisk/busybox crond -c "$MODDIR/RunAuto/crontabs"
sleep 2

exec "$MODDIR/RunAuto/sh/cron_update.sh"
