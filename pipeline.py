import tempfile
import os
import asyncio
import atexit
from threading import Event, Lock

# 从项目模块中导入各个组件
from screenshot import Screenshotter
from ocr import OcrEngine
from tts import TtsEngine
from audio import AudioPlayer

class ProcessingPipeline:
    """
    处理流水线，负责协调各个组件完成从截图到朗读的完整流程。
    """
    def __init__(self, screenshotter: Screenshotter, ocr_engine: OcrEngine, tts_engine: TtsEngine, audio_player: AudioPlayer):
        """
        初始化处理流水线。

        :param screenshotter: 截图器实例。
        :param ocr_engine: OCR引擎实例。
        :param tts_engine: TTS引擎实例。
        :param audio_player: 音频播放器实例。
        """
        self.screenshotter = screenshotter
        self.ocr_engine = ocr_engine
        self.tts_engine = tts_engine
        self.audio_player = audio_player
        
        self._lock = Lock()  # 用于确保同一时间只有一个流程在运行
        self._temp_files = []
        self._shutdown_event = Event()

        # 注册清理函数，确保程序退出时清理临时文件
        atexit.register(self.cleanup)

    def _cleanup(self):
        """清理所有在流程中产生的临时文件。"""
        print("🧹 清理临时文件...")
        for temp_file in self._temp_files:
            try:
                if os.path.exists(temp_file):
                    os.remove(temp_file)
                    print(f"  - 删除了 {os.path.basename(temp_file)}")
            except OSError as e:
                print(f"删除临时文件 {temp_file} 失败: {e}")
        self._temp_files.clear()

    def run(self):
        """
        执行从截图到朗读的完整流程。
        此方法是线程安全的，可以防止重复触发。
        """
        if not self._lock.acquire(blocking=False):
            print("⚠️  操作正在进行中，请勿重复触发。")
            return
        
        print("\n=== 开始新流程 ===")
        try:
            # 1. 截图
            image_path = self.screenshotter.take_screenshot()
            if not image_path:
                print("流程中断：未获取到截图。")
                return
            self._temp_files.append(image_path)

            # 2. OCR 识别
            text = self.ocr_engine.recognize(image_path)
            if not text:
                print("流程中断：未识别到文字。")
                return

            # 3. TTS 合成
            # 创建一个临时文件来保存音频
            with tempfile.NamedTemporaryFile(suffix='.mp3', delete=False) as temp_audio_file:
                audio_path = temp_audio_file.name
            self._temp_files.append(audio_path)
            
            # 运行异步的TTS任务
            asyncio.run(self.tts_engine.synthesize(text, audio_path))

            # 4. 播放音频
            self.audio_player.play(audio_path, stop_event=self._shutdown_event)

        except Exception as e:
            print(f"❌ 流水线执行过程中出现严重错误: {e}")
        finally:
            self._cleanup()
            self._lock.release()
            print("=== 流程结束 ===")

    def shutdown(self):
        """
        安全地关闭流程，例如停止正在播放的音频。
        """
        print("正在请求关闭流程...")
        self._shutdown_event.set()
        self.audio_player.stop()

if __name__ == '__main__':
    # 用于直接测试整个流水线
    print("--- 流水线功能测试 ---")
    try:
        # 1. 初始化所有组件
        from ocr import EasyOcrEngine
        
        screenshot_component = Screenshotter()
        ocr_component = EasyOcrEngine() # 使用EasyOCR
        tts_component = EdgeTtsEngine()
        audio_component = AudioPlayer()

        # 2. 创建流水线实例
        pipeline = ProcessingPipeline(
            screenshotter=screenshot_component,
            ocr_engine=ocr_component,
            tts_engine=tts_component,
            audio_player=audio_component
        )

        # 3. 运行完整流程
        pipeline.run()

    except (ImportError, RuntimeError) as e:
        print(f"初始化或运行时失败: {e}")
    except Exception as e:
        print(f"发生了未知错误: {e}")
    finally:
        # 在测试脚本中，确保pygame在最后退出
        if 'audio_component' in locals():
            audio_component.quit()
        print("--- 测试结束 ---")
