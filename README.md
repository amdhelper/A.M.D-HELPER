# A.M.D-HELPER
A mini program that helps patients with macular degeneration read text aloud.
这是一个运行在wayland环境下的视障辅助工具，帮助黄斑变性患者轻松的获取屏幕上的文本信息.只需要轻松按下"f4"快捷键,程序就能够识别屏幕上任意区域的文字或鼠标悬停处的文字，并将其朗读出来。
程序可以应对在线和离线的不同状况,在线tts使用的是edge-tts,离线模型使用的是piper-tts.目前支持了简体中文,繁体中文和英文.
希望这个小程序可以帮助到视障用户,特别是注射新冠疫苗以后发生眼底病变的朋友,电脑还是可以用的,但是尽量少用眼,尽量用听的.

## ⚙️ deb包安装方式
如果你是视障用户,因为deb包里面已经包含了piper-tts的模型文件,所以推荐用deb包的方式全自动安装最省心.
deb包安装好以后,程序会自动设置好"f4"键为默认触发快捷键.当程序第一次运行下载好所需的模型以后,右上角会出现托盘绿色图标,这时候您就可以直接按下"f4"按键触发程序开始截图,框选文字后程序就会朗读文字.

```bash
sudo dpkg -i a.m.d-helper_0.53.0_amd64.deb && sudo apt-get -f install && /usr/share/a.m.d-helper/run_with_init.sh
```

## 🔧 Ubuntu 26.04 / GNOME 50（Wayland）说明

新版系统不允许普通程序直接调 GNOME 的交互式截图。旧版在这种情况下会回退到
X11 抓屏，而 Wayland 下 XWayland 的根窗口是纯黑的 —— 按 F4 后会看到一个黑屏
框选层，用户等于盲选，必然识别失败。现在的流程是：

1. 按 **F4** → 用 xdg-desktop-portal 抓一张真实全屏画面（约 0.6 秒）；
2. 立刻弹出全屏覆盖层，把这张画面原样显示出来，鼠标变成十字准星；
3. 按住左键拖出要朗读的区域，松开就开始 OCR + 朗读；
   - **Esc** 或 **右键** = 取消
   - 直接按 **回车** = 整屏朗读
4. 朗读过程中再按 F4 会打断当前朗读，重新开始框选。

安装包会自动识别 GNOME / KDE / XFCE，并以桌面用户身份把 F4 自动绑定到
`/usr/share/a.m.d-helper/run.sh`；安装日志 `/tmp/a.m.d-helper-install.log`
里有一行 `快捷键校验: BOUND F4 ...` 可以核对。安装时如果没赶上图形会话，
下次登录会自动补绑定。托盘没在运行时按 F4 会自动把托盘拉起来，不需要手动开。

托盘菜单（Help 子菜单）：

- **复制F4截图命令** → 复制 `/usr/share/a.m.d-helper/run.sh`，可直接粘到系统快捷键里
- **重新绑定F4快捷键** → 一键重新写入绑定，并语音播报结果
- **打开系统快捷键设置** → 打开「设置 → 键盘」，再点「查看及自定义快捷键」
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
# 说明: 使用 requirements.txt，而不是手工列包名。
pip install -r requirements.txt
```

**关于依赖的三条硬约束（Ubuntu 24.04+/26.04 实测）：**

1. **PyGObject 不要用 pip 安装**。PyPI 上没有预编译 wheel，Python 3.13+ 下 pip 会现场编译并失败。`gi` / `Gtk` / `Atspi` 由系统包 `python3-gi` 提供，venv 必须带 `--system-site-packages` 创建。`requirements.txt` 里已不包含 PyGObject。
2. **pygame 在 Python 3.13/3.14 没有 wheel**（源码编译同样失败），因此改用 API 兼容的 `pygame-ce`（`import pygame` 不变）。
3. **torch/torchvision 建议用 CPU 版**：默认 PyPI 轮子会拖入 6GB+ 的 NVIDIA CUDA 运行库。无 NVIDIA 显卡时执行
   `pip install --no-deps --index-url https://download.pytorch.org/whl/cpu torch torchvision`
   再 `pip install -r requirements.txt` 即可。

### 系统升级后托盘图标消失/启动即退出

Ubuntu 大版本升级会更换系统 Python（例如 26.04 是 3.14）。旧 venv 的 `site-packages` 里的预编译扩展全部失效，表现为日志里：

```
ModuleNotFoundError: No module named 'pystray'
```

修复（幂等，只重建 venv，不动模型和配置）：

```bash
sudo /usr/share/a.m.d-helper/repair-venv.sh
```

新版 deb 的 `postinst` 与 `tray.sh` 都会自动检测 Python 版本变化并重建环境；上面的命令用于手工兜底。

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

关于日志
程序的报错日志主要存储在 /tmp
  目录下，具体路径取决于运行的组件：

   1. 托盘程序日志：/tmp/a.m.d-helper-tray.log（由 tray.py 和 tray.sh 使用）
   2. F1 悬浮窗日志：/tmp/a.m.d-helper-f1.log（由 run_hover.sh 定义）
   3. F4 主程序日志：/tmp/a.m.d-helper-f4.log（由 run.sh 定义）

  此外，安装和卸载过程的日志分别位于 /tmp/a.m.d-helper-install.log 和
  /tmp/a.m.d-helper-uninstall.log。

  如果您需要查看运行时的实时报错，通常检查 `/tmp/a.m.d-helper-f4.log` 或
  `/tmp/a.m.d-helper-tray.log` 是最直接的。
