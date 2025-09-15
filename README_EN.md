```markdown
# A.M.D-HELPER
A mini program that helps patients with macular degeneration read text aloud.
This is a visual impairment assistance tool running in a Wayland environment, designed to help patients with macular degeneration easily obtain text information from the screen. Simply press the "F4" hotkey, and the program can recognize text in any area of the screen or text under the mouse cursor, and read it out loud.
The program can handle both online and offline scenarios. The online TTS uses edge-tts, while the offline model uses piper-tts. It currently supports Simplified Chinese, Traditional Chinese, and English.
We hope this small program can assist visually impaired users, especially those who developed fundus lesions after receiving the COVID-19 vaccine. You can still use the computer, but try to use your eyes less and rely more on listening.

## ⚙️ Installation via deb package
If you are a visually impaired user, we recommend using the deb package for the most hassle-free automatic installation, as it already includes the piper-tts model files.
After installing the deb package, the program will automatically set the "F4" key as the default trigger hotkey. When the program runs for the first time and downloads the necessary models, a green tray icon will appear in the top-right corner. At this point, you can directly press the "F4" key to trigger the program to start screenshotting. After selecting the text area, the program will read the text aloud.

```bash
sudo dpkg -i a.m.d-helper_0.53.0_amd64.deb && sudo apt-get -f install && /usr/share/a.m.d-helper/run_with_init.sh
```
## ⚙️ Manual Installation
```bash
sudo apt-get update
sudo apt-get install -y python3-gi python3-gi-cairo gir1.2-gtk-3.0 libgirepository1.0-dev gir1.2-appindicator3-0.1 gnome-screenshot python3-tk
```
### Install Python Dependencies

It is recommended to install these libraries within a Python virtual environment (venv).

```bash
# Create and activate a virtual environment (if you haven't already)
python3 -m venv venv --system-site-packages
source venv/bin/activate

# Install all required Python libraries
pip install pystray Pillow pygame pyperclip easyocr edge-tts mss jeepney dbus-next piper-tts
```
**Note**: The `PyGObject` library provides the `gi` module. If your virtual environment was not created with the `--system-site-packages` flag and you encounter errors related to the `gi` module, please run `pip install PyGObject` within the virtual environment.

### Download TTS Model (Piper)
Piper is an offline TTS engine, and you need to manually download and place the voice models.

1.  **Download the model**: Go to the [Piper Models page](https://huggingface.co/rhasspy/piper-voices/tree/main) and download the voice model you prefer. Each model typically consists of an `.onnx` file and a `.json` file.
2.  **Place the model**:
Please place the downloaded files in the `models` folder within the project directory, as shown in the structure below:
```bash
models
├── en_US-kristin-medium.onnx
├── en_US-kristin-medium.onnx.json
├── zh_CN-huayan-medium.onnx
└── zh_CN-huayan-medium.onnx.json
```
# Run the Program
```bash
python3 tray.py
```
The OCR models are automatically managed by the `easyocr` library. The first time you run the program, it will automatically download the required language models (such as Chinese and English). Please wait patiently. Once you see the green icon appear in the top-right corner, you can click to customize the hotkey settings for the trigger key. The program provides commands that can be directly copied and pasted for use. You can also set up auto-start with one-click navigation, copy, and paste.
```