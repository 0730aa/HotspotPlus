#!/system/bin/sh

CONFIG_FILE="/data/adb/modules/HotspotPlus/config.json"
CLEANED_JSON=$(sed 's/\/\/.*$//' "$CONFIG_FILE" | sed '/^[ \t]*$/d')
SMS_FORWARDING_ENABLED=$(echo "$CLEANED_JSON" | /data/adb/modules/HotspotPlus/bin/jq -r '.sms_forwarding_enabled')

# 如果总开关为 false，则不执行短信转发
if [ "$SMS_FORWARDING_ENABLED" != "true" ]; then
    echo "短信转发功能已禁用。"
    exit 0
fi

# 获取短信数据库路径
SMS_DB_PATH="/data/data/com.android.providers.telephony/databases/mmssms.db"

get_config_value() {
    local key="$1"
    echo "$CLEANED_JSON" | /data/adb/modules/HotspotPlus/bin/jq -r "$key"
}

# 读取邮件发送配置
TLS=$(get_config_value '.sms_setting.defaults.tls')
TLS_TRUST_FILE=$(get_config_value '.sms_setting.defaults.tls_trust_file')
LOGFILE=$(get_config_value '.sms_setting.defaults.logfile')

ACCOUNT_NAME=$(get_config_value '.sms_setting.account.name')
SMTP_SERVER=$(get_config_value '.sms_setting.account.host')
SMTP_PORT=$(get_config_value '.sms_setting.account.port')
AUTH=$(get_config_value '.sms_setting.account.auth')
EMAIL=$(get_config_value '.sms_setting.account.user')
PASSWORD=$(get_config_value '.sms_setting.account.password')
FROM=$(get_config_value '.sms_setting.account.from')
TO_EMAIL=$(get_config_value '.sms_setting.email_settings.to_email')

send_email() {
    local subject="$1"
    local body="$2"
    echo -e "Subject: $subject\n\n$body" | /data/adb/modules/HotspotPlus/bin/msmtp \
        --tls=$TLS \
        --tls-trust-file=$TLS_TRUST_FILE \
        --logfile=$LOGFILE \
        --host=$SMTP_SERVER \
        --port=$SMTP_PORT \
        --auth=$AUTH \
        --user=$EMAIL \
        --passwordeval="echo $PASSWORD" \
        --from=$FROM \
        "$TO_EMAIL"
}

# 获取最新短信
get_new_sms() {
    /data/adb/modules/HotspotPlus/bin/sqlite3 "$SMS_DB_PATH" \
        "SELECT _id, address, body FROM sms ORDER BY _id DESC LIMIT 1;"
}
script_pid=$$
echo $script_pid > /data/adb/modules/HotspotPlus/bin/pid_file.txt
echo "The script PID is: $script_pid"

SMS_LAST_PROCESSED_ID=0
while /data/adb/modules/HotspotPlus/bin/inotifywait -e modify "$SMS_DB_PATH"; do

    NEW_SMS=$(get_new_sms)
    if [ -n "$NEW_SMS" ]; then
        SMS_ID=$(echo "$NEW_SMS" | awk -F'|' '{print $1}')
        if [ "$SMS_ID" -gt "$SMS_LAST_PROCESSED_ID" ]; then
            ADDRESS=$(echo "$NEW_SMS" | awk -F'|' '{print $2}')
            BODY=$(echo "$NEW_SMS" | awk -F'|' '{print $3}')
            # 发送邮件
            send_email "你有一条新的短信(来自安卓热点机) $ADDRESS" "$BODY"
            SMS_LAST_PROCESSED_ID="$SMS_ID"
        fi
    fi
done
