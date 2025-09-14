#!/bin/bash
# 测试打包结果的脚本

echo "======================================================"
echo "A.M.D-helper v0.53 打包验证"
echo "======================================================"

PACKAGE_FILE="build/release/amd-helper-v0.53.tar.gz"

if [[ ! -f "$PACKAGE_FILE" ]]; then
    echo "❌ 打包文件不存在: $PACKAGE_FILE"
    exit 1
fi

echo "✅ 打包文件存在: $PACKAGE_FILE"
echo "📦 文件大小: $(du -h "$PACKAGE_FILE" | cut -f1)"

echo
echo "🔍 验证关键文件..."

# 检查关键文件
key_files=(
    "./build/install.sh"
    "./build/first_time_guide.sh"
    "./build/fix_audio.sh"
    "./build/fix_pygame_audio.sh"
    "./build/TROUBLESHOOTING.md"
    "./build/FIX_NOTES.md"
    "./build/GUIDE_README.md"
    "./build/AUDIO_FIX_README.md"
    "./f4.py"
    "./f1.py"
    "./tray.py"
    "./core.py"
    "./requirements.txt"
)

missing_files=()
for file in "${key_files[@]}"; do
    if tar -tzf "$PACKAGE_FILE" | grep -q "^$file$"; then
        echo "✅ $file"
    else
        echo "❌ $file"
        missing_files+=("$file")
    fi
done

echo
if [[ ${#missing_files[@]} -eq 0 ]]; then
    echo "🎉 所有关键文件验证通过！"
    echo
    echo "📋 打包内容统计:"
    echo "  总文件数: $(tar -tzf "$PACKAGE_FILE" | wc -l)"
    echo "  Python文件: $(tar -tzf "$PACKAGE_FILE" | grep '\.py$' | wc -l)"
    echo "  Shell脚本: $(tar -tzf "$PACKAGE_FILE" | grep '\.sh$' | wc -l)"
    echo "  文档文件: $(tar -tzf "$PACKAGE_FILE" | grep '\.md$' | wc -l)"
    echo
    echo "✅ 打包验证成功！可以发布使用。"
else
    echo "❌ 发现 ${#missing_files[@]} 个缺失文件，请检查打包脚本"
    exit 1
fi