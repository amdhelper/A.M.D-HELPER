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
