#!/usr/bin/env bash
# 安装 / 卸载脚本的测试：都在 build/install-test 里的假目录里做（OHMYRIME_TEST_ROOT），
# 不碰 /Library/Input Methods、不弹密码框、不动真正的 ~/Library/Rime。
# 用仓库里的构建产物和 .cache/rime-ice/full.zip，先运行 scripts/build.sh。
#   scripts/test-install.sh
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
work="$root/build/install-test"
apps="$work/Applications"
rime="$work/home/Library/Rime"
fail=0
ok() { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; fail=1; }
expect() { if eval "$1"; then ok "$2"; else bad "$2"; fi; }

rm -rf "$work"

echo "== 新电脑：什么都不装"
mkdir -p "$work"
OHMYRIME_TEST_ROOT="$work" bash scripts/install.sh > "$work/new.log" 2>&1 || { cat "$work/new.log"; bad "install.sh 失败"; exit 1; }
grep -E "^==> " "$work/new.log" | sed 's/^/  /'
expect '[ -x "$work/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" ]' "鼠须管装进了输入法目录"
expect '[ -f "$rime/rime_ice.schema.yaml" ]' "雾凇拼音装好了（用 .cache 里的 full.zip，没联网）"
expect '[ -f "$rime/squirrel.custom.yaml" ] && [ -f "$rime/default.custom.yaml" ]' "配置模板写好了"
expect 'grep -q "schema: rime_ice" "$rime/default.custom.yaml"' "默认方案是雾凇拼音"
expect '[ -f "$rime/custom_phrase.txt" ]' "自定义短语文件"
expect '[ -x "$apps/鼠须管设置.app/Contents/MacOS/SquirrelSettings" ]' "鼠须管设置装进了 Applications"
expect '[ ! -e "$work/backups" ]' "空文件夹不备份"
hash=$(shasum -a 256 "$work/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" | cut -d" " -f1)
expect 'grep -q "\"squirrelHash\": \"$hash\"" "$work/home/Library/Application Support/鼠须管设置/installed.json"' "记下了装的是哪一版"
expect '! grep -q "无法" "$work/new.log"' "没有报错"

echo "== 重装：用户自己的配置和词库都保留"
printf '# 我自己的设置\npatch:\n  style/font_point: 18\n' > "$rime/squirrel.custom.yaml"
printf '# 我的短语\nceshi\tcs\t1\n' > "$rime/custom_phrase.txt"
mkdir -p "$rime/rime_ice.userdb"
head -c 1000 /dev/zero > "$rime/rime_ice.userdb/000003.log"
mv "$rime/rime_ice.schema.yaml" "$work/rime_ice.schema.yaml.old"
OHMYRIME_TEST_ROOT="$work" bash scripts/install.sh > "$work/reinstall.log" 2>&1 || { cat "$work/reinstall.log"; bad "重装失败"; exit 1; }
expect '[ "$(cat "$rime/squirrel.custom.yaml")" = "$(printf "# 我自己的设置\npatch:\n  style/font_point: 18")" ]' "squirrel.custom.yaml 没被覆盖"
expect 'grep -q 我的短语 "$rime/custom_phrase.txt"' "自定义短语没被覆盖"
expect '[ -f "$rime/rime_ice.userdb/000003.log" ]' "用户词库没被动"
expect '[ -f "$rime/rime_ice.schema.yaml" ]' "雾凇拼音补回来了"
expect 'ls "$work/backups"/*.tar.gz >/dev/null 2>&1' "装雾凇拼音前备份了"
expect 'grep -q "保留已有配置" "$work/reinstall.log"' "日志说了保留已有配置"

echo "== 卸载：默认保留配置和词库"
OHMYRIME_TEST_ROOT="$work" bash scripts/uninstall.sh > "$work/uninstall.log" 2>&1 || { cat "$work/uninstall.log"; bad "卸载失败"; exit 1; }
grep -E "^==> " "$work/uninstall.log" | sed 's/^/  /'
expect '[ ! -e "$work/Library/Input Methods/Squirrel.app" ]' "删掉了鼠须管"
expect '[ ! -e "$apps/鼠须管设置.app" ]' "删掉了鼠须管设置"
expect '[ -f "$rime/squirrel.custom.yaml" ] && [ -d "$rime/rime_ice.userdb" ]' "保留了配置和词库"
expect '[ ! -f "$work/home/Library/Application Support/鼠须管设置/installed.json" ]' "删掉了安装记录"

echo "== 卸载 --purge：连同配置和词库"
OHMYRIME_TEST_ROOT="$work" bash scripts/uninstall.sh --purge > "$work/purge.log" 2>&1 || { cat "$work/purge.log"; bad "purge 失败"; exit 1; }
expect '[ ! -e "$rime" ]' "删掉了用户文件夹"
expect '[ ! -e "$work/home/Library/Application Support/鼠须管设置" ]' "删掉了备份文件夹"

echo "== 没有雾凇拼音时（--no-rime-ice）：不写只启用雾凇的 default.custom.yaml"
rm -rf "$work/home" "$work/Library" "$apps"
OHMYRIME_TEST_ROOT="$work" bash scripts/install.sh --no-rime-ice > "$work/noice.log" 2>&1 || { cat "$work/noice.log"; bad "install.sh --no-rime-ice 失败"; exit 1; }
expect '[ ! -e "$rime/rime_ice.schema.yaml" ] && [ ! -e "$rime/default.custom.yaml" ]' "不装雾凇拼音，也不写会让人只能打英文的配置"
expect '[ -f "$rime/squirrel.custom.yaml" ]' "外观配置照写"

echo "== App 里的那一份：已经装在「应用程序」里的 App，用自带的鼠须管"
rm -rf "$apps"
mkdir -p "$apps"
ditto "$root/build/settings/鼠须管设置.app" "$apps/鼠须管设置.app"
OHMYRIME_TEST_ROOT="$work" bash "$apps/鼠须管设置.app/Contents/Resources/scripts/install.sh" --no-rime-ice > "$work/app.log" 2>&1 || { cat "$work/app.log"; bad "App 里的 install.sh 失败"; exit 1; }
grep -E "^==> " "$work/app.log" | sed 's/^/  /'
expect 'grep -q "准备鼠须管" "$work/app.log"' "从 Payload 里解压鼠须管"
expect '[ -x "$apps/鼠须管设置.app/Contents/MacOS/SquirrelSettings" ]' "把 App 自己装进 Applications"
expect 'grep -q "就是运行中的这一份" "$work/app.log"' "不重复复制自己"

echo ""
[ $fail -eq 0 ] && echo "ALL CHECKS PASSED" || echo "$fail CHECK(S) FAILED"
exit $fail
