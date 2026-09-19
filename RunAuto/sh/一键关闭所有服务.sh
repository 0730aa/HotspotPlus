#!/system/bin/sh
# 执行后关闭本模块拉起的所有服务: frpc、cron 定时任务、ftp、telnet、短信转发、adb

BB="/data/adb/magisk/busybox"

# kill_match <名称> <ps 里的匹配正则>
kill_match() {
  # 排除自己和调用自己的那个进程，避免命令行里正好带上关键字时把自己杀掉
  pids=$("$BB" ps 2>/dev/null | grep -E "$2" | grep -v '一键关闭' \
         | awk -v me="$$" -v pp="$PPID" '$1 != me && $1 != pp {print $1}')
  if [ -n "$pids" ]; then
    kill -9 $pids 2>/dev/null
    echo "已停止 $1"
  else
    echo "$1 未在运行"
  fi
}

pkill -9 -x frpc 2>/dev/null && echo "已停止 frpc" || echo "frpc 未在运行"
kill_match "cron 定时任务" '[c]rond'
kill_match "telnet"        '[t]elnetd'
kill_match "ftp"           '[t]cpsvd|[f]tpd|[f]tp_login'
kill_match "短信转发"      '[s]ms\.sh'

stop adbd
echo "已关闭 adb 端口"
