#!/usr/bin/env bash
# 安装 ohmyrime：
#   - ohmyrime 版鼠须管 → /Library/Input Methods（弹一次管理员密码框）；
#   - 还没有雾凇拼音就装上，已有的配置和用户词库都保留；
#   - 「鼠须管设置」→「应用程序」（写不了时装到 ~/Applications）。
# 不切换当前输入法，也不替你把鼠须管添加到输入法：macOS 要求用户自己在系统设置里添加第三方
# 输入法，「鼠须管设置」的欢迎页会一步步引导，加好了自动打勾。
#
# 同一个脚本两种用法：
#   - 「鼠须管设置」的「安装」按钮运行 App 里的这一份（Contents/Resources/scripts/install.sh）：
#     鼠须管和雾凇拼音都用 App 自带的（Contents/Resources/Payload），不联网；
#   - 从源码构建后在仓库里运行 scripts/install.sh：用 squirrel/build 和 build/settings 里的产物，
#     雾凇拼音用 scripts/build-settings.sh 下载的 .cache/rime-ice/full.zip。
#
#   scripts/install.sh [--no-rime-ice]
#
# 以「==> 」开头的行是步骤，App 用它们显示进度。
# 测试用：OHMYRIME_TEST_ROOT=<目录> 把安装位置都换到这个目录里，并跳过要系统配合的步骤
# （管理员密码、注册输入源、结束和启动进程）。
#
# 为什么不用 ~/Library/Input Methods：在 macOS 27 上，用户目录里的输入法虽然能被注册，
# 但启用请求会被静默忽略，系统设置里也列不出来。
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
step() { printf '==> %s\n' "$*"; }

install_ice=true
for arg in "$@"; do
  case "$arg" in
    --no-rime-ice) install_ice=false ;;
    *) echo "用法：scripts/install.sh [--no-rime-ice]" >&2; exit 2 ;;
  esac
done

test_root="${OHMYRIME_TEST_ROOT:-}"
if [ -n "$test_root" ]; then
  mkdir -p "$test_root"
  test_root="$(cd "$test_root" && pwd)"
  home="$test_root/home"
  input_methods="$test_root/Library/Input Methods"
  apps_dirs=("$test_root/Applications")
else
  home="$HOME"
  input_methods="/Library/Input Methods"
  apps_dirs=(/Applications "$HOME/Applications")
fi
# 真的安装（不是测试）时才做要系统配合的步骤
real() { [ -z "$test_root" ]; }
dest="$input_methods/Squirrel.app"
rime_dir="$home/Library/Rime"
support_dir="$home/Library/Application Support/鼠须管设置"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# 从哪里装：App 里（带着 Payload），或者仓库里
if [ -f "$root/Payload/Squirrel.zip" ]; then
  from_app=true
  settings_app="$(cd "$root/../.." && pwd)"
  ice_zip="$root/Payload/rime-ice.zip"
  ice_backups="$support_dir/Backups/$(date +%Y%m%d-%H%M%S)"
else
  from_app=false
  settings_app="$root/build/settings/鼠须管设置.app"
  ice_zip="$root/.cache/rime-ice/full.zip"
  ice_backups="$root/.backup"
  [ -n "$test_root" ] && ice_backups="$test_root/backups"
  squirrel_app="$root/squirrel/build/Build/Products/Release/Squirrel.app"
fi
work=$(mktemp -d "${TMPDIR:-/tmp}/ohmyrime-install.XXXXXX")
trap 'rm -rf "$work"' EXIT
if $from_app; then
  step "准备鼠须管"
  ditto -x -k "$root/Payload/Squirrel.zip" "$work"
  squirrel_app="$work/Squirrel.app"
fi
[ -x "$squirrel_app/Contents/MacOS/Squirrel" ] || { echo "未找到鼠须管：请先运行 scripts/build.sh" >&2; exit 1; }

# 之前就添加过鼠须管（重装、更新）：装完要确认系统没有把它弄丢
# macOS 27 把用户添加的第三方输入法记在 com.apple.inputsources，早一些的版本记在 HIToolbox
was_added=false
if real && { defaults read com.apple.inputsources AppleEnabledThirdPartyInputSources 2>/dev/null
             defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null; } | grep -q 'im.rime.inputmethod.Squirrel'; then
  was_added=true
fi

# 1. 退出正在运行的鼠须管，装完再启动新版本
if real; then
  pkill -x Squirrel 2>/dev/null && sleep 1 || true
