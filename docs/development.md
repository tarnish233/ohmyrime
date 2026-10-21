# ohmyrime 技术文档

README 只讲安装和设置 App。这里是实现、配置项和开发说明。

- [目录结构](#目录结构)
- [构建与安装](#构建与安装)
- [常见问题](#常见问题)
- [卷轴模式](#卷轴模式)
- [液态玻璃外观](#液态玻璃外观)
- [设置 App](#设置-app)
- [雾凇拼音](#雾凇拼音)
- [开发](#开发)
- [发布](#发布)

## 目录结构

| 路径 | 内容 |
|---|---|
| `squirrel/` | 鼠须管 fork，git 子模块：[tarnish233/squirrel](https://github.com/tarnish233/squirrel) 的 `ohmyrime` 分支，见[开发](#开发) |
| `settings/` | 「鼠须管设置」（SwiftUI）。它同时是安装器：里面带着鼠须管和雾凇拼音 |
| `rime/` | Rime 用户配置模板，安装时复制到 `~/Library/Rime`，不覆盖已有文件 |
| `scripts/` | 脚本，见下表 |
| `tools/` | `rime-smoke.c`：用本地 librime 部署配置并打印按键结果；`tis-props.swift`：只读查看系统输入法框架里的输入源状态 |
| `docs/` | 本文档；`images/` 是 README 的截图 |

| 脚本 | 用途 |
|---|---|
| `build.sh` | 构建鼠须管和设置 App |
| `build-settings.sh` | 只构建设置 App（要先有一次 `build.sh` 的产物） |
| `install.sh` | 安装；没装雾凇拼音时一并安装 |
| `uninstall.sh` | 卸载 |
| `rime-ice.sh` | 安装或更新雾凇拼音 |
| `rime-smoke.sh` | 冒烟测试：用 librime 部署一份配置副本，打印按键结果 |
| `test-settings.sh` | 设置 App 的模型测试 |
| `test-install.sh` | 安装 / 卸载脚本的测试，都在 `build/install-test` 的假目录里做 |
| `readme-shots.sh` | 重新生成 README 截图 |
| `package.sh` | 打预编译安装包，见[发布](#发布) |

## 构建与安装

`build.sh`：
- 刚 clone 下来时，先取 `squirrel` 子模块（它自己的子模块 librime 只取头文件需要的浅克隆）。
- 第一次运行时下载预编译的 librime 1.17.0（带 lua、octagram、predict 插件）、Sparkle 和默认方案。librime 源码子模块只用来提供头文件。
- 然后运行 `make release ARCHS=$(uname -m)`，最后运行 `build-settings.sh`。
- 脚本不设置代理：需要的话自己 `export https_proxy=…`，git 和 curl 都会用。

`build-settings.sh`：
- 编出 `build/settings/鼠须管设置.app`，里面除了 App 自己，还有它当安装器要用的东西（`Contents/Resources`）：

  | 内容 | 是什么 |
  |---|---|
  | `Payload/Squirrel.zip` | 刚构建好的鼠须管（`ditto` 压缩，保留签名在扩展属性里） |
  | `Payload/rime-ice.zip` | 雾凇拼音的 `full.zip`（`.cache/rime-ice/full.zip`，没有就先下载一次） |
  | `scripts/` | `install.sh`、`uninstall.sh`、`rime-ice.sh` |
  | `rime/` | ohmyrime 的配置模板 |

- `Info.plist` 里记下 `OhmyrimeSquirrelHash`（鼠须管可执行文件的 SHA-256）和 `OhmyrimeRimeIceVersion`。设置 App 用它判断已装的鼠须管是不是自己带的这一版。

`install.sh`：同一个脚本两种用法，靠「身边有没有 `Payload/`」自己判断。

- **App 里那一份**（`Contents/Resources/scripts/install.sh`）：鼠须管从 `Payload/Squirrel.zip` 解压，雾凇拼音用 `Payload/rime-ice.zip`，全程不联网。
- **仓库里那一份**（`scripts/install.sh`）：用 `squirrel/build` 和 `build/settings` 的产物，雾凇拼音用 `.cache/rime-ice/full.zip`。
- 鼠须管装到 `/Library/Input Methods`，会弹一次管理员密码框，只动 `Squirrel.app`。
  - 先完整复制到同目录的临时文件夹，再改名对调。如果先删后拷，app 不在的那几秒里系统重建输入法缓存，就会把鼠须管丢掉。
  - 用 `ditto` 复制，不用 `rsync`：`rsync` 会破坏 `Contents/MacOS/rime-install` 的签名（它存放在扩展属性里）。
  - 去掉下载带来的隔离标记（`com.apple.quarantine`）：App 没有经过 Apple 公证，带着标记的输入法会被拦下。设置 App 也一样。
- 雾凇拼音：装过的就跳过（更新在设置 App 里做）；加 `--no-rime-ice` 不装。没装上时不写只启用雾凇拼音的 `default.custom.yaml`，鼠须管先用自带的朙月拼音，不会变成只能打英文。
- 用户配置只补充缺失的文件，不覆盖已有修改。
- 注册输入源，但**不启用、不切换**：添加第三方输入法要用户自己在系统设置里做。
  - 重装（`com.apple.inputsources` 里本来就有鼠须管）时会再确认几次，丢了就重新注册。
  - 第一次安装不等：用户去系统设置添加时缓存早就建好了。
- 「鼠须管设置」装到 `/Applications`，不用密码；写不了时装到 `~/Applications`。正在运行的旧副本会被关掉，运行安装的这个 App 自己不关。
- 最后写下 `~/Library/Application Support/鼠须管设置/installed.json`（版本、鼠须管哈希、时间），并在后台启动一次鼠须管：新装的输入法在本次登录内可能拉不起来。
- 以 `==> ` 开头的行是步骤，设置 App 用它们显示进度。`OHMYRIME_TEST_ROOT=<目录>` 把安装位置都换到那个目录，并跳过要系统配合的步骤（管理员密码、注册、结束和启动进程），供 `test-install.sh` 使用。

`uninstall.sh`：
- 从输入法里移除鼠须管，删除鼠须管和「鼠须管设置」。
- 默认保留 `~/Library/Rime`；加 `--purge` 连同配置、词库、备份、缓存和偏好设置一起删除。
- 设置 App 的「词库与部署 → 卸载」运行的是 App 里那一份，参数和命令行一样；删完 App 自己退出。

macOS 上的三点限制（照实测写的）：
- 命令行启用第三方输入法（`TISEnableInputSource`）不靠得住：可能返回成功但没生效，所以添加这一步要用户在系统设置里点几下，App 只负责引导和确认。
- 系统重建输入法列表时不扫描 `~/Library/Input Methods`，装在那里会时有时无，所以装到 `/Library/Input Methods`。
- 没公证的 App 第一次打开会被 Gatekeeper 拦下，要在「隐私与安全性」里点「仍要打开」。安装脚本能去掉隔离标记，所以被拦的只有用户从浏览器下载的这一个 App。

## 常见问题

**双击「鼠须管设置」打不开，说无法验证开发者**
- 原因：App 没有经过 Apple 公证。macOS 15 起不能右键打开，要显式放行。
- 解决：打开「系统设置 → 隐私与安全性」，在「安全性」里点「仍要打开」，输入密码。

**欢迎页点「添加鼠须管」之后还没加上**
- macOS 只让用户自己添加第三方输入法，App 不能代做。两种情况：
  - 系统弹出「允许××启用第三方输入法」：点「允许」。
  - 没弹或点了没生效：App 会打开系统设置的「键盘」页，并在右上角浮一张提示卡，照三步做：输入法右边的「编辑…」→ 左下角「+」→「简体中文」里的「鼠须管」。
- 加好后欢迎页会自己打勾，提示卡也会消失。以后随时可以从菜单栏「鼠须管设置 → 欢迎使用 ohmyrime…」回到这一步。

**切到鼠须管后只能打英文、没有候选框**
- 原因：鼠须管进程没起来，日志里是 `imklaunchagent: LaunchInputMethod() Error, status=-50`。
- 解决：运行 `open -g "/Library/Input Methods/Squirrel.app"`，或者点欢迎页「试一试」里的「启动鼠须管」。`install.sh` 最后会自动做这一步；注销重新登录后，由系统自动启动。
- 另一种可能：启用的方案找不到方案文件，比如没装雾凇拼音。设置 App 会在每页顶部提示，「输入」页把这些方案标成「未安装」。

**菜单里有鼠须管却选不中**（系统设置里也可能加不上）
- 原因：系统的输入法缓存把它丢了，常见于刚替换完 app。
- 解决：运行 `"/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --register-input-source` 重新注册。重装时 `install.sh` 会自动确认几次，丢了就重新注册；欢迎页在等用户添加时也会每秒看一眼，发现丢了就重新注册。
- 查看系统是否认得它：运行 `swiftc tools/tis-props.swift -o build/tis-props && build/tis-props rime`，能列出 `im.rime.inputmethod.Squirrel.Hans` 就说明认得。

## 卷轴模式

横排单行候选按 Tab 展开成多行网格，每行就是 Rime 的一页，可以上下滚动。翻页键对齐微信输入法的「Tab / Shift+Tab 翻页」。

| 按键 | 单行时 | 展开后 |
|---|---|---|
| Tab、↓、`=`、滚轮向下 | 展开，高亮移到第 2 行同一列 | 下一行（同一列），超出可见行数时滚动 |
| Shift+Tab、↑、`-`、滚轮向上 | 回到第一个候选 | 上一行；在第一行时收起（`-` 不收起） |
| ←、→ | 前 / 后一个候选 | 同左，可跨行 |
| 数字键 | 选择本行候选 | 选择高亮行的候选（只有高亮行显示序号） |
| 空格 | 上屏高亮候选 | 同左 |
| 鼠标 | 点选、悬停高亮 | 可点选任意一行 |
| 继续输入、退格、Esc | — | 自动收起 |

配置（`~/Library/Rime/squirrel.custom.yaml`；设置 App 的「外观」页也能改）：

```yaml
patch:
  style/candidate_list_layout: linear   # 卷轴模式需要横排单行
  style/scroll_mode/enable: true
  style/scroll_mode/max_rows: 5         # 展开后最多显示几行（2–20）
  style/scroll_mode/tab_paging: true    # Tab / Shift+Tab 翻页；关掉后 Tab 交还给 Rime
```

- 每行候选数就是每页候选数：`default.custom.yaml` 里的 `menu/page_size`。
- 每一行都不换行，单行和展开后的每一行都是。
  - 行宽最多可到屏幕宽度的 90%，候选框靠近屏幕右边时会整体左移。
  - 超过这个宽度时，最长的几个候选末尾截成「…」，截到正好放下。截断只影响显示，上屏的仍是完整候选。

## 液态玻璃外观

参照微信输入法的玻璃主题（v10，本机的 `../wetype` 项目，只读参考）做，尺寸逐项对过它的实拍截图：

- 背景：macOS 26 起用系统液态玻璃（`NSGlassEffectView`，regular 样式），更早的系统用毛玻璃。
  - 单行是胶囊形，展开后是 18 pt 圆角。
  - 深色模式在玻璃上加 50% 黑色遮罩，亮背景上的白字也清楚。
  - 系统开了「减少透明度」时，改用不透明底色。
- 选中项：系统蓝胶囊（0.5 pt 白边、顶部微光），配白色苹方 Medium。
- 其余文字：苹方 Regular 16，浅色 #282828、深色 #E8E8E8。序号是浅灰（#828282 / #B4B4B4），和候选同字号，并占固定宽度，所以每个词都从同一位置开始。
- 尺寸：单行高 32 pt，选中胶囊高 26 pt；展开后行距 32 pt、列宽至少 66 pt。行高固定，emoji 不会把行撑高。
- 动效：
  - 展开、收起时，窗口按 0.20 s / 0.16 s 伸缩，缓动曲线和微信输入法相同，内容固定在顶部。
  - 文字从 30% 不透明度淡入，展开时下移 4 pt 落位。
  - 动画中途反向，会从当前位置接着走。系统开了「减弱动态效果」时不播放。
- emoji 一律用彩色字体：苹方里 🉑 🉐 等是黑白字形。

配置项（`~/Library/Rime/squirrel.custom.yaml`）：

| 配置 | 默认 | 说明 |
|---|---|---|
| `style/translucency` | `true` | 配合原生配色 `color_scheme: native` 即为液态玻璃外观；关掉回到不透明的系统窗口底色 |
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

- 本 fork 新增的项：`glass_style`、`hilited_font_face`、`candidate_spacing`、`scroll_mode/column_width`、`motion`，以及 `system` 字体。
- 和上游鼠须管含义不同的：原生配色加 `translucency` 的外观，以及液态玻璃下 `corner_radius`、`border_*`、`base_offset` 的含义。

预览和对比工具：
- `squirrel/tests/scroll_mode/preview.sh [某个 squirrel.custom.yaml] [输出目录]`：用 `~/Library/Rime` 的一份副本和给定配置，在屏幕上显示几秒钟测试窗口和真实候选框。
  - 截取浅色和深色下的单行、展开、带注释三种状态，以及展开 / 收起动画的中间帧，并打印动画过程中的窗口尺寸。
  - 默认输出到 `squirrel/build/preview/out`。截图前会检查截图区域里只有测试程序自己的窗口，有别的窗口挡着就跳过。
- `squirrel/tests/scroll_mode/measure.py <截图> [x y 宽 高]`：量出蓝色胶囊、白字、序号与候选之间的间距，用来和微信输入法的截图对比。
- `squirrel/tests/scroll_mode/contact-sheet.swift`：把多张截图拼成一张对比图。

## 设置 App

### 欢迎页和安装器

- 打开时先看状态（`InstallState`）：装的是不是自己带的这一版鼠须管、有没有加进输入法、鼠须管在不在运行。
  - 有事情要做，就显示欢迎页：安装 → 添加输入法 → 选择方案 → 试一试。
  - 都装好了就直接是设置。菜单里的「欢迎使用 ohmyrime…」随时可以回到欢迎页。
- 从下载目录打开时，装完会自动换成 `/Applications` 里装着的那一份（`finishWelcome`），下载的那份退出。
- 「安装」运行 App 里的 `install.sh`，输出到界面（`ScriptRunner` 把 `==>` 开头的行当步骤）。
  - 换掉的是自己带的上一版、或者官方鼠须管：`OhmyrimeSquirrelHash` 和已装的比对。
  - 已装的是另一个更新版本（`installed.json` 记着是更新版本装的）：只提示，不降级。
- 「添加输入法」先请系统帮忙（`TISEnableInputSource`），不成就打开系统设置的「键盘」并浮出提示卡（`AddGuidePanel`，`nonactivatingPanel`，不抢焦点）。
  - 等的时候每秒看一次状态：`com.apple.inputsources` 的 `AppleEnabledThirdPartyInputSources` 里有鼠须管、并且 TIS 说它已启用，才算加好。
  - 另外两种记录位置也兼容：早期的 `com.apple.HIToolbox` 的 `AppleEnabledInputSources`。
  - 发现系统又把它丢了（TIS 里没有），就重新注册一次。
- 每页顶部的提示条（`InstallBanner`）在鼠须管没装、版本不一样、或没加进输入法时出现，点一下回到欢迎页。
- 「词库与部署 → 卸载」运行 App 里的 `uninstall.sh`，可以选连配置和词库一起删；删完 App 自己退出。

### 页面和写入的文件

| 页面 | 能设置的 | 写到 |
|---|---|---|
| 外观 | 液态玻璃 / 系统配色 / 预设配色，玻璃质感，一行或一列、横排或竖排，卷轴模式（行数、Tab 翻页、列宽），字体和字号、选中项字重，候选格式，圆角、留白、间距、行距，动效，菜单栏图标，部署通知；顶部是实时预览 | `squirrel.custom.yaml` |
| 输入 | 启用哪些方案和顺序（找不到方案文件的标「未安装」），每页候选数，中文标点下 `/` 打成「、」，左右 Shift / Control / Caps Lock 怎样切换中英，翻页键（`-` `=` / `,` `.` / `[` `]` / Tab），以词定字，方案选单快捷键 | `default.custom.yaml` |
| 雾凇拼音 | 安装或更新雾凇拼音；新输入框的默认状态（中英、标点、简繁、Emoji、全角、单字优先），模糊音（z/zh、n/l、an/ang 等 10 组） | `rime_ice.custom.yaml`，启用的双拼方案也一起改 |
| 应用 | 按应用设置默认英文、不内嵌编码、Vim 模式；可以添加、移除应用。默认只有终端和 Safari 两个预设；这台机器没装、也没手动改过的预设不显示，装了或者改过才会出现 | `squirrel.custom.yaml` 的 `app_options` |
| 短语 | 自定义短语表格：短语、编码、权重，可以搜索 | `custom_phrase.txt` |
| 词库与部署 | 用户词库大小，同步文件夹（可以设到 iCloud 云盘）、立即同步、备份用户文件夹，部署状态和错误日志；卸载 ohmyrime | `installation.yaml` 的 `sync_dir` |
| 关于 | 版本、检查更新并下载安装、已装的鼠须管和雾凇拼音版本、项目链接 | App 自己的偏好设置（上次检查更新的时间） |

预览：顶部的候选框是鼠须管自己的候选框代码画的（`squirrel/sources` 编进了设置 App）。它用窗口里当前的设置，没保存的也算，所以和实际打字时一样，包括玻璃、字体和动效。

### 怎么写配置

- 只改动用到的那几项，其他行、注释、空行原样保留。
  - 原来就在文件里的行就地修改。
  - 设回默认值时，App 自己加的项会删掉，你写的行会留着。
- 写之前用 librime 自己的 YAML 解析器检查一遍，读不了就不写。
- 每次打开 App 后第一次改动之前，原文件备份到 `~/Library/Application Support/鼠须管设置/Backups/<时间>/`，保留最近 20 次。
- 用文本编辑器改过配置，切回 App 时会自动重新读取。
- 改动停手约 0.7 秒后保存，拖滑块也只算一次。

### 怎么生效

- 只改了外观（`style/…`、菜单栏图标、部署通知）时，鼠须管只重新生成 `build/squirrel.yaml`、重新载入外观，十几毫秒。Rime 不重启，各应用里打了一半的拼音和用 Shift 切换的中英状态都保留。
- 其他改动通知鼠须管「安静地」重新部署（不弹通知）。和菜单里的「重新部署」一样，会重启 Rime、重开所有输入会话。
  - 「雾凇拼音」页的改动约 0.2 秒。
  - 「输入」页改的是所有方案共用的 `default.yaml`，每个方案都要重建，英文方案最慢，合计约 3 秒。
  - 「应用」页的按应用选项只在打开输入会话时读取，所以也走这条路。
- librime 按秒比较文件时间，同一秒内的第二次保存会被当成没改。所以 App 会等过了上次部署的那一秒再保存，必要时再请求一次。

和鼠须管之间的接口（`squirrel/` 分支 `ohmyrime`）：

| 方向 | 内容 |
|---|---|
| 设置 App → 鼠须管 | 分布式通知 `SquirrelReloadNotification`。object 为空：照常部署；`"quiet"`：部署，不弹开始和成功通知；`"style"`：只重新载入外观 |
| 鼠须管 → 设置 App | 分布式通知 `SquirrelDeployDidFinishNotification`，object 为 `success` / `failure` / `unchanged` / `reloaded`（只重新载入了外观） |
| 菜单 | 「设置…」按 bundle ID `im.rime.ohmyrime.settings` 打开设置 App，没装时打开用户文件夹 |
| 预览 | `SquirrelConfig.open(yaml:)` 从 YAML 文本读入配置 |

### 中文标点下 / 打成「、」

- 写进 `default.custom.yaml` 的 `punctuator/half_shape/+`，只加 `'/': '、'` 这一项：`+` 是 Rime 的合并写法，rime-ice 原来的标点和其他改动都不动。
- 不能按普通路径写：librime 用 `/` 分隔路径，键名是 `/` 的这一项读不回来（连 `config_get_cstring` 都取不到，只能枚举）。
  - 所以这一项以补丁文件的原文为准：`SettingsStore.isIdeaLine` 认 `'/': '、'` 这样的行，开关状态、增删都基于行文本（`PatchDocument.addMemberLine` / `removeMemberLines`）。
  - 用户自己在同一个合并项里加的标点会保留，关掉时只删 `/` 那一行。

### 安装雾凇拼音

- 没装雾凇拼音时，「雾凇拼音」页的按钮用 App 自带的那一份（`Payload/rime-ice.zip`），不用联网，几乎瞬间装好。装好后同一个位置变成「更新到最新版」，那才下载。
- 按钮运行打包在 App 里的 `scripts/rime-ice.sh`，和命令行装的完全一样：先备份用户文件夹，再装雾凇拼音（不装它的 `squirrel.yaml`），保留你的 `*.custom.yaml`、用户词库和自定义短语。
- 下载显示进度，可以取消。装好后设为默认方案并部署，第一次要编译词库，十几秒。
- 下载不带自己的代理：curl 照用户环境里的 `https_proxy` 之类设置走，脚本不设置也不读取别的代理。
- 下载缓存在 `~/Library/Caches/im.rime.ohmyrime.settings`。整个用户文件夹的备份每份约 16 MB，只保留最近 3 份。

### 检查更新

- 「关于」页和菜单里的「检查更新…」查 GitHub 的最新发布。逻辑照 `workspace/OpenMouse` 的做法：
  - 对 `https://github.com/<仓库>/releases/latest` 发 HEAD 请求，GitHub 会 302 到 `/releases/tag/v0.2.0`，从落地 URL 里取版本号。不走 REST API，就不会被匿名 IP 的限流卡住。
  - 版本按点分数字比较（`1.10.0` 比 `1.9.9` 新），`v` 前缀和 `-beta` 之类的后缀不影响。
  - 落地 URL 必须是本仓库的 `https://github.com/…/releases/tag/…`，别的地址一律不认，防止代理或别的跳转变成「更新」。
- 启动后每天自动查一次（上次检查时间存在 App 的偏好设置里），失败不打扰；手动检查才显示失败原因。
- 有新版时：「关于」页显示版本对比，「设置」页顶部出现蓝色提示条。
- 「下载并安装」依次做：
  1. 下载 `releases/latest/download/ohmyrime.zip`（约 30 MB）；
  2. 下载同目录的 `.sha256`，比对下载文件的 SHA-256，不一致就不装；
  3. `ditto -x -k` 解压，比对解压出来的 App 版本号和发布版本；
  4. `codesign --verify --deep --strict`：Apple 芯片只跑有签名的代码，签名不对就不装；
  5. 在同一个文件夹里先把旧 App 改名让开，再把新的换进去，失败就换回来；
  6. 启动新的 App，旧的退出。
- 测这些：`SQUIRREL_SETTINGS_SELFTEST=update` 用真实网络查一次并打印结果；`SQUIRREL_SETTINGS_SELFTEST=update-install` 配 `OHMYRIME_UPDATE_SOURCE=<放了 zip 和 .sha256 的目录>`，在 App 的一份副本上走完下载、校验、解压、验签、替换，用来验证失败路径（改坏的校验值、对不上的版本、破坏的签名）。

### 测试

| 命令 | 检查什么 |
|---|---|
| `scripts/test-install.sh` | 安装、重装、卸载、`--purge`、`--no-rime-ice`、以及「App 里那一份」的 `install.sh`，都在 `build/install-test` 的假目录里做：不碰 `/Library/Input Methods`，不弹密码框，不动 `~/Library/Rime` |
| `scripts/test-settings.sh` | 在 `~/Library/Rime` 的副本上跑模型测试（YAML 往返、逐行编辑、各页设置），再用 librime 部署这份副本，打字确认改动生效。还会用 `.cache/rime-ice/full.zip` 往空文件夹离线装一遍雾凇拼音。不碰真正的配置 |
| `SQUIRREL_SETTINGS_SELFTEST=deploy …/SquirrelSettings` | 对正在用的鼠须管，把外观和每页候选数各改一个来回，确认外观改动只重新载入、Rime 日志里没有重启，文件最后恢复原样。要等 31 秒，glog 才把日志写出来 |
| `SQUIRREL_SETTINGS_SELFTEST=update` | 用真实网络查一次 GitHub 的最新发布，打印结果（`upToDate` / `available` / `failed`） |
| `SQUIRREL_SETTINGS_SELFTEST=update-install` | 配 `OHMYRIME_UPDATE_SOURCE=<目录>`（里面放 `ohmyrime.zip` 和 `.sha256`），在 App 的副本上走完下载、校验、验签、替换；用来验证失败路径 |
| `SQUIRREL_SETTINGS_SELFTEST=install-ice`（或 `-offline`、`-cancel`） | 配合 `SQUIRREL_SETTINGS_USER_DIR=<副本>`，按页面上的按钮那样装雾凇拼音：下载、离线安装、中途取消 |
| `SQUIRREL_SETTINGS_SNAPSHOT=<目录>` | 配合 `SQUIRREL_SETTINGS_USER_DIR=<副本>` 和 `SQUIRREL_SETTINGS_NO_DEPLOY=1`，截取每页的浅色、深色截图。只截这个 App 自己的窗口；`SQUIRREL_SETTINGS_SNAPSHOT_PAGES=input,ice` 只截部分页面；`welcome` 只截欢迎页的四步和浮在系统设置上的提示卡 |
| `scripts/readme-shots.sh` | 重新生成 `docs/images/settings-*.png` 和 `install-*.png`（欢迎页）。用干净的用户文件夹（配置模板加离线安装的雾凇拼音），截图里没有个人数据；截图时窗口会切到最前面约 15 秒 |

`…/SquirrelSettings` 指 `"/Applications/鼠须管设置.app/Contents/MacOS/SquirrelSettings"`。这些开关用环境变量传：用命令行参数时，AppKit 会把多出来的路径当成要打开的文件。

## 雾凇拼音

[雾凇拼音](https://github.com/iDvel/rime-ice) 是一整套 Rime 配置：词库、全拼和双拼方案、Lua 扩展脚本（日期、计算器、以词定字等）以及按键设置。

```bash
scripts/rime-ice.sh             # 下载最新版，备份 ~/Library/Rime 后安装，并通知鼠须管重新部署
scripts/rime-ice.sh --offline   # 用 .cache 里上次下载的版本
```

和官方的「清空用户目录再复制」不同，这个脚本：
- 保留 `*.custom.yaml`、用户词库和同步目录；
- 不装雾凇拼音的 `squirrel.yaml`：外观沿用本 fork 的配置，因为卷轴模式要横排，而它默认竖排；
- `custom_phrase.txt` 只在没有时才复制；
- 每次安装前，把 `~/Library/Rime`（不含 `build/`）备份到 `.backup/Rime-<时间>.tar.gz`。

脚本不设置也不读取代理：要的话自己 `export https_proxy=…`，curl 会用；断线会自动重试（`--retry-all-errors`）。

三种用法：`rime-ice.sh`（下载最新版）、`--offline`（用 `.cache` 里上次下载的）、`--from <full.zip>`（用指定的一份，安装器就是这么用 App 自带的）。设置 App 运行它时，还用环境变量指定目录（`OHMYRIME_RIME_DIR`、`OHMYRIME_CACHE_DIR`、`OHMYRIME_BACKUP_DIR`、`OHMYRIME_TEMPLATES_DIR`、`OHMYRIME_NO_RELOAD`），说明见脚本开头。

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
- 自定义短语：设置 App 的「短语」页，或直接编辑 `~/Library/Rime/custom_phrase.txt`。
- 要用双拼：在设置 App 的「输入」页启用，或在 `default.custom.yaml` 的 `schema_list` 里加上对应方案（如 `double_pinyin_flypy`）。
- 验证配置：`scripts/rime-smoke.sh` 把 `~/Library/Rime` 复制到 `build/rime-smoke`（不含用户词库），用本地 librime 重新部署，打印几组按键的结果和错误日志数量，不影响正在用的输入法。

## 开发

- `squirrel/` 是子模块，指向 fork [tarnish233/squirrel](https://github.com/tarnish233/squirrel)。在子模块里，remote `origin` 是这个 fork，`upstream` 是 [rime/squirrel](https://github.com/rime/squirrel)。两个分支：
  - `scroll-mode`：卷轴模式功能和测试，基于上游 master，可以单独提 PR；
  - `ohmyrime`：在 `scroll-mode` 之上，加上 fork 专用的改动：按实际安装位置注册输入源、关闭 Sparkle 自动更新、液态玻璃外观和预览工具，以及上面[和设置 App 的接口](#怎么生效)。
- 改了 `squirrel/`：先在子模块里提交并推送到 `origin`，再回到本仓库提交子模块指针（`git add squirrel`）。
- 测试鼠须管：`scripts/build.sh` 之后运行 `squirrel/tests/scroll_mode/run.sh`。
  - 它用真实 librime 和临时用户目录，驱动真实的 `SquirrelInputController` / `SquirrelPanel`，检查翻页、展开、选词。
  - 面板截图输出到 `squirrel/build/scroll-harness/out`。
- 本机的终端安全软件会扫描新编译程序的首次运行，扫描期间可能直接结束进程（`Killed: 9`，退出码 137）。
  - `/tmp` 下运行新程序尤其容易被结束，所以测试产物都放在 `build/`。
  - 脚本遇到 137 会重试。
- 同步上游：`git -C squirrel fetch upstream && git -C squirrel rebase upstream/master scroll-mode`，再把 `ohmyrime` rebase 到 `scroll-mode`，用 `--force-with-lease` 推送两个分支，最后提交新的子模块指针。

## 发布

1. 改版本号：`settings/Info.plist` 的 `CFBundleShortVersionString`。
2. `scripts/build.sh`，跑一遍测试（`squirrel/tests/scroll_mode/run.sh`、`scripts/test-settings.sh`、`scripts/test-install.sh`），再运行 `scripts/package.sh`，得到 `build/dist/ohmyrime.zip` 和它的 sha256。
3. 试装：`ditto -x -k` 解压，给 App 加上 `com.apple.quarantine` 模拟下载，双击打开，照欢迎页走一遍；也可以先 `open` 一份看被拦的样子。
4. 打标签并发布：`git tag v<版本> && git push origin v<版本>`，然后 `gh release create v<版本> build/dist/ohmyrime.zip build/dist/ohmyrime.zip.sha256`。

- 包里只有「鼠须管设置」：鼠须管和雾凇拼音在它的 `Contents/Resources/Payload` 里，打开 App 就装。App 约 30 MB。
- 文件名不带版本号，`releases/latest/download/ohmyrime.zip` 永远是最新版，README 里只写这一条。版本号见 App 和发布页。
- 只有 arm64，ad-hoc 签名，没有公证；所以第一次打开要在「隐私与安全性」里放行。要双击就能装，得买 Apple 开发者账号（每年 99 美元）签名并公证。
- 用 `ditto -c -k --sequesterRsrc` 打包：扩展属性（包括鼠须管里 `rime-install` 的签名）放在 `__MACOSX` 里，双击解压和 `ditto -x` 都会还原。`package.sh` 会先解压一份 `Payload/Squirrel.zip` 检查签名。
- GitHub 自动生成的「Source code」压缩包不含子模块，从源码构建要用 `git clone --recurse-submodules`。
