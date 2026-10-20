#!/usr/bin/env bash
# 重新生成 README 里的设置 App 截图：docs/images/settings-*.png。
# 用一个干净的用户文件夹（ohmyrime 配置模板 + 离线安装的雾凇拼音），不碰 ~/Library/Rime，截图里没有个人数据。
# 截图时设置窗口会切到最前面约 15 秒，控件才显示成激活状态；第一次运行时系统可能询问是否允许控制「系统事件」。
#   scripts/readme-shots.sh
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
work="$root/build/readme"
app="$root/build/settings/鼠须管设置.app"
[ -x "$app/Contents/MacOS/SquirrelSettings" ] || { echo "先构建设置 App：scripts/build-settings.sh" >&2; exit 1; }
[ -f .cache/rime-ice/full.zip ] || { echo "先下载一次雾凇拼音：scripts/rime-ice.sh" >&2; exit 1; }

rm -rf "$work"
mkdir -p "$work/Rime" "$work/cache" docs/images
cp rime/*.yaml "$work/Rime/"
cp .cache/rime-ice/full.zip "$work/cache/"
OHMYRIME_RIME_DIR="$work/Rime" OHMYRIME_CACHE_DIR="$work/cache" OHMYRIME_BACKUP_DIR="$work/backups" OHMYRIME_NO_RELOAD=1 \
  bash scripts/rime-ice.sh --offline > /dev/null
# 演示数据：同步文件夹设在 iCloud 云盘，有一个用户词库
printf 'sync_dir: "%s/Library/Mobile Documents/com~apple~CloudDocs/Rime"\n' "$HOME" > "$work/Rime/installation.yaml"
mkdir -p "$work/Rime/rime_ice.userdb"
head -c 1300000 /dev/zero > "$work/Rime/rime_ice.userdb/000003.log"

status=1
for attempt in 1 2 3; do
  SQUIRREL_SETTINGS_USER_DIR="$work/Rime" SQUIRREL_SETTINGS_NO_DEPLOY=1 SQUIRREL_SETTINGS_SNAPSHOT="$root/docs/images" \
    SQUIRREL_SETTINGS_SNAPSHOT_README=1 "$app/Contents/MacOS/SquirrelSettings" > "$work/run.log" 2>&1 &
  pid=$!
  # 从终端启动的 App 不能自己切到前台：用「系统事件」切过去，截完之前一直保持。
  # 已在最前面时不要再设：重复设置会让窗口闪一下失去焦点，正好截到就是灰的
  while kill -0 "$pid" 2>/dev/null; do
    osascript -e "tell application \"System Events\" to tell (first process whose unix id is $pid) to if not frontmost then set frontmost to true" > /dev/null 2>&1 || true
    sleep 0.5
  done
  status=0
  wait "$pid" || status=$?
  # 本机的终端安全软件可能结束刚编译的程序（Killed: 9），重试
  [ $status -ne 137 ] && break
  sleep 3
done
grep -E "^→|✗" "$work/run.log" || true
exit $status
