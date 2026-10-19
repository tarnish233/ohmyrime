#!/usr/bin/env bash
# 构建 ohmyrime 版鼠须管（Release，本机架构）。
# 首次运行会下载官方预编译 librime / Sparkle 和 plum 默认方案；GitHub 直连很慢，
# 如果本机代理（默认 http://127.0.0.1:7890，可用 OHMYRIME_PROXY 覆盖）可用就自动走代理。
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/squirrel"

proxy="${OHMYRIME_PROXY:-http://127.0.0.1:7890}"
use_proxy() {
  if curl -s -o /dev/null --max-time 5 -x "$proxy" https://github.com; then
    export https_proxy="$proxy" http_proxy="$proxy"
    echo "使用代理 $proxy"
  fi
}

# librime 源码只用于头文件（rime/key_table.h）；二进制用官方预编译版
if [ ! -f librime/src/rime_api_stdbool.h ]; then
  use_proxy
  git submodule update --init --depth 1 librime
fi
if [ ! -f lib/librime.1.dylib ] || [ ! -d Frameworks/Sparkle.framework ] || [ ! -f data/plum/default.yaml ]; then
  use_proxy
  bash action-install.sh
fi

make release ARCHS="$(uname -m)"
echo "构建完成：$root/squirrel/build/Build/Products/Release/Squirrel.app"

# 设置 App 用鼠须管自己的候选框代码做预览，所以跟着鼠须管一起构建
bash "$root/scripts/build-settings.sh"
