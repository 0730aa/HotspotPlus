#!/system/bin/sh
CONFIG_FILE="/data/adb/modules/autofrp/config.json"
# 获取配置文件的值
START_ADB=$(cat $CONFIG_FILE | grep -o '"start_adb": *true' | wc -l)
ADB_PORT=$(cat $CONFIG_FILE | grep -o '"adb_port": *[0-9]*' | grep -o '[0-9]*')
START_TELNET=$(cat $CONFIG_FILE | grep -o '"start_telnet": *true' | wc -l)
START_FTP=$(grep -o '"start_ftp": *true' $CONFIG_FILE | wc -l)

if [ $START_ADB -eq 1 ]; then
  stop adbd
  setprop service.adb.tcp.port $ADB_PORT
  start adbd
  echo "ADB 已开启，端口号: $ADB_PORT"
else
  echo "ADB 已关闭"
  stop adbd
fi

if [ $START_TELNET -eq 1 ]; then
  /data/adb/magisk/busybox telnetd -l /system/bin/sh
  echo "telnet 已开启，端口号为 23"
else
  echo "telnet 未开启"
fi

if [ $START_FTP -eq 1 ]; then
    /data/adb/magisk/busybox tcpsvd -vE 0.0.0.0 21 /data/adb/magisk/busybox ftpd -wA / &
    echo "FTP 已开启"
else
    echo "FTP 未开启"
fi