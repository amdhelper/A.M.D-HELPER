#!/bin/bash
# 专门修复pygame音频问题的脚本
# 适用于系统音频正常但pygame无法初始化的情况

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "======================================================"
echo -e "${BLUE}Pygame音频问题快速修复${NC}"
echo "======================================================"
echo -e "${YELLOW}适用于: 系统音频正常，但pygame mixer初始化失败${NC}"
echo

# 检查是否在正确的环境中
if [[ ! -d "/opt/amd-helper" ]]; then
    echo -e "${RED}错误: 未找到A.M.D-helper安装目录${NC}"
    exit 1
fi

cd /opt/amd-helper

if [[ ! -f "venv/bin/activate" ]]; then
    echo -e "${RED}错误: 未找到Python虚拟环境${NC}"
    exit 1
fi

source venv/bin/activate

# 测试pygame音频的函数
test_pygame_with_driver() {
    local driver="$1"
    echo -n "测试 $driver 驱动... "
    
    if python3 -c "
import pygame
import os
import sys
os.environ['SDL_AUDIODRIVER'] = '$driver'
try:
    pygame.mixer.pre_init(frequency=22050, size=-16, channels=2, buffer=512)
    pygame.mixer.init()
    pygame.mixer.quit()
    print('SUCCESS', end='')
except Exception as e:
    print(f'FAILED: {e}', end='')
    sys.exit(1)
" 2>/dev/null; then
        echo -e "${GREEN}✅ 成功${NC}"
        return 0
    else
        echo -e "${RED}❌ 失败${NC}"
        return 1
    fi
}

# 主要修复逻辑
echo -e "${BLUE}🔍 检测可用的SDL音频驱动...${NC}"

# 测试不同的驱动
drivers=("pulse" "alsa" "oss" "dsp")
working_driver=""

for driver in "${drivers[@]}"; do
    if test_pygame_with_driver "$driver"; then
        working_driver="$driver"
        break
    fi
done

if [[ -n "$working_driver" ]]; then
    echo
    echo -e "${GREEN}✅ 找到可用驱动: $working_driver${NC}"
    
    # 设置环境变量
    echo -e "${BLUE}🔧 配置环境变量...${NC}"
    
    # 检查是否已经设置
    if grep -q "SDL_AUDIODRIVER" ~/.bashrc; then
        echo "更新现有配置..."
        sed -i "s/export SDL_AUDIODRIVER=.*/export SDL_AUDIODRIVER=$working_driver/" ~/.bashrc
    else
        echo "添加新配置..."
        echo "export SDL_AUDIODRIVER=$working_driver" >> ~/.bashrc
    fi
    
    # 立即生效
    export SDL_AUDIODRIVER="$working_driver"
    
    echo -e "${GREEN}✅ 环境变量已设置${NC}"
    
    # 创建pygame音频配置文件
    echo -e "${BLUE}🔧 创建pygame音频配置...${NC}"
    
    cat > /opt/amd-helper/pygame_audio_fix.py << EOF
#!/usr/bin/env python3
"""
Pygame音频修复模块
自动设置正确的SDL音频驱动
"""

import os
import pygame
import logging

# 设置工作的音频驱动
os.environ['SDL_AUDIODRIVER'] = '$working_driver'

def init_pygame_audio():
    """初始化pygame音频系统"""
    try:
        pygame.mixer.pre_init(
            frequency=22050,
            size=-16,
            channels=2,
            buffer=512
        )
        pygame.mixer.init()
        return True
    except Exception as e:
        logging.error(f"Pygame audio initialization failed: {e}")
        return False

def cleanup_pygame_audio():
    """清理pygame音频资源"""
    try:
        pygame.mixer.quit()
    except:
        pass

# 在导入时自动初始化
if __name__ != "__main__":
    init_pygame_audio()
EOF
    
    echo -e "${GREEN}✅ 配置文件已创建${NC}"
    
    # 最终测试
    echo -e "${BLUE}🧪 进行最终测试...${NC}"
    
    if python3 -c "
import pygame
import os
os.environ['SDL_AUDIODRIVER'] = '$working_driver'
pygame.mixer.pre_init(frequency=22050, size=-16, channels=2, buffer=512)
pygame.mixer.init()
print('✅ Pygame音频初始化成功')

# 测试播放一个简单的音调
import numpy as np
import time

# 生成测试音调
sample_rate = 22050
duration = 0.3
frequency = 440

frames = int(duration * sample_rate)
arr = np.zeros((frames, 2))

for i in range(frames):
    wave = np.sin(2 * np.pi * frequency * i / sample_rate)
    arr[i][0] = wave * 0.1
    arr[i][1] = wave * 0.1

sound = pygame.sndarray.make_sound((arr * 32767).astype(np.int16))
sound.play()
time.sleep(duration + 0.1)

pygame.mixer.quit()
print('✅ 音频播放测试完成')
"; then
        echo
        echo -e "${GREEN}${BOLD}🎉 修复成功！${NC}"
        echo -e "${GREEN}Pygame音频现在可以正常工作了${NC}"
        echo
        echo -e "${BLUE}使用的驱动: $working_driver${NC}"
        echo -e "${BLUE}配置已保存到: ~/.bashrc${NC}"
        echo -e "${BLUE}重新启动终端或运行 'source ~/.bashrc' 使配置生效${NC}"
    else
        echo -e "${RED}❌ 最终测试失败${NC}"
    fi
    
else
    echo
    echo -e "${RED}❌ 未找到可用的SDL音频驱动${NC}"
    echo
    echo -e "${YELLOW}可能的解决方案:${NC}"
    echo "1. 重启系统"
    echo "2. 检查是否安装了必要的音频库:"
    echo "   sudo apt-get install libasound2-dev libpulse-dev"
    echo "3. 尝试重新安装pygame:"
    echo "   pip install --force-reinstall pygame"
    echo "4. 检查系统音频配置"
fi

echo
echo "修复完成！"