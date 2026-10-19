#!/usr/bin/env bash
# 卸载 ohmyrime 版鼠须管：禁用输入源并删除 ~/Library/Input Methods/Squirrel.app。
# 默认保留 ~/Library/Rime（配置与用户词库）；加 --purge 一并删除。
set -euo pipefail
dest="$HOME/Library/Input Methods/Squirrel.app"

if [ -x "$dest/Contents/MacOS/Squirrel" ]; then
  "$dest/Contents/MacOS/Squirrel" --disable-input-source || true
fi
pkill -x Squirrel 2>/dev/null || true
rm -rf "$dest"
echo "已删除：$dest"

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$HOME/Library/Rime"
  echo "已删除：$HOME/Library/Rime"
else
  echo "保留：$HOME/Library/Rime（需要时用 --purge 删除）"
fi
echo "如果菜单栏里仍有「鼠须管」，注销重新登录即可。"
