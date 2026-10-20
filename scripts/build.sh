#!/usr/bin/env bash
# 构建 ohmyrime 版鼠须管（Release，本机架构）和「鼠须管设置」。
# 首次运行会下载官方预编译 librime / Sparkle、plum 默认方案和雾凇拼音（打包进「鼠须管设置」）。
# 脚本不设置代理：需要的话自己设置 https_proxy 等环境变量，git 和 curl 都会用。
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

# 鼠须管 fork 是子模块（tarnish233/squirrel 的 ohmyrime 分支）：刚 clone 下来时先取下来
if [ ! -f "$root/squirrel/Makefile" ]; then
  git -C "$root" submodule update --init squirrel
fi
cd "$root/squirrel"

# librime 源码只用于头文件（rime/key_table.h）；二进制用官方预编译版
if [ ! -f librime/src/rime_api_stdbool.h ]; then
  git submodule update --init --depth 1 librime
fi
if [ ! -f lib/librime.1.dylib ] || [ ! -d Frameworks/Sparkle.framework ] || [ ! -f data/plum/default.yaml ]; then
  bash action-install.sh
fi

make release ARCHS="$(uname -m)"
echo "构建完成：$root/squirrel/build/Build/Products/Release/Squirrel.app"

# 设置 App 用鼠须管自己的候选框代码做预览，还要把鼠须管打包进去当安装器，所以跟着鼠须管一起构建
bash "$root/scripts/build-settings.sh"
