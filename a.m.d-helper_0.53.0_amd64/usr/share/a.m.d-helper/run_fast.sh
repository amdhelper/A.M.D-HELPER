#!/bin/bash

# 脚本的目的是为Python程序设置正确的运行环境，特别是当由系统快捷键调用时。

# 1. 设置项目所在的目录
APP_DIR="/home/didi88ss/pj/speechfy/0.53/linux"
#APP_DIR="/home/didi88ss/pj/speechfy/0.4_latest_ok/linux"

# 2. 激活Python虚拟环境
#    确保下面的路径是正确的
source "/home/didi88ss/pj/speechfy/0.53/linux/venv/bin/activate"

# 3. 为了确保截图等GUI工具能找到显示服务器，导出显示变量
export DISPLAY=:0
export XAUTHORITY=$HOME/.Xauthority

# 4. 切换到项目目录（这是一个好习惯）
cd "$APP_DIR"

# 5. 执行Python主脚本，并将所有输出（stdout和stderr）追加到日志文件中
#    这对于调试快捷键问题至关重要
echo "Hotkey triggered at $(date)" >> /tmp/sonar_hotkey.log
python3 "$APP_DIR/f4.py" >> /tmp/f4.log 2>&1
