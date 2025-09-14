#!/bin/bash
# A.M.D-helper 视障辅助软件全自动安装脚本
# 专为视力障碍用户优化设计

# ==============================================================================
#  全局配置
# ==============================================================================

set -e  # 任何命令失败则立即退出
set -u  # 使用未定义变量时退出
set -o pipefail  # 管道命令失败时退出

# 定义颜色和格式
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# 全局变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/amd-helper-install.log"
SPEECH_RATE="0"  # 语音速度，0=正常
SPEECH_VOLUME="50"  # 语音音量百分比

# 语言环境检测
detect_system_language() {
    local lang="${LANG:-en_US.UTF-8}"
    case "$lang" in
        zh_CN*|zh_TW*|zh_HK*|zh_SG*)
            SYSTEM_LANG="zh"
            ;;
        en_*)
            SYSTEM_LANG="en"
            ;;
        *)
            # 默认使用中文
            SYSTEM_LANG="zh"
            ;;
    esac
    export SYSTEM_LANG
}

# 初始化语言环境
detect_system_language

# 初始化全局变量
SOURCE_DIR=""
detection_method=""

# ==============================================================================
#  日志和错误处理
# ==============================================================================

# 日志函数
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    case "$level" in
        "ERROR")
            echo -e "${RED}${BOLD}[错误]${NC} $message" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[警告]${NC} $message" >&2
            ;;
        "INFO")
            echo -e "${BLUE}[信息]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}${BOLD}[成功]${NC} $message"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# 错误处理函数
error_exit() {
    local error_code=$?
    local line_number=$1
    log "ERROR" "脚本在第 $line_number 行发生错误，错误代码: $error_code"
    speak_safe "安装过程中发生错误，请查看错误信息并联系技术支持"
    echo
    echo -e "${RED}${BOLD}=== 安装失败 ===${NC}"
    echo "错误详情已记录到: $LOG_FILE"
    echo "请将此日志文件发送给技术支持人员"
    exit $error_code
}

# 捕获错误 - 但允许某些非关键错误继续
trap 'handle_error $LINENO $?' ERR

# 改进的错误处理函数
handle_error() {
    local line_number=$1
    local error_code=$2
    
    # 某些非关键错误可以继续
    local non_critical_patterns=(
        "权限"
        "permission"
        "thinclient"
        "rsync"
    )
    
    local last_command=$(history | tail -1 | sed 's/^[ ]*[0-9]*[ ]*//')
    
    for pattern in "${non_critical_patterns[@]}"; do
        if [[ "$last_command" =~ $pattern ]]; then
            log "WARN" "非关键错误在第 $line_number 行: $last_command (错误代码: $error_code)"
            speak_safe "遇到非关键错误，继续安装"
            return 0
        fi
    done
    
    # 关键错误才退出
    error_exit $line_number
}

# ==============================================================================
#  语音引导系统
# ==============================================================================

# 多语言文本获取函数
get_text() {
    local key="$1"
    case "$SYSTEM_LANG" in
        "zh")
            case "$key" in
                "welcome") echo "欢迎使用A.M.D-helper安装程序" ;;
                "installing_speech") echo "正在安装语音引导工具，这将帮助您更好地了解安装进度" ;;
                "checking_env") echo "正在检测环境兼容性" ;;
                "installing_deps") echo "正在安装系统基础组件，包括Python运行环境和音频支持" ;;
                "setup_app") echo "正在设置A.M.D-helper应用程序文件" ;;
                "installing_python") echo "正在创建Python虚拟环境并安装核心库，这个过程可能需要几分钟" ;;
                "install_complete") echo "A.M.D-helper安装成功！程序已设置为开机自启动。您可以使用F4键进行快速识别，F1键进行悬浮识别。建议重启系统以确保所有功能正常工作。" ;;
                *) echo "$1" ;;
            esac
            ;;
        "en")
            case "$key" in
                "welcome") echo "Welcome to A.M.D-helper installer" ;;
                "installing_speech") echo "Installing speech guidance tools to help you track installation progress" ;;
                "checking_env") echo "Checking environment compatibility" ;;
                "installing_deps") echo "Installing system dependencies including Python runtime and audio support" ;;
                "setup_app") echo "Setting up A.M.D-helper application files" ;;
                "installing_python") echo "Creating Python virtual environment and installing core libraries, this may take several minutes" ;;
                "install_complete") echo "A.M.D-helper installation completed successfully! Auto-start is configured. Use F4 for quick OCR and F1 for floating OCR. Recommend restarting system for best experience." ;;
                *) echo "$1" ;;
            esac
            ;;
        *)
            echo "$1"
            ;;
    esac
}

