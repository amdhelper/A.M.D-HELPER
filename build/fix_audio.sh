#!/bin/bash
# A.M.D-helper 音频问题修复脚本
# 专门解决 "mixer not initialized" 错误

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "======================================================"
echo -e "${BLUE}A.M.D-helper 音频问题修复工具${NC}"
echo "======================================================"

# 检查是否以普通用户运行
if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}错误: 请不要使用sudo运行此脚本${NC}"
    echo "正确用法: bash fix_audio.sh"
    exit 1
fi

# 诊断函数
diagnose_audio() {
    echo -e "${BLUE}🔍 音频系统诊断${NC}"
    echo
    
    # 检查PulseAudio
    echo -n "检查PulseAudio状态... "
    if pulseaudio --check 2>/dev/null; then
        echo -e "${GREEN}✅ 运行中${NC}"
    else
        echo -e "${RED}❌ 未运行${NC}"
        return 1
    fi
    
    # 检查音频设备
    echo -n "检查音频设备... "
    if pactl list sinks short | grep -q .; then
        echo -e "${GREEN}✅ 检测到音频设备${NC}"
        pactl list sinks short
    else
        echo -e "${RED}❌ 未检测到音频设备${NC}"
        return 1
    fi
    
    # 检查用户权限
    echo -n "检查用户音频权限... "
    if groups | grep -q audio; then
        echo -e "${GREEN}✅ 用户在audio组${NC}"
    else
        echo -e "${YELLOW}⚠️  用户不在audio组${NC}"
    fi
    
    # 检查SDL环境变量
    echo -n "检查SDL音频驱动... "
    if [[ -n "${SDL_AUDIODRIVER:-}" ]]; then
        echo -e "${GREEN}✅ 已设置: $SDL_AUDIODRIVER${NC}"
    else
        echo -e "${YELLOW}⚠️  未设置${NC}"
    fi
    
    return 0
}

# 修复PulseAudio
fix_pulseaudio() {
    echo -e "${BLUE}🔧 修复PulseAudio${NC}"
    
    echo "停止PulseAudio..."
    pulseaudio --kill 2>/dev/null || true
    sleep 2
    
    echo "启动PulseAudio..."
    if pulseaudio --start; then
        echo -e "${GREEN}✅ PulseAudio启动成功${NC}"
        return 0
    else
        echo -e "${RED}❌ PulseAudio启动失败${NC}"
        return 1
    fi
}

# 设置SDL环境变量
fix_sdl_driver() {
    echo -e "${BLUE}🔧 配置SDL音频驱动${NC}"
    
    # 测试不同的驱动
    local drivers=("pulse" "alsa" "oss")
    
    for driver in "${drivers[@]}"; do
        echo "测试 $driver 驱动..."
        export SDL_AUDIODRIVER="$driver"
        
        if python3 -c "
import pygame
import os
os.environ['SDL_AUDIODRIVER'] = '$driver'
try:
    pygame.mixer.pre_init(frequency=22050, size=-16, channels=2, buffer=512)
    pygame.mixer.init()
    pygame.mixer.quit()
    print('SUCCESS')
except:
    print('FAILED')
" 2>/dev/null | grep -q "SUCCESS"; then
            echo -e "${GREEN}✅ $driver 驱动工作正常${NC}"
            
            # 永久设置
            if ! grep -q "SDL_AUDIODRIVER" ~/.bashrc; then
                echo "export SDL_AUDIODRIVER=$driver" >> ~/.bashrc
                echo "已添加到 ~/.bashrc"
            fi
            
            return 0
        else
            echo -e "${RED}❌ $driver 驱动失败${NC}"
        fi
    done
    
    return 1
}

# 修复用户权限
fix_permissions() {
    echo -e "${BLUE}🔧 修复用户权限${NC}"
    
    if ! groups | grep -q audio; then
        echo "添加用户到audio组..."
        sudo usermod -a -G audio "$USER"
        echo -e "${GREEN}✅ 已添加到audio组${NC}"
        echo -e "${YELLOW}⚠️  需要重新登录或重启系统生效${NC}"
    else
        echo -e "${GREEN}✅ 用户已在audio组${NC}"
    fi
}

