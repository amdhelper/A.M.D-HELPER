# A.M.D-helper 故障排除指南

## 🚨 常见错误及解决方案

### 1. PyTorch 警告: pin_memory
**错误信息**: `'pin_memory' argument is set as true but no accelerator is found`

**原因**: 系统没有GPU或GPU驱动问题，但PyTorch尝试使用GPU内存固定功能

**解决方案**:
```bash
# 方法1: 重新安装并设置环境变量
sudo bash install.sh --force

# 方法2: 手动设置环境变量
export PYTORCH_DISABLE_PIN_MEMORY=1
```

### 2. Pygame 音频错误: mixer not initialized
**错误信息**: `mixer not initialized`

**原因**: 这通常是pygame的SDL音频驱动配置问题，而不是系统音频问题（如果网页视频能正常播放）

**针对pygame特定问题的修复步骤**:

#### 方法1: SDL音频驱动配置（最常见解决方案）
```bash
# 1. 直接设置SDL音频驱动（最有效）
export SDL_AUDIODRIVER=pulse

# 2. 测试pygame音频
cd /opt/amd-helper
source venv/bin/activate
python3 -c "
import pygame
import os
os.environ['SDL_AUDIODRIVER'] = 'pulse'
pygame.mixer.pre_init(frequency=22050, size=-16, channels=2, buffer=512)
pygame.mixer.init()
print('✅ 成功!')
pygame.mixer.quit()
"

# 3. 如果pulse不行，尝试alsa
export SDL_AUDIODRIVER=alsa

# 4. 永久设置（选择有效的驱动）
echo 'export SDL_AUDIODRIVER=pulse' >> ~/.bashrc
source ~/.bashrc
```

#### 方法2: 安装和配置音频系统
```bash
# 安装完整的音频系统
sudo apt-get update
sudo apt-get install pulseaudio pulseaudio-utils alsa-utils

# 重启音频服务
systemctl --user restart pulseaudio
```

#### 方法3: 修复SDL音频驱动配置
```bash
# 设置SDL音频驱动环境变量
export SDL_AUDIODRIVER=pulse

# 或者尝试其他驱动
export SDL_AUDIODRIVER=alsa

# 永久设置（添加到 ~/.bashrc）
echo 'export SDL_AUDIODRIVER=pulse' >> ~/.bashrc
source ~/.bashrc
```

#### 方法4: 修复程序中的pygame初始化
```bash
# 进入程序目录
cd /opt/amd-helper
source venv/bin/activate

# 测试pygame音频
python3 -c "
import pygame
import os
os.environ['SDL_AUDIODRIVER'] = 'pulse'
pygame.mixer.pre_init(frequency=22050, size=-16, channels=2, buffer=512)
pygame.mixer.init()
print('Pygame mixer initialized successfully')
pygame.mixer.quit()
"
```

#### 方法5: 创建音频配置文件
```bash
# 创建pygame配置
cat > /opt/amd-helper/audio_fix.py << 'EOF'
import pygame
import os
import sys

def init_audio():
    """安全初始化pygame音频系统"""
    # 设置SDL音频驱动
    drivers = ['pulse', 'alsa', 'oss', 'dsp']
    
    for driver in drivers:
        try:
            os.environ['SDL_AUDIODRIVER'] = driver
            pygame.mixer.pre_init(frequency=22050, size=-16, channels=2, buffer=512)
            pygame.mixer.init()
            print(f"Audio initialized with {driver} driver")
            return True
        except pygame.error as e:
            print(f"Failed to initialize with {driver}: {e}")
            pygame.mixer.quit()
            continue
    
    print("Failed to initialize audio with any driver")
    return False

if __name__ == "__main__":
    init_audio()
EOF

# 测试音频修复
python3 /opt/amd-helper/audio_fix.py
```

#### 方法6: 权限修复
```bash
# 添加用户到音频组
sudo usermod -a -G audio $USER

# 重新登录或重启会话
# 或者临时设置权限
sudo chmod 666 /dev/snd/*
```

#### 方法7: 系统级修复
```bash
# 重启音频相关服务
sudo systemctl restart alsa-state
sudo systemctl restart pulseaudio

# 重新加载ALSA配置
sudo alsactl restore

# 检查音频设备权限
ls -la /dev/snd/
```

#### 🚀 快速修复命令

**如果系统音频正常（能播放网页视频），使用pygame专用修复:**
```bash
# pygame音频专用修复（推荐）
bash /opt/amd-helper/fix_pygame_audio.sh

# 或者手动设置SDL驱动
export SDL_AUDIODRIVER=pulse
echo 'export SDL_AUDIODRIVER=pulse' >> ~/.bashrc
```

