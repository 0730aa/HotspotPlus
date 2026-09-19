#!/system/bin/sh
# 停止 frpc (这个文件原来是空的，执行了等于没执行)
pkill -9 -x frpc && echo "frpc 已停止" || echo "frpc 本来就没在运行"