# 测试pygame音频
test_pygame_audio() {
    echo -e "${BLUE}🧪 测试pygame音频${NC}"
    
    python3 -c "
import pygame
import os
import sys

# 设置环境变量
os.environ['SDL_AUDIODRIVER'] = '${SDL_AUDIODRIVER:-pulse}'

try:
    # 初始化pygame音频
    pygame.mixer.pre_init(frequency=22050, size=-16, channels=2, buffer=512)
    pygame.mixer.init()
    
    print('✅ Pygame mixer初始化成功')
    
    # 测试播放一个简单的音调
    import numpy as np
    
    # 生成440Hz的音调
    sample_rate = 22050
    duration = 0.5
    frequency = 440
    
    frames = int(duration * sample_rate)
    arr = np.zeros((frames, 2))
    
    for i in range(frames):
        wave = np.sin(2 * np.pi * frequency * i / sample_rate)
        arr[i][0] = wave * 0.1  # 左声道
        arr[i][1] = wave * 0.1  # 右声道
    
    sound = pygame.sndarray.make_sound((arr * 32767).astype(np.int16))
    sound.play()
    
    import time
    time.sleep(duration + 0.1)
    
    pygame.mixer.quit()
    print('✅ 音频测试完成')
    
except Exception as e:
    print(f'❌ 测试失败: {e}')
    sys.exit(1)
"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ pygame音频测试成功${NC}"
        return 0
    else
        echo -e "${RED}❌ pygame音频测试失败${NC}"
        return 1
    fi
}

# 创建音频修复配置
create_audio_config() {
    echo -e "${BLUE}🔧 创建音频配置${NC}"
    
    local config_file="/opt/amd-helper/audio_config.py"
    
    if [[ -d "/opt/amd-helper" ]]; then
        cat > "$config_file" << 'EOF'
#!/usr/bin/env python3
"""
A.M.D-helper 音频配置模块
解决pygame mixer初始化问题
"""

import pygame
import os
import sys
import logging

def safe_init_audio():
    """安全初始化pygame音频系统"""
    
    # 设置SDL音频驱动优先级
    drivers = ['pulse', 'alsa', 'oss', 'dsp']
    
    # 从环境变量获取首选驱动
    preferred_driver = os.environ.get('SDL_AUDIODRIVER')
    if preferred_driver and preferred_driver in drivers:
        drivers.insert(0, preferred_driver)
        drivers = list(dict.fromkeys(drivers))  # 去重
    
    for driver in drivers:
        try:
            os.environ['SDL_AUDIODRIVER'] = driver
            
            # 预初始化音频系统
            pygame.mixer.pre_init(
                frequency=22050,    # 采样率
                size=-16,          # 16位音频
                channels=2,        # 立体声
                buffer=512         # 缓冲区大小
            )
            
            # 初始化mixer
            pygame.mixer.init()
            
            logging.info(f"Audio initialized successfully with {driver} driver")
            return True
            
        except pygame.error as e:
            logging.warning(f"Failed to initialize audio with {driver}: {e}")
            try:
                pygame.mixer.quit()
            except:
                pass
            continue
        except Exception as e:
            logging.error(f"Unexpected error with {driver}: {e}")
            continue
    
    logging.error("Failed to initialize audio with any available driver")
    return False

def cleanup_audio():
    """清理音频资源"""
    try:
        pygame.mixer.quit()
    except:
        pass

# 自动初始化（当模块被导入时）
if __name__ != "__main__":
    safe_init_audio()

if __name__ == "__main__":
    # 测试模式
    logging.basicConfig(level=logging.INFO)
    if safe_init_audio():
        print("✅ 音频初始化成功")
        cleanup_audio()
    else:
        print("❌ 音频初始化失败")
        sys.exit(1)
EOF
        
        echo -e "${GREEN}✅ 音频配置文件已创建: $config_file${NC}"
    else
        echo -e "${YELLOW}⚠️  A.M.D-helper未安装，跳过配置文件创建${NC}"
    fi
}

# 主修复流程
main() {
    echo "开始音频问题诊断和修复..."
    echo
    
    # 1. 诊断当前状态
    if diagnose_audio; then
        echo -e "${GREEN}✅ 基础音频系统正常${NC}"
    else
        echo -e "${YELLOW}⚠️  检测到音频系统问题，开始修复...${NC}"
        
        # 2. 修复PulseAudio
        if ! fix_pulseaudio; then
            echo -e "${RED}❌ PulseAudio修复失败${NC}"
            echo "建议手动安装: sudo apt-get install pulseaudio pulseaudio-utils"
        fi
    fi
    
    # 3. 修复SDL驱动配置
    echo
    if ! fix_sdl_driver; then
        echo -e "${RED}❌ SDL驱动配置失败${NC}"
    fi
    
    # 4. 修复权限
    echo
    fix_permissions
    
    # 5. 创建音频配置
    echo
    create_audio_config
    
    # 6. 最终测试
    echo
    echo -e "${BLUE}🧪 进行最终测试${NC}"
    if test_pygame_audio; then
        echo
        echo -e "${GREEN}${BOLD}🎉 音频修复成功！${NC}"
        echo "现在可以正常使用A.M.D-helper的音频功能了"
    else
        echo
        echo -e "${RED}${BOLD}❌ 音频修复失败${NC}"
        echo "请尝试以下操作："
        echo "1. 重启系统"
        echo "2. 检查音频硬件连接"
        echo "3. 联系技术支持"
    fi
}

# 运行主程序
main "$@"