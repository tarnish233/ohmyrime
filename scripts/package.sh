#!/usr/bin/env bash
# 打预编译安装包：build/dist/ohmyrime-<版本>-<架构>.zip，发布到 GitHub Releases 用。
# 包里有 ohmyrime 版鼠须管、鼠须管设置、安装 / 卸载脚本、雾凇拼音安装脚本、配置模板和许可证，
# 解压后运行 bash scripts/install.sh 即可安装，不用装 Xcode。版本取自 settings/Info.plist。
#   scripts/package.sh       （先运行 scripts/build.sh）
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
squirrel_app="$root/squirrel/build/Build/Products/Release/Squirrel.app"
settings_app="$root/build/settings/鼠须管设置.app"
[ -d "$squirrel_app" ] && [ -d "$settings_app" ] || { echo "先构建：scripts/build.sh" >&2; exit 1; }

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" settings/Info.plist)
arch=$(lipo -archs "$squirrel_app/Contents/MacOS/Squirrel" | tr ' ' '-')
name="ohmyrime-$version-$arch"
dist="$root/build/dist"
stage="$dist/$name"
rm -rf "$stage" "$dist/$name.zip" "$dist/$name.zip.sha256"
mkdir -p "$stage/scripts" "$stage/rime"

ditto "$squirrel_app" "$stage/Squirrel.app"
ditto "$settings_app" "$stage/鼠须管设置.app"
cp scripts/install.sh scripts/uninstall.sh scripts/rime-ice.sh "$stage/scripts/"
cp rime/*.yaml "$stage/rime/"
cp LICENSE "$stage/"
cat > "$stage/安装说明.txt" <<TEXT
ohmyrime ${version}（Apple 芯片，macOS 14 或更新）

安装
1. 打开「终端」，输入 cd 和一个空格，把这个文件夹拖进终端窗口，回车。
2. 运行：bash scripts/install.sh
   会弹一次管理员密码框；还没装雾凇拼音时会一并下载。
3. 第一次安装后，在系统里添加一次输入法：⌘Q 退出「系统设置」再打开 →「键盘」→ 文字输入「输入法」→「编辑…」→「+」→「简体中文」→「鼠须管」。
4. 在菜单栏的输入法菜单里选「鼠须管」。设置：鼠须管菜单里的「设置…」。

卸载：bash scripts/uninstall.sh（保留词库和配置；加 --purge 一并删除）

这两个 App 没有经过 Apple 公证。安装脚本会去掉下载带来的隔离标记，不用在「隐私与安全性」里手动允许。
源码和说明：https://github.com/tarnish233/ohmyrime （GPL-3.0）
TEXT

codesign --verify --deep --strict "$stage/Squirrel.app"
codesign --verify --deep --strict "$stage/鼠须管设置.app"
# ditto 打包：保留 Sparkle.framework 里的符号链接和代码签名
(cd "$dist" && ditto -c -k --sequesterRsrc --keepParent "$name" "$name.zip")
(cd "$dist" && shasum -a 256 "$name.zip" > "$name.zip.sha256")
echo "已打包：$dist/$name.zip（$(du -h "$dist/$name.zip" | cut -f1)）"
cat "$dist/$name.zip.sha256"
