import time
from pathlib import Path
import threading

class AudioPlayer:
    """负责音频播放，使用 Pygame Mixer。"""
    def __init__(self):
        """初始化 Pygame Mixer。"""
        try:
            import pygame
            self._pygame = pygame

            # --- 增强的初始化和调试 ---
            print("🔊 正在初始化 Pygame 主模块...")
            self._pygame.init()  # 初始化所有Pygame模块

            print("🔊 正在初始化 Pygame Mixer...")
            # 使用更明确的参数尝试初始化 (44100Hz, 16-bit, 立体声, 2048字节缓冲区)
            self._pygame.mixer.init(frequency=44100, size=-16, channels=2, buffer=2048)
            
            # 打印SDL音频驱动信息
            try:
                driver = self._pygame.mixer.get_driver()
                if driver:
                    print(f"  - SDL 音频驱动: {driver}")
                else:
                    print("  - 警告: 无法获取SDL音频驱动名称。")
            except Exception as sdle:
                print(f"  - 警告: 获取SDL驱动信息时出错: {sdle}")
            # --- 结束 ---

            self._stop_event = threading.Event()
            # 当前这次 play() 真正在轮询的那个 Event（由调用方传入）。
            # stop() 必须同时 set 它：core.py 传进来的是 processor 自己的
            # _stop_event，跟 AudioPlayer._stop_event 不是同一个对象，
            # 只 set 自己的那个，play() 里的循环永远看不到，音频停不下来。
            self._active_event = None
            print("✅ 音频播放器初始化完成。")
        except ImportError:
            print("缺少 pygame 依赖包。")
            print("请运行 'pip install pygame' 来安装它。")
            raise
        except self._pygame.error as e:
            print(f"❌ 初始化Pygame Mixer失败: {e}")
            print("这可能是由于没有可用的音频设备或驱动问题。")
            # 添加更多环境变量的调试信息
            print("  - 检查环境变量 SDL_AUDIODRIVER...")
            import os
            print(f"    - SDL_AUDIODRIVER = {os.environ.get('SDL_AUDIODRIVER', '未设置')}")
            raise RuntimeError("无法初始化音频播放器。") from e

    def play(self, audio_file: str, stop_event: threading.Event = None):
        """
        播放指定的音频文件。
        
        :param audio_file: 音频文件的路径。
        :param stop_event: 用于从外部停止播放的线程事件。
        """
        if not Path(audio_file).exists() or Path(audio_file).stat().st_size == 0:
            print("❌ 音频文件无效或为空，跳过播放。")
            return
            
        if stop_event is None:
            stop_event = self._stop_event

        self._active_event = stop_event
        try:
            # 强制检查并重新初始化，确保播放总是有效
            if not self._pygame.mixer.get_init():
                print("⚠️ 音频混合器未初始化，正在尝试重新初始化...")
                self._pygame.mixer.init(frequency=44100, size=-16, channels=2, buffer=2048)

            print(f"🎧 正在播放: {audio_file}")
            self._pygame.mixer.music.load(audio_file)
            self._pygame.mixer.music.play()
            
            while self._pygame.mixer.music.get_busy():
                if stop_event.is_set():
                    self._pygame.mixer.music.stop()
                    print("⏹️ 播放被中断。")
                    break
                time.sleep(0.1)
            
            if not stop_event.is_set():
                print("✅ 音频播放结束。")
                
        except self._pygame.error as e:
            print(f"❌ 音频播放失败: {e}")
        finally:
            # 清除停止事件，为下一次播放做准备
            stop_event.clear()

    def stop(self):
        """停止当前正在播放的音频（必须同时 set 调用方传进来的那个 Event）。"""
        self._stop_event.set()
        active = getattr(self, "_active_event", None)
        if active is not None:
            active.set()

    def quit(self):
        """退出 Pygame，释放资源。"""
        print("正在关闭音频播放器...")
        self._pygame.quit()

if __name__ == '__main__':
    # 用于直接测试音频播放功能
    # 前提：需要先有一个音频文件，例如通过 tts.py 生成
    # 使用方法: python3 tts.py "测试音频播放" test.mp3 && python3 audio.py test.mp3
    import sys
    
    if len(sys.argv) > 1:
        audio_file_path = sys.argv[1]
        if not Path(audio_file_path).exists():
            print(f"错误: 文件 '{audio_file_path}' 不存在。")
        else:
            try:
                print("--- 音频播放功能测试 ---")
                player = AudioPlayer()
                
                # 创建一个模拟的停止事件，测试中断功能
                # 在新线程中运行播放，主线程等待几秒后停止它
                stop_flag = threading.Event()
                play_thread = threading.Thread(target=player.play, args=(audio_file_path, stop_flag))
                
                print("开始播放音频，将在3秒后自动停止...")
                play_thread.start()
                time.sleep(3)
                stop_flag.set() # 发送停止信号
                
                play_thread.join() # 等待播放线程结束
                print("\n--- 再次播放，完整播放 ---")
                player.play(audio_file_path)

                player.quit()
                print("--- 测试结束 ---")
            except (ImportError, RuntimeError) as e:
                print(f"运行失败: {e}")
    else:
        print("请提供一个音频文件路径作为参数。")
        print("用法: python3 audio.py /path/to/your/audio.mp3")
