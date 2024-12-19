# 说明
1. 本模块已经配置 frpc 相关基础服务，请在刷入前自行修改 frp/frpc.toml 里面的服务器IP地址和端口 (不保证 frp 是最新版本，需要使用最新版请自行前往 frp 官网下载)

2. 本模块包含安卓frpc端开机自动启动和定时启动模块。由于在我的红米安卓12上有不确定因素（好像断网一会之后frp就挂了，故需要搭配定时启动。不需要可自行关闭定时启动，留一个开机自启就好。）

3. 定时启动的配置文件可在模块目录下的 config.json 这个文件里面编辑,编辑完成后手动执行 cron_update.sh 立即生效，或者重启生效。

4. adb 端口，ftp 服务，telnet 服务开关配置也在模块目录下的 config.json

5. 附加功能(天玑处理器)，检测热点状态，保持热点常开(默认关闭)

6. frp 更多特性请自主前往官网查看，https://github.com/fatedier/frp


# 使用方法
1. 下载 HotspotPlus 模块

2. 下载完之后不要马上刷入，先把里面的 readme.md 看完，重点是修改里面的 frp/frpc.toml 服务器地址和端口（如果有需要的话）。本模块不保证 frp 最新版，需要最新版请自行下载后放入 frp 文件夹下即可。

3. adb，ftp，telnet ，热点，USB网络共享服务开启只需在 config.json 里设置就好（部分服务默认打开）

4. 热点检测（默认关闭），用于检测天玑处理器手机的热点状态，如果检测到关闭，则开启飞行模式（是否开启飞行模式是可选的，在 config 里面开启或者关闭，默认关闭）并延时15s后关闭飞行模式，之后将执行打开热点命令来确保热点常开。

5. USB共享网络检测(默认关闭)，通过定时检测手机USB共享网络是否打开，关闭则执行打开命令

6. 短信转发功能--按照注释来填写就好

7. 本模块已经下载并配置好一些frpc基础服务，需要更新frp最新版本请自行下载替换。

**注意事项**：模块电脑编辑有 bug 还是格式问题不知道，编辑后导致刷入时显示 error unzip 。所以请在安卓手机上编辑。

# 一些你可能需要了解的 sh 文件
1. additional.sh 是用来执行 adb，ftp，telnet 之类的，非必要不用修改

2. cron_update.sh 是用来更新定时规则的，当你修改完 config.json 里面的定时规则 cron_jobs 后可以执行这个脚本将立即生效。

3. frpc.sh 用来执行frpc的启动

4. test.sh 用来检测 cron 是否正常（通过 cron 定时运行 test.sh），在 frpc 挂了很久也不起来可以开启 test 检测。

5. keepfrpc.sh 用于检测 frpc 进程是否存在，若不存在则执行启动 frpc 命令

6. hotspot_status.sh 是热点状态检测。效果：当检测到热点关闭时，会执行这个脚本开关飞行模式之后执行打开热点的操作。并在模块目录的 log 下生成一个 log 文件:当热点打开时，不做任何动作，只输出日志 log

7. rndis_status.sh 是 USB 共享网络状态检测，通过 ifconfig 命令检测。

8. sms.sh 是提供短信转发服务，运行后会一直在监听本机短信库的ID，当有新的短信到来时，会通过 smtp 转发到接受者的邮箱账号上。

# 参考工具
本模块内置了 jq 工具来读取处理 json 文件，更多详情前往 https://github.com/jqlang/jq 查看

短信转发参考工具 inotifywait、msmtp、sqlite3 

frpc 更多特性详情查看官网 https://github.com/fatedier/frp

# 更新日志


- **HotspotPlus_v6.3**

   1. 新增短信转发功能，通过 smtp 发送到相应的邮箱

- **HotspotPlus_v6.0**

   1. 新增开关控制，在面具那里点击启用或者关闭模块就可以控制
       - 也可以在模块目录下的sh文件夹里一键打开和关闭的脚本
   2. additional 文件更改逻辑

- **HotspotPlus_v5.8**

  1. config 新增 热点检测中是否需要开关飞行模式的选项

- **HotspotPlus_v5.7**

   1. 修复了部分系统adb端口读取不到
      - 全部采用 jq 解析

- **HotspotPlus_v5.6**

   1. 修复了热点模式一某些场景下出现打开失败的bug
   2. 再次缩短各种服务启动的等待时间
      
- **HotspotPlus_v5.5**

   1. 新增手机热点的开机自启动选项（两种模式）
   2. 精简化热点检测脚本（随 config 选择的模式而操作）
   3. 缩短开机后脚本执行等待的各种时间
   4. 修改了 sed 筛选规则，保证其他系统的兼容性

- **HotspotPlus_v5.3**

   1. 添加 USB 网络共享模式的开机自启动选项（config里面打开）
        - 配置请在 config.json 里面打开(默认关闭)
   2. 开机log增加 additional 的相关服务是否开启的 log
   3. 完善了相关服务的注释
- **HotspotPlus_v5.2**
1. 添加 usb 网络共享 状态检测脚本
    - 启用和定时规则均在 config 文件里面。
    - 通过 ifconfig 检测 rndis，从而实现 usb 共享网络保持常开
    - 该功能默认关闭,需要启用请自行打开
2. 修正开机自启服务 log 输出，并添加 frpc 的 log 输出

- **HotspotPlus_v5.0**

**本模块从这个版本开始改名为 HotspotPlus（热点机模块）**
**由于改动较大，刷入前请删除旧版本模块**

1. 添加 keepfrpc 状态检测脚本
    - 现在不再定时运行 frpc 服务，而是通过 pid 检测 frpc 进程是否存在，如果不存在才重新启动。
    - 优化了逻辑，不再一味的运行 frpc
2. 简化 log 输出
    - 所有的 log 使用覆盖式输出
3. 热点状态检测完善
    - 通过解锁手机实现热点打开，不再依赖 xposededge
4. config 配置更新了部分定时规则时间
    - 由于 frpc 采用了新的检测方式，所以把时间改小
5. 移除 edgefrp.sh
6. 更新所有的路径，还有部分变量。

- **frpc自启动v4.2**
   
   - 修正 readme

- **frpc自启动v3.9**

   - 更新 frpc 到 v0.58.1
   - 修正 readme

- **frpc自启动v3.7**

   - 引入 jq 工具检索 config
   - config 文件配置新增定时规则设置
   - 新增 cron_update
   - 新增 service log 日志输出
   


- **frpc自启动v3.1**

   - 修改 magisk 模块的一些书写格式
   - 修改部分文件名和路径
   - 完善模块一些相关说明
   - 精简部分脚本内容


- **frpc自启动v2.6**

   - 修复了本模块 magisk 的更新逻辑
   - 一键启动脚本中将禁用打瞌睡模式的功能注释掉 


- **frpc自启动v2.4**

   - 修正文件路径
   - 添加 config.json 和 adb.sh 配置文件
   - 添加 log 路径，log 不再输出到内存目录下，而是模块的 log 目录下对应文件
   - 添加 adb端口开启，ftp 开启，telent 开启的功能


- **frpc自启动v1.0（已废弃，路径没改）**

   - 配置 frpc 功能
   - 写入常用 frpc 端口
   - 添加热点检测功能
