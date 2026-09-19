#!/system/bin/sh

# FTP 连接前置处理: UTF-8 协商 + 账号密码校验
# tcpsvd 每接到一个连接就单独跑一次这个脚本，脚本的标准输入/输出就是这个连接
# 用法: ftp_login.sh <共享目录> <是否允许上传 true/false>
# 账号密码取自 config.json 的 ftp_setting，处理完再把连接交给 busybox ftpd

BUSYBOX="${BUSYBOX:-/data/adb/magisk/busybox}"
LOG_FILE="${LOG_FILE:-/data/adb/modules/HotspotPlus/log/ftp.log}"

. "${LIB_CFG:-/data/adb/modules/HotspotPlus/RunAuto/sh/lib.sh}"

FTP_DIR="$1"
FTP_UPLOAD="$2"

FTP_USER=$(cfg .ftp_setting.user ftp)
FTP_PASS=$(cfg .ftp_setting.password)

CR=$(printf '\r')

# FTP 的每条响应都要以 \r\n 结尾
send() {
  printf '%s\r\n' "$1"
}

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE" 2>/dev/null
}

upper() {
  echo "$1" | tr 'a-z' 'A-Z'
}

# busybox ftpd 的 FEAT 里没有 UTF8，客户端会以为服务端不支持，
# 于是退回自己系统的编码(中文 Windows 是 GBK)发文件名。
# 这些字节到了只认 UTF-8 的安卓 /sdcard 就成了乱码的 0 字节垃圾文件。
# 所以这里自己答一份带 UTF8 的 FEAT，并接受 OPTS UTF8 ON
feat() {
  printf '211-Features:\r\n UTF8\r\n EPSV\r\n PASV\r\n REST STREAM\r\n MDTM\r\n SIZE\r\n211 End\r\n'
}

send "220 HotspotPlus FTP"

# 没设密码就是免登录(和以前一样)，任何账号密码都放行
if [ -n "$FTP_PASS" ]; then
  need_auth=1
else
  need_auth=0
fi

pass_ok=0
user_ok=0
tries=0

while [ $tries -lt 3 ]; do
  IFS= read -r line || exit 0
  line=${line%"$CR"}

  cmd=${line%% *}
  arg=""
  case "$line" in *" "*) arg=${line#* } ;; esac
  cmd=$(upper "$cmd")

  case "$cmd" in
    FEAT)
      feat
      ;;
    OPTS)
      case "$(upper "$arg")" in
        "UTF8 ON"|"UTF-8 ON"|UTF8|UTF-8) send "200 UTF8 mode enabled" ;;
        *) send "501 Option not supported" ;;
      esac
      ;;
    USER)
      if [ $need_auth -eq 0 ] || [ "$arg" = "$FTP_USER" ]; then
        user_ok=1
      else
        user_ok=0
      fi
      send "331 Please specify the password"
      ;;
    PASS)
      if [ $user_ok -eq 1 ] && { [ $need_auth -eq 0 ] || [ "$arg" = "$FTP_PASS" ]; }; then
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

# 交给 busybox ftpd。出口再过一道 awk:
#   1) 吃掉 ftpd 自己那行 220 欢迎信息，否则会和上面的 230 挤在一起，客户端响应全错位
#   2) 给 ftpd 的 FEAT 响应补上 UTF8(有些客户端是登录之后才问 FEAT 的)
# fflush 保证逐行立即送出，不会因为缓冲把协议卡住
exec 3>&1
if [ "$FTP_UPLOAD" = "true" ]; then
  "$BUSYBOX" ftpd -w -A "$FTP_DIR" 2>/dev/null
else
  "$BUSYBOX" ftpd -A "$FTP_DIR" 2>/dev/null
fi | {
  IFS= read -r _greeting
  exec "$BUSYBOX" awk '{ print; fflush() } /^211-Features:/ { printf " UTF8\r\n"; fflush() }'
} >&3
