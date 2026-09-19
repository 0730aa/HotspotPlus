#!/system/bin/sh

MODULE_DIR="/data/adb/modules/HotspotPlus"
PACKAGE="com.android.mms"
CONFIG="$MODULE_DIR/config.json"
LOG_FILE="$MODULE_DIR/log/sms.log"
LF="$MODULE_DIR/log/last_sms.txt"
PUSH_BIN="$MODULE_DIR/bin/push_arm64"

mkdir -p "$MODULE_DIR/log"
echo "=== 短信转发服务（全平台版）启动 ===" > "$LOG_FILE"
> "$LF"

. "$MODULE_DIR/RunAuto/sh/lib_cfg.sh"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 统一推送
send_all() {
  local title="$1"
  local content="$2"
  local msg="【短信转发】$title | $content"

  log "转发短信：$title | $content"

  # Webhook（企业微信/钉钉/飞书
  if [ -n "$WEBHOOK_URL" ] && [ "$WEBHOOK_URL" != "null" ]; then
    "$PUSH_BIN" webhook "$WEBHOOK_URL" "$msg"
    log "Webhook 推送完成"
  fi

  # SMTP 邮件（全邮箱通用
  if [ -n "$SMTP_HOST" ] && [ "$SMTP_HOST" != "null" ]; then
    "$PUSH_BIN" smtp "$SMTP_HOST" "$SMTP_PORT" "$SMTP_USER" "$SMTP_PASS" "$SMTP_FROM" "$SMTP_TO" "短信通知" "$msg"
    log "SMTP 邮件推送完成"
  fi
}

monitor() {
  local sms_enabled=$(cfg .sms_forwarding_enabled false)
  if [ "$sms_enabled" != "true" ]; then
    log "短信转发开关已关闭，退出监控进程"
    exit 0
  fi

  log "开始监听短信..."
  dumpsys notification --noredact | grep -A 50 "pkg=$PACKAGE" | grep -o "key=[^ ]*" | head -3 >> "$LF"

  while true; do
    # 每次循环都重新读取开关，支持运行中动态关闭
    local current_enabled=$(cfg .sms_forwarding_enabled false)
    if [ "$current_enabled" != "true" ]; then
      log "检测到短信转发开关已关闭，停止监控"
      exit 0
    fi

    current=$(dumpsys notification --noredact | grep -A 50 "pkg=$PACKAGE")
    key=$(echo "$current" | grep -o "key=[^ ]*" | head -n1)

    if ! grep -qF "$key" "$LF"; then
      echo "$key" >> "$LF"

      title=$(echo "$current" | grep -A 2 "android.title" | sed -n 's/.*String.\([^"]*\).*/\1/p' | head -n1)
      text=$(echo "$current" | grep -A 10 "android.text" | sed -n 's/.*String.\([^"]*\).*/\1/p' | head -n1)

      title=${title:-未知号码}
      text=${text:-空内容}

      send_all "$title" "$text"
    fi
    sleep 2
  done
}

# ----------------------
# 初始化配置（移到日志后，避免未初始化就读取）
# ----------------------
SMS_ENABLED=$(cfg .sms_forwarding_enabled false)
WEBHOOK_URL=$(cfg .webhook.url)
SMTP_HOST=$(cfg .smtp_setting.account.host)
SMTP_PORT=$(cfg .smtp_setting.account.port 587)
SMTP_USER=$(cfg .smtp_setting.account.user)
SMTP_PASS=$(cfg .smtp_setting.account.password)
SMTP_FROM=$(cfg .smtp_setting.account.from)
SMTP_TO=$(cfg .smtp_setting.email_settings.to_email)

# 全局开关校验：启动时直接判断，关闭则不进入监控
if [ "$SMS_ENABLED" != "true" ]; then
  log "短信转发总开关为关闭状态，服务不启动"
  exit 0
fi

# 信号捕获
trap "log '服务停止'; exit" INT TERM
# 启动监控
monitor