#!/usr/bin/env bash
# 安装 ohmyrime 版鼠须管到 ~/Library/Input Methods（仅当前用户，无需管理员密码），
# 注册并启用输入源，但不切换当前输入法。不会改动 /Library/Input Methods（如微信输入法）。
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/squirrel/build/Build/Products/Release/Squirrel.app"
dest_dir="$HOME/Library/Input Methods"
dest="$dest_dir/Squirrel.app"
rime_dir="$HOME/Library/Rime"

[ -d "$app" ] || { echo "未找到构建产物，请先运行 scripts/build.sh" >&2; exit 1; }
if [ -e "/Library/Input Methods/Squirrel.app" ]; then
  echo "检测到 /Library/Input Methods/Squirrel.app（可能是官方版），与本版本使用相同的输入源 ID，请先卸载它。" >&2
  exit 1
fi

# 1. 退出正在运行的鼠须管，下次使用时系统会启动新版本
pkill -x Squirrel 2>/dev/null && sleep 1 || true

# 2. 复制应用
mkdir -p "$dest_dir"
rm -rf "$dest"
ditto "$app" "$dest"
echo "已安装：$dest"

# 3. 用户配置：只补充缺失的文件，不覆盖已有修改
mkdir -p "$rime_dir"
for file in "$root"/rime/*.yaml; do
  target="$rime_dir/$(basename "$file")"
  if [ -e "$target" ]; then
    echo "保留已有配置：$target"
  else
    cp "$file" "$target"
    echo "写入配置：$target"
  fi
done

# 4. 注册并启用输入源（不切换）
# 新构建的程序第一次运行时，终端安全软件（如阿里郎）可能先扫描并结束进程（Killed: 9），
# 扫描通过后即可正常运行，所以先预热并重试几次。
squirrel() {
  for attempt in 1 2 3 4 5; do
    "$dest/Contents/MacOS/Squirrel" "$@" && return 0
    echo "（Squirrel $* 第 $attempt 次运行被中断，3 秒后重试）" >&2
    sleep 3
  done
  return 1
}
squirrel --help > /dev/null
squirrel --register-input-source
squirrel --enable-input-source

echo
if defaults read com.apple.inputsources AppleEnabledThirdPartyInputSources 2>/dev/null | grep -q "im.rime.inputmethod.Squirrel"; then
  echo "完成。在菜单栏输入法菜单中选择「鼠须管」即可使用，首次使用会自动部署（几秒钟）。"
else
  # macOS 27 上命令行启用第三方输入法不生效，需要手动添加一次（之后重装不用再加）
  echo "完成。还需手动添加一次输入法："
  echo "  系统设置 → 键盘 → 文字输入「输入法」→ 编辑… → 左下角 + → 简体中文 → 鼠须管 → 添加"
  echo "  （可运行 open 'x-apple.systempreferences:com.apple.Keyboard-Settings.extension' 打开键盘设置）"
fi
echo "修改 ~/Library/Rime 下的配置后，用「鼠须管 → 重新部署」生效。"
