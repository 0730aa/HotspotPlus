# 使用说明

1. 本模块已经配置 frpc 相关服务，请在刷入前自行修改 autorun_sh/frp 里面的服务器IP地址和端口

2. 本模块为安卓frpc端开机自动启动和定时启动模块。由于在我的红米安卓12上有不确定因素（好像断网一会之后frp就挂了，故需要搭配定时启动。不需要可自行关闭定时启动，留一个开机自启就好。）

3. 定时启动的配置文件在模块的 autorun_sh/crontabs/root 这个文件里面编辑

4. adb 端口，ftp 服务，telnet 服务开关配置在模块目录下的 config.json

5. 附加功能(天玑处理器)，检测热点状态，保持热点常开(默认关闭，需要使用请自行前往autorun_sh/crontabs/root下把注释删了)

# 更新日志

- **frpc自启动v3.7**

   引入 jq 工具检索 config
   config 文件配置新增定时规则设置
   新增 cron_update
   新增 service log 日志输出
   


- **frpc自启动v3.1**

   修改 magisk 模块的一些书写格式
   修改部分文件名和路径
   完善模块一些相关说明
   精简部分脚本内容


- **frpc自启动v2.6**

   修复了本模块 magisk 的更新逻辑
   一键启动脚本中将禁用打瞌睡模式的功能注释掉 


- **frpc自启动v2.4**

   修正文件路径
   添加 config.json 和 adb.sh 配置文件
   添加 log 路径，log 不再输出到内存目录下，而是模块的 log 目录下对应文件
   添加 adb端口开启，ftp 开启，telent 开启的功能


- **frpc自启动v1.0（已废弃，路径没改）**

   配置 frpc 功能
   写入常用 frpc 端口
   添加热点检测功能