fi

# 2. 早期版本装在 ~/Library/Input Methods：删掉，避免两个同 ID 的输入法互相干扰
user_copy="$home/Library/Input Methods/Squirrel.app"
if [ -d "$user_copy" ]; then
  real && { "$lsregister" -u "$user_copy" 2>/dev/null || true; }
  rm -rf "$user_copy"
  echo "已移除旧位置：$user_copy"
fi
# 构建目录里的副本也会被 LaunchServices 登记；取消登记，避免系统找错应用
if real && ! $from_app; then
  "$lsregister" -u "$squirrel_app" 2>/dev/null || true
fi

# 3. 复制到 /Library/Input Methods（弹出管理员密码框）。
#    先完整复制到同目录的临时文件夹，再改名对调。如果先删后拷，app 不在的那几秒里
#    系统重建输入法缓存，就会把鼠须管丢掉，表现为菜单里选不了鼠须管。
#    用 ditto 而不是 rsync：Contents/MacOS/rime-install 是脚本，它的签名存放在扩展属性里。
#    从网上下载的 App 带着隔离标记，没有经过 Apple 公证的输入法会被拦下，所以去掉。
step "安装鼠须管"
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
new="$input_methods/.Squirrel.app.new"
old="$input_methods/.Squirrel.app.old"
copy="set -e; /bin/rm -rf $(q "$new") $(q "$old"); /usr/bin/ditto $(q "$squirrel_app") $(q "$new")"
real && copy+="; /usr/sbin/chown -R root:wheel $(q "$new")"
copy+="; /usr/bin/xattr -dr com.apple.quarantine $(q "$new") 2>/dev/null || true"
copy+="; if [ -e $(q "$dest") ]; then /bin/mv $(q "$dest") $(q "$old"); fi"
copy+="; /bin/mv $(q "$new") $(q "$dest"); /bin/rm -rf $(q "$old")"
if real; then
  [ "$dest" = "/Library/Input Methods/Squirrel.app" ] || { echo "安装位置不对：$dest" >&2; exit 1; }
  /usr/bin/osascript -e 'on run argv' -e 'do shell script (item 1 of argv) with prompt (item 2 of argv) with administrator privileges' -e 'end run' \
    "$copy" "ohmyrime 要把鼠须管安装到 /Library/Input Methods。"
  "$lsregister" -f "$dest"
else
  mkdir -p "$input_methods"
  /bin/sh -c "$copy"
fi
echo "已安装：$dest"

# 4. 雾凇拼音：还没装就装上。装不上不中断安装，之后可以在「鼠须管设置 → 雾凇拼音」里再装
ice_installed() { [ -f "$rime_dir/rime_ice.schema.yaml" ]; }
if ice_installed; then
  echo "雾凇拼音已安装，保留现在的版本（更新在「鼠须管设置 → 雾凇拼音」里）"
elif ! $install_ice; then
  echo "按 --no-rime-ice 跳过雾凇拼音"
else
  step "安装雾凇拼音"
  # 仓库里还没有下载过（没运行过 build-settings.sh）就现下载
  ice_args=()
  [ -f "$ice_zip" ] && ice_args=(--from "$ice_zip")
  OHMYRIME_RIME_DIR="$rime_dir" OHMYRIME_BACKUP_DIR="$ice_backups" OHMYRIME_TEMPLATES_DIR="$root/rime" OHMYRIME_NO_RELOAD=1 \
    bash "$here/rime-ice.sh" ${ice_args[@]+"${ice_args[@]}"} || echo "雾凇拼音没装上，可以之后在「鼠须管设置 → 雾凇拼音」里再装" >&2
fi

