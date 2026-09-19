# 使用说明

0. 所有功能的开启与关闭均可在模块目录下的 config.json 里面设置开关

1. 本模块已经配置 frpc 相关服务，请在刷入前自行修改 frp/frpc.toml 里面的服务器IP地址和端口（如果服务器端设置了密码或者加密配置，请自行添加相关配置。默认配置为无密码无加密!!!）

2. 定时启动的配置文件可在模块目录下的 config.json 这个文件里面编辑,编辑完成后手动执行 cron_update.sh 立即生效，或者重启生效。

3. 开机自启服务: adb 端口、ftp 服务、telnet 服务、手机热点、USB网络共享服务，这些的开关配置也在模块目录下的 config.json（手机热点默认使用通用方式 api，start_ap 可改）
     - ftp 的共享目录、端口、是否允许上传、账号密码都在 config.json 的 ftp_setting 里设置。默认只共享 /sdcard(手机内部存储)，如果确实需要共享整个系统再把 dir 改成 "/"
     - ftp 的 password 留空就是免登录(和以前一样)，填了密码就要用 user + password 登录

4. 增加检测热点状态脚本，保持热点常开(默认关闭，配置同样在 config.json 里面)
     - 三个定时检测(热点/USB共享/frpc)已合并为一个 check.sh，分别是 `check.sh ap`、`check.sh usb`、`check.sh frpc`。旧 config.json 里写的旧文件名会被 cron_update.sh 自动映射，不用改
     - 每个检测都会先看 config.json 里对应的总开关，开关是关的就什么都不做。比如只想用 frp、把 start_ap 设成 false，热点检测就不会再去切飞行模式或开热点
     - ap_keep_alive(默认 true) 会关掉系统自带的"热点没有设备连接就自动关闭"，解决热点没人连一会儿就自己关掉的问题

5. 热点开启方式说明: 推荐用 api(默认)
     - api 走的是系统的网络共享(tethering)，和你在设置里手动开热点是同一套东西，连上的设备能正常上网，IPv6 是否可用取决于运营商和 ROM
     - mode2 用的 `cmd wifi start-softap` 起的是"本地热点"，不会启动系统的网络共享流程，所以部分机型会出现连上了没网、或者没有 IPv6 的情况。遇到这种情况请改用 api

6. frp 更多特性请自主前往官网查看，https://github.com/fatedier/frp

7. 更新比较快的通道是蓝奏云，请自行前往查看是否需要更新 https://wwm.lanzouo.com/b00g2dgwmd

8. 贡献: 请在 github 项目上给我点⭐️😘 https://github.com/0730aa/HotspotPlus

# 更新日志


- **HotspotPlus_v8.5**

      1. 修复 ap_keep_alive 不生效(热点没人连还是会自动关闭，系统设置里的"自动关闭热点"开关也纹丝不动)。
         原因是安卓 11 起这个开关已经从 Settings.Global.soft_ap_timeout_enabled 挪进了 SoftApConfiguration，
         再写 settings 没有任何效果。现在改为经 hotspotctl.dex 调 IWifiManager:
         getSoftApConfiguration -> Builder.setAutoShutdownEnabled(false) -> setSoftApConfiguration，
         并回读确认是否真的改成功(结果记在 log/open_hotspot.log)。安卓 10 及以下仍走原来的 Settings.Global
      2. 修复热点已经开着时不会去改这个配置的问题(上一版把它放在了"热点已开就退出"之后)
      3. 注意: 改的是热点配置，对"下一次开启热点"生效。如果热点当前正开着，需要它重开一次(或手动关一次再开)才会真正不再自动关闭

- **HotspotPlus_v8.4**

      1. ftp 共享目录可以自己指定(config.json 里的 ftp_setting.dir)，默认由根目录 / 改为 /sdcard，避免整个系统被局域网里的设备读写
      2. ftp 新增账号密码登录(ftp_setting.user / ftp_setting.password)，password 留空则和以前一样免登录
      3. ftp 新增自定义端口号(ftp_setting.port)和只读共享开关(ftp_setting.allow_upload)
      4. ftp 修复中文文件名变成乱码 0 字节垃圾文件的问题: busybox ftpd 不宣告 UTF8，客户端会退回自己系统的编码(中文 Windows 为 GBK)发文件名，这些字节在只认 UTF-8 的安卓 /sdcard 上就成了乱码。现在由 ftp_login.sh 统一宣告 UTF8 并接受 OPTS UTF8 ON
      5. ftp 共享目录填错(目录不存在)时不再启动服务，并在 service.log 里给出提示
      6. 新增 lib.sh 统一读取配置，各脚本里的 jq 调用统一成 cfg .ftp_setting.port 21 这种短写法; 顺带修掉了配置里缺某个键时会取到 null 的问题(现在会回落到默认值)
      7. 修复 start_ap 设为 false(只想用 frp)时，热点检测脚本仍然会去切飞行模式、并因此把热点带起来的问题。现在每个定时检测都先看自己的总开关，关了就什么都不做
      8. 新增 ap_keep_alive(默认开)，关掉系统"热点无设备连接自动关闭"的超时，解决热点没人连就自己关、热点检测也救不回来的问题
      9. 短信转发改为直接查系统短信库(content://sms/inbox)，不再依赖通知、也不再写死 com.android.mms 包名。以前默认短信应用不是这个包名(谷歌 Messages、三星等)就一条都转发不出去。退回通知方式时包名也改为自动识别
      10. 精简脚本: hotspot_status.sh + rndis_status.sh + keepfrpc.sh 合并为 check.sh，lib_cfg.sh + lib_ap.sh 合并为 lib.sh，frp 一键启动与 frpc.sh 不再各写一份(RunAuto/sh 由 14 个文件减到 11 个)
      11. 修复 frp/一键停止.sh 是空文件(执行了等于没执行)、一键关闭所有服务.sh 关不掉短信转发进程且会刷一屏 kill 报错、随包发布的 crontabs/root 仍指向旧模块名 autofrp 等遗留问题

- **HotspotPlus_v8.3**

      1. 热点默认开启方式改为 api（通用方式，config.json 的 start_ap 默认值由 mode1 改为 api）。仍可改回 mode1/mode2
      2. 文档同步说明

- **HotspotPlus_v8.2**

      1. api 补全 Android 11+ 路径：经 ServiceManager 调 tethering 服务 ITetheringConnector.startTethering，配合原有 Android 7~10 的 connectivity 路径，覆盖 Android 7~14
      2. 通用热点接口识别：热点网卡命名因芯片而异(联发科 ap0；高通 wlan1/softap0/swlan0；其他 uap0 等)，新增 lib_ap.sh 统一识别(已知名 + 192.168.x.1 网关兜底)，additional/hotspot_status/open_hotspot 三处共用，不再只认 ap0
      3. 层2(cmd wifi start-softap)仅 Android 11+ 尝试，避免旧系统无谓报错

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
