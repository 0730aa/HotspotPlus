#!/system/bin/sh
CRON_FILE="/data/adb/modules/HotspotPlus/RunAuto/crontabs/root"
. /data/adb/modules/HotspotPlus/RunAuto/sh/lib.sh

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误：配置文件 $CONFIG_FILE 不存在"
    exit 1
fi

# 检查 jq 工具是否存在
if [ ! -f "$JQ" ]; then
    echo "错误：jq 工具未找到，路径 $JQ 不存在"
    exit 1
fi

# 提取启用的 cron_jobs，并将 schedule 和 command 合并写入 CRON_FILE
# 旧版 config.json 里写的是 hotspot_status.sh / rndis_status.sh / keepfrpc.sh，
# 这三个已经合并成 check.sh，这里顺手映射一下，老配置不用改也能继续用
cfg_raw '.cron_jobs[] | select(.enabled == true) | "\(.schedule) \(.command)"' \
  | sed -e 's#/RunAuto/sh/hotspot_status\.sh#/RunAuto/sh/check.sh ap#' \
        -e 's#/RunAuto/sh/rndis_status\.sh#/RunAuto/sh/check.sh usb#' \
        -e 's#/RunAuto/sh/keepfrpc\.sh#/RunAuto/sh/check.sh frpc#' > "$CRON_FILE"

# 检查写入是否成功
if [ $? -eq 0 ]; then
    echo "成功更新 $CRON_FILE 文件，内容如下："
    cat "$CRON_FILE"
else
    echo "错误：无法更新 $CRON_FILE 文件"
    exit 1
fi
