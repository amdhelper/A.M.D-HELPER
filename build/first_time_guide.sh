#!/bin/bash
# A.M.D-helper 首次使用引导脚本
# 可以独立运行，帮助用户学习软件功能

# 定义颜色和格式
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# 语音播放函数
speak_safe() {
    local message="$1"
    
    # 尝试多种语音合成工具
    if command -v spd-say &> /dev/null; then
        timeout 10s spd-say -r 0 -v 50 "$message" 2>/dev/null || true
    elif command -v espeak &> /dev/null; then
        timeout 10s espeak -s 150 "$message" 2>/dev/null || true
    elif command -v festival &> /dev/null; then
        timeout 10s echo "$message" | festival --tts 2>/dev/null || true
    else
        # 如果没有语音工具，显示提示
        echo -e "${BOLD}${BLUE}[语音] $message${NC}"
    fi
}

# 等待用户准备
wait_for_user_ready() {
    local message="$1"
    echo
    echo -e "${BLUE}💡 $message${NC}"
    speak_safe "$message"
    read -p "按回车键继续..." -r
}

# 等待用户确认
wait_for_user_confirmation() {
    local message="$1"
    local timeout="${2:-15}"
    
    echo -e "${YELLOW}❓ $message${NC}"
    speak_safe "$message"
    
    if timeout "$timeout" read -p "请输入 y 确认，或等待 $timeout 秒自动继续: " -n 1 -r; then
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            return 0
        else
            return 1
        fi
    else
        echo
        echo -e "${BLUE}⏰ 超时，自动继续${NC}"
        return 1
    fi
}

# 询问用户选择
ask_user_choice() {
    local question="$1"
    echo
    echo -e "${YELLOW}❓ $question${NC}"
    speak_safe "$question"
    read -p "请选择 (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        return 0
    else
        return 1
    fi
}

# 检查程序是否已安装
check_installation() {
    if [[ ! -d "/opt/amd-helper" ]]; then
        echo -e "${RED}❌ 未检测到 A.M.D-helper 安装${NC}"
        echo -e "${BLUE}请先运行安装脚本：sudo bash install.sh${NC}"
        speak_safe "未检测到A.M.D-helper安装，请先运行安装脚本"
        exit 1
    fi
    
    if [[ ! -f "/opt/amd-helper/f4.py" ]]; then
        echo -e "${RED}❌ 核心文件缺失${NC}"
        echo -e "${BLUE}请重新安装：sudo bash install.sh --force${NC}"
        speak_safe "核心文件缺失，请重新安装"
        exit 1
    fi
}

# 介绍F4快速识别功能
introduce_f4_function() {
    echo
    echo -e "${BLUE}${BOLD}⚡ F4快速识别功能详解${NC}"
    echo "======================================================"
    
    echo -e "${YELLOW}🎯 功能特点：${NC}"
    echo -e "  ${GREEN}•${NC} 全屏截图并自动识别文字"
    echo -e "  ${GREEN}•${NC} 支持中文、英文等多种语言"
    echo -e "  ${GREEN}•${NC} 识别结果自动语音播报"
    echo -e "  ${GREEN}•${NC} 文字内容自动复制到剪贴板"
    echo -e "  ${GREEN}•${NC} 快捷键：F4 键"
    
    speak_safe "F4快速识别功能可以全屏截图并自动识别文字，支持多种语言，识别结果会语音播报并自动复制到剪贴板"
    
    echo
    echo -e "${YELLOW}📋 使用步骤：${NC}"
    echo -e "  ${BLUE}1.${NC} 确保屏幕上显示需要识别的文字内容"
    echo -e "  ${BLUE}2.${NC} 按下快捷键 F4"
    echo -e "  ${BLUE}3.${NC} 等待截图和识别完成（约2-5秒）"
    echo -e "  ${BLUE}4.${NC} 听取语音播报的识别结果"
    echo -e "  ${BLUE}5.${NC} 识别的文字已自动复制，可直接粘贴使用"
    
    speak_safe "使用步骤很简单：确保屏幕显示文字，按F4键，等待识别完成，听取语音播报，文字已自动复制可直接使用"
    
    wait_for_user_ready "了解了基本使用方法"
}

