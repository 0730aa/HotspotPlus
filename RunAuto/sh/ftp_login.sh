#!/system/bin/sh

# FTP 账号密码校验
# tcpsvd 每接到一个连接就单独跑一次这个脚本，脚本的标准输入/输出就是这个连接
# 用法: ftp_login.sh <共享目录> <是否允许上传 true/false>
# 账号密码取自 config.json 的 ftp_setting，校验通过后把连接交给 busybox ftpd

BUSYBOX="${BUSYBOX:-/data/adb/magisk/busybox}"
JQ="${JQ:-/data/adb/modules/HotspotPlus/bin/jq}"
CONFIG_FILE="${CONFIG_FILE:-/data/adb/modules/HotspotPlus/config.json}"
LOG_FILE="${LOG_FILE:-/data/adb/modules/HotspotPlus/log/ftp.log}"

FTP_DIR="$1"
FTP_UPLOAD="$2"

FTP_USER=$("$JQ" -r '.ftp_setting.user // "ftp"' "$CONFIG_FILE")
FTP_PASS=$("$JQ" -r '.ftp_setting.password // ""' "$CONFIG_FILE")

CR=$(printf '\r')

# FTP 的每条响应都要以 \r\n 结尾
send() {
  printf '%s\r\n' "$1"
}

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE" 2>/dev/null
}

send "220 HotspotPlus FTP"

user_ok=0
pass_ok=0
tries=0

while [ $tries -lt 3 ]; do
  IFS= read -r line || exit 0
  line=${line%"$CR"}

  cmd=${line%% *}
  arg=""
  case "$line" in *" "*) arg=${line#* } ;; esac
  cmd=$(echo "$cmd" | tr 'a-z' 'A-Z')

  case "$cmd" in
    USER)
      [ "$arg" = "$FTP_USER" ] && user_ok=1 || user_ok=0
      send "331 Please specify the password"
      ;;
    PASS)
      if [ $user_ok -eq 1 ] && [ "$arg" = "$FTP_PASS" ]; then
        pass_ok=1
        break
      fi
      user_ok=0
      tries=$((tries + 1))
      log "账号或密码错误(第 $tries 次)"
      send "530 Login incorrect"
      ;;
    QUIT)
      send "221 Goodbye"
      exit 0
      ;;
    *)
      # 登录前不接受其他命令。客户端收到 5xx 后会自动降级，比如 AUTH TLS 会退回明文
      send "530 Please login with USER and PASS"
      ;;
  esac
done

if [ $pass_ok -ne 1 ]; then
  send "421 Too many failed login attempts"
  log "校验未通过，已断开连接"
  exit 0
fi

send "230 Login successful"

# 校验通过，把连接交给 busybox ftpd。
# ftpd 启动时自己还会再发一行 220 欢迎信息，这里用 read 把这一行吃掉，
# 否则它会和上面的 230 挤在一起，客户端后面收到的响应就全错位了
exec 3>&1
if [ "$FTP_UPLOAD" = "true" ]; then
  "$BUSYBOX" ftpd -w -A "$FTP_DIR" 2>/dev/null
else
  "$BUSYBOX" ftpd -A "$FTP_DIR" 2>/dev/null
fi | { IFS= read -r _greeting; exec "$BUSYBOX" cat; } >&3
