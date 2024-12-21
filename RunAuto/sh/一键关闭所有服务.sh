#!/system/bin/sh

# 注意，此文件执行后将关闭 frpc，cron定时任务，ftp，telnet，adb
pkill -9 -x frpc
sleep 1
kill -9 $(cat /data/adb/modules/HotspotPlus/bin/pid_file.txt) && rm -f /data/adb/modules/HotspotPlus/bin/pid_file.txt
sleep 1
kill -9 $(/data/adb/magisk/busybox ps | grep '[c]rond' | awk '{print $1}')
sleep 1
kill -9 $(/data/adb/magisk/busybox ps | grep '[t]elnetd' | awk '{print $1}')
sleep 1
kill -9 $(/data/adb/magisk/busybox ps | grep '[t]cpsvd' | awk '{print $1}')
sleep 1
pkill -9 -x inotifywait
sleep 1
stop adbd