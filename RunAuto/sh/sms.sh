#!/system/bin/sh
CONFIG_FILE="/data/adb/modules/HotspotPlus/config.json"

get_config_value() {
    local key="$1"
    local value
    value=$(cat "$CONFIG_FILE" | /data/adb/modules/HotspotPlus/bin/jq -r "$key" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "Error: Failed to get config value for key: $key" >&2
        return 1
    fi
    echo "$value"
}

SMS_FORWARDING_ENABLED=$(get_config_value '.sms_forwarding_enabled')
if [ $? -ne 0 ]; then
    echo "Error: Failed to read SMS forwarding settings" >&2
    exit 1
fi

export PREFIX=/data/user/0/bin.mt.plus/files/term
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$PREFIX/lib:/data/adb/modules/HotspotPlus/RunAuto/bin:/data/adb/modules/HotspotPlus/bin
echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"

if [ "$SMS_FORWARDING_ENABLED" != "true" ]; then
    echo "短信转发功能已禁用。"
    exit 0
fi

SMS_DB_PATH="/data/data/com.android.providers.telephony/databases/mmssms.db"

# 读取配置并检查错误
WEBHOOK_URL=$(get_config_value '.webhook.url')
TLS=$(get_config_value '.smtp_setting.defaults.tls')
TLS_TRUST_FILE=$(get_config_value '.smtp_setting.defaults.tls_trust_file')
LOGFILE=$(get_config_value '.smtp_setting.defaults.logfile')
ACCOUNT_NAME=$(get_config_value '.smtp_setting.account.name')
SMTP_SERVER=$(get_config_value '.smtp_setting.account.host')
SMTP_PORT=$(get_config_value '.smtp_setting.account.port')
AUTH=$(get_config_value '.smtp_setting.account.auth')
EMAIL=$(get_config_value '.smtp_setting.account.user')
PASSWORD=$(get_config_value '.smtp_setting.account.password')
FROM=$(get_config_value '.smtp_setting.account.from')
TO_EMAIL=$(get_config_value '.smtp_setting.email_settings.to_email')

# 输出配置检查
echo "Configuration check:"
echo "WEBHOOK_URL: $WEBHOOK_URL"
echo "SMTP_SERVER: $SMTP_SERVER"
echo "EMAIL: $EMAIL"
echo "TO_EMAIL: $TO_EMAIL"

send_webhook() {
    local phone="$1"
    local message="$2"
    local json_data="{\"msgtype\":\"text\",\"text\":{\"content\":\"发送人号码: $phone\n短信内容: $message\"}}"
    
    echo "Sending webhook request to: $WEBHOOK_URL"
    /data/user/0/bin.mt.plus/files/term/bin/curl "$WEBHOOK_URL" \
        -H 'Content-Type: application/json' \
        -d "$json_data"
}

send_email() {
    local subject="$1"
    local body="$2"
    echo "Sending email to: $TO_EMAIL"
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
            
            if [ -n "$WEBHOOK_URL" ]; then
                send_webhook "$ADDRESS" "$BODY"
            fi
            
            send_email "你有一条新的短信(来自安卓热点机) $ADDRESS" "$BODY"
            SMS_LAST_PROCESSED_ID="$SMS_ID"
        fi
    fi
done