# 演示F4功能
demonstrate_f4_function() {
    echo
    echo -e "${GREEN}${BOLD}🎬 功能演示${NC}"
    echo "======================================================"
    
    speak_safe "现在进行功能演示。请准备一些包含文字的内容在屏幕上"
    
    echo -e "${YELLOW}📺 演示准备：${NC}"
    echo -e "  ${BLUE}•${NC} 请打开一个包含文字的网页、文档或图片"
    echo -e "  ${BLUE}•${NC} 确保文字清晰可见"
    echo -e "  ${BLUE}•${NC} 建议使用较大的字体以获得更好的识别效果"
    
    if wait_for_user_confirmation "准备好演示内容了吗？" 30; then
        echo
        echo -e "${GREEN}🚀 开始演示${NC}"
        speak_safe "很好！现在开始演示。请按F4键进行快速识别"
        
        echo -e "${BLUE}请按 F4 键开始识别...${NC}"
        echo -e "${YELLOW}（演示完成后按回车键继续）${NC}"
        
        # 等待用户尝试
        read -r
        
        echo -e "${GREEN}✅ 演示完成！${NC}"
        speak_safe "演示完成！您刚才体验了快速识别功能"
        
        # 询问演示效果
        echo
        if ask_user_choice "识别效果是否满意？"; then
            speak_safe "太好了！您已经掌握了基本使用方法"
        else
            provide_troubleshooting_tips
        fi
    else
        echo -e "${YELLOW}⏭️  跳过演示，继续介绍使用技巧${NC}"
        speak_safe "跳过演示，继续介绍使用技巧"
    fi
}

# 提供使用技巧
provide_usage_tips() {
    echo
    echo -e "${BLUE}${BOLD}💡 使用技巧和建议${NC}"
    echo "======================================================"
    
    echo -e "${YELLOW}🎯 获得最佳识别效果的技巧：${NC}"
    echo -e "  ${GREEN}•${NC} 确保文字清晰，避免模糊或过小的字体"
    echo -e "  ${GREEN}•${NC} 良好的对比度：深色文字配浅色背景效果最佳"
    echo -e "  ${GREEN}•${NC} 避免复杂的背景图案干扰"
    echo -e "  ${GREEN}•${NC} 中文识别通常比英文稍慢，请耐心等待"
    
    speak_safe "使用技巧：确保文字清晰，良好对比度，避免复杂背景，中文识别需要更多时间"
    
    echo
    echo -e "${YELLOW}⚠️  常见问题解决：${NC}"
    echo -e "  ${BLUE}•${NC} 如果识别不准确：尝试放大文字或改善显示效果"
    echo -e "  ${BLUE}•${NC} 如果没有语音：检查音量设置和语音合成工具"
    echo -e "  ${BLUE}•${NC} 如果快捷键无效：重启系统或手动运行程序"
    echo -e "  ${BLUE}•${NC} 如果识别很慢：关闭其他占用资源的程序"
    
    speak_safe "常见问题解决方法：识别不准确时放大文字，没有语音时检查音量，快捷键无效时重启系统"
    
    wait_for_user_ready "了解了使用技巧"
}

# 故障排除提示
provide_troubleshooting_tips() {
    echo
    echo -e "${YELLOW}${BOLD}🔧 故障排除建议${NC}"
    echo "======================================================"
    
    echo -e "${RED}如果遇到识别问题，请尝试：${NC}"
    echo -e "  ${BLUE}1.${NC} 调整屏幕亮度和对比度"
    echo -e "  ${BLUE}2.${NC} 放大文字字体"
    echo -e "  ${BLUE}3.${NC} 确保文字区域没有遮挡"
    echo -e "  ${BLUE}4.${NC} 重新启动程序：在终端运行 'amd-helper'"
    echo -e "  ${BLUE}5.${NC} 检查网络连接（某些识别功能需要网络）"
    
    speak_safe "故障排除建议：调整屏幕亮度对比度，放大字体，确保无遮挡，重启程序，检查网络连接"
    
    echo
    echo -e "${BLUE}📞 获取帮助：${NC}"
    echo -e "  ${GREEN}•${NC} 查看日志文件：/tmp/amd-helper-install.log"
    echo -e "  ${GREEN}•${NC} 重新安装：sudo bash install.sh --force"
    echo -e "  ${GREEN}•${NC} 联系技术支持并提供日志文件"
    
    speak_safe "如需帮助，可查看日志文件，重新安装，或联系技术支持"
}

