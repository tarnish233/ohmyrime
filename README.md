# ohmyrime

基于 [Rime](https://rime.im) 的个人输入法方案。

| 目录 | 内容 |
|---|---|
| `squirrel/` | [鼠须管](https://github.com/rime/squirrel) fork（独立 git 仓库，分支 `ohmyrime`），加入卷轴模式和液态玻璃外观 |
| `rime/` | Rime 用户配置模板，安装时复制到 `~/Library/Rime`（不覆盖已有文件） |
| `scripts/` | `build.sh` 构建、`install.sh` 安装、`uninstall.sh` 卸载、`rime-ice.sh` 安装或更新雾凇拼音、`rime-smoke.sh` 冒烟测试 |
| `tools/` | `rime-smoke.c`：用本地 librime 部署配置并打印按键结果；`tis-props.swift`：查看系统输入法框架里的输入源状态（只读） |

## 卷轴模式

横排单行候选按 Tab 展开成多行网格，每行就是 Rime 的一页，可以上下滚动。翻页键对齐微信输入法「Tab / Shift+Tab 翻页」。

| 按键 | 单行时 | 展开后 |
|---|---|---|
| Tab、↓、`=`、滚轮向下 | 展开，高亮移到第 2 行同一列 | 下一行（同一列），超出可见行数时滚动 |
| Shift+Tab、↑、`-`、滚轮向上 | 回到第一个候选 | 上一行；在第一行时收起（`-` 不收起） |
| ←、→ | 前 / 后一个候选 | 同左，可跨行 |
| 数字键 | 选择本行候选 | 选择高亮行的候选（只有高亮行显示序号） |
| 空格 | 上屏高亮候选 | 同左 |
| 鼠标 | 点选、悬停高亮 | 可点选任意一行 |
| 继续输入、退格、Esc | — | 自动收起 |

配置（`~/Library/Rime/squirrel.custom.yaml`，改完「重新部署」）：

```yaml
patch:
  style/candidate_list_layout: linear   # 卷轴模式需要横排单行
  style/scroll_mode/enable: true
  style/scroll_mode/max_rows: 5         # 展开后最多显示几行（2–20）
  style/scroll_mode/tab_paging: true    # Tab / Shift+Tab 翻页；关掉后 Tab 交还给 Rime
```

每行候选数就是每页候选数：`default.custom.yaml` 里的 `menu/page_size`。

## 外观：液态玻璃

照 `workspace/wetype` 里微信输入法的玻璃主题（v10）做，尺寸逐项对过它的实拍截图：

- 背景：macOS 26 起用系统液态玻璃（`NSGlassEffectView`，regular 样式），更早的系统是毛玻璃。单行是胶囊形，展开后是 18 pt 圆角。深色模式在玻璃上加 50% 黑色遮罩，亮背景上的白字也清楚。系统开了「减少透明度」时，改用不透明底色。
- 选中项：系统蓝胶囊（0.5 pt 白边、顶部微光），配白色苹方 Medium。
- 其余文字：苹方 Regular 16，浅色 #282828、深色 #E8E8E8。序号是浅灰（#828282 / #B4B4B4），和候选同字号，并占固定宽度，所以每个词都从同一位置开始。
- 尺寸：单行高 32 pt，选中胶囊高 26 pt；展开后行距 32 pt、列宽至少 66 pt。行高固定，emoji 不会把行撑高。
- 动效：展开、收起时，窗口按 0.20 s / 0.16 s 和微信输入法相同的缓动曲线伸缩，内容固定在顶部。文字从 30% 不透明度淡入，展开时下移 4 pt 落位。动画中途反向，会从当前位置接着走。系统开了「减弱动态效果」时不播放。
- emoji 一律用彩色字体：苹方里 🉑 🉐 等是黑白字形。

可调的项（`~/Library/Rime/squirrel.custom.yaml`，改完「重新部署」）：

| 配置 | 现在 | 说明 |
|---|---|---|
| `style/translucency` | `true` | 配合原生配色 `color_scheme: native` 即为上面的液态玻璃外观；关掉回到不透明的系统窗口底色 |
| `style/glass_style` | `regular` | `regular` 磨砂、文字清楚；`clear` 更通透 |
| `style/corner_radius` | `18` | 展开（多行）时的圆角；单行总是胶囊形 |
| `style/border_width` / `border_height` | `9.5` / `4.8` | 左右 / 上下留白 |
| `style/candidate_spacing` | `13` | 候选之间的间距（pt） |
| `style/line_spacing` | `9.6` | 展开后行与行的间距 |
| `style/scroll_mode/column_width` | `66` | 展开后每列的最小宽度，短词排成整齐的格子 |
| `style/font_face` / `hilited_font_face` | 苹方 / 苹方 Medium | 候选字体 / 选中项字体；`system` 表示系统字体（SF + 苹方） |
| `style/font_point` / `label_font_point` / `comment_font_point` | `16` / `16` / `13` | 候选 / 序号 / 注释字号 |
| `style/candidate_format` | `"[label][candidate] [comment]"` | 序号紧贴候选 |
| `style/base_offset` | `-1.5` | 文字在面板里整体上下移动（负数向下），选中胶囊不动 |
| `style/motion` | `true` | 展开 / 收起动效 |

`glass_style`、`hilited_font_face`、`candidate_spacing`、`scroll_mode/column_width`、`motion` 和 `system` 字体是本 fork 新增的。原生配色加 `translucency` 的外观、液态玻璃下 `corner_radius` / `border_*` / `base_offset` 的含义，也和上游鼠须管不同。

预览和对比工具：
- `squirrel/tests/scroll_mode/preview.sh [某个 squirrel.custom.yaml] [输出目录]`：用 `~/Library/Rime` 的一份副本和给定配置，在屏幕上显示几秒钟测试窗口和真实候选框。
  - 截取浅色和深色下的单行、展开、带注释三种状态，以及展开 / 收起的动画中间帧；
  - 打印动画过程中的窗口尺寸；
  - 默认输出到 `squirrel/build/preview/out`。
- 截图前会检查截图区域里只有测试程序自己的窗口，有别的窗口挡着就跳过，不会拍到其它内容。
- `squirrel/tests/scroll_mode/measure.py <截图> [x y 宽 高]`：量出截图里蓝色胶囊、白字、序号与候选之间的间距，可以拿来和微信输入法的截图对比。
- `squirrel/tests/scroll_mode/contact-sheet.swift`：把多张截图拼成一张对比图。

## 构建与安装

```bash
scripts/build.sh      # 首次会下载预编译 librime、Sparkle 和默认方案；本机 7890 端口有代理时自动使用
scripts/install.sh    # 装到 /Library/Input Methods（官方位置，会弹一次管理员密码框），只动 Squirrel.app
```

首次安装后要手动添加一次（以后重装不用再加）：先 ⌘Q 退出「系统设置」再打开 → 键盘 → 文字输入「输入法」→ 编辑… → + → 简体中文 → 鼠须管。

macOS 27 上有两点限制：
- 命令行启用第三方输入法（`TISEnableInputSource`）会返回成功但不生效，所以必须在系统设置里加一次；
- `~/Library/Input Methods` 里的输入法系统重建列表时不扫描，会时有时无，所以装到 `/Library/Input Methods`。

切到鼠须管后只能打英文、没有候选框：说明鼠须管进程没起来（日志里是 `imklaunchagent: LaunchInputMethod() Error, status=-50`）。运行 `open -g "/Library/Input Methods/Squirrel.app"` 即可；`install.sh` 最后会自动执行这一步。注销重新登录后由系统自动启动。

菜单里有鼠须管却选不中（系统设置里也可能加不上）：系统的输入法缓存把它丢了，常见于刚替换完 app。运行 `"/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --register-input-source` 重新注册即可。`install.sh` 会在安装后确认几次，丢了就自动重新注册。要查看系统是否认得它，运行 `swiftc tools/tis-props.swift -o build/tis-props && build/tis-props rime`：能列出 `im.rime.inputmethod.Squirrel.Hans` 就说明系统认得。

卸载：`scripts/uninstall.sh`，默认保留 `~/Library/Rime`；加 `--purge` 一并删除。

## 输入方案：雾凇拼音

[雾凇拼音](https://github.com/iDvel/rime-ice) 是一整套 Rime 配置：词库、全拼和双拼方案、Lua 扩展脚本（日期、计算器、以词定字等）以及按键设置。

```bash
scripts/rime-ice.sh             # 下载最新版，备份 ~/Library/Rime 后安装，并通知鼠须管重新部署
scripts/rime-ice.sh --offline   # 用 .cache 里上次下载的版本
```

和官方的「清空用户目录再复制」不同，这个脚本：
- 保留 `*.custom.yaml`、用户词库和同步目录；
- 不装雾凇拼音的 `squirrel.yaml`：外观沿用本 fork 的配置，因为卷轴模式依赖横排，而它默认是竖排；
- `custom_phrase.txt` 只在没有时才复制。

每次安装前，`~/Library/Rime`（不含 `build/`）会备份到 `.backup/Rime-时间.tar.gz`。

| 输入 | 结果 |
|---|---|
| 拼音后按 `[` / `]` | 以词定字：上屏当前词的第一个 / 最后一个字 |
| `rq` `sj` `xq` `dt` `ts` | 日期、时间、星期、ISO 时间、时间戳 |
| `nl` | 农历 |
| `R123` | 数字和金额的大小写 |
| `cC1+1` | 计算器 |
| `U62fc` | Unicode 字符 |
| `v` 开头 | 符号，见 `symbols_v.yaml` |
| F4 或 Control+` | 方案选单：切换方案、简繁、全半角等 |

- 翻页：有候选时用 Tab / Shift+Tab，由卷轴模式处理；`-` `=` 也可以，`,` `.` 不翻页。
- 自定义短语写在 `~/Library/Rime/custom_phrase.txt`。
- 要用双拼，在 `default.custom.yaml` 的 `schema_list` 里加上对应方案（如 `double_pinyin_flypy`）。

验证配置：`scripts/rime-smoke.sh`。它把 `~/Library/Rime` 复制到 `build/rime-smoke`（不含用户词库），用本地 librime 重新部署，打印几组按键的结果和错误日志数量，不影响正在用的输入法。

## 开发

- `squirrel` 仓库的分支：
  - `scroll-mode`：卷轴模式功能和测试，基于上游 master，可以单独提 PR；
  - `ohmyrime`：在 `scroll-mode` 之上，加上 fork 专用改动：按实际安装位置注册输入源、关闭 Sparkle 自动更新，以及液态玻璃外观和预览工具。
- 测试：先 `make release`，再运行 `squirrel/tests/scroll_mode/run.sh`。
  - 它用真实 librime 和临时用户目录驱动真实的 `SquirrelInputController` / `SquirrelPanel`，检查翻页、展开、选词。
  - 面板截图输出到 `squirrel/build/scroll-harness/out`。
- 本机装有终端安全软件（阿里郎），会扫描新编译程序的首次运行，扫描期间可能直接结束进程（`Killed: 9`）：
  - `/tmp` 下运行新程序尤其容易被结束，所以测试产物放在 `build/`；
  - 安装脚本会先预热一次，失败时重试。
- 上游：`git -C squirrel fetch origin && git -C squirrel rebase origin/master scroll-mode`，再把 `ohmyrime` rebase 到 `scroll-mode`。
