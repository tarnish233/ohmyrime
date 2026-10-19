#!/usr/bin/env bash
# 卸载 ohmyrime 版鼠须管：禁用输入源，删除 /Library/Input Methods/Squirrel.app（需要管理员密码）
# 以及早期装在 ~/Library/Input Methods 的副本。
# 默认保留 ~/Library/Rime（配置与用户词库）；加 --purge 一并删除。
set -euo pipefail
dest="/Library/Input Methods/Squirrel.app"
user_copy="$HOME/Library/Input Methods/Squirrel.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

for app in "$dest" "$user_copy"; do
  if [ -x "$app/Contents/MacOS/Squirrel" ]; then
    "$app/Contents/MacOS/Squirrel" --disable-input-source || true
  fi
done
pkill -x Squirrel 2>/dev/null || true

if [ -d "$user_copy" ]; then
  "$lsregister" -u "$user_copy" 2>/dev/null || true
  rm -rf "$user_copy"
  echo "已删除：$user_copy"
fi
if [ -d "$dest" ]; then
  "$lsregister" -u "$dest" 2>/dev/null || true
  /usr/bin/osascript -e 'do shell script "/bin/rm -rf \"/Library/Input Methods/Squirrel.app\"" with prompt "ohmyrime 要删除 /Library/Input Methods/Squirrel.app。" with administrator privileges'
  echo "已删除：$dest"
fi

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$HOME/Library/Rime"
  echo "已删除：$HOME/Library/Rime"
else
  echo "保留：$HOME/Library/Rime（需要时用 --purge 删除）"
fi
echo "如果系统设置里仍有「鼠须管」，在「键盘 → 输入法」里把它移除，或注销重新登录。"
