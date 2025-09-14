#!/bin/bash

# ==============================================================================
# A.M.D-helper 打包脚本
# ==============================================================================

# 获取版本号,可以从参数传入,默认为 0.1.0
VERSION=${1:-0.53}
APP_NAME="amd-helper"
ARCHIVE_NAME="${APP_NAME}-v${VERSION}.tar.gz"

# 获取脚本所在的目录, 以便我们能从项目根目录执行操作
BUILD_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$BUILD_DIR/.."

# 打包的目标文件夹
DEST_DIR="$BUILD_DIR/release"

# 清理旧的打包文件和目录
rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR"

echo "正在从 $PROJECT_ROOT 打包..."

# 检查必要文件是否存在
echo "检查必要文件..."
required_files=(
    "build/install.sh"
    "build/first_time_guide.sh"
    "build/fix_audio.sh"
    "build/fix_pygame_audio.sh"
    "build/TROUBLESHOOTING.md"
    "build/FIX_NOTES.md"
    "build/GUIDE_README.md"
    "build/AUDIO_FIX_README.md"
)

missing_files=()
for file in "${required_files[@]}"; do
    if [[ ! -f "$PROJECT_ROOT/$file" ]]; then
        missing_files+=("$file")
    fi
done

if [[ ${#missing_files[@]} -gt 0 ]]; then
    echo "警告: 以下文件缺失:"
    for file in "${missing_files[@]}"; do
        echo "  - $file"
    done
fi

# 使用 tar 命令创建压缩包
# --exclude 用于排除不需要的文件和目录
tar -czvf "$DEST_DIR/$ARCHIVE_NAME" \
    --directory="$PROJECT_ROOT" \
    --exclude=".git" \
    --exclude=".idea" \
    --exclude="build/release" \
    --exclude="*__pycache__*" \
    --exclude="*.pyc" \
    --exclude="*venv*" \
    --exclude="libshot/libshot.egg-info" \
    --exclude="对话进度.md" \
    --exclude="坑.md" \
    --exclude="build/error.png" \
    . # 代表当前目录 (相对于 --directory )

echo "打包完成！"
echo "发布包已生成在: $DEST_DIR/$ARCHIVE_NAME"

# 验证打包内容
echo
echo "验证打包内容..."
echo "压缩包大小: $(du -h "$DEST_DIR/$ARCHIVE_NAME" | cut -f1)"

# 检查关键文件是否包含在压缩包中
echo "检查关键文件..."
key_files=(
    "build/install.sh"
    "build/first_time_guide.sh" 
    "build/fix_audio.sh"
    "build/fix_pygame_audio.sh"
    "build/TROUBLESHOOTING.md"
    "f4.py"
    "f1.py"
    "tray.py"
    "core.py"
    "requirements.txt"
)

missing_in_archive=()
for file in "${key_files[@]}"; do
    if ! tar -tzf "$DEST_DIR/$ARCHIVE_NAME" | grep -q "^\./$file$"; then
        missing_in_archive+=("$file")
    fi
done

if [[ ${#missing_in_archive[@]} -eq 0 ]]; then
    echo "✅ 所有关键文件都已包含在压缩包中"
else
    echo "⚠️  以下关键文件未包含在压缩包中:"
    for file in "${missing_in_archive[@]}"; do
        echo "  - $file"
    done
fi

echo
echo "📦 打包信息:"
echo "  版本: v$VERSION"
echo "  文件: $ARCHIVE_NAME"
echo "  路径: $DEST_DIR/$ARCHIVE_NAME"
echo "  大小: $(du -h "$DEST_DIR/$ARCHIVE_NAME" | cut -f1)"

# 创建发布说明
cat > "$DEST_DIR/RELEASE_NOTES.md" << EOF
# A.M.D-helper v$VERSION 发布说明

## 📦 安装方法

\`\`\`bash
# 1. 解压文件
tar -xzf $ARCHIVE_NAME
cd amd-helper-v$VERSION

# 2. 运行安装脚本
sudo bash build/install.sh
\`\`\`

## 🆕 新功能

### 智能安装和修复系统
- ✅ 破损安装检测和修复
- ✅ 智能依赖管理（断点续传）
- ✅ 环境兼容性检查
- ✅ 完善的错误处理

### 首次使用引导
- ✅ 语音+图形双重引导
- ✅ F4功能专项教学
- ✅ 实际演示和测试
- ✅ 使用技巧传授

### 音频问题修复
- ✅ Pygame音频专用修复
- ✅ 完整音频系统修复
- ✅ 自动驱动检测和配置
- ✅ 详细的故障排除指南

## 🔧 维护工具

- \`amd-helper-guide\`: 首次使用引导
- \`amd-helper-fix-pygame\`: Pygame音频修复
- \`amd-helper-fix-audio\`: 完整音频修复

## 📚 文档

- \`build/FIX_NOTES.md\`: 修复说明和新功能介绍
- \`build/TROUBLESHOOTING.md\`: 详细故障排除指南
- \`build/GUIDE_README.md\`: 首次使用引导说明
- \`build/AUDIO_FIX_README.md\`: 音频问题修复指南

## 🎯 快捷键

- **F4**: 快速文字识别
- **F1**: 悬浮窗口识别

生成时间: $(date '+%Y-%m-%d %H:%M:%S')
EOF

echo "📝 发布说明已生成: $DEST_DIR/RELEASE_NOTES.md"
