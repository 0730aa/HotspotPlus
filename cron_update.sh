#!/system/bin/sh
CONFIG_FILE="/data/adb/modules/HotspotPlus/config.json"
CRON_FILE="/data/adb/modules/HotspotPlus/RunAuto/crontabs/root"
JQ_PATH="/data/adb/modules/HotspotPlus/bin/jq"

pkill -9 -x busybox crond # 先停止进程

echo "正在重新启动 crond，请稍等"
sleep 2

/data/adb/magisk/busybox crond -c /data/adb/modules/HotspotPlus/RunAuto/crontabs #重新启动

sleep 2

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误：配置文件 $CONFIG_FILE 不存在"
    exit 1
fi

# 检查 jq 工具是否存在
if [ ! -f "$JQ_PATH" ]; then
    echo "错误：jq 工具未找到，路径 $JQ_PATH 不存在"
    exit 1
fi

# 提取启用的 cron_jobs，并将 schedule 和 command 合并写入 CRON_FILE
$JQ_PATH -r '.cron_jobs[] | select(.enabled == true) | "\(.schedule) \(.command)"' "$CONFIG_FILE" > "$CRON_FILE"

# 检查写入是否成功
if [ $? -eq 0 ]; then
    echo "成功更新 $CRON_FILE 文件，内容如下："
    cat "$CRON_FILE"
else
    echo "错误：无法更新 $CRON_FILE 文件"
    exit 1
fi