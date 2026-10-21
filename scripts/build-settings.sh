#!/usr/bin/env bash
# 构建「鼠须管设置」：build/settings/鼠须管设置.app
# 预览直接用鼠须管自己的候选框代码（squirrel/sources），App 还兼任安装器、带着鼠须管，
# 所以要先构建鼠须管：scripts/build.sh。
# App 里带的东西（Contents/Resources）：
#   Payload/Squirrel.zip   鼠须管（ditto 压缩，保留签名用的扩展属性）
#   Payload/rime-ice.zip   雾凇拼音的 full.zip（.cache/rime-ice/full.zip，没有就下载）
#   scripts/               install.sh、uninstall.sh、rime-ice.sh
#   rime/                  ohmyrime 的配置模板
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
sq="$root/squirrel"
squirrel_app="$sq/build/Build/Products/Release/Squirrel.app"
app="$root/build/settings/鼠须管设置.app"
[ -f "$sq/lib/librime.1.dylib" ] && [ -d "$sq/Frameworks/Sparkle.framework" ] && [ -d "$squirrel_app" ] || { echo "先构建鼠须管：scripts/build.sh" >&2; exit 1; }
ice="$root/.cache/rime-ice/full.zip"
if [ ! -f "$ice" ]; then
  echo "下载雾凇拼音（打包进 App）…"
  mkdir -p "$(dirname "$ice")"
  curl -fL -# --retry 3 --retry-all-errors --retry-delay 1 --connect-timeout 20 -o "$ice.part" \
    https://github.com/iDvel/rime-ice/releases/latest/download/full.zip
  mv "$ice.part" "$ice"
fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources/zh-Hans.lproj"

sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find settings/Sources -name '*.swift' | sort)
swiftc -swift-version 5 -O -parse-as-library -enable-bare-slash-regex -target arm64-apple-macos14.0 \
  -import-objc-header "$sq/sources/Squirrel-Bridging-Header.h" -I "$sq/librime/src" -I "$sq/librime/include" \
  -L "$sq/lib" -lrime.1 -F "$sq/Frameworks" -framework Sparkle \
  -framework AppKit -framework SwiftUI -framework InputMethodKit -framework Carbon -framework UserNotifications -framework ScreenCaptureKit \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  "$sq"/sources/{BridgingFunctions,InputSource,MacOSKeyCodes,ReservedProperty,SquirrelApplicationDelegate,SquirrelConfig,SquirrelInputController,SquirrelPanel,SquirrelScrollMode,SquirrelTheme,SquirrelView}.swift \
  "${sources[@]}" -o "$app/Contents/MacOS/SquirrelSettings" 2>&1 | { grep -v -E "SwiftUICore|^ld: warning: Could not parse" || true; }
test -x "$app/Contents/MacOS/SquirrelSettings"

cp settings/Info.plist "$app/Contents/"
printf 'APPL????' > "$app/Contents/PkgInfo"
# 让系统菜单（退出、隐藏、编辑…）显示中文
: > "$app/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"
# 只要 arm64，体积减半
lipo "$sq/lib/librime.1.dylib" -thin arm64 -output "$app/Contents/Frameworks/librime.1.dylib" 2>/dev/null || cp "$sq/lib/librime.1.dylib" "$app/Contents/Frameworks/"
ditto "$sq/Frameworks/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp "$squirrel_app/Contents/Resources/Rime.icns" "$app/Contents/Resources/AppIcon.icns"
# 安装、卸载、雾凇拼音的脚本，和它们补上的 ohmyrime 配置模板
mkdir -p "$app/Contents/Resources/scripts" "$app/Contents/Resources/rime" "$app/Contents/Resources/Payload"
cp scripts/install.sh scripts/uninstall.sh scripts/rime-ice.sh "$app/Contents/Resources/scripts/"
cp rime/*.yaml rime/custom_phrase.txt "$app/Contents/Resources/rime/"
# 安装器带的鼠须管和雾凇拼音
ditto -c -k --sequesterRsrc --keepParent "$squirrel_app" "$app/Contents/Resources/Payload/Squirrel.zip"
cp "$ice" "$app/Contents/Resources/Payload/rime-ice.zip"
# 带的是哪一版：鼠须管可执行文件的 SHA-256（和已装的比，判断要不要更新）、雾凇拼音的版本
plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :OhmyrimeSquirrelHash string $(shasum -a 256 "$squirrel_app/Contents/MacOS/Squirrel" | cut -d' ' -f1)" "$plist"
ice_version=$(unzip -p "$ice" rime_ice.schema.yaml | sed -n 's/^  version: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' | head -1)
/usr/libexec/PlistBuddy -c "Add :OhmyrimeRimeIceVersion string ${ice_version:-?}" "$plist"

codesign --force --deep --sign - "$app" >/dev/null 2>&1
echo "已构建：$app"
