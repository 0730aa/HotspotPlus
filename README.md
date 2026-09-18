# 使用说明

0. 所有功能的开启与关闭均可在模块目录下的 config.json 里面设置开关

1. 本模块已经配置 frpc 相关服务，请在刷入前自行修改 frp/frpc.toml 里面的服务器IP地址和端口（如果服务器端设置了密码或者加密配置，请自行添加相关配置。默认配置为无密码无加密!!!）

2. 定时启动的配置文件可在模块目录下的 config.json 这个文件里面编辑,编辑完成后手动执行 cron_update.sh 立即生效，或者重启生效。

3. 开机自启服务: adb 端口、ftp 服务、telnet 服务、手机热点、USB网络共享服务，这些的开关配置也在模块目录下的 config.json

4. 增加检测热点状态脚本，保持热点常开(默认关闭，配置同样在 config.json 里面)

5. frp 更多特性请自主前往官网查看，https://github.com/fatedier/frp

6. 更新比较快的通道是蓝奏云，请自行前往查看是否需要更新 https://wwm.lanzouo.com/b00g2dgwmd

7. 贡献: 请在 github 项目上给我点⭐️😘 https://github.com/0730aa/HotspotPlus

# 更新日志


- **HotspotPlus_v8.1**

      1. 新增通用开热点方式 api（在 config.json 把 start_ap 设为 "api"）：通过 app_process 直接经 ServiceManager 调用系统 connectivity 服务的 startTethering，开的是与系统"个人热点"同源、带网络共享的真热点，SSID/密码沿用系统设置。不依赖屏幕/分辨率/语言，且规避了 MIUI 等 ROM 在获取 Context 阶段的崩溃（适配 Android 7~10）
      2. 分层回退：api(binder) 失败 -> cmd wifi start-softap(仅 Android 11+) -> uiautomator 精确点击(含 MIUI SlidingButton)，每层都用 ap0 检测是否成功
      3. 目的：解决部分机型模式一/模式二都打不开热点的问题，提升机型通用性（注：安卓热点受 ROM 定制影响大，无法保证 100% 全机型，若失败请查看 log/open_hotspot.log 反馈）

- **HotspotPlus_v7.9**

      1. AI 优化短信转发，整合一个工具
      2. 移除 curl，openssl 等文件
      3. 修改热点模式一兼容性（默认选择模式一）

- **HotspotPlus_v7.7**

      1. 优化短信监控转发内容，减少垃圾短信

- **HotspotPlus_v7.6**

      1. 通过短信通知来获取短信内容

- **HotspotPlus_v7.4**

   1. 更新短信获取方式，适配更多情况


- **HotspotPlus_v7.0**（无需依赖termux转发短信）

   1. 添加模块需要的lib库，短信转发不再依赖termux


- **HotspotPlus_v6.8**

   1. 增加了一些关于 frpc 配置文件的参数
   2. 热点模式默认更改为模式二
   

- **HotspotPlus_v6.7**(短信转发功能依赖termux app的lib库，自己手机安装有即可无需后台运行)

   1. 新增转发方式 Webhook，目前已测试企业微信机器人和钉钉机器人（关键词模式）
   2. 简化全部文件内容，config 删掉所有注释，新增 示例文件.json 参考对比修改 config.json。
   
- **HotspotPlus_v6.4**

   1. 不好意思，上个版本忘记放个东西了

- **HotspotPlus_v6.3**

   1. 新增短信转发功能，通过 smtp 发送到相应的邮箱

- **HotspotPlus_v6.0**

   1. 新增开关控制，在面具那里点击启用或者关闭模块就可以控制
     - 也可以在模块目录下的sh文件夹里一键打开和关闭的脚本
   2. additional 文件更改逻辑

- **HotspotPlus_v5.8**

   1. config 新增 定时热点检测是否需要开 飞行模式 的选择
   

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

   1. 添加 rndis USB 网络共享检测脚本
        - 配置请在 config.json 里面打开(默认关闭)
   2. 开机log增加 frpc 的错误日志
- **HotspotPlus_v5.0**

     **本模块从这个版本开始改名为 热点机模块(HotspotPlus)**

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

   1. 修改部分逻辑
   2. 修正 readme


- **frpc自启动v3.9**

   1. 更新 frpc 到 v0.58.1
   2. 修正 readme

- **frpc自启动v3.7**

   1. 引入 jq 工具检索 config
   2. config 文件配置新增定时规则设置
   3. 新增 cron_update
   4. 新增 service log 日志输出

- **frpc自启动v3.1**

   1. 修改 magisk 模块的一些书写格式
   2. 修改部分文件名和路径
   3. 完善模块一些相关说明
   4. 精简部分脚本内容


- **frpc自启动v2.6**

   1. 修复了本模块 magisk 的更新逻辑
   2. 一键启动脚本中将禁用打瞌睡模式的功能注释掉 


- **frpc自启动v2.4**

   1. 修正文件路径
   2. 添加 config.json 和 adb.sh 配置文件
   3. 添加 log 路径，log 不再输出到内存目录下，而是模块的 log 目录下对应文件
   4. 添加 adb端口开启，ftp 开启，telent 开启的功能


- **frpc自启动v1.0（已废弃，路径没改）**

   1. 配置 frpc 功能
   2. 写入常用 frpc 端口
   3. 添加热点检测功能
