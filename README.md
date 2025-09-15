# A.M.D-HELPER
A mini program that helps patients with macular degeneration read text aloud.
这是一个运行在wayland环境下的视障辅助工具，帮助黄斑变性患者轻松的获取屏幕上的文本信息.只需要轻松按下"f4"快捷键,程序就能够识别屏幕上任意区域的文字或鼠标悬停处的文字，并将其朗读出来。
程序可以应对在线和离线的不同状况,在线tts使用的是edge-tts,离线模型使用的是piper-tts.目前只吃了建中,繁中和英文.
希望这个小程序可以帮助到视障用户,特别是注射新冠疫苗以后发生眼底病变的朋友,电脑还是可以用的,但是尽量少用眼,尽量用听的.

## ⚙️ deb包安装方式
如果你是视障用户,因为deb包里面已经包含了piper-tts的模型文件,所以推荐用deb包的方式全自动安装最省心.
deb包安装好以后,程序会自动设置好"f4"键为默认触发快捷键.当程序第一次运行下载好所需的模型以后,右上角会出现托盘绿色图标,这时候您就可以直接按下"f4"按键触发程序开始截图,框选文字后程序就会朗读文字.

```bash
sudo dpkg -i a.m.d-helper_0.53.0_amd64.deb && sudo apt-get -f install && /usr/share/a.m.d-helper/run_with_init.sh
```
## ⚙️ 手动安装
```bash
sudo apt-get update
sudo apt-get install -y python3-gi python3-gi-cairo gir1.2-gtk-3.0 libgirepository1.0-dev gir1.2-appindicator3-0.1 gnome-screenshot python3-tk
```
### 安装Python 依赖

建议在一个Python虚拟环境（venv）中安装这些库。

```bash
# 创建并激活虚拟环境 (如果还没有)
python3 -m venv venv --system-site-packages
source venv/bin/activate

# 安装所有需要的Python库
pip install pystray Pillow pygame pyperclip easyocr edge-tts mss jeepney dbus-next piper-tts
```
**注意**: `PyGObject` 库用于提供 `gi` 模块。如果您的虚拟环境没有使用 `--system-site-packages` 标志创建，并且遇到了 `gi` 模块相关的错误，请在虚拟环境中执行 `pip install PyGObject`。

### 下载TTS 模型 (Piper)
Piper是一个离线的TTS引擎，需要您手动下载放置语音模型。

1.  **下载模型**: 前往 [Piper Models 页面](https://huggingface.co/rhasspy/piper-voices/tree/main) 下载您喜欢的语音模型。每个模型通常包含一个 `.onnx` 文件和一个 `.json` 文件。
2.  **放置模型**:
请将下载好的文件按照如图的方式放置在项目文件夹内的models文件夹中
```bash
models
├── en_US-kristin-medium.onnx
├── en_US-kristin-medium.onnx.json
├── zh_CN-huayan-medium.onnx
└── zh_CN-huayan-medium.onnx.json
```
# 运行程序
```bash
python3 tray.py
```
OCR模型由 `easyocr` 库自动管理。在您第一次运行程序时，它会自动下载所需的语言模型（如中文和英文），您只需耐心等待即可。当您看到右上角的绿色图标出现以后,可以点击自定义快捷键设置触发快捷键,程序提供了命令,可以直接复制粘贴使用.自启动也可以一键跳转,复制粘贴设置.