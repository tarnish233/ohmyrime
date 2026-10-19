#!/usr/bin/env bash
# 「鼠须管设置」的模型测试：在 ~/Library/Rime 的一份副本（不含词库）上改设置、保存，
# 再用 librime 部署这份副本，确认写出的文件 Rime 能读、改动生效。不碰真正的 ~/Library/Rime。
#   scripts/test-settings.sh
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
sq="$root/squirrel"
work="$root/build/settings-test"
[ -f "$sq/lib/librime.1.dylib" ] || { echo "先构建鼠须管：scripts/build.sh" >&2; exit 1; }

rm -rf "$work"
mkdir -p "$work/Rime"
rsync -a --exclude 'build/' --exclude '*.userdb/' --exclude '*.userdb.txt' --exclude 'sync/' "$HOME/Library/Rime/" "$work/Rime/"

swiftc -swift-version 5 -Onone -enable-bare-slash-regex -target arm64-apple-macos14.0 \
  -import-objc-header "$sq/sources/Squirrel-Bridging-Header.h" -I "$sq/librime/src" -I "$sq/librime/include" \
  -L "$sq/lib" -lrime.1 -Xlinker -rpath -Xlinker "$sq/lib" \
  "$sq/sources/BridgingFunctions.swift" settings/Sources/Model/*.swift settings/Tests/main.swift -o "$work/settings-tests" 2>&1 | { grep -v -E "SwiftUICore|^ld: warning: Could not parse" || true; }

# 本机的终端安全软件可能杀掉刚编译出来的程序（Killed: 9），重试几次
status=1
for attempt in 1 2 3; do
  set +e
  "$work/settings-tests" "$root" "$work/Rime" 2> "$work/stderr.log"
  status=$?
  set -e
  [ $status -ne 137 ] && break
  sleep 3
done
[ $status -eq 0 ] || exit $status

echo "== 用 librime 部署改过的副本"
out=$(bash scripts/rime-smoke.sh "$work/Rime" nihao zi "nihao," "nihao." cshi 2>&1)
echo "$out" | grep -E "=>|错误|schema:"
fail=0
expect() {
  if echo "$out" | grep -q -E "$1"; then echo "  ✓ $2"; else echo "  ✗ $2"; fail=1; fi
}
expect "^nihao +=> .* 7\." "每页 7 个候选"
expect "^zi +=> .*(只|知|之|支)" "模糊音 z ↔ zh：zi 也出 zhi 的字"
expect "^nihao, +=> 1\." "逗号翻页：第一页时 , 不上屏标点"
expect "^nihao\. +=> page 2:" "句号翻页：. 到第 2 页"
expect "^cshi +=> 1\.测试短语" "自定义短语"
expect "librime 错误日志：0 条" "部署没有错误"
exit $fail
