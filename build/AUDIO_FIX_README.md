# 🔧 音频问题修复指南

## 🎯 快速修复 "mixer not initialized" 错误

### 🚀 针对性修复（推荐）

**如果系统音频正常（能播放网页视频）:**
```bash
# 使用pygame专用修复
amd-helper-fix-pygame
```

**如果系统音频也有问题:**
```bash
# 使用完整音频修复
amd-helper-fix-audio
```

### 📋 手动修复步骤

#### 1. 基础检查
```bash
# 检查PulseAudio状态
pulseaudio --check -v

# 检查音频设备
pactl list sinks short
```

#### 2. 重启音频服务
```bash
# 重启PulseAudio
pulseaudio --kill
pulseaudio --start
```

#### 3. 设置环境变量
```bash
# 设置SDL音频驱动
export SDL_AUDIODRIVER=pulse

# 永久设置
echo 'export SDL_AUDIODRIVER=pulse' >> ~/.bashrc
source ~/.bashrc
```

#### 4. 测试修复结果
```bash
cd /opt/amd-helper
source venv/bin/activate
python3 -c "
import pygame
pygame.mixer.init()
print('✅ 修复成功')
pygame.mixer.quit()
"
```

## 🔍 快速诊断

### 判断问题类型
```bash
# 测试系统音频（播放测试音）
paplay /usr/share/sounds/alsa/Front_Left.wav

# 如果能听到声音 → 使用pygame专用修复
# 如果听不到声音 → 使用完整音频修复
```

## 🔍 常见原因

**对于pygame特定问题（系统音频正常）:**
1. **SDL驱动未配置**: pygame不知道使用哪个音频驱动
2. **环境变量缺失**: 缺少SDL_AUDIODRIVER设置
3. **pygame配置问题**: 初始化参数不正确

**对于系统音频问题:**
1. **PulseAudio未运行**: 音频服务没有启动
2. **权限问题**: 用户没有音频设备访问权限
3. **音频系统冲突**: 多个音频系统同时运行

## 💡 预防措施

1. **确保音频系统正常**: 测试系统音频播放
2. **避免多个音频程序**: 同时运行可能导致冲突
3. **定期重启音频服务**: 清理音频系统状态
4. **保持系统更新**: 音频驱动和库的更新

## 🆘 如果仍然有问题

1. **重启系统**: 清理所有音频相关进程
2. **检查硬件**: 确保音频设备正常连接
3. **查看详细日志**: 运行程序时查看具体错误信息
4. **联系技术支持**: 提供系统信息和错误日志