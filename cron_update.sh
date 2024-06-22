#!/system/bin/sh
set -e  # 遇到错误立即退出

CONFIG_FILE="/data/adb/modules/autofrp/config.json"
CRON_FILE="/data/adb/modules/autofrp/RunAuto/crontabs/root"

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误：配置文件 $CONFIG_FILE 不存在"
    exit 1
fi

# 直接处理配置文件并输出到 CRON_FILE
{
    sed 's/\/\/.*$//' "$CONFIG_FILE" | \
    sed '/^\s*$/d' | \
    /data/adb/modules/autofrp/jq -c '.cron_jobs[]' | \
    while read -r job; do
        ENABLED=$(echo "$job" | /data/adb/modules/autofrp/jq -r '.enabled')
        if [ "$ENABLED" = "true" ]; then
            COMMENT=$(echo "$job" | /data/adb/modules/autofrp/jq -r '.comment')
            SCHEDULE=$(echo "$job" | /data/adb/modules/autofrp/jq -r '.schedule')
            COMMAND=$(echo "$job" | /data/adb/modules/autofrp/jq -r '.command')
            echo "# $COMMENT"
            echo "$SCHEDULE $COMMAND"
        fi
    done
} > "$CRON_FILE"

if [ $? -eq 0 ]; then
    echo "成功更新cron文件"
else
    echo "错误：无法更新cron文件"
    exit 1
fi

echo "定时规则已更新，立即生效"