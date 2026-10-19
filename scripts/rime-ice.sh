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
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
rime_dir="$HOME/Library/Rime"
cache="$root/.cache/rime-ice"
url="https://github.com/iDvel/rime-ice/releases/latest/download/full.zip"
squirrel="/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
proxy="${OHMYRIME_PROXY:-http://127.0.0.1:7890}"

# 1. 下载并解压
mkdir -p "$cache"
if [ "${1:-}" != "--offline" ]; then
  opts=(-fL -# --retry 2 -o "$cache/full.zip.part")
  if curl -s -o /dev/null --max-time 5 -x "$proxy" https://github.com; then
    opts+=(-x "$proxy")
  fi
  echo "下载：$url"
  curl "${opts[@]}" "$url"
  mv "$cache/full.zip.part" "$cache/full.zip"
fi
[ -f "$cache/full.zip" ] || { echo "没有可用的 full.zip，请去掉 --offline 重新下载" >&2; exit 1; }
rm -rf "$cache/full"
mkdir -p "$cache/full"
unzip -q "$cache/full.zip" -d "$cache/full"
[ -f "$cache/full/rime_ice.schema.yaml" ] || { echo "压缩包里没有 rime_ice.schema.yaml，内容不对" >&2; exit 1; }

# 2. 备份
mkdir -p "$rime_dir" "$root/.backup"
backup="$root/.backup/Rime-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf "$backup" -C "$HOME/Library" --exclude 'Rime/build' Rime
echo "已备份：$backup"

# 3. 安装
rsync -a --exclude squirrel.yaml --exclude weasel.yaml --exclude LICENSE --exclude custom_phrase.txt \
  "$cache/full/" "$rime_dir/"
[ -e "$rime_dir/custom_phrase.txt" ] || cp "$cache/full/custom_phrase.txt" "$rime_dir/"
for file in "$root"/rime/*.yaml; do
  target="$rime_dir/$(basename "$file")"
  if [ ! -e "$target" ]; then
    cp "$file" "$target"
    echo "写入配置：$target"
  fi
done
if ! grep -q "schema: rime_ice" "$rime_dir/default.custom.yaml"; then
  echo "注意：$rime_dir/default.custom.yaml 的 schema_list 里没有 rime_ice，可参考 $root/rime/default.custom.yaml" >&2
fi
echo "已安装雾凇拼音到：$rime_dir"

# 4. 重新部署
if pgrep -xq Squirrel; then
  "$squirrel" --reload
  echo "已通知鼠须管重新部署，十几秒后即可使用。"
else
  echo "鼠须管没有运行，下次使用时会自动部署。"
fi
