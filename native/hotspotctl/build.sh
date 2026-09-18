#!/usr/bin/env bash
# 把 HotspotCtl.java 编译并打包成 dex（bin/hotspotctl.dex）。
# 依赖: JDK(javac) + dalvik-dx。用法: [DX_JAR=/path/dalvik-dx.jar] ./build.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUT_DEX="$REPO/bin/hotspotctl.dex"
WORK="$HERE/.build"; rm -rf "$WORK"; mkdir -p "$WORK/appcls"

DX_JAR="${DX_JAR:-$HERE/.tools/dalvik-dx.jar}"
if [ ! -f "$DX_JAR" ]; then
  echo "[build] 下载 dalvik-dx ..."; mkdir -p "$(dirname "$DX_JAR")"; V=16.0.1
  URL="https://repo1.maven.org/maven2/com/jakewharton/android/repackaged/dalvik-dx/$V/dalvik-dx-$V.jar"
  for i in 1 2 3 4 5; do
    code=$(curl -sSL -o "$DX_JAR" -w "%{http_code}" --max-time 120 "$URL" || echo 000)
    [ "$code" = "200" ] && break; echo "[build] 重试#$i HTTP $code"; sleep $((i*5))
  done
fi
[ -f "$DX_JAR" ] || { echo "[build] 无法获得 dalvik-dx.jar"; exit 1; }

# 可选编译期桩（本版本无需，保留兼容）
CP=""
if ls "$HERE"/stubs/**/*.java >/dev/null 2>&1; then
  mkdir -p "$WORK/stubcls"
  javac -source 8 -target 8 -Xlint:-options -d "$WORK/stubcls" $(find "$HERE/stubs" -name '*.java')
  CP="-cp $WORK/stubcls"
fi

echo "[build] 编译应用类"
javac -source 8 -target 8 -Xlint:-options -encoding UTF-8 $CP -d "$WORK/appcls" \
  "$HERE"/src/com/hotspotplus/*.java

echo "[build] dex（只打应用类）"
java -cp "$DX_JAR" com.android.dx.command.Main --dex --min-sdk-version=21 \
  --output="$OUT_DEX" "$WORK/appcls"

echo "[build] 完成 -> $OUT_DEX"; ls -la "$OUT_DEX"; file "$OUT_DEX" 2>/dev/null || true
