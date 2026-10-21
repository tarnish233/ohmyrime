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
out=$(bash scripts/rime-smoke.sh "$work/Rime" nihao zi "nihao," "nihao." cshi / 2>&1)
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
expect "^/ +=> commit「、」" "中文标点下 / 打成「、」（设置里打开的）"
expect "librime 错误日志：0 条" "部署没有错误"

# 模型测试里离线装好雾凇拼音的文件夹（没有 .cache/rime-ice/full.zip 时跳过）
if [ -f "$work/ice/Rime/rime_ice.schema.yaml" ]; then
  echo "== 用 librime 部署刚装好雾凇拼音的文件夹"
  out=$(bash scripts/rime-smoke.sh "$work/ice/Rime" nihao csaz 2>&1)
  echo "$out" | grep -E "=>|错误|schema:"
  expect "^schema: rime_ice" "默认方案是雾凇拼音"
  expect "^nihao +=> 1\.你好.* 6\." "每页 6 个：保留了用户自己的设置"
  if echo "$out" | grep -q -E "^nihao +=> .* 7\."; then echo "  ✗ 每页不多于 6 个"; fail=1; fi
  expect "^csaz +=> 1\.测试安装" "保留了用户的自定义短语"
  expect "librime 错误日志：0 条" "部署没有错误"
fi
# 全新文件夹（还没 custom_phrase.txt）：短语预设用 ohmyrime 自己的精简示例，不是雾凇拼音那份大文件
if [ -f "$root/.cache/rime-ice/full.zip" ]; then
  echo "== 全新安装雾凇拼音：短语预设"
  fresh="$work/fresh-ice"
  rm -rf "$fresh"
  mkdir -p "$fresh/Rime" "$fresh/cache"
  cp "$root/.cache/rime-ice/full.zip" "$fresh/cache/"
  OHMYRIME_RIME_DIR="$fresh/Rime" OHMYRIME_CACHE_DIR="$fresh/cache" OHMYRIME_BACKUP_DIR="$fresh/backups" OHMYRIME_NO_RELOAD=1 \
    bash scripts/rime-ice.sh --offline > /dev/null
  phrase_file="$fresh/Rime/custom_phrase.txt"
  if grep -q "又双叒叕	uuuu" "$phrase_file" 2>/dev/null && ! grep -q "^go	go$" "$phrase_file" 2>/dev/null; then
    echo "  ✓ 用的是 ohmyrime 自己的精简示例，不是雾凇拼音那份"
  else
    echo "  ✗ 用的是 ohmyrime 自己的精简示例，不是雾凇拼音那份"; fail=1
  fi
  entries=$(grep -v '^#' "$phrase_file" | grep -c "$(printf '\t')" || true)
  if [ "${entries:-0}" -eq 6 ]; then echo "  ✓ 只有 6 条，不是雾凇拼音的一大份（$entries 条）"; else echo "  ✗ 条数不对（$entries 条）"; fail=1; fi
fi

exit $fail
