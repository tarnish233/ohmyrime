#!/usr/bin/env bash
# 冒烟测试：把一份 Rime 用户目录复制到 build/rime-smoke（不含用户词库和编译产物），
# 用本地 librime（含 lua 等插件）重新部署，再打印几组按键的候选 / 上屏结果。
# 只读源目录，不会改动它，也不影响正在运行的鼠须管。
#   scripts/rime-smoke.sh [源目录，默认 ~/Library/Rime] [按键序列...]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
squirrel="$root/squirrel"
src="${1:-$HOME/Library/Rime}"
[ $# -gt 0 ] && shift
shared="/Library/Input Methods/Squirrel.app/Contents/SharedSupport"
[ -d "$shared" ] || shared="$squirrel/build/Build/Products/Release/Squirrel.app/Contents/SharedSupport"
# 不放 /tmp：终端安全软件可能结束在那里新编译的程序
work="$root/build/rime-smoke"

rm -rf "$work"
mkdir -p "$work/user" "$work/log"
rsync -a --exclude 'build/' --exclude '*.userdb/' --exclude '*.userdb.txt' --exclude 'sync/' --exclude 'installation.yaml' "$src/" "$work/user/"
clang -O1 -I "$squirrel/librime/dist/include" "$root/tools/rime-smoke.c" \
  -L "$squirrel/lib" -lrime.1 -Wl,-rpath,"$squirrel/lib" -o "$work/rime-smoke"

keys=("$@")
[ ${#keys[@]} -gt 0 ] || keys=(nihao 'nihao[' 'nihao]' shijie 'shi{Tab}' rq sj xq nl R123 'cC1+1' U62fc)
start=$(date +%s)
"$work/rime-smoke" "$shared" "$work/user" "$work/log" "${keys[@]}"
echo "（含部署共 $(( $(date +%s) - start )) 秒）"
errors=$(cat "$work"/log/*.ERROR 2>/dev/null | grep -c '^E' || true)
echo "librime 错误日志：${errors} 条"
[ "$errors" = 0 ] || grep -h '^E' "$work"/log/*.ERROR | cut -c1-200 | sort | uniq -c | head -20
