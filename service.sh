#!/system/bin/sh
MODDIR=${0%/*}

# 等待系统初始化完成
until [ "$(getprop sys.boot_completed)" -eq 1 ] ; do
    sleep 5
done

# 确保所有服务已启动
sleep 20

# 终止 crond 进程
pkill -9 -x busybox crond

# 获取满权限
chmod -R 777 /data/adb/modules/autofrp

# 确保权限设置生效
sleep 5

# 计划任务守护进程
/data/adb/magisk/busybox crond -c /data/adb/modules/autofrp/RunAuto/crontabs

sleep 5

# 运行 additional 文件
/data/adb/modules/autofrp/RunAuto/sh/additional.sh

sleep 5

# 开机首次启动 frpc
/data/adb/modules/autofrp/frp/一键启动.sh
