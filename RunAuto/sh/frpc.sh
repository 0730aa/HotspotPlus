#!/system/bin/sh
# frpc 启动(会先杀掉已有的 frpc 再重新起)
# frp/一键启动.sh 和 check.sh frpc 都统一调这里，不再各写一份

MODDIR="/data/adb/modules/HotspotPlus"

# 禁用 打瞌睡 模式（需要禁用请自行把注释删了）
# dumpsys deviceidle disable

pkill -9 -x frpc
setsid "$MODDIR/frp/frpc" -c "$MODDIR/frp/frpc.toml" >/dev/null 2>&1 &

sleep 1
pid=$(pgrep -x frpc | head -1)
[ -z "$pid" ] && { echo "frpc 启动失败，请检查 frp/frpc.toml"; exit 1; }

# 放进前台 cgroup + 绑核 + 提高调度优先级，降低被系统回收的概率
for f in /dev/cpuset/top-app/tasks /dev/cpuset/top-app/cgroup.procs \
         /dev/stune/top-app/tasks /dev/stune/top-app/cgroup.procs; do
  [ -w "$f" ] && echo "$pid" > "$f" 2>/dev/null
done
taskset -ap 0xff "$pid" >/dev/null 2>&1
chrt -f -p 99 "$pid" >/dev/null 2>&1
renice -n -20 -p "$pid" >/dev/null 2>&1

echo "frpc 已启动 (pid=$pid)"
