# AGENTS.md

ohmyrime：基于鼠须管（Squirrel）的 macOS 输入法，加上设置 App「鼠须管设置」和安装脚本。实现细节见 [docs/development.md](docs/development.md)。

## 约定

- 用中文和用户交流，回答简洁。
- 推送、发布、删除用户数据等对外可见或不可逆的操作，先征得用户同意。
- 提交信息：本仓库用中文；`squirrel/` 用英文，格式如 `feat(scope): …`。
- 改了行为就同步改文档：README 只写安装和设置 App 展示，其余写进 `docs/development.md`。

## 结构

| 路径 | 内容 |
|---|---|
| `squirrel/` | 鼠须管 fork，git 子模块（tarnish233/squirrel）。工作分支 `ohmyrime`；`scroll-mode` 只放能提给上游的卷轴模式；remote `upstream` 是 rime/squirrel |
| `settings/` | 鼠须管设置（SwiftUI）。构建时把 `squirrel/sources` 的面板代码一起编进去做预览 |
| `rime/` | Rime 用户配置模板 |
| `scripts/` | 构建、安装、测试脚本 |
| `docs/` | 技术文档、README 截图 |

## 命令

| 做什么 | 命令 |
|---|---|
| 构建全部 | `scripts/build.sh` |
| 只构建设置 App | `scripts/build-settings.sh` |
| 测试鼠须管 | `squirrel/tests/scroll_mode/run.sh`（先构建） |
| 测试设置 App | `scripts/test-settings.sh` |
| 验证 Rime 配置 | `scripts/rime-smoke.sh` |
| 更新 README 截图 | `scripts/readme-shots.sh` |
| 打预编译安装包 | `scripts/package.sh`（发布流程见 `docs/development.md` 的「发布」） |
| 安装 | `scripts/install.sh`：会弹管理员密码框、替换正在用的输入法，用户同意后再运行 |

## 必须遵守

- 不在 `squirrel/` 里运行 `make install`：它会改 `/Library/Input Methods` 的属主。安装只用 `scripts/install.sh`。
- 不切换当前输入法，只注册、启用。不碰别的输入法（如 `/Library/Input Methods/WeType.app`），不改 `../wetype`（只读参考）。
- 不读写用户词库 `~/Library/Rime/*.userdb`；测试用 `~/Library/Rime` 的副本（脚本已排除词库）。必须改真实配置的自测，结束时要恢复原样。
- 需要管理员权限时用 osascript（见 `install.sh`），不用 sudo。
- 新编译的程序第一次运行可能被终端安全软件结束（`Killed: 9`，退出码 137）：重试即可。产物放 `build/`，不要放 `/tmp`。
- 访问 GitHub 用代理 `http://127.0.0.1:7890`（脚本自动检测，`OHMYRIME_PROXY` 可改）。
- `squirrel/` 里不新增源文件（否则要改 Xcode 工程），新代码写进已有文件。
- 改了 `squirrel/`：先在子模块里提交并推送，再在本仓库提交子模块指针。不要在本仓库里留下指向未推送提交的指针。
- 截图只截自己的窗口，不能拍到别的应用（`Snapshot.swift`、`preview.sh` 已有检查）。
- bash 脚本里变量后面紧跟全角字符时写成 `${var}`：macOS 自带的 bash 3.2 在 UTF-8 下会把全角字符的字节读进变量名。
