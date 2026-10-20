# ohmyrime

基于 [Rime](https://rime.im) 的个人输入法方案。

| 目录 | 内容 |
|---|---|
| `squirrel/` | [鼠须管](https://github.com/rime/squirrel) fork（独立 git 仓库，分支 `ohmyrime`），加入卷轴模式和液态玻璃外观 |
| `settings/` | 「鼠须管设置」：图形界面的设置 App（SwiftUI），改完自动生效 |
| `rime/` | Rime 用户配置模板，安装时复制到 `~/Library/Rime`（不覆盖已有文件） |
| `scripts/` | `build.sh` 构建（含设置 App）、`install.sh` 安装（没装雾凇拼音时一并安装）、`uninstall.sh` 卸载、`rime-ice.sh` 安装或更新雾凇拼音、`rime-smoke.sh` 冒烟测试、`test-settings.sh` 设置 App 的测试 |
| `tools/` | `rime-smoke.c`：用本地 librime 部署配置并打印按键结果；`tis-props.swift`：查看系统输入法框架里的输入源状态（只读） |

## 设置 App：鼠须管设置

不用再手改 YAML：鼠须管菜单里的「设置…」（⌃⌥,），或「应用程序」里的「鼠须管设置」。改完停手约 0.7 秒自动保存，鼠须管随即重新部署：外观立刻生效，方案改动要几秒。工具栏右上角显示状态（已生效 / 部署中 / 失败时的错误）。

| 页面 | 能设置的 | 写到 |
|---|---|---|
| 外观 | 液态玻璃 / 系统配色 / 预设配色，玻璃质感，一行或一列、横排或竖排，卷轴模式（行数、Tab 翻页、列宽），字体和字号、选中项字重，候选格式，圆角、留白、间距、行距，动效，菜单栏图标，部署通知；顶部是实时预览 | `squirrel.custom.yaml` |
| 输入 | 启用哪些方案和顺序（找不到方案文件的标「未安装」），每页候选数，左右 Shift / Control / Caps Lock 怎样切换中英，翻页键（- = / , . / [ ] / Tab），以词定字，方案选单快捷键 | `default.custom.yaml` |
| 雾凇拼音 | 安装或更新雾凇拼音；新输入框的默认状态（中英、标点、简繁、Emoji、全角、单字优先），模糊音（z/zh、n/l、an/ang 等 10 组） | `rime_ice.custom.yaml`，启用的双拼方案也一起改 |
| 应用 | 按应用：默认英文、不内嵌编码、Vim 模式；可添加、移除应用 | `squirrel.custom.yaml` 的 `app_options` |
| 短语 | 自定义短语表格：短语、编码、权重，可搜索 | `custom_phrase.txt` |
| 词库与部署 | 用户词库大小，同步文件夹（可设到 iCloud 云盘）、立即同步、备份用户文件夹，部署状态和错误日志 | `installation.yaml` 的 `sync_dir` |

- 预览：顶部的候选框就是鼠须管自己的候选框代码画的（编进了设置 App），用的是窗口里当前的设置，没保存的也算，和实际打字时一模一样，包括玻璃、字体和动效。可以切「单行 / 展开」和「浅色 / 深色」。
- 怎么写配置：只改动用到的那几项，其他行、注释、空行原样保留。原来就在文件里的行就地修改；设回默认值时，App 自己加的项会删掉，你写的行会留着。
  - 写之前用 librime 自己的 YAML 解析器检查一遍，读不了就不写。
  - 每次打开 App 后第一次改动之前，原文件备份到 `~/Library/Application Support/鼠须管设置/Backups/<时间>/`，保留最近 20 次。
- 用文本编辑器改过配置，切回 App 时会自动重新读取。
- 没装雾凇拼音时：「雾凇拼音」页有「安装雾凇拼音」按钮；启用的方案都找不到（只能打英文）时，每页顶部有提示，「输入」页把这些方案标成「未安装」。
  - 按钮运行打包在 App 里的 `scripts/rime-ice.sh`，和命令行装的完全一样：先备份用户文件夹，再装雾凇拼音（不装它的 `squirrel.yaml`），保留你的 `*.custom.yaml`、用户词库和自定义短语。
  - 装好后设为默认方案并部署，第一次要编译词库，十几秒。下载显示进度，可以取消；装好后同一个位置变成「更新到最新版」。
  - 先用系统代理，或本机 7890 端口的代理，连不上就直接连接。下载缓存在 `~/Library/Caches/im.rime.ohmyrime.settings`，备份放在 `~/Library/Application Support/鼠须管设置/Backups`。
- 生效方式：
  - 只改了外观（`style/…`、菜单栏图标、部署通知）时，鼠须管只重新生成 `build/squirrel.yaml`、重新载入外观，十几毫秒；Rime 不重启，各应用里打了一半的拼音和用 Shift 切换的中英状态都保留。
  - 其他改动通知鼠须管「安静地」重新部署（不弹通知），和菜单「重新部署」一样会重启 Rime、重开所有输入会话。「雾凇拼音」页约 0.2 秒；「输入」页改的是所有方案共用的 `default.yaml`，每个方案都要重建，英文方案最慢，合计约 3 秒。「应用」页的按应用选项只在打开输入会话时读取，所以也走这条路。
  - 鼠须管做完回报结果（`success` / `failure` / `unchanged` / `reloaded`）。
  - librime 按秒比较文件时间，同一秒内的第二次保存会被当成没改，所以 App 会等过了上次部署的那一秒再保存，必要时再请求一次。

测试：`scripts/test-settings.sh` 在 `~/Library/Rime` 的副本上跑模型测试（YAML 往返、逐行编辑、各页设置），再用 librime 部署这份副本，打字确认改动生效（每页 7 个、模糊音、翻页键、自定义短语），不碰真正的配置。它还用 `.cache/rime-ice/full.zip` 往一个空文件夹离线装一遍雾凇拼音，确认用户自己的设置和短语保留、部署没有错误。对真正的鼠须管：`SQUIRREL_SETTINGS_SELFTEST=deploy "/Applications/鼠须管设置.app/Contents/MacOS/SquirrelSettings"` 把外观和每页候选数各改一个来回，确认外观改动只重新载入、Rime 日志里没有重启，文件最后恢复原样（要等 31 秒，glog 才把日志写出来）。截图检查：`SQUIRREL_SETTINGS_USER_DIR=<副本> SQUIRREL_SETTINGS_NO_DEPLOY=1 SQUIRREL_SETTINGS_SNAPSHOT=<输出目录> "/Applications/鼠须管设置.app/Contents/MacOS/SquirrelSettings"`，只截这个 App 自己的窗口。

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

每一行（单行和展开后的每一行）都不换行。行宽最多可到屏幕宽度的 90%，候选框靠近屏幕右边时会整体左移。超过这个宽度时，最长的几个候选末尾截成「…」，截到正好放下。截断只影响显示，上屏的仍是完整候选。

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
scripts/build.sh      # 首次会下载预编译 librime、Sparkle 和默认方案；本机 7890 端口有代理时自动使用；最后构建设置 App
scripts/install.sh    # 鼠须管装到 /Library/Input Methods（官方位置，会弹一次管理员密码框），只动 Squirrel.app；
                      # 还没装雾凇拼音就一并下载安装；「鼠须管设置」装到 /Applications（不用密码）
```

新电脑上这两条就够了，之后在菜单栏选「鼠须管」就能打字。`install.sh` 的其他行为：
- 雾凇拼音装过的就跳过；加 `--no-rime-ice` 不装。
- 下载失败不会中断安装，可以之后再用 `scripts/rime-ice.sh` 或设置 App 补装。
- 没装上雾凇拼音时，不写入只启用雾凇拼音的 `default.custom.yaml`，鼠须管先用自带的朙月拼音，不会变成只能打英文。

首次安装后要手动添加一次（以后重装不用再加）：先 ⌘Q 退出「系统设置」再打开 → 键盘 → 文字输入「输入法」→ 编辑… → + → 简体中文 → 鼠须管。

macOS 27 上有两点限制：
- 命令行启用第三方输入法（`TISEnableInputSource`）会返回成功但不生效，所以必须在系统设置里加一次；
- `~/Library/Input Methods` 里的输入法系统重建列表时不扫描，会时有时无，所以装到 `/Library/Input Methods`。

切到鼠须管后只能打英文、没有候选框：说明鼠须管进程没起来（日志里是 `imklaunchagent: LaunchInputMethod() Error, status=-50`）。运行 `open -g "/Library/Input Methods/Squirrel.app"` 即可；`install.sh` 最后会自动执行这一步。注销重新登录后由系统自动启动。

菜单里有鼠须管却选不中（系统设置里也可能加不上）：系统的输入法缓存把它丢了，常见于刚替换完 app。运行 `"/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --register-input-source` 重新注册即可。`install.sh` 会在安装后确认几次，丢了就自动重新注册。要查看系统是否认得它，运行 `swiftc tools/tis-props.swift -o build/tis-props && build/tis-props rime`：能列出 `im.rime.inputmethod.Squirrel.Hans` 就说明系统认得。

卸载：`scripts/uninstall.sh`，同时删掉「鼠须管设置」，默认保留 `~/Library/Rime`；加 `--purge` 一并删除。

## 输入方案：雾凇拼音

[雾凇拼音](https://github.com/iDvel/rime-ice) 是一整套 Rime 配置：词库、全拼和双拼方案、Lua 扩展脚本（日期、计算器、以词定字等）以及按键设置。

```bash
scripts/rime-ice.sh             # 下载最新版，备份 ~/Library/Rime 后安装，并通知鼠须管重新部署
scripts/rime-ice.sh --offline   # 用 .cache 里上次下载的版本
```

`install.sh` 在没装雾凇拼音时会自动运行这个脚本。不用命令行也行：「鼠须管设置 → 雾凇拼音」里的「安装雾凇拼音 / 更新到最新版」运行的是同一个脚本（打包在 App 里），装完自动部署。

下载会先走代理：本机 7890 端口，或用 `OHMYRIME_PROXY` 指定。下载文件的服务器经代理不通时，改为直接连接。断线会自动重试。

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
  - `ohmyrime`：在 `scroll-mode` 之上，加上 fork 专用改动：按实际安装位置注册输入源、关闭 Sparkle 自动更新、液态玻璃外观和预览工具，以及配合设置 App 的部分：
    - 菜单「设置…」；
    - `SquirrelReloadNotification` 的 object 为 `"quiet"` 时安静部署，为 `"style"` 时只重新载入外观、不重启 Rime；
    - 部署完成通知 `SquirrelDeployDidFinishNotification`；
    - `SquirrelConfig.open(yaml:)`，供预览用。
- 测试：先 `make release`，再运行 `squirrel/tests/scroll_mode/run.sh`。
  - 它用真实 librime 和临时用户目录驱动真实的 `SquirrelInputController` / `SquirrelPanel`，检查翻页、展开、选词。
  - 面板截图输出到 `squirrel/build/scroll-harness/out`。
- 本机装有终端安全软件（阿里郎），会扫描新编译程序的首次运行，扫描期间可能直接结束进程（`Killed: 9`）：
  - `/tmp` 下运行新程序尤其容易被结束，所以测试产物放在 `build/`；
  - 安装脚本会先预热一次，失败时重试。
- 上游：`git -C squirrel fetch origin && git -C squirrel rebase origin/master scroll-mode`，再把 `ohmyrime` rebase 到 `scroll-mode`。
