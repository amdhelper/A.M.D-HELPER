# A.M.D-HELPER - 屏幕快捷朗读工具

这是一个运行在wayland环境下的视障辅助工具，帮助黄斑变性患者轻松的获取屏幕上的文本信息.程序能够识别屏幕上任意区域的文字或鼠标悬停处的文字，并将其朗读出来。程序通过一个系统托盘图标进行核心控制，如切换文本转语音（TTS）引擎，并提供了便捷的命令复制功能，以帮助用户在系统中设置全局快捷键。

## ✨ 主要功能

- **两种朗读模式**:
  1.  **截图朗读**: 通过dbus接口截取屏幕任意区域，自动oce识别其中的文字并朗读。(f4.py)
  2.  **悬停朗读**: 鼠标悬停在文本上，自动通过dbus接口获取主动暴露文字信息的app界面上的文字并朗读。*(f1.py)
- **系统托盘控制**:
  - 在不同的TTS引擎（如 Edge TTS, Piper TTS）之间动态切换。(后期接入kitten-tts)
  - 提供快捷帮助，自动获取关键程序的启动脚本绝对路径,提供一键复制用于绑定系统快捷键的命令。
  - 安全退出程序。
- **多引擎TTS支持**:
  - 内置支持微软的 Edge TTS。
  - 内置支持离线的 Piper TTS。
  (后期接入解决中文支持问题的kitten-tts)
  - 模块化设计，可轻松扩展以支持更多TTS引擎。
- **跨桌面环境兼容**: 通过强制使用 `appindicator` 后端，并指导安装相关依赖，最大限度地兼容不同的Linux桌面环境。

## 📂 模块功能说明

本程序由多个独立的模块构成，各司其职：

- `tray.py`: **主入口程序**。负责创建和管理系统托盘图标及其菜单。所有核心设置（如TTS引擎切换）和用户交互（如复制命令、退出程序）都在这里处理。
- `core.py`: **核心处理器**。负责编排整个“截图 -> OCR -> TTS -> 播放”的工作流。它从其他模块导入功能类，并按顺序调用它们。
- `run.sh` & `f4.py`: **截图朗读**的执行脚本。`run.sh` 是一个简单的bash包装器，用于确保 `f4.py` 在正确的Python环境中运行。您应该将系统快捷键（如F4）绑定到 `run.sh`。
- `run_hover.sh` & `f1.py`: **悬停朗读**的执行脚本。与截图朗读类似，您应该将系统快捷键（如F1）绑定到 `run_hover.sh`。
- `ocr.py`: **文字识别模块**。使用 `easyocr` 库来从图像中提取文本。
- `tts.py`: **文本转语音模块**。采用工厂模式设计，可以根据配置文件动态选择并实例化不同的TTS引擎。要添加新的TTS引擎，主要修改此文件。
- `audio.py`: **音频播放模块**。使用 `pygame` 库来播放TTS引擎生成的音频文件。
- `screenshot.py`: **截图模块**。调用系统命令（如 `gnome-screenshot`）来执行截图操作。
- `config.json`: **配置文件**。以JSON格式存储用户的偏好设置，例如当前选择的TTS引擎、Piper模型的路径等。

## ⚙️ 安装与依赖

在运行本程序前，需要安装系统和Python两方面的依赖。

### 1. 系统依赖 (以Debian/Ubuntu为例)

这些库对于托盘图标的正确显示和编译Python包至关重要。

```bash
sudo apt-get update
sudo apt-get install -y python3-gi python3-gi-cairo gir1.2-gtk-3.0 libgirepository1.0-dev gir1.2-appindicator3-0.1 gnome-screenshot python3-tk
```

### 2. Python 依赖

建议在一个Python虚拟环境（venv）中安装这些库。

```bash
# 创建并激活虚拟环境 (如果还没有)
# python3 -m venv venv --system-site-packages
# source venv/bin/activate

# 安装所有需要的Python库
pip install pystray Pillow pygame pyperclip easyocr edge-tts mss jeepney dbus-next piper-tts
```
**注意**: `PyGObject` 库用于提供 `gi` 模块。如果您的虚拟环境没有使用 `--system-site-packages` 标志创建，并且遇到了 `gi` 模块相关的错误，请在虚拟环境中执行 `pip install PyGObject`。

## 🗣️ 模型安装

### OCR 模型
OCR模型由 `easyocr` 库自动管理。在您第一次运行程序时，它会自动下载所需的语言模型（如中文和英文），您只需耐心等待即可。

