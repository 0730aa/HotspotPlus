# HotspotPlus 开发约定

热点机 Magisk 模块：开机自启 frpc、热点、adb、ftp、telnet、USB 共享、短信转发。

## 更新日志与提交

- README 的更新日志要简洁，照 v7.9 的写法：版本标题下每条一行、编号、6 格缩进，一般 3~7 条，只写改了什么，不写原理和技术细节
- commit message 也保持简短
- 发新版本时同时改 module.prop 的 version 和 versionCode

## 代码

- 脚本跑在安卓 /system/bin/sh(mksh) 或 Magisk 的 busybox ash 下：只用 POSIX sh，命令要兼容 toybox 和 busybox，awk 要兼容 one-true-awk 和 busybox awk
- 公共函数放 RunAuto/sh/lib.sh（读配置 cfg、热点检测 ap_up 等）
- 改了 native/hotspotctl/src 下的 Java，要运行 native/hotspotctl/build.sh 重新生成 bin/hotspotctl.dex，并一起提交
- RunAuto/sh/diag.sh 是只读诊断脚本，要能在无 root 的 adb shell 下跑（远程真机平台测试用，流程见 docs/远程真机测试流程.md）
