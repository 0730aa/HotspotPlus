#!/system/bin/sh
# ============================================================================
# sms.sh —— 新短信转发(webhook / 邮件)
#
# 取短信有两种方式，启动时自动选:
#   db           直接查系统短信库 content://sms/inbox (推荐)
#                不挑短信应用、不依赖通知，通知被关掉、免打扰、锁屏也照样能转发
#   notification 退而求其次，解析系统通知
#                只在查不了短信库时才用，短信应用包名自动识别，不再写死
#
# 以前写死了 PACKAGE="com.android.mms"，只要手机默认短信应用不是这个包名
# (谷歌 Messages、三星、部分 MIUI 等)，就一条都转发不出去，这次修掉
# ============================================================================

MODULE_DIR="/data/adb/modules/HotspotPlus"
LOG_FILE="$MODULE_DIR/log/sms.log"
STATE="$MODULE_DIR/log/sms_state.txt"
PUSH_BIN="$MODULE_DIR/bin/push_arm64"

mkdir -p "$MODULE_DIR/log"
echo "=== 短信转发服务启动 ===" > "$LOG_FILE"

. "$MODULE_DIR/RunAuto/sh/lib.sh"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# ---------------------------------------------------------------- 推送
send_all() {
  title="$1"
  content="$2"
  msg="【短信转发】$title | $content"

  log "转发短信：$title | $content"

  if [ -n "$WEBHOOK_URL" ]; then
    "$PUSH_BIN" webhook "$WEBHOOK_URL" "$msg" >/dev/null 2>&1
    log "Webhook 推送完成"
  fi

  if [ -n "$SMTP_HOST" ]; then
    "$PUSH_BIN" smtp "$SMTP_HOST" "$SMTP_PORT" "$SMTP_USER" "$SMTP_PASS" "$SMTP_FROM" "$SMTP_TO" "短信通知" "$msg" >/dev/null 2>&1
    log "SMTP 邮件推送完成"
  fi
}

enabled() {
  [ "$(cfg .sms_forwarding_enabled false)" = "true" ]
}

# ------------------------------------------------- 方式一: 直接查短信库
# 收件箱里的 _id 列表，从新到旧
sms_ids() {
  content query --uri content://sms/inbox --projection _id --sort "_id DESC" 2>/dev/null \
    | sed -n 's/^Row: [0-9]* _id=\([0-9][0-9]*\).*$/\1/p'
}

# 取某条短信的某一列。短信正文可能有换行，所以只去掉第一行的前缀，其余原样保留
sms_field() {
  content query --uri content://sms/inbox --projection "$2" --where "_id=$1" 2>/dev/null \
    | sed "1s/^Row: [0-9]* $2=//"
}

db_available() {
  content query --uri content://sms/inbox --projection _id --sort "_id DESC" >/dev/null 2>&1
}

monitor_db() {
  last=$(sms_ids | head -1)
  [ -z "$last" ] && last=0
  echo "$last" > "$STATE"
  log "方式: 直接查短信库，当前最新短信 _id=$last，之后的新短信才会转发"

  while enabled; do
    # 只看最新的 20 条，够用且省事
    ids=$(sms_ids | head -20 | awk -v l="$last" '$1 > l' | sort -n)
    for id in $ids; do
      addr=$(sms_field "$id" address)
      body=$(sms_field "$id" body)
      [ -z "$addr" ] && addr="未知号码"
      [ -z "$body" ] && body="空内容"
      send_all "$addr" "$body"
      last="$id"
      echo "$last" > "$STATE"
    done
    sleep "$POLL"
  done
}

# --------------------------------------------- 方式二: 解析系统通知(兜底)
# 自动识别默认短信应用的包名，识别不出来就按关键字匹配
sms_package() {
  p=$(cmd role get-role-holders android.app.role.SMS 2>/dev/null | tr -d '[]' | tr ',' '\n' | head -1)
  [ -z "$p" ] && p=$(settings get secure sms_default_application 2>/dev/null)
  p=${p%%/*}
  case "$p" in
    ''|null) p="" ;;
  esac
  echo "$p"
}

monitor_notification() {
  pkg=$(sms_package)
  if [ -n "$pkg" ]; then
    log "方式: 解析系统通知，短信应用包名 $pkg"
    filter="pkg=$pkg"
  else
    log "方式: 解析系统通知，未能识别短信应用包名，改用关键字匹配"
    filter="pkg=.*\(mms\|messag\|sms\)"
  fi

  seen="$MODULE_DIR/log/sms_seen.txt"
  : > "$seen"
  dumpsys notification --noredact 2>/dev/null | grep -A 50 "$filter" | grep -o "key=[^ ]*" | head -3 >> "$seen"

  while enabled; do
    current=$(dumpsys notification --noredact 2>/dev/null | grep -A 50 "$filter")
    key=$(echo "$current" | grep -o "key=[^ ]*" | head -n1)

    if [ -n "$key" ] && ! grep -qF "$key" "$seen"; then
      echo "$key" >> "$seen"
      title=$(echo "$current" | grep -A 2 "android.title" | sed -n 's/.*String.\([^"]*\).*/\1/p' | head -n1)
      text=$(echo "$current" | grep -A 10 "android.text" | sed -n 's/.*String.\([^"]*\).*/\1/p' | head -n1)
      send_all "${title:-未知号码}" "${text:-空内容}"
    fi
    sleep "$POLL"
  done
}

# ---------------------------------------------------------------- 启动
WEBHOOK_URL=$(cfg .webhook.url)
SMTP_HOST=$(cfg .smtp_setting.account.host)
SMTP_PORT=$(cfg .smtp_setting.account.port 587)
SMTP_USER=$(cfg .smtp_setting.account.user)
SMTP_PASS=$(cfg .smtp_setting.account.password)
SMTP_FROM=$(cfg .smtp_setting.account.from)
SMTP_TO=$(cfg .smtp_setting.email_settings.to_email)
POLL=$(cfg .sms_setting.poll_seconds 5)
METHOD=$(cfg .sms_setting.method auto)

case "$POLL" in
  ''|*[!0-9]*) POLL=5 ;;
esac

if ! enabled; then
  log "短信转发总开关为关闭状态，服务不启动"
  exit 0
fi

if [ -z "$WEBHOOK_URL" ] && [ -z "$SMTP_HOST" ]; then
  log "webhook 和 smtp 都没有配置，转发出去也没有去处，服务不启动"
  exit 0
fi

trap 'log "服务停止"; exit 0' INT TERM

case "$METHOD" in
  db)
    monitor_db
    ;;
  notification)
    monitor_notification
    ;;
  *)
    if db_available; then
      monitor_db
    else
      log "短信库读不了(可能是系统限制)，改用通知方式"
      monitor_notification
    fi
    ;;
esac

log "短信转发开关已关闭，监控退出"
