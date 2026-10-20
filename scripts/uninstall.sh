#!/usr/bin/env bash
# 卸载 ohmyrime：从输入法里移除鼠须管，删除 /Library/Input Methods/Squirrel.app（弹一次管理员
# 密码框）、早期装在 ~/Library/Input Methods 的副本和「鼠须管设置」。
# 默认保留 ~/Library/Rime（配置与用户词库）和改设置前的备份；加 --purge 一并删除，
# 连同「鼠须管设置」的缓存和偏好设置。「鼠须管设置 → 词库与部署 → 卸载」运行的也是这个脚本。
#
#   scripts/uninstall.sh [--purge]
#
# 测试用：OHMYRIME_TEST_ROOT=<目录>，同 install.sh。
set -euo pipefail
step() { printf '==> %s\n' "$*"; }
purge=false
for arg in "$@"; do
  case "$arg" in
    --purge) purge=true ;;
    *) echo "用法：scripts/uninstall.sh [--purge]" >&2; exit 2 ;;
  esac
done

test_root="${OHMYRIME_TEST_ROOT:-}"
if [ -n "$test_root" ]; then
  test_root="$(cd "$test_root" && pwd)"
  home="$test_root/home"
  input_methods="$test_root/Library/Input Methods"
  apps_dirs=("$test_root/Applications")
else
  home="$HOME"
  input_methods="/Library/Input Methods"
  apps_dirs=(/Applications "$HOME/Applications")
fi
real() { [ -z "$test_root" ]; }
dest="$input_methods/Squirrel.app"
user_copy="$home/Library/Input Methods/Squirrel.app"
support_dir="$home/Library/Application Support/鼠须管设置"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# 1. 从输入法里移除（系统会切到别的输入法），再退出鼠须管
if real; then
  step "从输入法中移除鼠须管"
  for app in "$dest" "$user_copy"; do
    if [ -x "$app/Contents/MacOS/Squirrel" ]; then
      "$app/Contents/MacOS/Squirrel" --disable-input-source || true
    fi
  done
  pkill -x Squirrel 2>/dev/null || true
fi

# 2. 删除鼠须管
step "删除鼠须管"
if [ -d "$user_copy" ]; then
  real && { "$lsregister" -u "$user_copy" 2>/dev/null || true; }
  rm -rf "$user_copy"
  echo "已删除：$user_copy"
fi
if [ -d "$dest" ]; then
  if real; then
    "$lsregister" -u "$dest" 2>/dev/null || true
    /usr/bin/osascript -e 'do shell script "/bin/rm -rf \"/Library/Input Methods/Squirrel.app\"" with prompt "ohmyrime 要删除 /Library/Input Methods/Squirrel.app。" with administrator privileges'
  else
    rm -rf "$dest"
  fi
  echo "已删除：$dest"
fi

# 3. 删除「鼠须管设置」（运行卸载的 App 自己不结束，删完由它自己退出）
step "删除鼠须管设置"
for apps_dir in "${apps_dirs[@]}"; do
  settings_app="$apps_dir/鼠须管设置.app"
  [ -d "$settings_app" ] || continue
  if real; then
    for pid in $(pgrep -x SquirrelSettings || true); do
      [ "$pid" = "${OHMYRIME_APP_PID:-}" ] || kill "$pid" 2>/dev/null || true
    done
    "$lsregister" -u "$settings_app" 2>/dev/null || true
  fi
  rm -rf "$settings_app"
  echo "已删除：$settings_app"
done
rm -f "$support_dir/installed.json"

# 4. 个人数据
if $purge; then
  step "删除配置和用户词库"
  rm -rf "$home/Library/Rime" "$support_dir" "$home/Library/Caches/im.rime.ohmyrime.settings"
  echo "已删除：$home/Library/Rime"
  echo "已删除：$support_dir"
  if real; then
    defaults delete im.rime.ohmyrime.settings 2>/dev/null || true
    defaults delete im.rime.inputmethod.Squirrel 2>/dev/null || true
    rm -rf "${TMPDIR:-/tmp}/rime.squirrel"
  fi
else
  echo "保留：$home/Library/Rime（配置和用户词库；需要时用 --purge 删除）"
fi

step "完成"
if real && { defaults read com.apple.inputsources AppleEnabledThirdPartyInputSources 2>/dev/null
             defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null; } | grep -q 'im.rime.inputmethod.Squirrel'; then
  echo "系统设置里还列着「鼠须管」：在「键盘 → 输入法」里把它移除，或者注销重新登录。"
fi
