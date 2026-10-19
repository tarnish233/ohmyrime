#!/usr/bin/env bash
# 安装 ohmyrime 版鼠须管到 /Library/Input Methods（官方位置，需要输入一次管理员密码），
# 注册并尝试启用输入源，但不切换当前输入法。只改动 /Library/Input Methods/Squirrel.app，
# 不碰同目录下的其他输入法（如微信输入法）。
#
# 为什么不用 ~/Library/Input Methods：在 macOS 27 上，用户目录里的输入法虽然能被注册，
# 但启用请求会被静默忽略，系统设置里也列不出来。
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/squirrel/build/Build/Products/Release/Squirrel.app"
dest="/Library/Input Methods/Squirrel.app"
user_copy="$HOME/Library/Input Methods/Squirrel.app"
rime_dir="$HOME/Library/Rime"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

[ -d "$app" ] || { echo "未找到构建产物，请先运行 scripts/build.sh" >&2; exit 1; }

# 1. 退出正在运行的鼠须管，下次使用时系统会启动新版本
pkill -x Squirrel 2>/dev/null && sleep 1 || true

# 2. 早期版本装在 ~/Library/Input Methods：删掉，避免两个同 ID 的输入法互相干扰
if [ -d "$user_copy" ]; then
  "$lsregister" -u "$user_copy" 2>/dev/null || true
  rm -rf "$user_copy"
  echo "已移除旧位置：$user_copy"
fi
# 构建目录里的副本也会被 LaunchServices 登记；取消登记，避免系统找错应用
"$lsregister" -u "$app" 2>/dev/null || true

# 3. 复制到 /Library/Input Methods（弹出管理员密码框）。
#    先完整复制到同目录的临时文件夹，再改名对调。如果先删后拷，app 不在的那几秒里
#    系统重建输入法缓存，就会把鼠须管丢掉，表现为菜单里选不了鼠须管。
#    用 ditto 而不是 rsync：Contents/MacOS/rime-install 是脚本，它的签名存放在扩展属性里。
/usr/bin/osascript - "$app" "$dest" <<'APPLESCRIPT'
on run argv
  set src to item 1 of argv
  set dst to item 2 of argv
  if dst is not "/Library/Input Methods/Squirrel.app" then error "unexpected destination: " & dst
  set newCopy to quoted form of "/Library/Input Methods/.Squirrel.app.new"
  set oldCopy to quoted form of "/Library/Input Methods/.Squirrel.app.old"
  set cmd to "set -e; /bin/rm -rf " & newCopy & " " & oldCopy
  set cmd to cmd & "; /usr/bin/ditto " & quoted form of src & " " & newCopy
  set cmd to cmd & "; /usr/sbin/chown -R root:wheel " & newCopy
  set cmd to cmd & "; if [ -e " & quoted form of dst & " ]; then /bin/mv " & quoted form of dst & " " & oldCopy & "; fi"
  set cmd to cmd & "; /bin/mv " & newCopy & " " & quoted form of dst
  set cmd to cmd & "; /bin/rm -rf " & oldCopy
  do shell script cmd with prompt "ohmyrime 要把鼠须管安装到 /Library/Input Methods。" with administrator privileges
end run
APPLESCRIPT
"$lsregister" -f "$dest"
echo "已安装：$dest"

# 4. 用户配置：只补充缺失的文件，不覆盖已有修改
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

# 5. 注册并启用输入源（不切换）
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
# 替换 app 后，系统会在十几秒内重建输入法缓存，偶尔会把刚注册的鼠须管丢掉。过一会儿再确认
# 几次：系统里看不到已启用的鼠须管时，--register-input-source 会重新注册；看得到时只打印
# 「already registered」。
registered=false
for check in 1 2 3 4; do
  sleep 6
  output=$(squirrel --register-input-source)
  if [[ $output == *"already registered"* ]]; then
    registered=true
    break
  fi
done
squirrel --enable-input-source

# 6. 在后台启动一次：新装的输入法在本次登录内可能拉不起来（imklaunchagent 报
#    LaunchInputMethod() Error -50，表现为只能打英文）。启动后它会自己登记连接端点，
#    并完成首次部署；下次登录后由系统自动启动。
open -g "$dest"

echo
if $registered; then
  echo "完成。在菜单栏输入法菜单中选择「鼠须管」即可使用，首次使用会自动部署（几秒钟）。"
else
  echo "完成。如果输入法菜单里还没有「鼠须管」，手动添加一次（之后重装不用再加）："
  echo "  先 ⌘Q 退出「系统设置」再打开 → 键盘 → 文字输入「输入法」→ 编辑… → 左下角 + → 简体中文 → 鼠须管 → 添加"
  echo "如果菜单里有鼠须管却选不中，等半分钟后重新注册："
  echo "  '$dest/Contents/MacOS/Squirrel' --register-input-source"
fi
echo "修改 ~/Library/Rime 下的配置后，用「鼠须管 → 重新部署」生效。"