# 手动测试功能
manual_test_function() {
    echo
    echo -e "${GREEN}${BOLD}🧪 手动测试功能${NC}"
    echo "======================================================"
    
    speak_safe "现在可以手动测试F4快速识别功能"
    
    echo -e "${BLUE}测试方法：${NC}"
    echo -e "  ${YELLOW}1.${NC} 直接运行识别程序"
    echo -e "  ${YELLOW}2.${NC} 使用快捷键测试"
    
    if ask_user_choice "是否直接运行一次识别程序进行测试？"; then
        echo
        echo -e "${GREEN}🚀 启动识别程序...${NC}"
        speak_safe "正在启动识别程序，请稍等"
        
        if [[ -f "/opt/amd-helper/f4.py" ]]; then
            echo -e "${BLUE}程序将在3秒后开始截图识别...${NC}"
            speak_safe "程序将在3秒后开始截图识别，请准备好屏幕内容"
            
            sleep 3
            
            # 尝试运行识别程序
            if cd /opt/amd-helper && source venv/bin/activate && python3 f4.py; then
                echo -e "${GREEN}✅ 测试完成${NC}"
                speak_safe "测试完成，您应该听到了识别结果"
            else
                echo -e "${RED}❌ 测试失败${NC}"
                speak_safe "测试失败，可能需要检查程序配置"
            fi
        else
            echo -e "${RED}❌ 程序文件不存在${NC}"
            speak_safe "程序文件不存在，请重新安装"
        fi
    fi
}

# 主函数
main() {
    echo "======================================================"
    echo -e "${GREEN}${BOLD}🎓 A.M.D-helper 首次使用引导${NC}"
    echo "======================================================"
    
    speak_safe "欢迎使用A.M.D-helper首次使用引导！"
    
    # 检查安装
    check_installation
    
    echo -e "${BLUE}本引导将帮助您：${NC}"
    echo -e "  ${GREEN}•${NC} 了解F4快速识别功能"
    echo -e "  ${GREEN}•${NC} 学习正确的使用方法"
    echo -e "  ${GREEN}•${NC} 掌握使用技巧"
    echo -e "  ${GREEN}•${NC} 解决常见问题"
    
    speak_safe "本引导将帮助您了解F4快速识别功能，学习使用方法，掌握技巧，解决常见问题"
    
    wait_for_user_ready "开始学习"
    
    # 功能介绍
    introduce_f4_function
    
    # 实际演示
    if ask_user_choice "是否进行实际功能演示？"; then
        demonstrate_f4_function
    fi
    
    # 手动测试
    if ask_user_choice "是否进行手动测试？"; then
        manual_test_function
    fi
    
    # 使用技巧
    provide_usage_tips
    
    # 完成引导
    echo
    echo "======================================================"
    echo -e "${GREEN}${BOLD}🎉 引导完成！${NC}"
    echo "======================================================"
    
    echo -e "${BLUE}您现在可以：${NC}"
    echo -e "  ${GREEN}•${NC} 随时使用 F4 进行快速识别"
    echo -e "  ${GREEN}•${NC} 运行 'amd-helper' 启动完整程序"
    echo -e "  ${GREEN}•${NC} 重新运行此引导：bash first_time_guide.sh"
    
    speak_safe "引导完成！您现在可以随时使用F4进行快速识别，或运行amd-helper启动完整程序"
    
    echo -e "${GREEN}${BOLD}祝您使用愉快！${NC}"
    speak_safe "祝您使用愉快！"
}

# 检查是否为直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi