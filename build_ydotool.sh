#!/bin/bash

# 如果任何命令失败，脚本将立即退出
set -e

# --- 1. 安装编译依赖 ---
echo "--- 正在安装编译所需的依赖工具 (git, cmake, g++, etc.)... ---"
sudo apt-get update
sudo apt-get install -y git build-essential cmake scdoc pkg-config libinput-dev

# --- 2. 下载 ydotool 源代码 ---
echo "--- 正在从 GitHub 下载 ydotool 源代码... ---"
# 我们在 /tmp 目录下进行操作，这是一个安全的临时位置
cd /tmp
# 如果之前有残留，先删除
rm -rf ydotool
git clone https://github.com/ReimuNotMoe/ydotool.git
cd ydotool

# --- 3. 编译源代码 ---
echo "--- 正在配置和编译... ---"
cmake .
make

# --- 4. 安装编译好的程序 ---
echo "--- 正在安装 ydotool 和 ydotoold 到系统中... ---"
sudo make install

# --- 5. 清理 ---
echo "--- 正在清理临时文件... ---"
cd /
rm -rf /tmp/ydotool

echo "--- ✅ 编译和安装成功！---"
echo "ydotool 和 ydotoold 现在应该已经安装在 /usr/local/bin/ 中了。"