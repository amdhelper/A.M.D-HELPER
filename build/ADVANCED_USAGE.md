# A.M.D-helper: 高级命令行技巧

这份文档为希望通过命令行进行更深度定制的用户提供指导。

## 通过命令行修改快捷键

虽然我们推荐您通过系统的“设置”->“键盘”->“自定义快捷键”图形界面来管理快捷键，但使用命令行也是一个高效的方式。

本程序使用 `gsettings` 工具与 GNOME 桌面环境（Ubuntu 默认桌面）的设置系统交互。

### 1. 查找按键名称 (Key-Code)

在设置快捷键之前，您需要知道系统是如何识别您想使用的按键的。例如，`Ctrl` 键是 `<Primary>`，`Alt` 键是 `<Alt>`，`Windows` 键是 `<Super>`。

对于普通按键，通常就是其小写字母，例如 `F4` 键就是 `F4`，`A` 键就是 `a`。

如果您不确定某个特殊按键的名称，可以使用 `wev` 或 `xev` 工具来查找。在终端中运行 `xev`，按下一个按键，终端就会打印出这个按键的详细信息，您可以在其中找到 `keysym` 或 `keycode` 的名称。

### 2. 查看当前快捷键

您可以随时查看当前绑定的快捷键是什么。

- **查看“快速识别” (F4) 的快捷键:**
  ```bash
  gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/amd-helper-fast-ocr/ binding
  ```

- **查看“悬浮识别” (F1) 的快捷键:**
  ```bash
  gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/amd-helper-hover-ocr/ binding
  ```

### 3. 修改快捷键

使用 `gsettings set` 命令来绑定新的快捷键。

**示例：**

假设您想把“快速识别”的快捷键修改为 `Ctrl + Alt + R`，可以输入以下命令：
```bash
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/amd-helper-fast-ocr/ binding '<Primary><Alt>r'
```

**重置快捷键为空：**

如果您想禁用某个快捷键，可以将其设置为空字符串：
```bash
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/amd-helper-fast-ocr/ binding ''
```

## 通过命令行修改配置

您也可以直接用命令行编辑器（如 `nano` 或 `vim`）来修改配置文件。

配置文件位于：`/opt/amd-helper/config.json`

例如，使用 `nano` 编辑器打开它：
```bash
nano /opt/amd-helper/config.json
```
修改完毕后，按 `Ctrl + X`，然后按 `Y`，最后按回车键保存退出。
