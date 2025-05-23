#!/system/bin/sh
# 禁用 打瞌睡 模式（需要禁用请自行把注释删了）
# dumpsys deviceidle disable
# 终止 frpc 进程
pkill -9 -x frpc
# 后台运行 frp内网穿透
setsid /data/adb/modules/HotspotPlus/frp/frpc -c /data/adb/modules/HotspotPlus/frp/frpc.toml &
# 获取frpc进程pid
pid=$(pgrep frpc)
# 添加frpc进程pid到cpu核心组
echo $pid >/dev/cpuset/top-app/tasks
echo $pid >/dev/cpuset/top-app/cgroup.procs
echo $pid >/dev/stune/top-app/tasks
echo $pid >/dev/stune/top-app/cgroup.procs
# 绑定frpc进程pid到cpu核心使用
taskset -ap 0xff $pid
# 调整frpc进程pid调度优先级
chrt -f -p 99 $pid
renice -n -20 -p $pid