### TTS 模型 (Piper)
Piper是一个离线的TTS引擎，需要您手动下载语音模型。

1.  **下载模型**: 前往 [Piper Models 页面](https://huggingface.co/rhasspy/piper-voices/tree/main) 下载您喜欢的语音模型。每个模型通常包含一个 `.onnx` 文件和一个 `.json` 文件。
2.  **放置模型**:
    - **简单方式**: 将下载的 `.onnx` 文件放在本程序根目录下，并重命名为 `model.onnx`。
    - **推荐方式**: 在 `config.json` 文件中，添加一个 `piper_model_path` 字段来指定您模型的**绝对路径**，例如：
      ```json
      {
          "tts_model": "piper",
          "piper_model_path": "/path/to/your/zh_CN-huayan-medium.onnx"
      }
      ```

## 🚀 如何运行

1.  **安装所有依赖**：确保上述的系统依赖和Python依赖都已正确安装。
2.  **配置全局快捷键**：
    - 右键点击托盘图标，选择 “快捷键帮助” -> “复制截图命令 (F4)”。
    - 打开您Linux系统的“设置” -> “键盘” -> “快捷键”，创建一个新的自定义快捷键。
    - 将刚才复制的命令粘贴进去，并为此快捷键分配一个您喜欢的按键组合（例如 `F4`）。
    - 对“复制悬停命令 (F1)”重复以上步骤（例如分配 `F1` 键）。
3.  **运行主程序**:
    ```bash
    python3 tray.py
    ```
4.  **使用**: 按下您设置的全局快捷键（如 `F4` 或 `F1`）来使用对应的朗读功能。通过右键托盘菜单随时切换TTS引擎。

## 📦 打包与分发

如果您想将此程序打包成单个可执行文件，方便在其他机器上分发，可以使用 **PyInstaller**。

1.  **安装 PyInstaller**:
    ```bash
    pip install pyinstaller
    ```
2.  **打包命令**:
    在项目根目录运行以下命令。这个命令会尝试将所有依赖打包，并将脚本文件作为数据文件包含进来。
    ```bash
    pyinstaller --onefile --windowed \
      --add-data "run.sh:." \
      --add-data "run_hover.sh:." \
      --add-data "config.json:." \
      --hidden-import "pystray._appindicator" \
      tray.py
    ```
    - `--onefile`: 创建单个可执行文件。
    - `--windowed`: 在Windows上隐藏控制台窗口，对Linux也适用。
    - `--add-data`: 将非代码文件（如我们的 `.sh` 脚本）捆绑到包中。
    - `--hidden-import`: 明确告诉PyInstaller一些它可能找不到的库。

3.  **运行**: 打包成功后，可在 `dist` 目录下找到生成的可执行文件 `tray`。

## 🔧 代码扩展与参数调整

### 扩展新的TTS引擎
本程序的设计使得添加新的TTS引擎非常简单：
1.  **打开 `tts.py` 文件**。
2.  **创建新的引擎类**: 仿照 `EdgeTtsEngine` 或 `PiperTtsEngine`，创建一个新的类。它需要有一个 `async def synthesize(self, text: str, output_path: str)` 方法，该方法负责调用您想集成的TTS工具的命令或API。
3.  **注册新的引擎**: 在文件底部的 `get_tts_engine()` 函数中，添加一个新的 `elif` 分支。让它在 `config.json` 中检测到您指定的新模型名称时，返回您新创建的引擎类的实例。
4.  **更新托盘菜单**: 在 `tray.py` 中，为您的新引擎添加一个 `MenuItem`，以便用户可以在菜单中选择它。

### 调整参数
- **TTS引擎与Piper模型路径**: 直接修改 `config.json` 文件。
- **Edge TTS 语音**: 在 `tts.py` 的 `EdgeTtsEngine` 类中，`command` 列表里的 `--voice` 参数是硬编码的（`zh-CN-XiaoxiaoNeural`）。您可以直接修改为您喜欢的任何 `edge-tts` 支持的语音名称。
- **截图工具**: 在 `screenshot.py` 中，您可以修改 `self.backend` 的值来更换系统截图工具，如从 `gnome-screenshot` 改为 `flameshot`，并相应调整其命令行参数。

===================================================
deb包安装方式
sudo dpkg -i a.m.d-helper_0.53.0_amd64.deb && sudo apt-get -f install && source /usr/share/a.m.d-helper/venv/bin/activate && python3 /usr/share/a.m.d-helper/tray.py