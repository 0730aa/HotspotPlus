#!/system/bin/sh

# ============================================================================
# 安装脚本
# 升级(覆盖刷入)时，可以选择保留上一次装好的配置，不用每次重新填
# ============================================================================

# 升级时需要保留的用户配置文件(相对模块目录)
KEEP_FILES="config.json frp/frpc.toml"

# 已安装的旧模块目录(测试时可用环境变量覆盖)
OLD_DIR="${OLD_DIR:-/data/adb/modules/${MODID:-HotspotPlus}}"

# 等音量键，$1 秒超时。音量上 = 0，音量下 = 1，超时按音量上处理
wait_key() {
  _sec="${1:-10}"
  _ev="${TMPDIR:-/tmp}/hotspotplus_keys"
  rm -f "$_ev"

  # 没有 getevent 就不等了，直接走默认
  command -v getevent >/dev/null 2>&1 || return 0

  getevent -lqc 200 > "$_ev" 2>/dev/null &
  _pid=$!
  _i=0
  while [ "$_i" -lt "$_sec" ]; do
    if grep -q KEY_VOLUMEDOWN "$_ev" 2>/dev/null; then
      kill "$_pid" 2>/dev/null
      return 1
    fi
    if grep -q KEY_VOLUMEUP "$_ev" 2>/dev/null; then
      kill "$_pid" 2>/dev/null
      return 0
    fi
    sleep 1
    _i=$((_i + 1))
  done
  kill "$_pid" 2>/dev/null
  return 0
}

ui_print "*******************************"
ui_print "    热点机模块 HotspotPlus"
ui_print "*******************************"

# 看看以前装过没有
HAS_OLD=0
for f in $KEEP_FILES; do
  [ -f "$OLD_DIR/$f" ] && HAS_OLD=1
done

if [ "$HAS_OLD" -eq 1 ]; then
  ui_print " "
  ui_print "检测到你之前安装过本模块"
  ui_print "  音量上键 = 保留原来的配置(推荐)"
  ui_print "  音量下键 = 全部改用新版默认配置"
  ui_print "  10 秒内不按键，就保留原来的配置"
  ui_print " "

  if wait_key 10; then
    ui_print "→ 保留原来的配置"
    for f in $KEEP_FILES; do
      [ -f "$OLD_DIR/$f" ] || continue
      # 新版自带的那份存成 .new，方便对照这次新增了哪些选项
      [ -f "$MODPATH/$f" ] && cp -f "$MODPATH/$f" "$MODPATH/$f.new"
      cp -f "$OLD_DIR/$f" "$MODPATH/$f"
      ui_print "   已保留 $f (新版默认配置见 $f.new)"
    done
  else
    BACKUP="/data/adb/HotspotPlus_backup/$(date '+%Y%m%d_%H%M%S')"
    mkdir -p "$BACKUP"
    ui_print "→ 使用新版默认配置"
    for f in $KEEP_FILES; do
      [ -f "$OLD_DIR/$f" ] || continue
      mkdir -p "$BACKUP/$(dirname "$f")"
      cp -f "$OLD_DIR/$f" "$BACKUP/$f"
    done
    ui_print "   旧配置已备份到 $BACKUP"
  fi
else
  ui_print " "
  ui_print "首次安装，请刷入后到模块目录编辑 config.json"
fi

ui_print " "
ui_print "*******************************"
ui_print "     安装完成后重启生效"
ui_print "     Happy to use！！！"
ui_print "*******************************"
