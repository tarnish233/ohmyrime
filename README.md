# ohmyrime

macOS 上的 Rime 输入法：鼠须管加上卷轴模式和液态玻璃候选框，默认用雾凇拼音，所有设置都能在「鼠须管设置」里点选。

![鼠须管设置：外观页和候选框实时预览](docs/images/settings-appearance.png)

## 安装

需要 Apple 芯片的 Mac、macOS 14 或更新（液态玻璃外观要 macOS 26），以及 Xcode。

1. 在 ohmyrime 目录里构建并安装（鼠须管 fork 放在 `squirrel/` 子目录，分支 `ohmyrime`）：

   ```bash
   scripts/build.sh     # 构建鼠须管和「鼠须管设置」，第一次要下载依赖
   scripts/install.sh   # 安装，会弹一次管理员密码框；还没装雾凇拼音会一并下载
   ```

2. 第一次安装后，在系统里添加一次输入法：⌘Q 退出「系统设置」再打开 →「键盘」→ 文字输入「输入法」→「编辑…」→「+」→「简体中文」→「鼠须管」。
3. 在菜单栏的输入法菜单里选「鼠须管」开始打字。候选条按 Tab 展开更多候选，Shift+Tab 收起。

- 更新：代码更新后重新运行这两条命令。
- 卸载：`scripts/uninstall.sh`，默认保留词库和配置；加 `--purge` 一并删除。
- 遇到问题（只能打英文、菜单里选不中鼠须管）：见[常见问题](docs/development.md#常见问题)。

## 鼠须管设置

打开方式：鼠须管菜单里的「设置…」（⌃⌥,），或「应用程序」里的「鼠须管设置」。改完自动保存、立即生效，不用手改配置文件。

| | |
|---|---|
| ![外观](docs/images/settings-appearance-dark.png)<br>**外观**：液态玻璃、卷轴模式、字体、间距、动效。顶部是实时预览，可以切换单行 / 展开、浅色 / 深色 | ![输入](docs/images/settings-input.png)<br>**输入**：启用哪些方案，每页候选数，中英切换键，翻页键，以词定字 |
| ![雾凇拼音](docs/images/settings-ice.png)<br>**雾凇拼音**：安装和更新，新输入框的默认状态，模糊音 | ![应用](docs/images/settings-apps.png)<br>**应用**：按应用设置默认英文、不内嵌编码、Vim 模式 |
| ![短语](docs/images/settings-phrases.png)<br>**短语**：自定义短语，可以搜索 | ![词库与部署](docs/images/settings-data.png)<br>**词库与部署**：用户词库、iCloud 同步、备份、部署状态 |

卷轴模式的按键、各配置项、实现和开发说明见[技术文档](docs/development.md)。
