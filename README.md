# ohmyrime

基于 [Rime](https://rime.im) 的个人输入法方案。

| 目录 | 内容 |
|---|---|
| `squirrel/` | [鼠须管](https://github.com/rime/squirrel) fork（独立 git 仓库，分支 `ohmyrime`），加入卷轴模式 |
| `rime/` | Rime 用户配置模板，安装时复制到 `~/Library/Rime`（不覆盖已有文件） |
| `scripts/` | `build.sh` 构建、`install.sh` 安装、`uninstall.sh` 卸载 |

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

## 构建与安装

```bash
scripts/build.sh      # 首次会下载预编译 librime、Sparkle 和默认方案；本机 7890 端口有代理时自动使用
scripts/install.sh    # 装到 /Library/Input Methods（官方位置，会弹一次管理员密码框），只动 Squirrel.app
```

首次安装后要手动添加一次（以后重装不用再加）：先 ⌘Q 退出「系统设置」再打开 → 键盘 → 文字输入「输入法」→ 编辑… → + → 简体中文 → 鼠须管。

macOS 27 上有两点限制：
- 命令行启用第三方输入法（`TISEnableInputSource`）会返回成功但不生效，所以必须在系统设置里加一次；
- `~/Library/Input Methods` 里的输入法系统重建列表时不扫描，会时有时无，所以装到 `/Library/Input Methods`。

卸载：`scripts/uninstall.sh`，默认保留 `~/Library/Rime`；加 `--purge` 一并删除。

## 开发

- `squirrel` 仓库的分支：
  - `scroll-mode`：卷轴模式功能和测试，基于上游 master，可以单独提 PR；
  - `ohmyrime`：在 `scroll-mode` 之上，加上 fork 专用改动：按实际安装位置注册输入源、关闭 Sparkle 自动更新。
- 测试：先 `make release`，再运行 `squirrel/tests/scroll_mode/run.sh`。
  - 它用真实 librime 和临时用户目录驱动真实的 `SquirrelInputController` / `SquirrelPanel`，检查翻页、展开、选词。
  - 面板截图输出到 `squirrel/build/scroll-harness/out`。
- 本机装有终端安全软件（阿里郎），会扫描新编译程序的首次运行，扫描期间可能直接结束进程（`Killed: 9`）：
  - `/tmp` 下运行新程序尤其容易被结束，所以测试产物放在 `build/`；
  - 安装脚本会先预热一次，失败时重试。
- 上游：`git -C squirrel fetch origin && git -C squirrel rebase origin/master scroll-mode`，再把 `ohmyrime` rebase 到 `scroll-mode`。
