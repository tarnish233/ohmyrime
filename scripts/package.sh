#!/usr/bin/env bash
# 打发布包：build/dist/ohmyrime.zip（和它的 .sha256），发布到 GitHub Releases 用。
# 包里只有「鼠须管设置.app」：它兼任安装器，带着鼠须管和雾凇拼音，打开后按欢迎页安装。
# 文件名不带版本号，这样 releases/latest/download/ohmyrime.zip 总是最新版（README 的一行命令用它）；
# 版本号见 App 和发布页，取自 settings/Info.plist。
#   scripts/package.sh       （先运行 scripts/build.sh）
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
app="$root/build/settings/鼠须管设置.app"
payload="$app/Contents/Resources/Payload"
[ -f "$payload/Squirrel.zip" ] && [ -f "$payload/rime-ice.zip" ] || { echo "先构建：scripts/build.sh" >&2; exit 1; }

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
dist="$root/build/dist"
mkdir -p "$dist"
rm -f "$dist/ohmyrime.zip" "$dist/ohmyrime.zip.sha256"

# 签名要完整：App 本身，和解压出来的鼠须管（rime-install 的签名存放在扩展属性里）
codesign --verify --deep --strict "$app"
check=$(mktemp -d "${TMPDIR:-/tmp}/ohmyrime-package.XXXXXX")
trap 'rm -rf "$check"' EXIT
ditto -x -k "$payload/Squirrel.zip" "$check"
codesign --verify --deep --strict "$check/Squirrel.app"

# ditto 打包：保留 Sparkle.framework 里的符号链接和扩展属性（放在 __MACOSX 里，解压时还原）
(cd "$(dirname "$app")" && ditto -c -k --sequesterRsrc --keepParent "$(basename "$app")" "$dist/ohmyrime.zip")
(cd "$dist" && shasum -a 256 ohmyrime.zip > ohmyrime.zip.sha256)
echo "已打包 ohmyrime ${version}：$dist/ohmyrime.zip（$(du -h "$dist/ohmyrime.zip" | cut -f1)）"
cat "$dist/ohmyrime.zip.sha256"
