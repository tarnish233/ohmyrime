#!/usr/bin/env bash
# 构建「鼠须管设置」：build/settings/鼠须管设置.app
# 预览直接用鼠须管自己的候选框代码（squirrel/sources），所以要先构建鼠须管：scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
sq="$root/squirrel"
app="$root/build/settings/鼠须管设置.app"
[ -f "$sq/lib/librime.1.dylib" ] && [ -d "$sq/Frameworks/Sparkle.framework" ] || { echo "先构建鼠须管：scripts/build.sh" >&2; exit 1; }

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
icon="$sq/build/Build/Products/Release/Squirrel.app/Contents/Resources/Rime.icns"
[ -f "$icon" ] || icon="/Library/Input Methods/Squirrel.app/Contents/Resources/Rime.icns"
[ -f "$icon" ] && cp "$icon" "$app/Contents/Resources/AppIcon.icns"
# 「安装雾凇拼音」运行的脚本，和它补上的 ohmyrime 配置模板
cp scripts/rime-ice.sh "$app/Contents/Resources/"
mkdir -p "$app/Contents/Resources/rime"
cp rime/*.yaml "$app/Contents/Resources/rime/"

codesign --force --deep --sign - "$app" >/dev/null 2>&1
echo "已构建：$app"