# 5. 用户配置：只补充缺失的文件，不覆盖已有修改。default.custom.yaml 只启用雾凇拼音，
#    雾凇拼音还没装时不写它，否则鼠须管找不到方案，只能打英文（装雾凇拼音时会补上）
step "写入配置"
mkdir -p "$rime_dir"
for file in "$root"/rime/*.yaml; do
  name=$(basename "$file")
  target="$rime_dir/$name"
  if [ -e "$target" ]; then
    echo "保留已有配置：$target"
  elif [ "$name" = default.custom.yaml ] && ! ice_installed; then
    echo "暂不写入：${target}（它只启用雾凇拼音）"
  else
    cp "$file" "$target"
    echo "写入配置：$target"
  fi
done

# 6. 注册输入源（不启用、不切换：添加由用户在系统设置里做）
# 新构建的程序第一次运行时，终端安全软件（如阿里郎）可能先扫描并结束进程（Killed: 9），
# 扫描通过后即可正常运行，所以先预热并重试几次。
if real; then
  step "注册输入法"
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
  # 重装时：替换 app 后，系统会在十几秒内重建输入法缓存，偶尔会把鼠须管丢掉。过一会儿再确认
  # 几次：系统里看不到已启用的鼠须管时，--register-input-source 会重新注册；看得到时只打印
  # 「already registered」。第一次安装不用等：用户去系统设置添加时缓存早就建好了，
  # 欢迎页也会在列表里没有鼠须管时重新注册。
  if $was_added; then
    for check in 1 2 3 4; do
      sleep 6
      output=$(squirrel --register-input-source)
      [[ $output == *"already registered"* ]] && break
    done
  fi
fi

# 7. 「鼠须管设置」装进「应用程序」：管理员用户可直接写 /Applications，不用密码；
#    写不了时装到 ~/Applications。鼠须管菜单里的「设置…」按 bundle ID 找到它。
same() { [ "$(cd "$1" 2>/dev/null && pwd -P)" = "$(cd "$2" 2>/dev/null && pwd -P)" ]; }
settings_dest=""
if [ -d "$settings_app" ]; then
  step "安装鼠须管设置"
  apps_dir="${apps_dirs[0]}"
  if real && [ ! -w "$apps_dir" ]; then
    apps_dir="${apps_dirs[1]}"
  fi
  mkdir -p "$apps_dir"
  settings_dest="$apps_dir/鼠须管设置.app"
  if same "$settings_app" "$settings_dest"; then
    echo "就是运行中的这一份：$settings_dest"
  else
    # 旧版本还开着就关掉（运行安装的 App 自己除外）
    if real; then
      for pid in $(pgrep -x SquirrelSettings || true); do
        [ "$pid" = "${OHMYRIME_APP_PID:-}" ] || kill "$pid" 2>/dev/null || true
      done
    fi
    rm -rf "$settings_dest"
    ditto "$settings_app" "$settings_dest"
    xattr -dr com.apple.quarantine "$settings_dest" 2>/dev/null || true
    real && { "$lsregister" -f "$settings_dest" 2>/dev/null || true; }
    echo "已安装：$settings_dest"
  fi
  # 另一个位置的旧副本（比如以前 /Applications 写不了时装在 ~/Applications）
  for other in "${apps_dirs[@]}"; do
    other_app="$other/鼠须管设置.app"
    if [ "$other" != "$apps_dir" ] && [ -d "$other_app" ] && ! same "$other_app" "$settings_app"; then
      rm -rf "$other_app"
      echo "已移除旧副本：$other_app"
    fi
  done
else
  echo "没有找到「鼠须管设置」，跳过：$settings_app" >&2
fi

# 8. 记下装的是哪一版：「鼠须管设置」打开时据此判断已装的鼠须管是不是它带的那一版
mkdir -p "$support_dir"
hash=$(shasum -a 256 "$dest/Contents/MacOS/Squirrel" | cut -d' ' -f1)
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$settings_app/Contents/Info.plist" 2>/dev/null || true)
printf '{"version": "%s", "squirrelHash": "%s", "date": "%s"}\n' "$version" "$hash" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$support_dir/installed.json"

# 9. 在后台启动：新装的输入法在本次登录内可能拉不起来（imklaunchagent 报
#    LaunchInputMethod() Error -50，表现为只能打英文）。启动后它会自己登记连接端点，
#    并完成首次部署；下次登录后由系统自动启动。
if real; then
  step "启动鼠须管"
  open -g "$dest"
fi

step "完成"
if ! $from_app; then
  echo
  if ! ice_installed; then
    echo "还没有雾凇拼音：联网后运行 scripts/rime-ice.sh，或在「鼠须管设置 → 雾凇拼音」里安装。"
  fi
  if $was_added || ! real; then
    echo "鼠须管已更新。设置：鼠须管菜单 →「设置…」。"
  else
    echo "装好了。接下来在「鼠须管设置」里把鼠须管添加到输入法，它会一步步引导。"
    if [ -n "$settings_dest" ]; then
      open "$settings_dest"
    fi
  fi
fi
