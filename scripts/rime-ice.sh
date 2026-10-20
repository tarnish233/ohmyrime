#!/usr/bin/env bash
# 安装 / 更新雾凇拼音（https://github.com/iDvel/rime-ice）到 ~/Library/Rime，并让鼠须管重新部署。
#
# 和官方「清空用户目录再复制」不同：
#   - 保留 *.custom.yaml、用户词库（*.userdb）、同步目录等个人数据；
#   - 不安装它的 squirrel.yaml / weasel.yaml：外观沿用 ohmyrime 版鼠须管的配置
#     （卷轴模式只在横排生效，而雾凇拼音的 squirrel.yaml 默认竖排）；
#   - custom_phrase.txt 只在不存在时复制，不覆盖你加的短语。
# 每次安装前把 ~/Library/Rime（不含 build/）备份到 .backup/。
#
#   scripts/rime-ice.sh            下载最新版并安装
#   scripts/rime-ice.sh --offline  使用 .cache 里上次下载的版本
#
# 「鼠须管设置」里的「安装雾凇拼音」运行的也是这个脚本（打包在 App 里），用环境变量换目录：
#   OHMYRIME_RIME_DIR       装到哪个用户文件夹（默认 ~/Library/Rime）
#   OHMYRIME_CACHE_DIR      下载缓存（默认 .cache/rime-ice）
#   OHMYRIME_BACKUP_DIR     备份放在哪（默认 .backup）
#   OHMYRIME_TEMPLATES_DIR  ohmyrime 的配置模板（默认 rime/）
#   OHMYRIME_NO_RELOAD=1    装完不通知鼠须管（App 自己部署）
#   OHMYRIME_PROXY          下载用的代理（默认 http://127.0.0.1:7890），连得上才用
#   OHMYRIME_RIME_ICE_URL   从别处下载 full.zip（如镜像）
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
rime_dir="${OHMYRIME_RIME_DIR:-$HOME/Library/Rime}"
cache="${OHMYRIME_CACHE_DIR:-$root/.cache/rime-ice}"
backup_dir="${OHMYRIME_BACKUP_DIR:-$root/.backup}"
templates="${OHMYRIME_TEMPLATES_DIR:-$root/rime}"
url="${OHMYRIME_RIME_ICE_URL:-https://github.com/iDvel/rime-ice/releases/latest/download/full.zip}"
squirrel="/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
proxy="${OHMYRIME_PROXY:-http://127.0.0.1:7890}"

# 1. 下载并解压
mkdir -p "$cache"
# download <重试次数> [curl 选项…]。代理或网络偶尔会断开连接（curl 35/56），
# 这类错误 --retry 默认不重试，所以加 --retry-all-errors
download() {
  echo "下载：$url"
  curl -fL -# --retry "$1" --retry-all-errors --retry-delay 1 --connect-timeout 20 -o "$cache/full.zip.part" "${@:2}" "$url"
}
if [ "${1:-}" != "--offline" ]; then
  # 代理连得上 github.com 时先走代理；下载文件的服务器（release-assets.githubusercontent.com）
  # 经代理不一定通，失败就改为直接连接
  if curl -s -o /dev/null --max-time 5 -x "$proxy" https://github.com; then
    echo "代理：$proxy"
    download 1 -x "$proxy" || { echo "经代理下载失败，改为直接连接"; download 3; }
  else
    download 3
  fi
  mv "$cache/full.zip.part" "$cache/full.zip"
fi
[ -f "$cache/full.zip" ] || { echo "没有可用的 full.zip，请去掉 --offline 重新下载" >&2; exit 1; }
echo "解压：$cache/full.zip"
rm -rf "$cache/full"
mkdir -p "$cache/full"
unzip -q "$cache/full.zip" -d "$cache/full"
[ -f "$cache/full/rime_ice.schema.yaml" ] || { echo "压缩包里没有 rime_ice.schema.yaml，内容不对" >&2; exit 1; }

# 2. 备份
mkdir -p "$rime_dir" "$backup_dir"
backup="$backup_dir/Rime-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf "$backup" -C "$(dirname "$rime_dir")" --exclude "$(basename "$rime_dir")/build" "$(basename "$rime_dir")"
echo "已备份：$backup"

# 3. 安装
rsync -a --exclude squirrel.yaml --exclude weasel.yaml --exclude LICENSE --exclude custom_phrase.txt \
  "$cache/full/" "$rime_dir/"
[ -e "$rime_dir/custom_phrase.txt" ] || cp "$cache/full/custom_phrase.txt" "$rime_dir/"
# 解压出来的约 50 MB 用完就删；full.zip 留给 --offline
rm -rf "$cache/full"
for file in "$templates"/*.yaml; do
  [ -e "$file" ] || continue
  target="$rime_dir/$(basename "$file")"
  if [ ! -e "$target" ]; then
    cp "$file" "$target"
    echo "写入配置：$target"
  fi
done
if ! grep -q "schema: rime_ice" "$rime_dir/default.custom.yaml" 2>/dev/null; then
  echo "注意：$rime_dir/default.custom.yaml 的 schema_list 里没有 rime_ice，可参考 $templates/default.custom.yaml" >&2
fi
version=$(sed -n 's/^  version: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' "$rime_dir/rime_ice.schema.yaml" | head -1)
# 变量名后紧跟全角字符要加花括号：UTF-8 环境下 bash 3.2 会把全角字符的第一个字节当成变量名的一部分
echo "已安装雾凇拼音${version:+（${version}）}到：$rime_dir"

# 4. 重新部署
if [ -n "${OHMYRIME_NO_RELOAD:-}" ]; then
  :
elif pgrep -xq Squirrel; then
  "$squirrel" --reload
  echo "已通知鼠须管重新部署，十几秒后即可使用。"
else
  echo "鼠须管没有运行，下次使用时会自动部署。"
fi
