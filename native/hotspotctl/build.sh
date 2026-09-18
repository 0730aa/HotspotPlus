#!/usr/bin/env bash
# 在 x86 Linux 上把 HotspotCtl.java 编译并打包成 dex。
# 依赖: JDK(javac) + dalvik-dx (dexer)。
# 用法: DX_JAR=/path/to/dalvik-dx.jar ./build.sh   (不指定则自动从 Maven Central 拉取)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUT_DEX="$REPO/bin/hotspotctl.dex"
WORK="$HERE/.build"; rm -rf "$WORK"; mkdir -p "$WORK/stubcls" "$WORK/appcls"

DX_JAR="${DX_JAR:-$HERE/.tools/dalvik-dx.jar}"
if [ ! -f "$DX_JAR" ]; then
  echo "[build] 未找到 dalvik-dx，尝试从 Maven Central 下载..."
  mkdir -p "$(dirname "$DX_JAR")"
  V=16.0.1
  URL="https://repo1.maven.org/maven2/com/jakewharton/android/repackaged/dalvik-dx/$V/dalvik-dx-$V.jar"
  for i in 1 2 3 4 5; do
    code=$(curl -sSL -o "$DX_JAR" -w "%{http_code}" --max-time 120 "$URL" || echo 000)
    [ "$code" = "200" ] && break
    echo "[build] 下载重试 #$i (HTTP $code)"; sleep $((i*5))
  done
fi
[ -f "$DX_JAR" ] || { echo "[build] 无法获得 dalvik-dx.jar"; exit 1; }

echo "[build] 1/3 编译桩(仅编译期)"
javac -source 8 -target 8 -Xlint:-options -d "$WORK/stubcls" \
  "$HERE"/stubs/android/net/*.java

echo "[build] 2/3 编译应用类"
javac -source 8 -target 8 -Xlint:-options -encoding UTF-8 \
  -cp "$WORK/stubcls" -d "$WORK/appcls" \
  "$HERE"/src/com/hotspotplus/*.java

echo "[build] 3/3 dex (只打应用类，桩不进 dex)"
java -cp "$DX_JAR" com.android.dx.command.Main --dex \
  --min-sdk-version=21 --output="$OUT_DEX" "$WORK/appcls"

echo "[build] 完成 -> $OUT_DEX"
ls -la "$OUT_DEX"
file "$OUT_DEX" 2>/dev/null || true