**如果系统音频也有问题，使用完整修复:**
```bash
# 完整音频系统修复
amd-helper-fix-audio

# 或者直接运行
bash /opt/amd-helper/fix_audio.sh
```

#### 🔍 验证修复结果
```bash
# 测试pygame音频
cd /opt/amd-helper
source venv/bin/activate
python3 -c "
import pygame
pygame.mixer.init()
print('✅ Mixer initialized successfully')
pygame.mixer.quit()
"
```

### 3. Piper TTS 错误
**错误信息**: Piper命令执行失败

**原因**: Piper TTS版本不兼容或模型文件缺失

**解决方案**:
```bash
# 重新安装指定版本
pip install piper-tts==1.2.0 --force-reinstall

# 检查模型文件
ls /opt/amd-helper/models/
```

### 4. EasyOCR 内存问题
**错误信息**: CUDA out of memory 或类似内存错误

**原因**: 系统内存不足或GPU内存不足

**解决方案**:
```bash
# 强制使用CPU模式
export EASYOCR_MODULE_PATH=/opt/amd-helper/venv/lib/python3.*/site-packages/easyocr
export CUDA_VISIBLE_DEVICES=""
```

## 🔧 环境检查命令

### 检查Python环境
```bash
python3 --version
which python3
pip3 --version
```

### 检查音频系统
```bash
# PulseAudio
pulseaudio --check -v
pactl info

# ALSA
aplay -l
amixer
```

### 检查GPU支持
```bash
# NVIDIA
nvidia-smi
lspci | grep -i nvidia

# AMD
lspci | grep -i amd
lspci | grep -i radeon
```

### 检查内存使用
```bash
free -h
top
htop
```

## 🛠️ 修复步骤

### 完全重新安装
```bash
# 1. 完全卸载
sudo bash /opt/amd-helper/uninstall.sh

# 2. 清理残留文件
sudo rm -rf /opt/amd-helper
rm -f ~/.config/autostart/amd-helper.desktop

# 3. 重新安装
sudo bash install.sh --force --auto-cleanup
```

### 修复依赖问题
```bash
# 进入虚拟环境
cd /opt/amd-helper
source venv/bin/activate

# 重新安装核心依赖
pip install --force-reinstall piper-tts==1.2.0
pip install --force-reinstall easyocr
pip install --force-reinstall pygame
```

### 修复权限问题
```bash
# 修复文件权限
sudo chown -R $USER:$USER /opt/amd-helper
chmod +x /opt/amd-helper/*.sh
```

## 📋 收集诊断信息

如果问题仍然存在，请收集以下信息并联系技术支持：

### 系统信息
```bash
# 系统版本
lsb_release -a
uname -a

# 桌面环境
echo $XDG_CURRENT_DESKTOP
echo $DESKTOP_SESSION
```

### 安装日志
```bash
# 查看安装日志
cat /tmp/amd-helper-install.log

# 查看运行日志
journalctl --user -u amd-helper
```

### 依赖版本
```bash
cd /opt/amd-helper
source venv/bin/activate
pip list | grep -E "(torch|easyocr|piper|pygame)"
```

## 🔍 特定环境解决方案

### Ubuntu 20.04/22.04
```bash
# 更新系统
sudo apt update && sudo apt upgrade

# 安装必要的音频包
sudo apt install pulseaudio pulseaudio-utils alsa-utils

# 安装Python开发包
sudo apt install python3-dev python3-pip python3-venv
```

### 低内存系统 (< 4GB)
```bash
# 设置交换文件
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 优化Python内存使用
export PYTHONOPTIMIZE=1
export EASYOCR_MODULE_PATH=""
```

### 无GPU系统
```bash
# 强制CPU模式
export CUDA_VISIBLE_DEVICES=""
export PYTORCH_DISABLE_PIN_MEMORY=1

# 安装CPU版本的PyTorch
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
```

## 📞 获取帮助

1. **查看日志**: `/tmp/amd-helper-install.log`
2. **重新运行引导**: `amd-helper-guide`
3. **完全重新安装**: `sudo bash install.sh --force`
4. **联系技术支持**: 提供系统信息和错误日志

## 🎯 预防措施

1. **定期更新系统**: `sudo apt update && sudo apt upgrade`
2. **保持足够的磁盘空间**: 至少2GB可用空间
3. **确保音频系统正常**: 测试系统音频播放
4. **避免同时运行多个OCR程序**: 可能导致内存不足
5. **定期重启系统**: 清理内存和临时文件