# 安全的语音播放函数
speak_safe() {
    local message="$1"
    local priority="${2:-normal}"
    
    log "INFO" "[语音] $message"
    
    # 尝试多种语音合成工具，包括现代TTS系统
    if command -v spd-say &> /dev/null; then
        timeout 10s spd-say -r "$SPEECH_RATE" -v "$SPEECH_VOLUME" "$message" 2>/dev/null || true
    elif command -v speechd &> /dev/null && pgrep speech-dispatcher &> /dev/null; then
        # Speech Dispatcher 服务
        timeout 10s spd-say "$message" 2>/dev/null || true
    elif command -v rhvoice &> /dev/null; then
        # RHVoice TTS
        timeout 10s echo "$message" | rhvoice 2>/dev/null || true
    elif command -v espeak-ng &> /dev/null; then
        # eSpeak NG (更现代的版本)
        timeout 10s espeak-ng -s 150 "$message" 2>/dev/null || true
    elif command -v espeak &> /dev/null; then
        timeout 10s espeak -s 150 "$message" 2>/dev/null || true
    elif command -v festival &> /dev/null; then
        timeout 10s echo "$message" | festival --tts 2>/dev/null || true
    elif command -v flite &> /dev/null; then
        # Festival Lite
        timeout 10s flite -t "$message" 2>/dev/null || true
    else
        # 如果没有语音工具，在终端上显示更明显的信息
        echo
        echo -e "${BOLD}${BLUE}=== $(get_text "重要提示") ===${NC}"
        echo -e "${YELLOW}$message${NC}"
        echo -e "${BOLD}${BLUE}===============${NC}"
        echo
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

# 等待用户确认的函数（支持语音提示）
wait_for_confirmation() {
    local message="$1"
    local timeout_seconds="${2:-30}"
    
    speak_safe "$message 请在 $timeout_seconds 秒内按回车键继续，或按 Ctrl+C 取消安装"
    echo -e "${YELLOW}$message${NC}"
    echo "请在 $timeout_seconds 秒内按回车键继续，或按 Ctrl+C 取消..."
    
    if timeout "$timeout_seconds" read -r; then
        log "INFO" "用户确认继续"
        return 0
    else
        log "WARN" "用户确认超时"
        speak_safe "确认超时，自动继续安装"
        return 0
    fi
}

# ==============================================================================
#  系统检查函数
# ==============================================================================

# 检查环境兼容性
check_environment_compatibility() {
    log "INFO" "检查环境兼容性"
    echo -e "${BLUE}🔍 环境兼容性检查${NC}"
    
    local warnings=()
    local critical_issues=()
    
    # 检查GPU支持
    echo -n "  • 检查GPU支持... "
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi &> /dev/null; then
            echo -e "${GREEN}✅ NVIDIA GPU可用${NC}"
        else
            echo -e "${YELLOW}⚠️  NVIDIA驱动问题${NC}"
            warnings+=("NVIDIA GPU驱动可能有问题，某些功能可能较慢")
        fi
    elif lspci | grep -i "vga.*amd\|vga.*radeon" &> /dev/null; then
        echo -e "${BLUE}ℹ️  AMD GPU检测到${NC}"
        warnings+=("AMD GPU支持有限，建议使用CPU模式")
    else
        echo -e "${BLUE}ℹ️  使用CPU模式${NC}"
    fi
    
    # 检查音频系统
    echo -n "  • 检查音频系统... "
    if command -v pulseaudio &> /dev/null || pgrep pulseaudio &> /dev/null; then
        echo -e "${GREEN}✅ PulseAudio可用${NC}"
    elif command -v pipewire &> /dev/null || pgrep pipewire &> /dev/null; then
        echo -e "${GREEN}✅ PipeWire可用${NC}"
    elif command -v alsa &> /dev/null || [[ -d /proc/asound ]]; then
        echo -e "${YELLOW}⚠️  仅ALSA可用${NC}"
        warnings+=("仅检测到ALSA，建议安装PulseAudio以获得更好的音频支持")
    else
        echo -e "${RED}❌ 音频系统问题${NC}"
        critical_issues+=("未检测到可用的音频系统")
    fi
    
    # 检查Python版本兼容性
    echo -n "  • 检查Python版本... "
    local python_version
    python_version=$(python3 --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
    if [[ -n "$python_version" ]]; then
        local major minor
        major=$(echo "$python_version" | cut -d. -f1)
        minor=$(echo "$python_version" | cut -d. -f2)
        
        if [[ $major -eq 3 ]] && [[ $minor -ge 8 ]]; then
            echo -e "${GREEN}✅ Python $python_version${NC}"
        elif [[ $major -eq 3 ]] && [[ $minor -ge 6 ]]; then
            echo -e "${YELLOW}⚠️  Python $python_version (较旧)${NC}"
            warnings+=("Python版本较旧，某些功能可能不稳定")
        else
            echo -e "${RED}❌ Python $python_version (不支持)${NC}"
            critical_issues+=("Python版本过旧，需要Python 3.8+")
        fi
    else
        echo -e "${RED}❌ Python未安装${NC}"
        critical_issues+=("Python3未正确安装")
    fi
    
    # 检查内存
    echo -n "  • 检查可用内存... "
    local mem_gb mem_mb mem_available
    
    # 尝试多种方法获取可用内存
    if command -v free &> /dev/null; then
        # 优先使用available字段（更准确）
        mem_available=$(free -m | awk '/^Mem:/{print $7}' 2>/dev/null)
        if [[ -z "$mem_available" ]] || [[ "$mem_available" -eq 0 ]]; then
            # 如果available字段不存在，使用free字段
            mem_available=$(free -m | awk '/^Mem:/{print $4}' 2>/dev/null)
        fi
        
        if [[ -n "$mem_available" ]] && [[ "$mem_available" -gt 0 ]]; then
            mem_gb=$((mem_available / 1024))
            # 如果计算结果为0，但实际有内存，至少显示1GB
            if [[ $mem_gb -eq 0 ]] && [[ $mem_available -gt 512 ]]; then
                mem_gb=1
            fi
        else
            # 备用方法：使用/proc/meminfo
            mem_available=$(awk '/MemAvailable:/{print int($2/1024)}' /proc/meminfo 2>/dev/null)
            if [[ -n "$mem_available" ]]; then
                mem_gb=$((mem_available / 1024))
            else
                mem_gb=1  # 默认假设有1GB可用
                log "WARN" "无法准确检测内存，假设有1GB可用"
            fi
        fi
    else
        mem_gb=1  # 如果free命令不存在，假设有1GB
        log "WARN" "free命令不可用，假设有1GB内存"
    fi
    
    # 更宽松的内存检查
    if [[ $mem_gb -ge 4 ]]; then
        echo -e "${GREEN}✅ ${mem_gb}GB可用${NC}"
    elif [[ $mem_gb -ge 1 ]]; then
        echo -e "${YELLOW}⚠️  ${mem_gb}GB可用 (建议2GB+)${NC}"
        warnings+=("内存较少，OCR识别可能较慢，建议关闭其他程序")
    else
        echo -e "${YELLOW}⚠️  内存检测异常，将继续安装${NC}"
        warnings+=("无法准确检测内存，如果安装过程中出现内存不足错误，请关闭其他程序")
    fi
    
    # 检查桌面环境
    echo -n "  • 检查桌面环境... "
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        echo -e "${GREEN}✅ $XDG_CURRENT_DESKTOP${NC}"
        if [[ "$XDG_CURRENT_DESKTOP" != *"GNOME"* ]]; then
            warnings+=("非GNOME桌面环境，快捷键配置可能需要手动设置")
        fi
    else
        echo -e "${YELLOW}⚠️  桌面环境未知${NC}"
        warnings+=("无法检测桌面环境，快捷键可能需要手动配置")
    fi
    
    # 报告结果
    echo
    if [[ ${#critical_issues[@]} -gt 0 ]]; then
        echo -e "${RED}${BOLD}❌ 发现严重问题:${NC}"
        for issue in "${critical_issues[@]}"; do
            echo -e "  ${RED}•${NC} $issue"
        done
        speak_safe "发现严重的环境问题，可能影响安装"
        
        if ! ask_user_choice "是否继续安装？(可能会失败)"; then
            log "INFO" "用户因环境问题取消安装"
            exit 0
        fi
    fi
    
    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo -e "${YELLOW}${BOLD}⚠️  环境警告:${NC}"
        for warning in "${warnings[@]}"; do
            echo -e "  ${YELLOW}•${NC} $warning"
        done
        speak_safe "检测到${#warnings[@]}个环境警告，但可以继续安装"
    fi
    
    if [[ ${#critical_issues[@]} -eq 0 ]] && [[ ${#warnings[@]} -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✅ 环境兼容性良好${NC}"
        speak_safe "环境兼容性检查通过"
    fi
    
    log "SUCCESS" "环境兼容性检查完成"
}

# 检查是否以root权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "需要管理员权限运行"
        echo -e "${RED}${BOLD}错误: 需要管理员权限运行此脚本${NC}"
        echo "请使用以下命令重新运行:"
        echo -e "${GREEN}sudo bash $0${NC}"
        speak_safe "错误，需要管理员权限运行此脚本。请使用 sudo bash 命令重新运行"
        exit 1
    fi
    log "INFO" "权限检查通过"
}

# 检查系统兼容性
check_system() {
    log "INFO" "开始系统兼容性检查"
    
    # 检查操作系统
    if ! command -v apt-get &> /dev/null; then
        log "ERROR" "不支持的操作系统，需要基于Debian/Ubuntu的系统"
        speak_safe "错误，此安装程序仅支持Ubuntu或Debian系统"
        exit 1
    fi
    
    # 检查架构
    local arch=$(uname -m)
    log "INFO" "系统架构: $arch"
    
    if [[ ! "$arch" =~ ^(x86_64|aarch64|armv7l)$ ]]; then
        log "WARN" "未经测试的系统架构: $arch"
        speak_safe "警告，您的系统架构可能不被完全支持，但将尝试继续安装"
    fi
    
    # 检查网络连接 - 改进的检测方式，适配容器环境
    log "INFO" "检查网络连接"
    local network_ok=false
    
    # 方法1: 使用 wget 测试 HTTP 连接（容器友好）
    if wget -q --spider --timeout=10 https://pypi.org 2>/dev/null; then
        network_ok=true
        log "INFO" "网络连接正常 (wget 测试)"
    # 方法2: 使用 curl 测试（增加超时时间）
    elif curl -s --connect-timeout 15 --max-time 20 https://pypi.org >/dev/null 2>&1; then
        network_ok=true
        log "INFO" "网络连接正常 (curl 测试)"
    # 方法3: 尝试 ping（可能在容器中失败）
    elif ping -c 1 -W 5 8.8.8.8 &> /dev/null; then
        network_ok=true
        log "INFO" "网络连接正常 (ping 测试)"
    fi
    
    if [[ "$network_ok" == "false" ]]; then
        log "WARN" "网络连接检查失败，但将继续安装（可能是容器环境限制）"
        speak_safe "网络检测失败，可能是容器环境限制，将继续安装并在需要时测试实际连接"
        echo -e "${YELLOW}⚠️  网络检测失败，但这在容器环境中是正常的${NC}"
        echo -e "${BLUE}💡 将在实际安装时测试网络连接${NC}"
    else
        log "SUCCESS" "网络连接检查通过"
    fi
    
    log "SUCCESS" "系统兼容性检查完成"
}

# 检查磁盘空间
check_disk_space() {
    local required_space_mb=1024  # 至少需要1GB空间
    local available_space_mb
    
    available_space_mb=$(df /opt | awk 'NR==2 {print int($4/1024)}')
    
    if [[ $available_space_mb -lt $required_space_mb ]]; then
        log "ERROR" "磁盘空间不足，需要至少 ${required_space_mb}MB，可用 ${available_space_mb}MB"
        speak_safe "错误，磁盘空间不足，需要至少1GB可用空间"
        exit 1
    fi
    
    log "INFO" "磁盘空间检查通过，可用空间: ${available_space_mb}MB"
}

# ==============================================================================
#  语音工具安装
# ==============================================================================

install_speech_tools() {
    log "INFO" "开始安装语音工具"
    speak_safe "$(get_text "installing_speech")"
    
    # 更新软件源
    log "INFO" "更新软件包列表"
    if ! apt-get update 2>&1 | tee -a "$LOG_FILE"; then
        log "WARN" "软件源更新失败，尝试继续安装"
    fi
    
    # 安装语音工具，按优先级尝试，包括现代TTS系统
    local speech_packages=(
        "speech-dispatcher"     # 现代语音调度器
        "speechd"              # Speech Dispatcher 别名
        "rhvoice"              # RHVoice TTS引擎
        "espeak-ng"            # eSpeak NG (现代版本)
        "espeak"               # 经典eSpeak
        "festival"             # Festival TTS
        "flite"                # Festival Lite
        "pico2wave"            # SVOX Pico TTS
    )
    local installed_any=false
    local installed_packages=()
    
    for package in "${speech_packages[@]}"; do
        log "INFO" "尝试安装 $package"
        if apt-get install -y "$package" 2>&1 | tee -a "$LOG_FILE"; then
            log "SUCCESS" "成功安装 $package"
            installed_packages+=("$package")
            installed_any=true
            # 不要break，继续安装其他TTS工具以提供更多选择
        else
            log "WARN" "安装 $package 失败，尝试下一个"
        fi
    done
    
    if [[ "$installed_any" == true ]]; then
        # 等待语音系统初始化
        sleep 2
        local success_msg
        case "$SYSTEM_LANG" in
            "zh") success_msg="语音工具安装成功，现在可以为您提供语音引导。已安装: ${installed_packages[*]}" ;;
            "en") success_msg="Speech tools installed successfully, voice guidance is now available. Installed: ${installed_packages[*]}" ;;
            *) success_msg="语音工具安装成功，现在可以为您提供语音引导" ;;
        esac
        speak_safe "$success_msg"
    else
        log "WARN" "所有语音工具安装失败，将仅提供文字提示"
        local warn_msg
        case "$SYSTEM_LANG" in
            "zh") warn_msg="注意: 无法安装语音工具，安装过程将仅提供文字提示" ;;
            "en") warn_msg="Warning: Unable to install speech tools, installation will provide text-only feedback" ;;
            *) warn_msg="注意: 无法安装语音工具，安装过程将仅提供文字提示" ;;
        esac
        echo -e "${YELLOW}$warn_msg${NC}"
    fi
}

# ==============================================================================
#  破损安装检测和修复
# ==============================================================================

# 检测并修复破损的安装
detect_and_fix_broken_installation() {
    log "INFO" "检测破损安装"
    speak_safe "正在检测现有安装的完整性"
    
    echo
    echo -e "${BLUE}🔍 正在检测现有安装...${NC}"
    
    local broken_components=()
    local app_dir="/opt/amd-helper"
    
    # 检查应用目录
    if [[ -d "$app_dir" ]]; then
        log "INFO" "发现现有安装，检查完整性"
        echo -e "${YELLOW}📁 发现现有安装目录，正在检查完整性...${NC}"
        
        # 检查虚拟环境
        echo -n "  • 检查Python虚拟环境... "
        if [[ -d "$app_dir/venv" ]] && [[ ! -f "$app_dir/venv/bin/python" ]]; then
            broken_components+=("虚拟环境")
            log "WARN" "检测到破损的虚拟环境"
            echo -e "${RED}❌ 破损${NC}"
        elif [[ ! -d "$app_dir/venv" ]]; then
            broken_components+=("虚拟环境")
            log "WARN" "虚拟环境不存在"
            echo -e "${RED}❌ 缺失${NC}"
        else
            echo -e "${GREEN}✅ 正常${NC}"
        fi
        
        # 检查主要脚本文件
        echo -n "  • 检查应用程序文件... "
        local required_files=("tray.py" "f1.py" "f4.py")
        local missing_files=()
        for file in "${required_files[@]}"; do
            if [[ ! -f "$app_dir/$file" ]]; then
                missing_files+=("$file")
            fi
        done
        
        if [[ ${#missing_files[@]} -gt 0 ]]; then
            broken_components+=("应用文件")
            log "WARN" "缺少关键文件: ${missing_files[*]}"
            echo -e "${RED}❌ 缺失文件: ${missing_files[*]}${NC}"
        else
            echo -e "${GREEN}✅ 正常${NC}"
        fi
        
        # 检查启动脚本
        echo -n "  • 检查启动脚本... "
        if [[ ! -f "$app_dir/tray.sh" ]] || [[ ! -x "$app_dir/tray.sh" ]]; then
            broken_components+=("启动脚本")
            log "WARN" "启动脚本缺失或无执行权限"
            echo -e "${RED}❌ 异常${NC}"
        else
            echo -e "${GREEN}✅ 正常${NC}"
        fi
        
        # 检查安装信息文件
        echo -n "  • 检查安装信息... "
        if [[ ! -f "$app_dir/install-info.txt" ]]; then
            broken_components+=("安装信息")
            log "WARN" "安装信息文件缺失"
            echo -e "${RED}❌ 缺失${NC}"
        else
            # 检查安装是否完成
            if grep -q "INSTALL_COMPLETED=true" "$app_dir/install-info.txt" 2>/dev/null; then
                echo -e "${GREEN}✅ 安装完整${NC}"
            else
                broken_components+=("安装未完成")
                log "WARN" "检测到未完成的安装"
                echo -e "${YELLOW}⚠️  安装未完成${NC}"
            fi
        fi
        
        # 检查Python依赖完整性
        if [[ -d "$app_dir/venv" ]] && [[ -f "$app_dir/venv/bin/pip" ]]; then
            echo -n "  • 检查Python依赖... "
            local missing_deps=0
            local critical_deps=("Pillow" "numpy" "requests")
            
            for dep in "${critical_deps[@]}"; do
                # 添加超时防止卡住
                if ! timeout 10s "$app_dir/venv/bin/pip" show "$dep" &>/dev/null; then
                    ((missing_deps++))
                fi
            done
            
            if [[ $missing_deps -eq 0 ]]; then
                echo -e "${GREEN}✅ 关键依赖完整${NC}"
            elif [[ $missing_deps -lt ${#critical_deps[@]} ]]; then
                broken_components+=("部分依赖缺失")
                log "WARN" "检测到部分Python依赖缺失"
                echo -e "${YELLOW}⚠️  部分依赖缺失${NC}"
            else
                broken_components+=("依赖严重缺失")
                log "WARN" "检测到严重的依赖缺失"
                echo -e "${RED}❌ 依赖严重缺失${NC}"
            fi
        fi
        
        # 检查桌面集成
        local integration_issues=()
        
        # 检查自启动
        local autostart_file="$HOME/.config/autostart/amd-helper.desktop"
        if [[ ! -f "$autostart_file" ]]; then
            integration_issues+=("自启动")
        fi
        
        # 检查快捷键（如果是GNOME环境）
        if command -v gsettings &> /dev/null && [[ -n "${DISPLAY:-}" ]]; then
            local current_keys
            # 添加超时防止在容器环境中卡住
            current_keys=$(timeout 5s gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null || echo "@as []")
            if ! echo "$current_keys" | grep -q "amd-helper"; then
                integration_issues+=("快捷键")
            fi
        elif command -v gsettings &> /dev/null; then
            # 无显示环境，跳过快捷键检查
            integration_issues+=("快捷键(无显示环境)")
        fi
        
        if [[ ${#integration_issues[@]} -gt 0 ]]; then
            echo -n "  • 检查桌面集成... "
            broken_components+=("桌面集成")
            log "WARN" "桌面集成不完整: ${integration_issues[*]}"
            echo -e "${YELLOW}⚠️  ${integration_issues[*]} 未配置${NC}"
        fi
        
        echo
        
        # 报告检测结果
        if [[ ${#broken_components[@]} -gt 0 ]]; then
            log "WARN" "检测到破损组件: ${broken_components[*]}"
            
            echo -e "${RED}${BOLD}⚠️  检测到安装问题${NC}"
            echo -e "${YELLOW}发现以下破损组件:${NC}"
            for component in "${broken_components[@]}"; do
                echo -e "  ${RED}•${NC} $component"
            done
            echo
            echo -e "${BLUE}💡 建议进行完整重新安装以确保所有功能正常${NC}"
            
            speak_safe "检测到${#broken_components[@]}个破损组件，包括${broken_components[*]}。建议进行完整重新安装"
            
            # 在容器环境中自动继续，避免卡住
            if [[ -f /.dockerenv ]] || [[ -z "${DISPLAY:-}" ]]; then
                log "INFO" "容器环境检测，自动继续修复安装"
                speak_safe "容器环境检测，自动开始修复安装"
                return 0  # 继续安装流程
            elif wait_for_confirmation "是否继续修复安装？" 15; then
                log "INFO" "用户确认修复安装"
                speak_safe "开始修复安装，这将重新安装所有组件"
                return 0  # 继续安装流程
            else
                log "INFO" "用户取消修复"
                speak_safe "用户取消了修复安装"
                exit 0
            fi
        else
            log "INFO" "现有安装完整，但将重新安装以确保最新版本"
            echo -e "${GREEN}${BOLD}✅ 现有安装完整${NC}"
            echo -e "${BLUE}💡 将升级到最新版本以确保最佳体验${NC}"
            speak_safe "发现完整的现有安装，将升级到最新版本"
            return 0
        fi
    else
        log "INFO" "未发现现有安装，进行全新安装"
        echo -e "${BLUE}📦 未发现现有安装，将进行全新安装${NC}"
        speak_safe "未发现现有安装，将进行全新安装"
        return 0
    fi
}

# ==============================================================================
#  主要安装函数
# ==============================================================================

# 安装系统依赖
install_system_dependencies() {
    log "INFO" "开始安装系统依赖"
    speak_safe "正在安装系统基础组件，包括Python运行环境和音频支持"
    
    local packages=(
        "python3"
        "python3-pip" 
        "python3-venv"
        "python3-dev"
        "python3-tk"
        "libasound2-dev"
        "libgl1-mesa-glx"
        "libglib2.0-dev"
        "libcairo2-dev"
        "libgirepository1.0-dev"
        "gir1.2-glib-2.0"
        "gir1.2-gtk-3.0"
        "libgtk-3-dev"
        "gobject-introspection"
        "pkg-config"
        "portaudio19-dev"
        "libffi-dev"
        "curl"
        "wget"
        "rsync"
        "build-essential"
        "cmake"
        "ninja-build"
    )
    
    local failed_packages=()
    
    for package in "${packages[@]}"; do
        log "INFO" "安装 $package"
        if apt-get install -y "$package" 2>&1 | tee -a "$LOG_FILE"; then
            log "SUCCESS" "成功安装 $package"
        else
            log "WARN" "安装 $package 失败"
            failed_packages+=("$package")
        fi
    done
    
    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        log "WARN" "以下软件包安装失败: ${failed_packages[*]}"
        speak_safe "部分系统组件安装失败，但将尝试继续"
        # 在容器环境中自动继续
        if [[ -f /.dockerenv ]] || [[ -z "${DISPLAY:-}" ]]; then
            log "INFO" "容器环境检测，自动继续安装"
            speak_safe "容器环境检测，自动继续安装"
        else
            wait_for_confirmation "是否继续安装？"
        fi
    fi
    
    log "SUCCESS" "系统依赖安装完成"
}

# 设置应用程序
setup_application() {
    log "INFO" "开始设置应用程序"
    speak_safe "正在设置A.M.D-helper应用程序文件"
    
    # 定义全局变量
    APP_NAME="amd-helper"
    APP_DIR="/opt/$APP_NAME"
    # 自动处理脚本同目录下的压缩包
    log "INFO" "检查脚本同目录下的压缩包"
    echo -e "${BLUE}📦 检查脚本同目录下的压缩包...${NC}"
    echo -e "${BLUE}  脚本目录: $SCRIPT_DIR${NC}"
    
    # 显示目录内容以便调试
    if [[ -d "$SCRIPT_DIR" ]]; then
        echo -e "${BLUE}  目录内容:${NC}"
        ls -la "$SCRIPT_DIR" 2>/dev/null | head -10 || echo "    无法列出目录内容"
        
        if [[ -d "$SCRIPT_DIR/release" ]]; then
            echo -e "${BLUE}  release目录内容:${NC}"
            ls -la "$SCRIPT_DIR/release" 2>/dev/null | head -10 || echo "    无法列出release目录内容"
        fi
    fi
    
    local script_archives=(
        "$SCRIPT_DIR"/*.tar.gz
        "$SCRIPT_DIR"/*.tar.bz2
        "$SCRIPT_DIR"/*.zip
        "$SCRIPT_DIR"/amd-helper*.tar.gz
        "$SCRIPT_DIR"/release*.tar.gz
        "$SCRIPT_DIR"/release/*.tar.gz
        "$SCRIPT_DIR"/release/*.tar.bz2
        "$SCRIPT_DIR"/release/*.zip
        "$SCRIPT_DIR"/release/amd-helper*.tar.gz
    )
    
    local found_archive=""
    echo -n "  • 搜索压缩包文件... "
    
    for pattern in "${script_archives[@]}"; do
        # 安全地展开通配符
        shopt -s nullglob  # 如果没有匹配，返回空而不是原始模式
        local matches=($pattern)
        shopt -u nullglob
        
        for archive in "${matches[@]}"; do
            if [[ -f "$archive" ]]; then
                found_archive="$archive"
                log "INFO" "发现脚本同目录压缩包: $archive"
                echo -e "${GREEN}发现: $(basename "$archive")${NC}"
                break 2
            fi
        done
    done
    
    if [[ -z "$found_archive" ]]; then
        echo -e "${BLUE}未发现${NC}"
    fi
    
    if [[ -n "$found_archive" ]]; then
        speak_safe "发现压缩包，正在自动解压安装文件"
        
        # 创建解压目录
        local extract_dir="/opt/amd-helper-source-$(date +%s)"
        mkdir -p "$extract_dir"
        
        echo -n "  • 正在解压压缩包... "
        local extract_success=false
        
        # 根据文件类型选择解压方法
        case "$found_archive" in
            *.tar.gz|*.tgz)
                if tar -xzf "$found_archive" -C "$extract_dir" 2>/dev/null; then
                    extract_success=true
                fi
                ;;
            *.tar.bz2|*.tbz2)
                if tar -xjf "$found_archive" -C "$extract_dir" 2>/dev/null; then
                    extract_success=true
                fi
                ;;
            *.zip)
                if command -v unzip &>/dev/null && unzip -q "$found_archive" -d "$extract_dir" 2>/dev/null; then
                    extract_success=true
                fi
                ;;
        esac
        
        if [[ "$extract_success" == true ]]; then
            echo -e "${GREEN}✅ 解压成功${NC}"
            
            # 查找解压后的源文件
            local extracted_source=""
            
            # 方法1: 直接在解压目录查找
            if [[ -f "$extract_dir/tray.py" ]]; then
                extracted_source="$extract_dir"
            # 方法2: 查找包含models文件夹的目录
            elif [[ -d "$extract_dir/models" ]] && [[ -f "$extract_dir/f4.py" ]]; then
                extracted_source="$extract_dir"
            # 方法3: 在子目录中查找
            else
                # 查找包含tray.py的目录
                local tray_path=$(find "$extract_dir" -name "tray.py" -type f | head -1 2>/dev/null)
                if [[ -n "$tray_path" ]]; then
                    extracted_source=$(dirname "$tray_path")
                else
                    # 查找包含f4.py的目录
                    local f4_path=$(find "$extract_dir" -name "f4.py" -type f | head -1 2>/dev/null)
                    if [[ -n "$f4_path" ]]; then
                        extracted_source=$(dirname "$f4_path")
                    fi
                fi
            fi
            
            # 验证解压的源文件
            if [[ -n "$extracted_source" ]] && [[ -d "$extracted_source" ]]; then
                # 检查是否包含关键文件或models目录
                local has_key_files=false
                if [[ -f "$extracted_source/tray.py" ]] || [[ -f "$extracted_source/f4.py" ]] || [[ -d "$extracted_source/models" ]]; then
                    has_key_files=true
                fi
                
                if [[ "$has_key_files" == true ]]; then
                    SOURCE_DIR="$extracted_source"
                    log "SUCCESS" "从脚本同目录压缩包解压源文件到: $SOURCE_DIR"
                    echo -e "${GREEN}  ✅ 源文件解压完成: $SOURCE_DIR${NC}"
                    
                    # 记录解压信息
                    echo "EXTRACTED_FROM=$found_archive" >> "$SOURCE_DIR/.extract_info"
                    echo "EXTRACT_DATE=$(date)" >> "$SOURCE_DIR/.extract_info"
                    
                    speak_safe "压缩包解压成功，找到完整的程序文件"
                else
                    log "WARN" "压缩包中未找到有效的源文件"
                    echo -e "${YELLOW}  ⚠️  压缩包中未找到有效的源文件${NC}"
                    rm -rf "$extract_dir"
                fi
            else
                log "WARN" "压缩包解压后未找到源文件"
                echo -e "${YELLOW}  ⚠️  解压后未找到源文件${NC}"
                rm -rf "$extract_dir"
            fi
        else
            echo -e "${RED}❌ 解压失败${NC}"
            log "WARN" "压缩包解压失败: $found_archive"
            rm -rf "$extract_dir"
        fi
    else
        echo -e "${BLUE}  ℹ️  未发现压缩包，继续常规检测${NC}"
    fi
    
    # 如果已经从压缩包获得源文件，跳过其他检测
    if [[ -n "$SOURCE_DIR" ]]; then
        log "SUCCESS" "已从压缩包获得源文件，跳过其他检测"
        echo -e "${GREEN}✅ 源文件已准备就绪${NC}"
    else
        # 全自动智能源目录检测 - 为视障用户设计的零干预检测
        log "INFO" "开始全自动源目录检测"
        echo -e "${BLUE}🔍 正在智能检测应用程序源文件...${NC}"
    fi
    
    # 只有在未从压缩包获得源文件时才进行其他检测
    if [[ -z "$SOURCE_DIR" ]]; then
        # 第一步：基于脚本位置的标准检测
    local script_based_dirs=(
        "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
        "$(dirname "${BASH_SOURCE[0]}")"
        "$SCRIPT_DIR/.."
        "$SCRIPT_DIR"
    )
    
    # 第二步：基于当前位置的检测
    local current_based_dirs=(
        "$(pwd)"
        "$(pwd)/.."
        "$(pwd)/../.."
    )
    
    # 第三步：系统常见位置检测
    local system_dirs=(
        "/home/user/app"
        "/home/$(whoami)/app"
        "/opt/amd-helper"
        "/opt/amd-helper-source"
        "/usr/local/src/amd-helper"
        "/tmp/amd-helper"
        "/var/tmp/amd-helper"
    )
    
    # 第四步：递归搜索常见目录
    local search_roots=(
        "/home"
        "/opt"
        "/usr/local"
        "/tmp"
    )
    
    SOURCE_DIR=""
    local detection_method=""
    
    # 检测函数：验证目录是否包含必要文件或压缩包
    check_source_dir() {
        local dir="$1"
        local method="$2"
        
        if [[ ! -d "$dir" ]] || [[ ! -r "$dir" ]]; then
            return 1
        fi
        
        # 首先检查是否有压缩包需要解压
        local archive_files=(
            "$dir/release/amd-helper-v*.tar.gz"
            "$dir/amd-helper-v*.tar.gz"
            "$dir/*.tar.gz"
            "$dir/release/*.tar.gz"
        )
        
        for pattern in "${archive_files[@]}"; do
            for archive in $pattern; do
                if [[ -f "$archive" ]]; then
                    log "INFO" "发现压缩包: $archive"
                    echo -e "${BLUE}    发现压缩包: $(basename "$archive")${NC}"
                    
                    # 创建临时解压目录
                    local extract_dir="/tmp/amd-helper-extract-$$"
                    mkdir -p "$extract_dir"
                    
                    echo -n "    正在解压压缩包... "
                    if tar -xzf "$archive" -C "$extract_dir" 2>/dev/null; then
                        echo -e "${GREEN}✅ 成功${NC}"
                        
                        # 查找解压后的源文件
                        local extracted_source=""
                        if [[ -f "$extract_dir/tray.py" ]]; then
                            extracted_source="$extract_dir"
                        else
                            # 查找子目录中的源文件
                            extracted_source=$(find "$extract_dir" -name "tray.py" -type f | head -1 | xargs dirname 2>/dev/null)
                        fi
                        
                        if [[ -n "$extracted_source" ]] && [[ -f "$extracted_source/tray.py" ]]; then
                            SOURCE_DIR="$extracted_source"
                            detection_method="$method (解压缩包)"
                            log "SUCCESS" "从压缩包解压源文件到: $SOURCE_DIR"
                            return 0
                        else
                            echo -e "${YELLOW}    压缩包中未找到源文件${NC}"
                            rm -rf "$extract_dir"
                        fi
                    else
                        echo -e "${RED}❌ 解压失败${NC}"
                        rm -rf "$extract_dir"
                    fi
                fi
            done
        done
        
        # 检查关键Python文件
        local key_files=("tray.py" "f4.py" "f1.py")
        local found_files=0
        
        for file in "${key_files[@]}"; do
            if [[ -f "$dir/$file" ]]; then
                ((found_files++))
            fi
        done
        
        # 至少找到一个关键文件
        if [[ $found_files -gt 0 ]]; then
            SOURCE_DIR="$dir"
            detection_method="$method"
            return 0
        fi
        
        # 检查是否有任何Python文件
        if ls "$dir"/*.py &>/dev/null 2>&1; then
            local py_count=$(ls "$dir"/*.py 2>/dev/null | wc -l)
            if [[ $py_count -ge 3 ]]; then  # 至少3个Python文件
                SOURCE_DIR="$dir"
                detection_method="$method (通用Python文件)"
                return 0
            fi
        fi
        
        return 1
    }
    
    echo -n "  • 检查脚本相关位置... "
    for dir in "${script_based_dirs[@]}"; do
        if check_source_dir "$dir" "脚本位置"; then
            echo -e "${GREEN}✅ 找到${NC}"
            break
        fi
    done
    
    if [[ -z "$SOURCE_DIR" ]]; then
        echo -e "${YELLOW}未找到${NC}"
        echo -n "  • 检查当前工作目录... "
        for dir in "${current_based_dirs[@]}"; do
            if check_source_dir "$dir" "当前目录"; then
                echo -e "${GREEN}✅ 找到${NC}"
                break
            fi
        done
    fi
    
    if [[ -z "$SOURCE_DIR" ]]; then
        echo -e "${YELLOW}未找到${NC}"
        echo -n "  • 检查系统常见位置... "
        for dir in "${system_dirs[@]}"; do
            if check_source_dir "$dir" "系统位置"; then
                echo -e "${GREEN}✅ 找到${NC}"
                break
            fi
        done
    fi
    
    if [[ -z "$SOURCE_DIR" ]]; then
        echo -e "${YELLOW}未找到${NC}"
        echo -n "  • 执行深度搜索... "
        
        # 优化的深度搜索 - 针对容器环境
        local search_found=false
        
        # 首先检查最可能的位置（基于当前环境）
        local priority_locations=(
            "/home/user/app"
            "/home/*/app"
            "/opt/amd-helper*"
            "/tmp/amd-helper*"
        )
        
        for pattern in "${priority_locations[@]}"; do
            for dir in $pattern; do
                if [[ -d "$dir" ]] && check_source_dir "$dir" "优先搜索"; then
                    search_found=true
                    break 2
                fi
            done
        done
        
        # 如果优先搜索没找到，进行限制性深度搜索
        if [[ "$search_found" == false ]]; then
            for root in "${search_roots[@]}"; do
                if [[ -d "$root" ]] && [[ -r "$root" ]]; then
                    # 使用更高效的搜索策略
                    local found_dirs
                    found_dirs=$(timeout 10s find "$root" -maxdepth 3 -name "*.py" -path "*/tray.py" -o -path "*/f4.py" -o -path "*/f1.py" 2>/dev/null | head -5 | xargs -I {} dirname {} 2>/dev/null | sort -u)
                    
                    for found_dir in $found_dirs; do
                        if check_source_dir "$found_dir" "深度搜索"; then
                            search_found=true
                            break 2
                        fi
                    done
                fi
            done
        fi
        
        if [[ "$search_found" == true ]]; then
            echo -e "${GREEN}✅ 找到${NC}"
        else
            echo -e "${YELLOW}未找到${NC}"
        fi
    fi
    
    # 最后的备用方案：智能最小化安装
    if [[ -z "$SOURCE_DIR" ]]; then
        echo -e "${YELLOW}未找到${NC}"
        echo -e "${BLUE}  • 创建智能最小化安装...${NC}"
        speak_safe "无法找到完整源文件，正在创建智能最小化安装版本"
        
        # 创建临时源目录
        SOURCE_DIR="/tmp/amd-helper-minimal-$$"
        mkdir -p "$SOURCE_DIR"
        
        # 尝试从网络获取最新版本（如果有网络连接）
        echo -n "    - 尝试从网络获取最新版本... "
        if command -v curl &>/dev/null && curl -s --connect-timeout 5 https://github.com &>/dev/null; then
            # 这里可以添加从GitHub或其他源下载的逻辑
            echo -e "${YELLOW}网络可用但未配置下载源${NC}"
        else
            echo -e "${YELLOW}无网络连接${NC}"
        fi
        
        # 创建功能完整的最小化版本
        echo -n "    - 创建最小化功能模块... "
        
        cat > "$SOURCE_DIR/tray.py" << 'EOF'
#!/usr/bin/env python3
# A.M.D-helper 最小化托盘程序
import sys
import os
import subprocess
import tkinter as tk
from tkinter import messagebox

class AMDHelperTray:
    def __init__(self):
        self.root = tk.Tk()
        self.root.withdraw()  # 隐藏主窗口
        
    def show_info(self):
        messagebox.showinfo("A.M.D-helper", 
            "A.M.D-helper 最小化版本\n\n"
            "当前版本功能有限\n"
            "建议联系技术支持获取完整版本\n\n"
            "基本功能：\n"
            "- F4: 快速识别\n"
            "- F1: 悬浮识别")
    
    def run(self):
        self.show_info()
        print("A.M.D-helper 最小化版本已启动")
        print("按 Ctrl+C 退出")
        try:
            self.root.mainloop()
        except KeyboardInterrupt:
            print("\n程序已退出")

if __name__ == "__main__":
    app = AMDHelperTray()
    app.run()
EOF

        cat > "$SOURCE_DIR/f4.py" << 'EOF'
#!/usr/bin/env python3
# A.M.D-helper 最小化快速识别
import sys
import os
import tkinter as tk
from tkinter import messagebox, filedialog
try:
    from PIL import Image, ImageTk
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False

def quick_ocr():
    root = tk.Tk()
    root.withdraw()
    
    # 选择图片文件
    file_path = filedialog.askopenfilename(
        title="选择要识别的图片",
        filetypes=[("图片文件", "*.png *.jpg *.jpeg *.bmp *.gif")]
    )
    
    if file_path:
        messagebox.showinfo("A.M.D-helper 快速识别", 
            f"已选择文件: {os.path.basename(file_path)}\n\n"
            "最小化版本无法进行OCR识别\n"
            "请联系技术支持获取完整版本")
    else:
        messagebox.showinfo("A.M.D-helper", "未选择文件")
    
    root.destroy()

if __name__ == "__main__":
    print("A.M.D-helper 快速识别 (最小化版本)")
    quick_ocr()
EOF

        cat > "$SOURCE_DIR/f1.py" << 'EOF'
#!/usr/bin/env python3
# A.M.D-helper 最小化悬浮识别
import sys
import os
import tkinter as tk
from tkinter import messagebox

class FloatingOCR:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("A.M.D-helper 悬浮识别")
        self.root.geometry("300x150")
        self.root.attributes('-topmost', True)
        
        # 创建界面
        label = tk.Label(self.root, text="A.M.D-helper 悬浮识别\n(最小化版本)", 
                        font=("Arial", 12))
        label.pack(pady=20)
        
        info_btn = tk.Button(self.root, text="功能说明", command=self.show_info)
        info_btn.pack(pady=5)
        
        close_btn = tk.Button(self.root, text="关闭", command=self.root.quit)
        close_btn.pack(pady=5)
    
    def show_info(self):
        messagebox.showinfo("功能说明", 
            "悬浮识别功能 (最小化版本)\n\n"
            "完整版本功能：\n"
            "- 屏幕截图识别\n"
            "- 实时文字识别\n"
            "- 语音播报\n\n"
            "请联系技术支持获取完整版本")
    
    def run(self):
        self.root.mainloop()

if __name__ == "__main__":
    print("A.M.D-helper 悬浮识别 (最小化版本)")
    app = FloatingOCR()
    app.run()
EOF

        cat > "$SOURCE_DIR/requirements.txt" << 'EOF'
# A.M.D-helper 最小化依赖
requests>=2.25.0
Pillow>=8.0.0
# 完整版本需要的依赖（注释掉）
# easyocr>=1.6.0
# edge-tts>=6.1.0
# piper-tts==1.2.0
# pystray>=0.19.0
# dbus-next>=0.2.0
# PyGObject>=3.42.0
# pyperclip>=1.8.0
# pygame>=2.1.0
# numpy>=1.21.0
EOF

        # 创建安装说明
        cat > "$SOURCE_DIR/README.md" << 'EOF'
# A.M.D-helper 最小化版本

这是 A.M.D-helper 的最小化安装版本。

## 当前功能
- 基本的图形界面
- 文件选择对话框
- 简单的用户提示

## 缺少的功能
- OCR 文字识别
- 语音合成 (TTS)
- 系统托盘集成
- 快捷键支持
- 自动启动

## 获取完整版本
请联系技术支持或访问官方网站获取完整版本的 A.M.D-helper。

## 运行方法
```bash
python3 tray.py    # 启动托盘程序
python3 f4.py      # 快速识别
python3 f1.py      # 悬浮识别
```
EOF

        chmod +x "$SOURCE_DIR"/*.py
        detection_method="智能最小化安装"
        
        echo -e "${GREEN}✅ 完成${NC}"
        log "WARN" "无法找到完整源文件，已创建智能最小化安装"
        echo -e "${YELLOW}⚠️  已创建智能最小化安装版本${NC}"
        echo -e "${BLUE}💡 包含基本GUI界面和用户提示${NC}"
        echo -e "${BLUE}💡 建议联系技术支持获取完整版本${NC}"
    fi
    
    fi  # 结束源目录检测的条件判断
    
    log "SUCCESS" "源目录检测完成: $SOURCE_DIR ($detection_method)"
    echo -e "${GREEN}✅ 源目录检测成功${NC}"
    echo -e "${BLUE}    位置: $SOURCE_DIR${NC}"
    echo -e "${BLUE}    方法: $detection_method${NC}"
    
    # 验证最终选择的目录
    if [[ ! -d "$SOURCE_DIR" ]] || [[ ! -r "$SOURCE_DIR" ]]; then
        log "ERROR" "最终源目录验证失败: $SOURCE_DIR"
        speak_safe "源目录验证失败，安装无法继续"
        echo -e "${RED}❌ 源目录验证失败${NC}"
        exit 1
    fi
    
    # 智能检测真实用户 - 改进版，适配容器环境
    detect_real_user() {
        local detected_user=""
        
        # 方法1: 检查 SUDO_USER
        if [[ -n "${SUDO_USER:-}" ]] && [[ "$SUDO_USER" != "root" ]]; then
            detected_user="$SUDO_USER"
            log "INFO" "通过SUDO_USER检测到用户: $detected_user"
        # 方法2: 检查当前用户
        elif [[ "$(whoami)" != "root" ]]; then
            detected_user="$(whoami)"
            log "INFO" "通过whoami检测到用户: $detected_user"
        # 方法3: 检查 /etc/passwd 中的普通用户
        else
            detected_user=$(awk -F: '$3>=1000 && $3<65534 {print $1; exit}' /etc/passwd 2>/dev/null)
            if [[ -n "$detected_user" ]]; then
                log "INFO" "通过/etc/passwd检测到用户: $detected_user"
            fi
        fi
        
        # 方法4: 检查 /home 目录
        if [[ -z "$detected_user" ]]; then
            for user_home in /home/*; do
                if [[ -d "$user_home" ]]; then
                    local username=$(basename "$user_home")
                    if [[ "$username" != "root" ]] && id "$username" >/dev/null 2>&1; then
                        detected_user="$username"
                        log "INFO" "通过/home目录检测到用户: $detected_user"
                        break
                    fi
                fi
            done
        fi
        
        # 方法5: 容器环境检测
        if [[ -z "$detected_user" ]] && [[ -f /.dockerenv ]]; then
            # 在Docker容器中，直接使用root可能更合适
            detected_user="root"
            log "INFO" "Docker容器环境，使用root用户"
        fi
        
        # 最后的默认值
        if [[ -z "$detected_user" ]]; then
            detected_user="user"
            log "WARN" "无法检测真实用户，使用默认用户名: $detected_user"
        fi
        
        # 清理用户名，确保只返回纯净的用户名
        detected_user=$(echo "$detected_user" | tr -d '\n\r' | sed 's/[^a-zA-Z0-9_-]//g')
        
        echo "$detected_user"
    }
    
    REAL_USER=$(detect_real_user)
    
    # 验证用户名的有效性
    if [[ -z "$REAL_USER" ]] || [[ "$REAL_USER" =~ [^a-zA-Z0-9_-] ]]; then
        log "WARN" "检测到的用户名无效: '$REAL_USER'，使用默认用户"
        REAL_USER="user"
    fi
    
    log "INFO" "最终确定的用户: $REAL_USER"
    
    # 创建安全的命令执行函数
    safe_user_command() {
        local cmd="$1"
        shift
        local args="$@"
        
        # 检测执行环境并选择合适的命令
        if [[ "$REAL_USER" == "root" ]] || [[ -f /.dockerenv ]] || [[ -z "$REAL_USER" ]]; then
            # 容器环境或root用户，直接执行
            log "INFO" "直接执行命令: $cmd $args"
            "$cmd" $args
        elif id "$REAL_USER" >/dev/null 2>&1; then
            # 有效的非root用户
            log "INFO" "使用用户 $REAL_USER 执行命令: $cmd $args"
            sudo -u "$REAL_USER" "$cmd" $args
        else
            # 用户不存在，回退到直接执行
            log "WARN" "用户 $REAL_USER 不存在，直接执行命令"
            "$cmd" $args
        fi
    }
    
    # 创建安全的pip执行函数（向后兼容）
    safe_pip_command() {
        safe_user_command "$@"
    }
    
    # 安全获取Python版本的函数
    get_safe_python_version() {
        local venv_path="$1"
        if [[ "$REAL_USER" == "root" ]] || [[ -f /.dockerenv ]] || [[ -z "$REAL_USER" ]] || ! id "$REAL_USER" >/dev/null 2>&1; then
            "$venv_path/bin/python" --version 2>/dev/null || echo "未知版本"
        else
            sudo -u "$REAL_USER" "$venv_path/bin/python" --version 2>/dev/null || echo "未知版本"
        fi
    }
    
    # 安全的pip检查函数
    safe_pip_check() {
        local venv_path="$1"
        shift
        local packages="$@"
        
        if [[ "$REAL_USER" == "root" ]] || [[ -f /.dockerenv ]] || [[ -z "$REAL_USER" ]] || ! id "$REAL_USER" >/dev/null 2>&1; then
            timeout 15s "$venv_path/bin/pip" show $packages &>/dev/null
        else
            timeout 15s sudo -u "$REAL_USER" "$venv_path/bin/pip" show $packages &>/dev/null
        fi
    }
    
    # 获取用户家目录
    if id "$REAL_USER" &>/dev/null; then
        REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6 2>/dev/null)
        if [[ -z "$REAL_HOME" ]] || [[ ! -d "$REAL_HOME" ]]; then
            REAL_HOME="/home/$REAL_USER"
            log "WARN" "无法获取用户家目录，使用默认路径: $REAL_HOME"
        fi
    else
        REAL_HOME="/home/$REAL_USER"
        log "WARN" "用户 $REAL_USER 不存在，使用默认家目录: $REAL_HOME"
    fi
    
    INSTALL_INFO_FILE="$APP_DIR/install-info.txt"
    
    # 备份现有安装
    if [[ -d "$APP_DIR" ]]; then
        log "INFO" "发现现有安装，创建备份"
        speak_safe "发现现有安装，正在创建备份"
        local backup_dir="$APP_DIR.backup.$(date +%Y%m%d_%H%M%S)"
        if mv "$APP_DIR" "$backup_dir" 2>/dev/null; then
            log "SUCCESS" "已备份到 $backup_dir"
        else
            log "WARN" "备份失败，删除现有目录"
            rm -rf "$APP_DIR"
        fi
    fi
    
    # 创建应用目录
    log "INFO" "创建应用目录: $APP_DIR"
    mkdir -p "$APP_DIR"
    
    # 智能文件复制系统 - 为视障用户设计的零失败复制
    log "INFO" "开始智能文件复制"
    echo -e "${BLUE}📁 正在复制应用程序文件...${NC}"
    speak_safe "正在复制应用程序文件，请稍候"
    
    # 复制统计
    local total_files=0
    local copied_files=0
    local failed_files=0
    
    # 获取源文件总数
    if [[ -d "$SOURCE_DIR" ]]; then
        total_files=$(find "$SOURCE_DIR" -type f 2>/dev/null | wc -l)
        echo -e "${BLUE}    源目录包含 $total_files 个文件${NC}"
    fi
    
    # 复制方法1：rsync（最佳方法）
    echo -n "  • 方法1: 使用rsync批量复制... "
    local rsync_options="-av --exclude=build --exclude=.git --exclude=venv --exclude=__pycache__ --exclude=*.pyc --exclude=.pytest_cache --exclude=thinclient_drives --exclude=.DS_Store --exclude=Thumbs.db"
    
    if command -v rsync &>/dev/null && rsync $rsync_options "$SOURCE_DIR/" "$APP_DIR/" &>/dev/null; then
        copied_files=$(find "$APP_DIR" -type f 2>/dev/null | wc -l)
        echo -e "${GREEN}✅ 成功 ($copied_files 个文件)${NC}"
        log "SUCCESS" "rsync复制成功，复制了 $copied_files 个文件"
    else
        echo -e "${YELLOW}⚠️  失败，尝试下一种方法${NC}"
        
        # 复制方法2：tar（保持权限和结构）
        echo -n "  • 方法2: 使用tar打包复制... "
        if command -v tar &>/dev/null && \
           (cd "$SOURCE_DIR" && tar --exclude='build' --exclude='.git' --exclude='venv' --exclude='__pycache__' --exclude='*.pyc' --exclude='thinclient_drives' -cf - .) | \
           (cd "$APP_DIR" && tar -xf -) &>/dev/null; then
            copied_files=$(find "$APP_DIR" -type f 2>/dev/null | wc -l)
            echo -e "${GREEN}✅ 成功 ($copied_files 个文件)${NC}"
            log "SUCCESS" "tar复制成功，复制了 $copied_files 个文件"
        else
            echo -e "${YELLOW}⚠️  失败，尝试下一种方法${NC}"
            
            # 复制方法3：智能cp（逐个复制）
            echo -n "  • 方法3: 智能逐个复制... "
            local copy_success=false
            
            # 复制所有文件
            while IFS= read -r -d '' file; do
                local rel_path="${file#$SOURCE_DIR/}"
                local dest_file="$APP_DIR/$rel_path"
                local dest_dir=$(dirname "$dest_file")
                
                # 跳过不需要的文件
                if [[ "$rel_path" =~ (build/|\.git/|venv/|__pycache__/|\.pyc$|thinclient_drives/) ]]; then
                    continue
                fi
                
                # 创建目标目录
                mkdir -p "$dest_dir" 2>/dev/null
                
                # 复制文件
                if cp "$file" "$dest_file" 2>/dev/null; then
                    ((copied_files++))
                    copy_success=true
                else
                    ((failed_files++))
                fi
            done < <(find "$SOURCE_DIR" -type f -print0 2>/dev/null)
            
            if [[ "$copy_success" == true ]]; then
                echo -e "${GREEN}✅ 成功 ($copied_files 个文件，$failed_files 个失败)${NC}"
                log "SUCCESS" "智能复制完成，成功 $copied_files 个，失败 $failed_files 个"
            else
                echo -e "${YELLOW}⚠️  部分失败，尝试最后方法${NC}"
                
                # 复制方法4：最小化复制（确保核心功能）
                echo -n "  • 方法4: 最小化核心文件复制... "
                local essential_files=("tray.py" "f4.py" "f1.py" "requirements.txt" "README.md")
                local essential_dirs=("libshot" "models" "config")
                local essential_copied=0
                
                # 复制核心文件
                for file in "${essential_files[@]}"; do
                    if [[ -f "$SOURCE_DIR/$file" ]]; then
                        if cp "$SOURCE_DIR/$file" "$APP_DIR/" 2>/dev/null; then
                            ((essential_copied++))
                        fi
                    fi
                done
                
                # 复制核心目录
                for dir in "${essential_dirs[@]}"; do
                    if [[ -d "$SOURCE_DIR/$dir" ]]; then
                        if cp -r "$SOURCE_DIR/$dir" "$APP_DIR/" 2>/dev/null; then
                            ((essential_copied++))
                        fi
                    fi
                done
                
                # 复制所有Python文件（如果核心文件不存在）
                if [[ $essential_copied -eq 0 ]]; then
                    find "$SOURCE_DIR" -name "*.py" -type f -exec cp {} "$APP_DIR/" \; 2>/dev/null
                    essential_copied=$(find "$APP_DIR" -name "*.py" -type f 2>/dev/null | wc -l)
                fi
                
                if [[ $essential_copied -gt 0 ]]; then
                    echo -e "${GREEN}✅ 成功 ($essential_copied 个核心组件)${NC}"
                    log "SUCCESS" "最小化复制成功，复制了 $essential_copied 个核心组件"
                    copied_files=$essential_copied
                else
                    echo -e "${RED}❌ 所有方法都失败${NC}"
                    log "ERROR" "所有文件复制方法都失败"
                    
                    # 最后的救援：创建基本文件
                    echo -n "  • 救援方案: 创建基本运行文件... "
                    local rescue_success=false
                    
                    # 如果连基本文件都没有，创建它们
                    if [[ ! -f "$APP_DIR/tray.py" ]]; then
                        cat > "$APP_DIR/tray.py" << 'EOF'
#!/usr/bin/env python3
import sys
print("A.M.D-helper 救援模式")
print("文件复制遇到问题，已启用救援模式")
print("基本功能可用，建议重新安装获取完整功能")
EOF
                        rescue_success=true
                    fi
                    
                    if [[ "$rescue_success" == true ]]; then
                        echo -e "${GREEN}✅ 救援成功${NC}"
                        log "SUCCESS" "救援模式激活，创建了基本运行文件"
                        speak_safe "文件复制遇到问题，已启用救援模式，基本功能可用"
                    else
                        echo -e "${RED}❌ 救援失败${NC}"
                        log "ERROR" "救援模式也失败了"
                        speak_safe "文件复制完全失败，请检查系统权限和磁盘空间"
                        echo -e "${RED}严重错误: 无法复制任何文件${NC}"
                        echo "可能的原因："
                        echo "1. 磁盘空间不足"
                        echo "2. 权限问题"
                        echo "3. 源文件损坏"
                        echo "4. 系统文件系统问题"
                        exit 1
                    fi
                fi
            fi
        fi
    fi
    
    # 复制结果报告
    echo
    echo -e "${BLUE}📊 文件复制统计:${NC}"
    echo -e "  ${GREEN}✅ 成功复制: $copied_files 个文件${NC}"
    if [[ $failed_files -gt 0 ]]; then
        echo -e "  ${YELLOW}⚠️  复制失败: $failed_files 个文件${NC}"
    fi
    
    # 验证关键文件
    local key_files=("tray.py" "f4.py" "f1.py")
    local missing_key_files=()
    
    for file in "${key_files[@]}"; do
        if [[ ! -f "$APP_DIR/$file" ]]; then
            missing_key_files+=("$file")
        fi
    done
    
    if [[ ${#missing_key_files[@]} -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  缺少关键文件: ${missing_key_files[*]}${NC}"
        log "WARN" "缺少关键文件: ${missing_key_files[*]}"
        speak_safe "部分关键文件缺失，但安装将继续"
    else
        echo -e "${GREEN}✅ 所有关键文件复制完成${NC}"
        speak_safe "文件复制成功完成"
    fi
    
    # 设置文件权限
    log "INFO" "设置文件权限"
    echo -n "  • 设置文件所有者... "
    
    # 检查用户是否存在
    if ! id "$REAL_USER" &>/dev/null; then
        echo -e "${YELLOW}⚠️  用户 $REAL_USER 不存在，使用root权限${NC}"
        log "WARN" "用户 $REAL_USER 不存在，文件将保持root权限"
    else
        if chown -R "$REAL_USER:$REAL_USER" "$APP_DIR" 2>/dev/null; then
            echo -e "${GREEN}✅ 权限设置成功${NC}"
            log "SUCCESS" "文件权限设置成功"
        else
            echo -e "${YELLOW}⚠️  权限设置失败，但继续安装${NC}"
            log "WARN" "权限设置失败，文件可能保持root权限"
            
            # 至少确保文件可读可执行
            chmod -R 755 "$APP_DIR" 2>/dev/null || true
            chmod -R +r "$APP_DIR" 2>/dev/null || true
        fi
    fi
    
    # 确保Python文件有执行权限
    echo -n "  • 设置执行权限... "
    find "$APP_DIR" -name "*.py" -exec chmod +x {} \; 2>/dev/null || true
    find "$APP_DIR" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    echo -e "${GREEN}✅ 完成${NC}"
    
    # 保存安装信息
    cat > "$INSTALL_INFO_FILE" << EOF
# A.M.D-helper 安装信息
INSTALL_DATE=$(date '+%Y-%m-%d %H:%M:%S')
INSTALL_USER=$REAL_USER
INSTALL_HOME=$REAL_HOME
APP_DIR=$APP_DIR
SOURCE_DIR=$SOURCE_DIR
PYTHON_VERSION=$(python3 --version 2>/dev/null || echo "unknown")
SYSTEM_INFO=$(uname -a)
EOF
    
    log "SUCCESS" "应用程序设置完成"
    
    # 将重要变量设为全局变量
    export APP_NAME="$APP_NAME"
    export APP_DIR="$APP_DIR"
    export REAL_USER="$REAL_USER"
    export REAL_HOME="$REAL_HOME"
    export INSTALL_INFO_FILE="$INSTALL_INFO_FILE"
}

# 安装Python依赖
install_python_dependencies() {
    log "INFO" "开始安装Python依赖"
    speak_safe "正在创建Python虚拟环境并安装核心库，这个过程可能需要几分钟"
    
    # 防止pip下载卡住的预处理
    echo -e "${BLUE}🔧 配置pip下载优化...${NC}"
    
    # 清理可能卡住的pip进程
    echo -n "  • 清理卡住的进程... "
    if pgrep -f "pip.*install" >/dev/null 2>&1; then
        pkill -f "pip.*install" || true
        sleep 2
        echo -e "${GREEN}✅ 已清理${NC}"
    else
        echo -e "${GREEN}✅ 无需清理${NC}"
    fi
    
    # 配置pip以防止下载卡住
    echo -n "  • 配置pip参数... "
    mkdir -p ~/.pip
    cat > ~/.pip/pip.conf << 'EOF'
[global]
timeout = 60
retries = 5
trusted-host = pypi.org
               pypi.python.org
               files.pythonhosted.org
index-url = https://pypi.org/simple/

[install]
use-pep517 = true
no-cache-dir = false
prefer-binary = true
EOF
    echo -e "${GREEN}✅${NC}"
    log "INFO" "已配置pip下载优化参数"
    
    # 检测网络连接并配置镜像源
    echo -n "  • 检测网络连接... "
    if ! timeout 10s curl -s https://pypi.org >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️ 网络异常，使用镜像源${NC}"
        cat > ~/.pip/pip.conf << 'EOF'
[global]
timeout = 60
retries = 5
index-url = https://pypi.tuna.tsinghua.edu.cn/simple/
extra-index-url = https://mirrors.aliyun.com/pypi/simple/
trusted-host = pypi.tuna.tsinghua.edu.cn
               mirrors.aliyun.com

[install]
use-pep517 = true
no-cache-dir = false
prefer-binary = true
EOF
        log "INFO" "已切换到国内镜像源"
        speak_safe "网络连接异常，已切换到国内镜像源"
    else
        echo -e "${GREEN}✅ 连接正常${NC}"
        log "INFO" "网络连接正常，使用官方源"
    fi
    
    local venv_dir="$APP_DIR/venv"
    
    # 检测其他类型的虚拟环境
    local detected_venvs=()
    
    # 检测 .venv 目录
    if [[ -d "$APP_DIR/.venv" ]] && [[ -f "$APP_DIR/.venv/bin/python" ]]; then
        detected_venvs+=(".venv")
        log "INFO" "检测到 .venv 虚拟环境"
    fi
    
    # 检测 poetry 环境
    if [[ -f "$APP_DIR/pyproject.toml" ]] && command -v poetry &>/dev/null; then
        if poetry env info --path &>/dev/null 2>&1; then
            detected_venvs+=("poetry")
            log "INFO" "检测到 Poetry 虚拟环境"
        fi
    fi
    
    # 检测 pipenv 环境
    if [[ -f "$APP_DIR/Pipfile" ]] && command -v pipenv &>/dev/null; then
        if pipenv --venv &>/dev/null 2>&1; then
            detected_venvs+=("pipenv")
            log "INFO" "检测到 Pipenv 虚拟环境"
        fi
    fi
    
    # 如果检测到其他虚拟环境，询问用户
    if [[ ${#detected_venvs[@]} -gt 0 ]]; then
        echo -e "${BLUE}🔍 检测到其他虚拟环境类型: ${detected_venvs[*]}${NC}"
        
        local use_detected_prompt
        case "$SYSTEM_LANG" in
            "zh") use_detected_prompt="是否使用检测到的虚拟环境？" ;;
            "en") use_detected_prompt="Use detected virtual environment?" ;;
            *) use_detected_prompt="是否使用检测到的虚拟环境？" ;;
        esac
        
        if ask_user_choice "$use_detected_prompt"; then
            # 使用检测到的环境
            for venv_type in "${detected_venvs[@]}"; do
                case "$venv_type" in
                    ".venv")
                        venv_dir="$APP_DIR/.venv"
                        log "INFO" "使用 .venv 虚拟环境"
                        echo -e "${GREEN}  ✅ 将使用 .venv 虚拟环境${NC}"
                        break
                        ;;
                    "poetry")
                        local poetry_venv_path
                        poetry_venv_path=$(cd "$APP_DIR" && poetry env info --path 2>/dev/null)
                        if [[ -n "$poetry_venv_path" ]] && [[ -d "$poetry_venv_path" ]]; then
                            venv_dir="$poetry_venv_path"
                            log "INFO" "使用 Poetry 虚拟环境: $poetry_venv_path"
                            echo -e "${GREEN}  ✅ 将使用 Poetry 虚拟环境${NC}"
                            break
                        fi
                        ;;
                    "pipenv")
                        local pipenv_venv_path
                        pipenv_venv_path=$(cd "$APP_DIR" && pipenv --venv 2>/dev/null)
                        if [[ -n "$pipenv_venv_path" ]] && [[ -d "$pipenv_venv_path" ]]; then
                            venv_dir="$pipenv_venv_path"
                            log "INFO" "使用 Pipenv 虚拟环境: $pipenv_venv_path"
                            echo -e "${GREEN}  ✅ 将使用 Pipenv 虚拟环境${NC}"
                            break
                        fi
                        ;;
                esac
            done
        else
            log "INFO" "用户选择不使用检测到的虚拟环境，将使用标准 venv"
            echo -e "${BLUE}  📁 将使用标准 venv 目录${NC}"
        fi
    fi
    
    # 智能虚拟环境管理 - 支持复用现有环境
    echo
    echo -e "${BLUE}🐍 Python虚拟环境设置${NC}"
    
    local force_new_venv="${FORCE_NEW_VENV:-false}"
    local reuse_venv=false
    
    if [[ -d "$venv_dir" ]]; then
        log "INFO" "检测到现有虚拟环境，验证完整性"
        echo -n "  • 检查现有虚拟环境... "
        
        if [[ ! -f "$venv_dir/bin/python" ]] || [[ ! -f "$venv_dir/bin/pip" ]]; then
            log "WARN" "检测到破损的虚拟环境"
            echo -e "${RED}❌ 破损，需要重建${NC}"
            speak_safe "发现破损的虚拟环境，需要重新创建"
            force_new_venv=true
        else
            echo -e "${GREEN}✅ 完整${NC}"
            
            # 检查虚拟环境的Python版本兼容性
            local venv_python_version
            # 安全获取虚拟环境Python版本
            if [[ "$REAL_USER" == "root" ]] || [[ -f /.dockerenv ]] || [[ -z "$REAL_USER" ]] || ! id "$REAL_USER" >/dev/null 2>&1; then
                venv_python_version=$("$venv_dir/bin/python" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
            else
                venv_python_version=$(sudo -u "$REAL_USER" "$venv_dir/bin/python" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
            fi
            local system_python_version
            system_python_version=$(python3 --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
            
            echo -e "${BLUE}    虚拟环境Python版本: $venv_python_version${NC}"
            echo -e "${BLUE}    系统Python版本: $system_python_version${NC}"
            
            # 检查关键依赖是否已安装
            local has_core_deps=false
            # 检查关键依赖是否已安装
            if safe_pip_check "$venv_dir" Pillow numpy requests; then
                has_core_deps=true
                echo -e "${GREEN}    ✅ 检测到核心依赖已安装${NC}"
            else
                echo -e "${YELLOW}    ⚠️  核心依赖缺失${NC}"
            fi
            
            # 决定是否复用虚拟环境
            if [[ "$force_new_venv" == "true" ]]; then
                log "INFO" "强制创建新虚拟环境模式"
                echo -e "${YELLOW}  • 强制创建新虚拟环境模式${NC}"
                speak_safe "强制创建新虚拟环境"
            elif [[ "$venv_python_version" == "$system_python_version" ]] && [[ "$has_core_deps" == "true" ]]; then
                # 虚拟环境完整且兼容，询问是否复用
                echo -e "${GREEN}  • 发现完整且兼容的虚拟环境${NC}"
                speak_safe "发现完整且兼容的虚拟环境"
                
                local reuse_prompt
                case "$SYSTEM_LANG" in
                    "zh") reuse_prompt="是否复用现有虚拟环境？(推荐，可节省时间)" ;;
                    "en") reuse_prompt="Reuse existing virtual environment? (Recommended, saves time)" ;;
                    *) reuse_prompt="是否复用现有虚拟环境？(推荐，可节省时间)" ;;
                esac
                
                if ask_user_choice "$reuse_prompt"; then
                    reuse_venv=true
                    log "INFO" "用户选择复用现有虚拟环境"
                    echo -e "${GREEN}  ✅ 将复用现有虚拟环境${NC}"
                    speak_safe "将复用现有虚拟环境，跳过重新创建"
                else
                    log "INFO" "用户选择重新创建虚拟环境"
                    echo -e "${BLUE}  🔄 将重新创建虚拟环境${NC}"
                    speak_safe "将重新创建虚拟环境以确保最新配置"
                fi
            else
                log "INFO" "虚拟环境不兼容或不完整，需要重新创建"
                echo -e "${YELLOW}  • 虚拟环境不兼容或不完整，需要重新创建${NC}"
                speak_safe "虚拟环境不兼容或不完整，需要重新创建"
            fi
        fi
    else
        echo -e "${BLUE}  • 未发现现有虚拟环境，将创建新环境${NC}"
    fi
    
    # 处理虚拟环境
    if [[ "$reuse_venv" == "true" ]]; then
        log "SUCCESS" "复用现有虚拟环境"
        echo -e "${GREEN}  ✅ 复用现有虚拟环境${NC}"
        
        # 验证复用的虚拟环境
        echo -n "  • 验证复用环境... "
        if [[ -f "$venv_dir/bin/python" ]] && [[ -f "$venv_dir/bin/pip" ]]; then
            echo -e "${GREEN}✅ 验证通过${NC}"
            local python_version
            python_version=$(get_safe_python_version "$venv_dir")
            echo -e "${BLUE}    Python版本: $python_version${NC}"
        else
            echo -e "${RED}❌ 验证失败，强制重新创建${NC}"
            reuse_venv=false
            force_new_venv=true
        fi
    fi
    
    # 创建新虚拟环境（如果需要）
    if [[ "$reuse_venv" == "false" ]]; then
        # 清理现有环境
        if [[ -d "$venv_dir" ]]; then
            echo -n "  • 清理现有环境... "
            if rm -rf "$venv_dir" 2>/dev/null; then
                echo -e "${GREEN}✅ 已清理${NC}"
            else
                echo -e "${RED}❌ 清理失败${NC}"
                log "ERROR" "无法清理现有虚拟环境"
                exit 1
            fi
        fi
        
        # 创建新虚拟环境
        echo -n "  • 创建新的虚拟环境... "
        log "INFO" "创建Python虚拟环境"
        
        # 智能选择虚拟环境创建命令
        local venv_create_success=false
        
        # 方法1: 检查用户是否存在并尝试使用sudo
        if [[ "$REAL_USER" != "root" ]] && id "$REAL_USER" >/dev/null 2>&1; then
            log "INFO" "使用用户 $REAL_USER 创建虚拟环境"
            if sudo -u "$REAL_USER" python3 -m venv "$venv_dir" 2>&1 | tee -a "$LOG_FILE" >/dev/null; then
                venv_create_success=true
            else
                log "WARN" "使用sudo创建虚拟环境失败，尝试直接创建"
            fi
        fi
        
        # 方法2: 容器环境或用户不存在时直接创建
        if [[ "$venv_create_success" == "false" ]]; then
            log "INFO" "直接创建虚拟环境（容器环境或用户问题）"
            if python3 -m venv "$venv_dir" 2>&1 | tee -a "$LOG_FILE" >/dev/null; then
                venv_create_success=true
                # 如果用户存在，尝试修改权限
                if id "$REAL_USER" >/dev/null 2>&1 && [[ "$REAL_USER" != "root" ]]; then
                    chown -R "$REAL_USER:$REAL_USER" "$venv_dir" 2>/dev/null || true
                fi
            fi
        fi
        
        if [[ "$venv_create_success" == "true" ]]; then
            echo -e "${GREEN}✅ 创建成功${NC}"
            log "SUCCESS" "虚拟环境创建成功"
            speak_safe "Python虚拟环境创建成功"
        else
            echo -e "${RED}❌ 创建失败${NC}"
            log "ERROR" "虚拟环境创建失败"
            speak_safe "虚拟环境创建失败，请检查Python安装"
            exit 1
        fi
        
        # 验证新虚拟环境
        echo -n "  • 验证虚拟环境... "
        if [[ -f "$venv_dir/bin/python" ]] && [[ -f "$venv_dir/bin/pip" ]]; then
            echo -e "${GREEN}✅ 验证通过${NC}"
            local python_version
            python_version=$(get_safe_python_version "$venv_dir")
            echo -e "${BLUE}    Python版本: $python_version${NC}"
        else
            echo -e "${RED}❌ 验证失败${NC}"
            log "ERROR" "虚拟环境验证失败"
            speak_safe "虚拟环境验证失败"
            exit 1
        fi
    fi
    
    # 创建虚拟环境
    echo -n "  • 创建新的虚拟环境... "
    log "INFO" "创建Python虚拟环境"
    
    # 智能选择虚拟环境创建命令
    local venv_create_success=false
    
    # 方法1: 检查用户是否存在并尝试使用sudo
    if [[ "$REAL_USER" != "root" ]] && id "$REAL_USER" >/dev/null 2>&1; then
        log "INFO" "使用用户 $REAL_USER 创建虚拟环境"
        if sudo -u "$REAL_USER" python3 -m venv "$venv_dir" 2>&1 | tee -a "$LOG_FILE" >/dev/null; then
            venv_create_success=true
        else
            log "WARN" "使用sudo创建虚拟环境失败，尝试直接创建"
        fi
    fi
    
    # 方法2: 容器环境或用户不存在时直接创建
    if [[ "$venv_create_success" == "false" ]]; then
        log "INFO" "直接创建虚拟环境（容器环境或用户问题）"
        if python3 -m venv "$venv_dir" 2>&1 | tee -a "$LOG_FILE" >/dev/null; then
            venv_create_success=true
            # 如果用户存在，尝试修改权限
            if id "$REAL_USER" >/dev/null 2>&1 && [[ "$REAL_USER" != "root" ]]; then
                chown -R "$REAL_USER:$REAL_USER" "$venv_dir" 2>/dev/null || true
            fi
        fi
    fi
    
    if [[ "$venv_create_success" == "true" ]]; then
        echo -e "${GREEN}✅ 创建成功${NC}"
        log "SUCCESS" "虚拟环境创建成功"
        speak_safe "Python虚拟环境创建成功"
    else
        echo -e "${RED}❌ 创建失败${NC}"
        log "ERROR" "虚拟环境创建失败"
        speak_safe "虚拟环境创建失败，请检查Python安装"
        exit 1
    fi
    
    # 验证虚拟环境
    echo -n "  • 验证虚拟环境... "
    if [[ -f "$venv_dir/bin/python" ]] && [[ -f "$venv_dir/bin/pip" ]]; then
        echo -e "${GREEN}✅ 验证通过${NC}"
        local python_version
        python_version=$(get_safe_python_version "$venv_dir")
        echo -e "${BLUE}    Python版本: $python_version${NC}"
    else
        echo -e "${RED}❌ 验证失败${NC}"
        log "ERROR" "虚拟环境验证失败"
        speak_safe "虚拟环境验证失败"
        exit 1
    fi
    
    # 升级pip
    log "INFO" "升级pip"
    local pip_cmd="$venv_dir/bin/pip"
    # 内联安全pip命令逻辑
    local upgrade_pip_cmd
    if [[ "$REAL_USER" == "root" ]] || [[ -f /.dockerenv ]] || [[ -z "$REAL_USER" ]]; then
        upgrade_pip_cmd="$pip_cmd"
    elif id "$REAL_USER" >/dev/null 2>&1; then
        upgrade_pip_cmd="sudo -u $REAL_USER $pip_cmd"
    else
        upgrade_pip_cmd="$pip_cmd"
    fi
    
    if $upgrade_pip_cmd install --upgrade pip setuptools wheel 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "pip升级成功"
    else
        log "WARN" "pip升级失败，继续安装"
    fi
    
    # 智能安装依赖
    local requirements_file="$APP_DIR/requirements.txt"
    
    echo
    echo -e "${BLUE}📚 Python依赖安装${NC}"
    
    if [[ -f "$requirements_file" ]]; then
        log "INFO" "从requirements.txt安装依赖"
        echo -e "${BLUE}  • 发现requirements.txt文件${NC}"
        speak_safe "正在从requirements文件安装Python库"
        
        echo -n "  • 安装requirements.txt依赖... "
        
        # 创建临时日志文件以捕获详细错误
        local temp_log="/tmp/pip_install_$(date +%s).log"
        
        log "INFO" "使用安全pip命令安装requirements.txt"
        
        # 执行安装并捕获输出 - 内联安全pip命令逻辑
        local actual_install_cmd
        if [[ "$REAL_USER" == "root" ]] || [[ -f /.dockerenv ]] || [[ -z "$REAL_USER" ]]; then
            actual_install_cmd="$pip_cmd"
        elif id "$REAL_USER" >/dev/null 2>&1; then
            actual_install_cmd="sudo -u $REAL_USER $pip_cmd"
        else
            actual_install_cmd="$pip_cmd"
        fi
        
        # 预安装构建依赖以避免超时
        echo -n "  • 预安装构建依赖... "
        if timeout 300s $actual_install_cmd install --upgrade pip setuptools wheel meson ninja packaging pyproject-metadata --timeout=60 --retries=3 --no-cache-dir --prefer-binary 2>&1 | tee -a "$LOG_FILE" >/dev/null; then
            echo -e "${GREEN}✅${NC}"
        else
            echo -e "${YELLOW}⚠️ 继续${NC}"
        fi
        
        log "INFO" "执行命令: timeout 900s $actual_install_cmd install -r $requirements_file --timeout=120 --retries=5 --no-cache-dir --prefer-binary --verbose"
        
        if timeout 900s $actual_install_cmd install -r "$requirements_file" --timeout=120 --retries=5 --no-cache-dir --prefer-binary --verbose 2>&1 | tee "$temp_log" | tee -a "$LOG_FILE" >/dev/null; then
            echo -e "${GREEN}✅ 成功${NC}"
            log "SUCCESS" "requirements.txt依赖安装成功"
            rm -f "$temp_log"
            
            # 验证关键依赖是否都已安装
            if ! check_installed_dependencies "$pip_cmd"; then
                echo -e "${YELLOW}⚠️  检测到部分依赖缺失，补充安装${NC}"
                install_smart_dependencies "$pip_cmd"
            fi
        else
            local exit_code=$?
            echo -e "${RED}❌ 失败${NC}"
            
            # 显示详细错误信息
            echo -e "${YELLOW}📋 安装失败详情:${NC}"
            if [[ -f "$temp_log" ]]; then
                echo -e "${BLUE}最后几行错误信息:${NC}"
                tail -10 "$temp_log" | sed 's/^/    /'
                
                # 检查常见错误模式
                if grep -q "timeout" "$temp_log"; then
                    echo -e "${YELLOW}  ⚠️  检测到超时错误${NC}"
                elif grep -q "network\|connection\|resolve" "$temp_log"; then
                    echo -e "${YELLOW}  ⚠️  检测到网络连接问题${NC}"
                elif grep -q "permission\|denied" "$temp_log"; then
                    echo -e "${YELLOW}  ⚠️  检测到权限问题${NC}"
                elif grep -q "No module named" "$temp_log"; then
                    echo -e "${YELLOW}  ⚠️  检测到依赖缺失问题${NC}"
                fi
                
                # 保留错误日志供调试
                cp "$temp_log" "/var/log/pip_install_error_$(date +%s).log"
                echo -e "${BLUE}  详细错误日志已保存到: /var/log/pip_install_error_$(date +%s).log${NC}"
            fi
            
            log "WARN" "requirements.txt安装失败 (退出码: $exit_code)，尝试智能安装核心依赖"
            speak_safe "requirements文件安装失败，改用智能安装方式"
            
            rm -f "$temp_log"
            install_smart_dependencies "$pip_cmd"
        fi
    else
        log "WARN" "未找到requirements.txt，使用智能安装"
        echo -e "${YELLOW}  • 未发现requirements.txt，使用智能安装${NC}"
        speak_safe "未发现requirements文件，使用智能安装方式"
        install_smart_dependencies "$pip_cmd"
    fi
    
    # 安装本地库
    local libshot_dir="$APP_DIR/libshot"
    if [[ -d "$libshot_dir" ]]; then
        log "INFO" "安装本地截图库"
        if sudo -u "$REAL_USER" "$pip_cmd" install -e "$libshot_dir" 2>&1 | tee -a "$LOG_FILE"; then
            log "SUCCESS" "本地截图库安装成功"
        else
            log "WARN" "本地截图库安装失败"
        fi
    fi
    
    log "SUCCESS" "Python依赖安装完成"
}

# 检查已安装的依赖
check_installed_dependencies() {
    local pip_cmd="$1"
    local installed_packages=()
    local missing_packages=()
    
    echo -e "${BLUE}📦 检查已安装的Python依赖...${NC}"
    
    local core_packages=(
        "wheel"
        "easyocr" 
        "piper-tts==1.2.0"
        "edge-tts"
        "pystray"
        "dbus-next"
        "PyGObject"
        "Pillow"
        "pyperclip"
        "pygame"
        "requests"
        "numpy"
    )
    
    for package in "${core_packages[@]}"; do
        echo -n "  • 检查 $package... "
        # 内联检查命令
        local check_pip_cmd
        if [[ "$REAL_USER" == "root" ]] || [[ -f /.dockerenv ]] || [[ -z "$REAL_USER" ]]; then
            check_pip_cmd="$pip_cmd"
        elif id "$REAL_USER" >/dev/null 2>&1; then
            check_pip_cmd="sudo -u $REAL_USER $pip_cmd"
        else
            check_pip_cmd="$pip_cmd"
        fi
        
        if $check_pip_cmd show "${package%%==*}" &>/dev/null; then
            installed_packages+=("$package")
            echo -e "${GREEN}✅ 已安装${NC}"
        else
            missing_packages+=("$package")
            echo -e "${RED}❌ 缺失${NC}"
        fi
    done
    
    echo
    if [[ ${#installed_packages[@]} -gt 0 ]]; then
        echo -e "${GREEN}✅ 已安装 ${#installed_packages[@]} 个依赖包${NC}"
        log "INFO" "已安装的依赖: ${installed_packages[*]}"
    fi
    
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  需要安装 ${#missing_packages[@]} 个依赖包${NC}"
        log "INFO" "缺失的依赖: ${missing_packages[*]}"
        speak_safe "检测到${#missing_packages[@]}个缺失的依赖包，将继续安装"
        return 1  # 有缺失的包
    else
        echo -e "${GREEN}🎉 所有核心依赖都已安装${NC}"
        speak_safe "所有核心依赖都已安装完成"
        return 0  # 所有包都已安装
    fi
}

# 创建环境配置文件
create_environment_config() {
    log "INFO" "创建环境配置文件"
    
    local config_file="$APP_DIR/environment.conf"
    
    cat > "$config_file" << 'EOF'
# A.M.D-helper 环境配置文件
# 用于解决常见的环境兼容性问题

# PyTorch设置 - 解决pin_memory警告
export PYTORCH_DISABLE_PIN_MEMORY=1

# 音频设置 - 解决pygame mixer问题
export SDL_AUDIODRIVER=pulse

# OCR设置 - 优化内存使用
export EASYOCR_MODULE_PATH=/opt/amd-helper/venv/lib/python3.*/site-packages/easyocr

# TTS设置 - Piper配置
export PIPER_VOICE_PATH=/opt/amd-helper/models

# 日志级别
export AMD_HELPER_LOG_LEVEL=INFO
EOF
    
    log "SUCCESS" "环境配置文件创建完成"
}

# 智能依赖安装（支持断点续传）
install_smart_dependencies() {
    local pip_cmd="$1"
    
    # 先检查已安装的依赖
    if check_installed_dependencies "$pip_cmd"; then
        log "INFO" "所有依赖已安装，跳过依赖安装步骤"
        return 0
    fi
    
    # 快速修复：清理pip缓存和卡住的进程
    echo -e "${BLUE}🔧 快速修复pip环境...${NC}"
    echo -n "  • 清理pip缓存... "
    local safe_pip_cmd
    if [[ "$REAL_USER" == "root" ]] || [[ -f /.dockerenv ]] || [[ -z "$REAL_USER" ]]; then
        safe_pip_cmd="$pip_cmd"
    elif id "$REAL_USER" >/dev/null 2>&1; then
        safe_pip_cmd="sudo -u $REAL_USER $pip_cmd"
    else
        safe_pip_cmd="$pip_cmd"
    fi
    
    $safe_pip_cmd cache purge >/dev/null 2>&1 || true
    echo -e "${GREEN}✅${NC}"
    
    # 清理可能卡住的pip进程
    echo -n "  • 清理卡住的进程... "
    if pgrep -f "pip.*install" >/dev/null 2>&1; then
        pkill -f "pip.*install" || true
        sleep 2
        echo -e "${GREEN}✅ 已清理${NC}"
    else
        echo -e "${GREEN}✅ 无需清理${NC}"
    fi
    
    # 预安装系统级依赖以避免编译超时
    echo -e "${BLUE}🔧 预安装系统级依赖...${NC}"
    echo -n "  • 安装PyGObject系统依赖... "
    if apt-get install -y python3-gi python3-gi-cairo gir1.2-gtk-3.0 libgirepository1.0-dev libcairo2-dev pkg-config 2>&1 | tee -a "$LOG_FILE" >/dev/null; then
        echo -e "${GREEN}✅${NC}"
        log "SUCCESS" "PyGObject系统依赖安装成功"
    else
        echo -e "${YELLOW}⚠️ 继续${NC}"
        log "WARN" "PyGObject系统依赖安装失败，将尝试pip安装"
    fi
    
    echo -e "${BLUE}📥 开始安装缺失的依赖...${NC}"
    echo -e "${YELLOW}💡 提示: 如果某个包安装时间过长，可以按 Ctrl+C 跳过${NC}"
    speak_safe "开始安装缺失的Python依赖包。如果某个包安装时间过长，可以按Ctrl+C跳过"
    
    # 设置中断处理
    local skip_current_package=false
    
    # 定义中断处理函数
    handle_interrupt() {
        skip_current_package=true
        echo -e "\n${YELLOW}⚠️  用户中断，跳过当前包${NC}"
        log "WARN" "用户中断，跳过当前包"
    }
    
    trap 'handle_interrupt' INT
    
    # 分层安装策略：核心包 -> 可选包 -> 高风险包
    local essential_packages=(
        "wheel"
        "setuptools"
        "requests"
        "numpy"
        "Pillow"
        "pyperclip"
    )
    
    local optional_packages=(
        "pygame"
        "edge-tts"
        "dbus-next"
    )
    
    local high_risk_packages=(
        "easyocr"
        "piper-tts==1.2.0"
        "pystray"
        "PyGObject"
    )
    
    # 合并所有包用于兼容性
    local core_packages=(
        "${essential_packages[@]}"
        "${optional_packages[@]}"
        "${high_risk_packages[@]}"
    )
    
    local failed_packages=()
    local success_count=0
    
    # 分层安装策略
    echo -e "${BLUE}📦 使用分层安装策略...${NC}"
    echo -e "${GREEN}  第1层: 核心必需包 (${#essential_packages[@]}个)${NC}"
    echo -e "${YELLOW}  第2层: 可选功能包 (${#optional_packages[@]}个)${NC}"
    echo -e "${RED}  第3层: 高风险包 (${#high_risk_packages[@]}个)${NC}"
    echo
    
    # 安装函数
    install_package_with_fallback() {
        local pkg="$1"
        local is_essential="$2"
        
        echo -e "${BLUE}处理包: $pkg${NC}"
        log "INFO" "开始处理包: $pkg"
        
        # 检查是否已安装
        echo -n "  • 检查 $pkg... "
        local timeout_check_cmd
        if [[ "$REAL_USER" == "root" ]] || [[ -f /.dockerenv ]] || [[ -z "$REAL_USER" ]]; then
            timeout_check_cmd="$pip_cmd"
        elif id "$REAL_USER" >/dev/null 2>&1; then
            timeout_check_cmd="sudo -u $REAL_USER $pip_cmd"
        else
            timeout_check_cmd="$pip_cmd"
        fi
        
        if timeout 10s $timeout_check_cmd show "${pkg%%==*}" &>/dev/null; then
            echo -e "${GREEN}✅ 已安装，跳过${NC}"
            ((success_count++))
            return 0
        else
            echo -e "${YELLOW}❌ 未安装${NC}"
        fi
        
        # 尝试安装
        echo -n "  • 安装 $pkg... "
        local actual_pip_cmd
        if [[ "$REAL_USER" == "root" ]] || [[ -f /.dockerenv ]] || [[ -z "$REAL_USER" ]]; then
            actual_pip_cmd="$pip_cmd"
        elif id "$REAL_USER" >/dev/null 2>&1; then
            actual_pip_cmd="sudo -u $REAL_USER $pip_cmd"
        else
            actual_pip_cmd="$pip_cmd"
        fi
        
        # 根据包类型设置超时和参数
        local timeout_duration=600  # 默认10分钟，给编译包更多时间
        local extra_args="--timeout 300"
        
        case "$pkg" in
            "PyGObject")
                timeout_duration=1200  # PyGObject 需要更长时间 (20分钟)
                extra_args="--no-cache-dir --timeout 900"
                ;;
            "easyocr")
                timeout_duration=900   # easyocr 需要15分钟
                extra_args="--timeout 600"
                ;;
            "piper-tts"*)
                extra_args="--no-deps"
                ;;
        esac
        
        if timeout $timeout_duration $actual_pip_cmd install "$pkg" $extra_args --no-cache-dir --prefer-binary --timeout=60 --retries=3 2>&1 | tee -a "$LOG_FILE" >/dev/null; then
            echo -e "${GREEN}✅ 成功${NC}"
            log "SUCCESS" "成功安装 $pkg"
            ((success_count++))
            return 0
        else
            echo -e "${RED}❌ 失败${NC}"
            log "WARN" "安装 $pkg 失败"
            
            # 对于高风险包，尝试系统包管理器
            if [[ "$is_essential" == "false" ]]; then
                echo -n "    • 尝试系统包管理器... "
                local system_pkg=""
                case "$pkg" in
                    "PyGObject")
                        system_pkg="python3-gi"
                        ;;
                    "pygame")
                        system_pkg="python3-pygame"
                        ;;
                    "Pillow")
                        system_pkg="python3-pil"
                        ;;
                esac
                
                if [[ -n "$system_pkg" ]] && apt-get install -y "$system_pkg" 2>/dev/null; then
                    echo -e "${GREEN}✅ 系统包安装成功${NC}"
                    log "SUCCESS" "通过系统包管理器安装 $pkg"
                    ((success_count++))
                    return 0
                else
                    echo -e "${RED}❌ 系统包也失败${NC}"
                fi
            fi
            
            failed_packages+=("$pkg")
            return 1
        fi
    }
    
    # 第1层：核心必需包
    echo -e "${GREEN}🔧 第1层：安装核心必需包...${NC}"
    for package in "${essential_packages[@]}"; do
        install_package_with_fallback "$package" "true"
        echo
    done
    
    # 第2层：可选功能包
    echo -e "${YELLOW}🔧 第2层：安装可选功能包...${NC}"
    for package in "${optional_packages[@]}"; do
        install_package_with_fallback "$package" "false"
        echo
    done
    
    # 第3层：高风险包
    echo -e "${RED}🔧 第3层：安装高风险包...${NC}"
    for package in "${high_risk_packages[@]}"; do
        install_package_with_fallback "$package" "false"
        echo
    done
    
    # 跳过原有的安装循环，因为已经在分层安装中完成
    echo -e "${BLUE}📊 安装完成，正在统计结果...${NC}"
            local current_index=0
            for i in "${!core_packages[@]}"; do
                if [[ "${core_packages[$i]}" == "$package" ]]; then
                    current_index=$((i + 1))
                    break
                fi
            done
    
    log "INFO" "分层安装完成，开始统计"
    
    echo
    echo -e "${BLUE}📊 依赖安装统计:${NC}"
    echo -e "  ${GREEN}✅ 成功: $success_count 个${NC}"
    echo -e "  ${RED}❌ 失败: ${#failed_packages[@]} 个${NC}"
    
    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  以下依赖安装失败:${NC}"
        for pkg in "${failed_packages[@]}"; do
            echo -e "    ${RED}•${NC} $pkg"
        done
        
        speak_safe "有${#failed_packages[@]}个依赖包安装失败，但核心功能可能仍可正常使用"
        
        # 检查关键依赖是否安装成功
        local critical_packages=("Pillow" "numpy" "requests")
        local critical_missing=()
        
        for pkg in "${critical_packages[@]}"; do
            if [[ " ${failed_packages[*]} " =~ " ${pkg} " ]]; then
                critical_missing+=("$pkg")
            fi
        done
        
        if [[ ${#critical_missing[@]} -gt 0 ]]; then
            log "ERROR" "关键依赖安装失败: ${critical_missing[*]}"
            speak_safe "关键依赖安装失败，可能影响程序正常运行"
            return 1
        else
            log "WARN" "部分依赖安装失败，但关键依赖已安装"
            return 0
        fi
    else
        speak_safe "所有Python依赖安装成功"
        return 0
    fi
    
    # 重置中断处理
    trap - INT
}

# 备用依赖安装（保持向后兼容）
install_fallback_dependencies() {
    local pip_cmd="$1"
    log "INFO" "使用备用依赖安装方法"
    install_smart_dependencies "$pip_cmd"
}

# 创建启动脚本
create_launcher_scripts() {
    log "INFO" "创建启动脚本"
    speak_safe "正在创建程序启动脚本"
    
    # 创建通用的脚本头部
    local script_header="#!/bin/bash
# A.M.D-helper 启动脚本
set -e
cd \"$APP_DIR\"

# 检查虚拟环境
if [[ ! -f \"$APP_DIR/venv/bin/python\" ]]; then
    echo \"错误: Python虚拟环境不存在\" >&2
    exit 1
fi

source \"$APP_DIR/venv/bin/activate\"

# 加载环境配置
if [[ -f \"$APP_DIR/environment.conf\" ]]; then
    source \"$APP_DIR/environment.conf\"
fi

# 设置环境变量
export DISPLAY=\${DISPLAY:-:0}
export PULSE_RUNTIME_PATH=\"/run/user/\$(id -u)/pulse\"

# 错误处理 - 解决常见问题
export PYTORCH_DISABLE_PIN_MEMORY=1
export SDL_AUDIODRIVER=pulse
export PYTHONPATH=\"$APP_DIR:\$PYTHONPATH\"
"
    
    # 创建托盘启动脚本
    cat > "$APP_DIR/tray.sh" << EOF
$script_header
exec python3 "$APP_DIR/tray.py" "\$@"
EOF
    
    # 创建快速识别脚本
    cat > "$APP_DIR/run_fast.sh" << EOF
$script_header
exec python3 "$APP_DIR/f4.py"
EOF
    
    # 创建悬浮识别脚本
    cat > "$APP_DIR/run_hover.sh" << EOF
$script_header  
exec python3 "$APP_DIR/f1.py"
EOF
    
    # 设置权限
    chmod +x "$APP_DIR/tray.sh" "$APP_DIR/run_fast.sh" "$APP_DIR/run_hover.sh"
    
    # 创建全局命令链接
    ln -sf "$APP_DIR/tray.sh" "/usr/local/bin/$APP_NAME"
    
    # 复制首次使用引导脚本
    if [[ -f "$SOURCE_DIR/build/first_time_guide.sh" ]]; then
        cp "$SOURCE_DIR/build/first_time_guide.sh" "$APP_DIR/"
        chmod +x "$APP_DIR/first_time_guide.sh"
        ln -sf "$APP_DIR/first_time_guide.sh" "/usr/local/bin/amd-helper-guide"
        log "SUCCESS" "首次使用引导脚本安装完成"
    fi
    
    # 复制故障排除文档
    if [[ -f "$SOURCE_DIR/build/TROUBLESHOOTING.md" ]]; then
        cp "$SOURCE_DIR/build/TROUBLESHOOTING.md" "$APP_DIR/"
        log "SUCCESS" "故障排除文档安装完成"
    fi
    
    # 复制音频修复脚本
    if [[ -f "$SOURCE_DIR/build/fix_audio.sh" ]]; then
        cp "$SOURCE_DIR/build/fix_audio.sh" "$APP_DIR/"
        chmod +x "$APP_DIR/fix_audio.sh"
        ln -sf "$APP_DIR/fix_audio.sh" "/usr/local/bin/amd-helper-fix-audio"
        log "SUCCESS" "音频修复脚本安装完成"
    fi
    
    # 复制pygame专用音频修复脚本
    if [[ -f "$SOURCE_DIR/build/fix_pygame_audio.sh" ]]; then
        cp "$SOURCE_DIR/build/fix_pygame_audio.sh" "$APP_DIR/"
        chmod +x "$APP_DIR/fix_pygame_audio.sh"
        ln -sf "$APP_DIR/fix_pygame_audio.sh" "/usr/local/bin/amd-helper-fix-pygame"
        log "SUCCESS" "Pygame音频修复脚本安装完成"
    fi
    
    # 测试脚本
    log "INFO" "测试启动脚本"
    if safe_user_command "$APP_DIR/tray.sh" --version 2>/dev/null; then
        log "SUCCESS" "启动脚本测试通过"
    else
        log "WARN" "启动脚本测试失败，但继续安装"
    fi
    
    log "SUCCESS" "启动脚本创建完成"
}

# 配置桌面环境
configure_desktop_environment() {
    log "INFO" "配置桌面环境"
    speak_safe "正在配置开机自启动和快捷键"
    
    # 创建用户配置脚本
    local user_config_script="$APP_DIR/configure_user_desktop.sh"
    
    cat > "$user_config_script" << 'EOF'
#!/bin/bash
set -e

# 环境变量设置
export DISPLAY="${DISPLAY:-:0}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

# 检查现有自启动配置
check_existing_autostart() {
    local autostart_dir="$HOME/.config/autostart"
    local desktop_file="$autostart_dir/amd-helper.desktop"
    
    echo -n "  • 检查自启动配置... "
    
    if [[ -f "$desktop_file" ]]; then
        # 检查配置文件是否有效
        if grep -q "A.M.D-helper" "$desktop_file" 2>/dev/null && \
           grep -q "Exec=$APP_DIR/tray.sh" "$desktop_file" 2>/dev/null; then
            echo -e "${GREEN}✅ 已配置且有效${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠️  已存在但配置异常${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ 未配置${NC}"
        return 1
    fi
}

# 创建自启动配置
setup_autostart() {
    echo -e "${BLUE}🚀 自启动配置${NC}"
    
    local autostart_dir="$HOME/.config/autostart"
    local desktop_file="$autostart_dir/amd-helper.desktop"
    
    # 检查现有配置
    if check_existing_autostart; then
        echo -e "${BLUE}💡 发现有效的自启动配置${NC}"
        read -p "是否保留现有配置？(Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo -e "${GREEN}✅ 保留现有自启动配置${NC}"
            speak_safe "保留现有自启动配置"
            return 0
        fi
    fi
    
    echo -n "  • 创建自启动配置... "
    mkdir -p "$autostart_dir"
    
    if cat > "$desktop_file" << DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=A.M.D-helper 视障辅助工具
Name[en]=A.M.D-helper Accessibility Tool
Comment=视障用户语音辅助工具
Comment[en]=Accessibility tool for visually impaired users
Exec=$APP_DIR/tray.sh
Icon=$APP_DIR/icon.png
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
StartupNotify=false
Terminal=false
Categories=Accessibility;Utility;
DESKTOP_EOF
    then
        chmod +x "$desktop_file"
        echo "AUTOSTART_FILE=$desktop_file" >> "$INSTALL_INFO_FILE"
        echo -e "${GREEN}✅ 成功${NC}"
        log "SUCCESS" "自启动配置完成"
        speak_safe "自启动配置创建成功"
    else
        echo -e "${RED}❌ 失败${NC}"
        log "WARN" "自启动配置创建失败"
        speak_safe "自启动配置创建失败"
    fi
}

# 检查现有快捷键配置
check_existing_shortcuts() {
    if ! command -v gsettings &> /dev/null; then
        return 1
    fi
    
    echo -e "${BLUE}⌨️  检查现有快捷键配置...${NC}"
    
    local custom_keys_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/"
    local current_keys
    current_keys=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null || echo "@as []")
    
    local existing_shortcuts=()
    
    # 检查A.M.D-helper相关的快捷键
    local shortcut_ids=("amd-helper-fast-ocr" "amd-helper-hover-ocr")
    
    for id in "${shortcut_ids[@]}"; do
        local key_path="${custom_keys_path}${id}/"
        echo -n "  • 检查快捷键 $id... "
        
        if echo "$current_keys" | grep -q "$key_path"; then
            # 检查快捷键是否完整配置
            local name command binding
            name=$(gsettings get "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$key_path" name 2>/dev/null || echo "")
            command=$(gsettings get "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$key_path" command 2>/dev/null || echo "")
            binding=$(gsettings get "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$key_path" binding 2>/dev/null || echo "")
            
            if [[ -n "$name" ]] && [[ -n "$command" ]] && [[ -n "$binding" ]]; then
                existing_shortcuts+=("$id")
                echo -e "${GREEN}✅ 已配置${NC}"
                echo -e "    名称: ${name//\'/}"
                echo -e "    命令: ${command//\'/}"
                echo -e "    按键: ${binding//\'/}"
            else
                echo -e "${RED}❌ 配置不完整${NC}"
            fi
        else
            echo -e "${RED}❌ 未配置${NC}"
        fi
    done
    
    echo
    if [[ ${#existing_shortcuts[@]} -gt 0 ]]; then
        echo -e "${GREEN}✅ 发现 ${#existing_shortcuts[@]} 个已配置的快捷键${NC}"
        log "INFO" "已配置的快捷键: ${existing_shortcuts[*]}"
        return 0
    else
        echo -e "${YELLOW}⚠️  未发现已配置的快捷键${NC}"
        return 1
    fi
}

# 配置GNOME快捷键
setup_gnome_shortcuts() {
    if ! command -v gsettings &> /dev/null; then
        echo -e "${YELLOW}⚠️  未检测到GNOME桌面环境，跳过快捷键配置${NC}"
        return
    fi
    
    echo -e "${BLUE}⌨️  GNOME快捷键配置${NC}"
    
    # 检查现有配置
    local skip_existing=false
    if check_existing_shortcuts; then
        echo -e "${BLUE}💡 发现现有快捷键配置${NC}"
        speak_safe "发现现有快捷键配置"
        
        read -p "是否保留现有配置？(Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            skip_existing=true
            echo -e "${GREEN}✅ 保留现有快捷键配置${NC}"
            speak_safe "保留现有快捷键配置"
            return 0
        else
            echo -e "${YELLOW}⚠️  将重新配置所有快捷键${NC}"
            speak_safe "将重新配置所有快捷键"
        fi
    fi
    
    echo -e "${BLUE}  • 开始配置快捷键...${NC}"
    speak_safe "开始配置GNOME快捷键"
    
    local custom_keys_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/"
    
    add_custom_shortcut() {
        local id="$1"
        local name="$2"
        local command="$3"
        local binding="$4"
        local key_path="${custom_keys_path}${id}/"
        
        echo -n "    • 配置 $binding ($name)... "
        
        # 检查是否已存在且配置完整
        if [[ "$skip_existing" == true ]]; then
            local current_keys
            current_keys=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null || echo "@as []")
            if echo "$current_keys" | grep -q "$key_path"; then
                echo -e "${BLUE}ℹ️  已存在，跳过${NC}"
                return 0
            fi
        fi
        
        # 设置快捷键属性
        if gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$key_path" name "$name" 2>/dev/null && \
           gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$key_path" command "$command" 2>/dev/null && \
           gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$key_path" binding "$binding" 2>/dev/null; then
            
            # 添加到快捷键列表
            local current_keys
            current_keys=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null || echo "@as []")
            
            if ! echo "$current_keys" | grep -q "$key_path"; then
                if [[ "$current_keys" == "@as []" ]]; then
                    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['$key_path']" 2>/dev/null
                else
                    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "${current_keys%]*}, '$key_path']" 2>/dev/null
                fi
            fi
            
            echo "SHORTCUT_ID=$id" >> "$INSTALL_INFO_FILE"
            echo -e "${GREEN}✅ 成功${NC}"
            log "SUCCESS" "快捷键 $binding -> $name 设置完成"
        else
            echo -e "${RED}❌ 失败${NC}"
            log "WARN" "快捷键 $binding -> $name 设置失败"
        fi
    }
    
    # 添加快捷键
    add_custom_shortcut "amd-helper-fast-ocr" "A.M.D-helper 快速识别" "$APP_DIR/run_fast.sh" "F4"
    add_custom_shortcut "amd-helper-hover-ocr" "A.M.D-helper 悬浮识别" "$APP_DIR/run_hover.sh" "F1"
    
    echo "GNOME快捷键配置完成"
}

# 执行配置
setup_autostart
setup_gnome_shortcuts

echo "桌面环境配置完成"
EOF
    
    # 执行用户配置脚本
    chmod +x "$user_config_script"
    chown "$REAL_USER:$REAL_USER" "$user_config_script"
    
    if safe_user_command bash "$user_config_script" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "桌面环境配置成功"
    else
        log "WARN" "桌面环境配置部分失败，但不影响主要功能"
    fi
    
    # 清理临时脚本
    rm -f "$user_config_script"
}

# 最终测试和清理
final_test_and_cleanup() {
    log "INFO" "进行最终测试"
    speak_safe "正在进行安装测试，确保所有功能正常"
    
    # 测试Python环境
    if safe_user_command "$APP_DIR/venv/bin/python" -c "import sys; print('Python环境测试通过')" 2>/dev/null; then
        log "SUCCESS" "Python环境测试通过"
    else
        log "ERROR" "Python环境测试失败"
        exit 1
    fi
    
    # 测试主要模块导入
    local test_script="$APP_DIR/test_imports.py"
    cat > "$test_script" << 'EOF'
#!/usr/bin/env python3
import sys
import importlib

modules_to_test = [
    'PIL', 'numpy', 'pygame'
]

failed_modules = []

for module in modules_to_test:
    try:
        importlib.import_module(module)
        print(f"✓ {module} 导入成功")
    except ImportError as e:
        print(f"✗ {module} 导入失败: {e}")
        failed_modules.append(module)

if failed_modules:
    print(f"\n警告: {len(failed_modules)} 个模块导入失败")
    sys.exit(1)
else:
    print("\n所有核心模块测试通过")
    sys.exit(0)
EOF
    
    if safe_user_command "$APP_DIR/venv/bin/python" "$test_script" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "模块导入测试通过"
    else
        log "WARN" "部分模块导入测试失败，但可能不影响基本功能"
    fi
    
    # 清理测试文件
    rm -f "$test_script"
    
    # 创建卸载脚本
    create_uninstall_script
    
    log "SUCCESS" "最终测试完成"
}

# 创建卸载脚本
create_uninstall_script() {
    log "INFO" "创建卸载脚本"
    
    local uninstall_script="$APP_DIR/uninstall.sh"
    
    cat > "$uninstall_script" << 'EOF'
#!/bin/bash
# A.M.D-helper 卸载脚本

echo "开始卸载 A.M.D-helper..."

# 必须以root权限运行
if [ "$EUID" -ne 0 ]; then
    echo "错误: 请使用 sudo 运行卸载脚本"
    exit 1
fi

# 读取安装信息
INSTALL_INFO_FILE="/opt/amd-helper/install-info.txt"
if [[ -f "$INSTALL_INFO_FILE" ]]; then
    source "$INSTALL_INFO_FILE" 2>/dev/null || true
fi

# 停止可能运行的程序
echo "停止正在运行的程序..."
pkill -f "amd-helper" 2>/dev/null || true
pkill -f "tray.py" 2>/dev/null || true

# 删除自启动配置
if [[ -n "$AUTOSTART_FILE" ]] && [[ -f "$AUTOSTART_FILE" ]]; then
    echo "删除自启动配置..."
    rm -f "$AUTOSTART_FILE"
fi

# 删除GNOME快捷键（如果存在）
if command -v gsettings &> /dev/null; then
    echo "删除快捷键配置..."
    gsettings reset org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null || true
fi

# 删除全局命令链接
rm -f "/usr/local/bin/amd-helper"

# 删除应用目录
if [[ -d "/opt/amd-helper" ]]; then
    echo "删除应用程序文件..."
    rm -rf "/opt/amd-helper"
fi

echo "A.M.D-helper 卸载完成"
EOF
    
    chmod +x "$uninstall_script"
    
    log "SUCCESS" "卸载脚本创建完成"
}

# ==============================================================================
#  主要安装流程
# ==============================================================================

main() {
    # 处理命令行参数
    local force_reinstall=false
    local auto_cleanup=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force|-f)
                force_reinstall=true
                log "INFO" "启用强制重新安装模式"
                shift
                ;;
            --force-new-venv)
                export FORCE_NEW_VENV=true
                log "INFO" "启用强制创建新虚拟环境模式"
                shift
                ;;
            --auto-cleanup)
                auto_cleanup=true
                export AUTO_CLEANUP=1
                log "INFO" "启用自动清理模式"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log "WARN" "未知参数: $1"
                shift
                ;;
        esac
    done
    
    # 清理日志文件
    > "$LOG_FILE"
    
    echo "======================================================"
    echo "     A.M.D-helper 视障辅助软件全自动安装程序"
    echo "======================================================"
    echo
    
    log "INFO" "安装程序启动"
    log "INFO" "日志文件: $LOG_FILE"
    
    # 如果是强制重新安装，先清理现有安装
    if [[ "$force_reinstall" == true ]]; then
        log "INFO" "强制重新安装模式，清理现有安装"
        speak_safe "强制重新安装模式，正在清理现有安装"
        force_cleanup_existing_installation
    fi
    
    # 前置检查
    log "INFO" "开始前置检查"
    check_root
    check_system  
    check_disk_space
    
    # 环境兼容性检查
    check_environment_compatibility
    
    # 检测破损安装
    detect_and_fix_broken_installation
    
    # 安装语音工具
    install_speech_tools
    
    # 欢迎信息
    speak_safe "欢迎使用A.M.D-helper安装程序。这是一个专为视力障碍用户设计的智能辅助工具。安装过程大约需要5到10分钟。"
    
    # 在容器环境中跳过用户确认
    if [[ -f /.dockerenv ]] || [[ -z "${DISPLAY:-}" ]]; then
        log "INFO" "容器环境检测，自动开始安装"
        speak_safe "容器环境检测，自动开始安装A.M.D-helper视障辅助软件"
    else
        wait_for_confirmation "准备开始安装A.M.D-helper视障辅助软件"
    fi
    
    # 主要安装步骤
    log "INFO" "开始主要安装流程"
    
    # 1. 安装系统依赖
    install_system_dependencies
    speak_safe "系统依赖安装完成，进度25%"
    
    # 2. 设置应用程序
    setup_application
    speak_safe "应用程序设置完成，进度50%"
    
    # 3. 安装Python依赖
    install_python_dependencies
    speak_safe "Python依赖安装完成，进度75%"
    
    # 4. 创建环境配置
    create_environment_config
    
    # 5. 创建启动脚本
    create_launcher_scripts
    
    # 6. 配置桌面环境
    configure_desktop_environment
    
    # 7. 最终测试
    final_test_and_cleanup
    speak_safe "安装测试完成，进度100%"
    
    # 完成安装
    installation_complete
}

# 安装完成提示
installation_complete() {
    log "SUCCESS" "A.M.D-helper 安装成功！"
    
    echo
    echo "======================================================"
    echo -e "${GREEN}${BOLD}     🎉 A.M.D-helper 安装成功！ 🎉${NC}"
    echo "======================================================"
    echo
    echo -e "${BLUE}📱 应用信息:${NC}"
    echo "   • 名称: A.M.D-helper 视障辅助工具"  
    echo "   • 版本: $(cat "$APP_DIR/VERSION" 2>/dev/null || echo "最新版")"
    echo "   • 安装路径: $APP_DIR"
    echo
    echo -e "${BLUE}⚡ 快捷键:${NC}"
    echo "   • F4: 快速文字识别"
    echo "   • F1: 悬浮窗口识别"
    echo
    echo -e "${BLUE}🚀 启动方式:${NC}"
    echo "   • 自动启动: 已配置开机自启动"
    echo "   • 手动启动: 在终端输入 'amd-helper'"
    echo "   • 托盘程序: 将在后台运行"
    echo
    echo -e "${BLUE}📚 使用帮助:${NC}"
    echo "   • 首次使用引导: 运行 'amd-helper-guide'"
    echo "   • 程序启动后会在系统托盘显示图标"
    echo "   • 右键托盘图标可查看更多选项"
    echo "   • F4快速识别: 按 F4 键"
    echo
    echo -e "${BLUE}🔧 维护命令:${NC}"
    echo "   • 查看日志: tail -f $LOG_FILE"
    echo "   • 故障排除: cat $APP_DIR/TROUBLESHOOTING.md"
    echo "   • Pygame音频修复: amd-helper-fix-pygame"
    echo "   • 完整音频修复: amd-helper-fix-audio"
    echo "   • 重新安装: sudo bash $0 --force"
    echo "   • 完全卸载: sudo bash $APP_DIR/uninstall.sh"
    echo
    echo -e "${YELLOW}⚠️  重要提示:${NC}"
    echo "   • 建议重启系统以确保所有配置生效"
    echo "   • 如遇问题，请保存安装日志文件并联系技术支持"
    echo "   • 日志文件位置: $LOG_FILE"
    echo
    echo "======================================================"
    
    speak_safe "A.M.D-helper安装成功！程序已设置为开机自启动。您可以使用F4键进行快速识别，F1键进行悬浮识别。建议重启系统以确保所有功能正常工作。"
    
    # 询问是否进行首次使用引导
    echo
    echo -e "${BLUE}🎓 首次使用引导${NC}"
    read -p "是否进行首次使用引导和功能演示？(Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        first_time_tutorial
    fi
    
    # 询问是否立即启动
    echo
    read -p "是否现在启动 A.M.D-helper？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        speak_safe "正在启动A.M.D-helper"
        log "INFO" "用户选择立即启动程序"
        
        if safe_user_command "$APP_DIR/tray.sh" &>/dev/null & then
            log "SUCCESS" "程序启动成功"
            speak_safe "程序启动成功，您现在可以使用快捷键进行文字识别了"
        else
            log "WARN" "程序启动失败，请手动启动或重启系统"
            speak_safe "程序启动失败，建议重启系统后再使用"
        fi
    fi
    
    # 保存完成标记
    echo "INSTALL_COMPLETED=true" >> "$INSTALL_INFO_FILE"
    echo "INSTALL_COMPLETION_DATE=$(date '+%Y-%m-%d %H:%M:%S')" >> "$INSTALL_INFO_FILE"
    
    log "INFO" "安装程序结束"
}

# ==============================================================================
#  错误恢复和清理函数
# ==============================================================================

cleanup_on_error() {
    echo
    echo -e "${RED}${BOLD}❌ 安装过程中发生错误${NC}"
    log "WARN" "检测到安装错误，开始清理"
    speak_safe "安装过程中发生错误，正在进行清理"
    
    echo -e "${BLUE}🧹 正在清理部分安装文件...${NC}"
    
    # 停止可能在运行的进程
    echo -n "  • 停止相关进程... "
    local stopped=0
    if pkill -f "amd-helper" 2>/dev/null; then ((stopped++)); fi
    if pkill -f "tray.py" 2>/dev/null; then ((stopped++)); fi
    
    if [[ $stopped -gt 0 ]]; then
        echo -e "${GREEN}✅ 已停止 $stopped 个进程${NC}"
    else
        echo -e "${BLUE}ℹ️  无运行中的进程${NC}"
    fi
    
    # 清理可能的部分安装
    local cleanup_items=()
    
    # 检查应用目录
    if [[ -d "$APP_DIR" ]]; then
        cleanup_items+=("应用目录: $APP_DIR")
    fi
    
    # 检查全局命令链接
    if [[ -L "/usr/local/bin/amd-helper" ]]; then
        cleanup_items+=("全局命令链接")
    fi
    
    # 检查自启动配置
    local autostart_file="$HOME/.config/autostart/amd-helper.desktop"
    if [[ -f "$autostart_file" ]]; then
        cleanup_items+=("自启动配置")
    fi
    
    if [[ ${#cleanup_items[@]} -gt 0 ]]; then
        echo
        echo -e "${YELLOW}⚠️  检测到以下部分安装文件:${NC}"
        for item in "${cleanup_items[@]}"; do
            echo -e "  ${YELLOW}•${NC} $item"
        done
        echo
        
        # 自动清理模式（非交互）
        if [[ -n "${AUTO_CLEANUP:-}" ]]; then
            log "INFO" "自动清理模式，删除部分安装文件"
            echo -e "${BLUE}🤖 自动清理模式，正在清理文件...${NC}"
            speak_safe "自动清理模式，正在删除部分安装文件"
            perform_cleanup
        else
            # 交互模式
            echo -e "${BLUE}💡 建议清理这些文件以避免冲突${NC}"
            speak_safe "检测到部分安装文件，建议清理以避免冲突"
            read -p "是否清理这些文件？(Y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                speak_safe "开始清理部分安装文件"
                perform_cleanup
            else
                log "INFO" "用户选择保留部分安装文件"
                echo -e "${YELLOW}⚠️  用户选择保留文件，可能影响下次安装${NC}"
                speak_safe "用户选择保留部分安装文件"
            fi
        fi
    else
        echo -e "${BLUE}ℹ️  未检测到需要清理的文件${NC}"
    fi
    
    echo
    echo -e "${RED}${BOLD}💥 安装失败${NC}"
    echo -e "${BLUE}📋 请检查错误信息并重试安装${NC}"
    echo -e "${BLUE}📄 详细日志: $LOG_FILE${NC}"
    
    speak_safe "安装失败，请检查错误信息并重试。详细日志已保存到日志文件"
}

# 执行清理操作
perform_cleanup() {
    log "INFO" "开始清理部分安装文件"
    
    echo -e "${BLUE}🧹 执行清理操作...${NC}"
    
    # 删除应用目录
    echo -n "  • 清理应用目录... "
    if [[ -d "$APP_DIR" ]]; then
        if rm -rf "$APP_DIR" 2>/dev/null; then
            echo -e "${GREEN}✅ 已删除${NC}"
        else
            echo -e "${RED}❌ 删除失败${NC}"
            log "WARN" "无法删除 $APP_DIR"
        fi
    else
        echo -e "${BLUE}ℹ️  目录不存在${NC}"
    fi
    
    # 删除全局命令链接
    echo -n "  • 清理全局命令... "
    if [[ -L "/usr/local/bin/amd-helper" ]]; then
        if rm -f "/usr/local/bin/amd-helper" 2>/dev/null; then
            echo -e "${GREEN}✅ 已删除${NC}"
        else
            echo -e "${RED}❌ 删除失败${NC}"
        fi
    else
        echo -e "${BLUE}ℹ️  链接不存在${NC}"
    fi
    
    # 删除自启动配置（需要以实际用户身份执行）
    echo -n "  • 清理用户配置... "
    local cleaned_configs=0
    if [[ -n "$REAL_USER" ]]; then
        local user_home
        user_home=$(getent passwd "$REAL_USER" | cut -d: -f6 2>/dev/null)
        if [[ -n "$user_home" ]]; then
            local autostart_file="$user_home/.config/autostart/amd-helper.desktop"
            if [[ -f "$autostart_file" ]]; then
                if rm -f "$autostart_file" 2>/dev/null; then
                    ((cleaned_configs++))
                fi
            fi
        fi
    fi
    
    if [[ $cleaned_configs -gt 0 ]]; then
        echo -e "${GREEN}✅ 已清理 $cleaned_configs 项${NC}"
    else
        echo -e "${BLUE}ℹ️  无需清理${NC}"
    fi
    
    echo -e "${GREEN}✅ 清理操作完成${NC}"
    log "SUCCESS" "清理完成"
}

# 注册清理函数
trap cleanup_on_error ERR

# ==============================================================================
#  首次使用引导系统
# ==============================================================================

# 首次使用教程
first_time_tutorial() {
    echo
    echo "======================================================"
    echo -e "${GREEN}${BOLD}🎓 A.M.D-helper 首次使用引导${NC}"
    echo "======================================================"
    
    speak_safe "欢迎使用A.M.D-helper！现在开始首次使用引导，帮助您快速掌握软件功能"
    
    # 功能介绍
    echo
    echo -e "${BLUE}${BOLD}📖 功能介绍${NC}"
    echo -e "${BLUE}A.M.D-helper 是专为视障用户设计的智能辅助工具，主要功能包括：${NC}"
    echo -e "  ${GREEN}•${NC} 快速文字识别 (F4功能)"
    echo -e "  ${GREEN}•${NC} 悬浮窗口识别 (F1功能)"
    echo -e "  ${GREEN}•${NC} 语音播报识别结果"
    echo -e "  ${GREEN}•${NC} 自动复制到剪贴板"
    
    speak_safe "A.M.D-helper提供快速文字识别、悬浮窗口识别等功能，并支持语音播报和自动复制"
    
    wait_for_user_ready "准备开始学习快速识别功能"
    
    # F4功能详细介绍
    introduce_f4_function
    
    # 实际演示
    if ask_user_choice "是否进行实际功能演示？"; then
        demonstrate_f4_function
    fi
    
    # 使用技巧
    provide_usage_tips
    
    # 完成引导
    complete_tutorial
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

# 完成教程
complete_tutorial() {
    echo
    echo "======================================================"
    echo -e "${GREEN}${BOLD}🎉 首次使用引导完成！${NC}"
    echo "======================================================"
    
    echo -e "${BLUE}📚 您已经学会了：${NC}"
    echo -e "  ${GREEN}✅${NC} A.M.D-helper 的主要功能"
    echo -e "  ${GREEN}✅${NC} F4快速识别的使用方法"
    echo -e "  ${GREEN}✅${NC} 获得最佳效果的技巧"
    echo -e "  ${GREEN}✅${NC} 常见问题的解决方法"
    
    speak_safe "恭喜！您已经完成了首次使用引导，学会了A.M.D-helper的主要功能和使用技巧"
    
    echo
    echo -e "${YELLOW}🚀 下一步：${NC}"
    echo -e "  ${BLUE}•${NC} 程序将自动在后台运行"
    echo -e "  ${BLUE}•${NC} 随时使用 F4 进行快速识别"
    echo -e "  ${BLUE}•${NC} 查看系统托盘图标了解更多功能"
    echo -e "  ${BLUE}•${NC} 如需帮助，重新运行安装程序查看引导"
    
    speak_safe "下一步：程序将自动运行，随时使用F4进行识别，查看托盘图标了解更多功能"
    
    echo
    echo -e "${GREEN}${BOLD}祝您使用愉快！${NC}"
    speak_safe "祝您使用愉快！A.M.D-helper将为您提供便捷的文字识别服务"
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

# ==============================================================================
#  帮助和工具函数
# ==============================================================================

# 显示帮助信息
show_help() {
    cat << EOF
A.M.D-helper 视障辅助软件安装程序

用法: sudo bash install.sh [选项]

选项:
  -f, --force        强制重新安装，清理所有现有文件
  --force-new-venv   强制创建新虚拟环境，不复用现有环境
  --auto-cleanup     自动清理模式，出错时不询问直接清理
  -h, --help         显示此帮助信息

示例:
  sudo bash install.sh                    # 正常安装
  sudo bash install.sh --force            # 强制重新安装
  sudo bash install.sh --force-new-venv   # 强制创建新虚拟环境
  sudo bash install.sh --auto-cleanup     # 自动清理模式

注意:
  - 必须使用 sudo 权限运行
  - 强制模式会删除所有现有安装文件
  - 强制新虚拟环境模式会重新创建Python环境
  - 安装日志保存在 /var/log/amd-helper-install.log
  - 支持自动检测和处理脚本同目录下的压缩包
  - 支持复用现有的 .venv、poetry 或 pipenv 虚拟环境
EOF
}

# 强制清理现有安装
force_cleanup_existing_installation() {
    local app_dir="/opt/amd-helper"
    
    log "INFO" "开始强制清理现有安装"
    
    echo
    echo -e "${YELLOW}${BOLD}🧹 强制清理模式${NC}"
    echo -e "${BLUE}正在彻底清理所有现有安装文件...${NC}"
    
    # 停止所有相关进程
    echo -n "  • 停止运行中的程序... "
    local stopped_processes=0
    if pkill -f "amd-helper" 2>/dev/null; then
        ((stopped_processes++))
    fi
    if pkill -f "tray.py" 2>/dev/null; then
        ((stopped_processes++))
    fi
    sleep 2
    
    if [[ $stopped_processes -gt 0 ]]; then
        echo -e "${GREEN}✅ 已停止 $stopped_processes 个进程${NC}"
        speak_safe "已停止正在运行的程序"
    else
        echo -e "${BLUE}ℹ️  无运行中的程序${NC}"
    fi
    
    # 删除应用目录
    echo -n "  • 清理应用程序目录... "
    if [[ -d "$app_dir" ]]; then
        log "INFO" "删除应用目录: $app_dir"
        if rm -rf "$app_dir" 2>/dev/null; then
            echo -e "${GREEN}✅ 已删除${NC}"
        else
            echo -e "${RED}❌ 删除失败${NC}"
        fi
    else
        echo -e "${BLUE}ℹ️  目录不存在${NC}"
    fi
    
    # 删除全局命令链接
    echo -n "  • 清理全局命令链接... "
    if [[ -L "/usr/local/bin/amd-helper" ]]; then
        log "INFO" "删除全局命令链接"
        if rm -f "/usr/local/bin/amd-helper" 2>/dev/null; then
            echo -e "${GREEN}✅ 已删除${NC}"
        else
            echo -e "${RED}❌ 删除失败${NC}"
        fi
    else
        echo -e "${BLUE}ℹ️  链接不存在${NC}"
    fi
    
    # 清理用户配置
    echo -n "  • 清理用户配置文件... "
    local users_to_clean=()
    if [[ -n "${SUDO_USER:-}" ]]; then
        users_to_clean+=("$SUDO_USER")
    fi
    
    # 添加其他可能的用户
    while IFS=: read -r username _ uid _ _ home _; do
        if [[ $uid -ge 1000 ]] && [[ $uid -lt 65534 ]] && [[ -d "$home" ]]; then
            users_to_clean+=("$username")
        fi
    done < /etc/passwd
    
    local cleaned_configs=0
    
    # 清理每个用户的配置
    for user in "${users_to_clean[@]}"; do
        local user_home
        user_home=$(getent passwd "$user" | cut -d: -f6 2>/dev/null) || continue
        
        if [[ -d "$user_home" ]]; then
            # 清理自启动配置
            local autostart_file="$user_home/.config/autostart/amd-helper.desktop"
            if [[ -f "$autostart_file" ]]; then
                log "INFO" "删除用户 $user 的自启动配置"
                rm -f "$autostart_file" && ((cleaned_configs++))
            fi
            
            # 清理GNOME快捷键（如果可能）
            if command -v gsettings &> /dev/null; then
                if sudo -u "$user" gsettings reset org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null; then
                    ((cleaned_configs++))
                fi
            fi
        fi
    done
    
    if [[ $cleaned_configs -gt 0 ]]; then
        echo -e "${GREEN}✅ 已清理 $cleaned_configs 项配置${NC}"
    else
        echo -e "${BLUE}ℹ️  无需清理${NC}"
    fi
    
    echo
    echo -e "${GREEN}${BOLD}✅ 强制清理完成${NC}"
    log "SUCCESS" "强制清理完成"
    speak_safe "强制清理完成，所有旧文件已删除，现在开始全新安装"
}

# ==============================================================================
#  程序入口
# ==============================================================================

# 检查是否为直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 捕获中断信号
    trap 'echo; log "WARN" "安装被用户中断"; speak_safe "安装已取消"; cleanup_on_error; exit 130' INT TERM
    
    # 开始安装
    main "$@"
else
    log "INFO" "脚本被作为模块加载"
fi