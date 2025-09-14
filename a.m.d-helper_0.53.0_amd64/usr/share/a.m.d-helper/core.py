#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import tempfile
import os
import asyncio
import threading
from threading import Event

import json
import os
import tempfile
import asyncio
from threading import Event

# Import existing components
from screenshot import Screenshotter
from ocr import EasyOcrEngine
from tts import get_tts_engine, PiperTtsEngine
from audio import AudioPlayer

# --- 路径处理 ---
# 用户特定的配置文件路径（与 tray.py 中的定义保持一致）
USER_CONFIG_PATH = os.path.expanduser(os.path.join("~", ".config", "a.m.d-helper", "config.json"))

def get_core_config():
    """
    读取核心配置。
    假定主程序(tray.py)已经处理了首次运行的配置创建。
    """
    try:
        with open(USER_CONFIG_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        # 如果文件不存在或损坏，返回空字典，让调用者处理默认值
        print("⚠️ core.py: 无法读取用户配置文件，将使用默认设置。")
        return {}

class OcrAndTtsProcessor:
    """一个为服务模式设计的处理器，一次性加载模型。"""
    
    def __init__(self):
        """在初始化时，一次性加载所有重量级引擎。"""
        print("🔄 正在初始化所有核心引擎 (这应该只在服务启动时发生一次)...")
        self.screenshotter = Screenshotter()
        self.ocr_engine = EasyOcrEngine()
        # 在初始化时，根据文件加载一次引擎
        self.tts_engine = get_tts_engine() 
        self.audio_player = AudioPlayer()
        self._temp_files = []
        self._stop_event = Event()
        print("✅ 所有核心引擎初始化完毕，服务就绪。")

    def reload_tts_engine(self, new_config: dict):
        """根据传入的最新配置重新加载TTS引擎。"""
        print("🔄 正在根据新配置重新加载TTS引擎...")
        # 直接使用传入的配置，不再读取文件，避免竞态条件
        self.tts_engine = get_tts_engine(config=new_config)
        print("✅ TTS引擎已更新。")

    def _cleanup_files(self):
        """清理所有临时文件。"""
        if not self._temp_files:
            return
        print("🧹 清理临时文件...")
        for f in self._temp_files:
            try:
                if os.path.exists(f):
                    os.remove(f)
            except OSError as e:
                print(f"  - 删除临时文件失败: {f}, 原因: {e}")
        self._temp_files.clear()

    def run_full_process(self):
        """执行截图 -> OCR -> TTS -> 音频播放的完整流程。"""
        print("\n=== (核心) 收到请求，开始处理流程 ===")
        
        try:
            # 1. 立即进行截图
            image_path = self.screenshotter.take_screenshot()

            if not image_path:
                print("流程中断：用户取消了截图。" )
                return
            self._temp_files.append(image_path)

            # 2. OCR 识别
            text, ocr_lang = self.ocr_engine.recognize(image_path)
            if not text:
                print("流程中断：未识别到文字。" )
                return
            
            print(f"ℹ️ OCR 识别语言: {ocr_lang}，将使用此语言进行语音合成。")

            # 3. TTS 合成
            # 注意：此处不再重新加载引擎，而是使用初始化或reload时设置的引擎
            audio_suffix = '.wav' if isinstance(self.tts_engine, PiperTtsEngine) else '.mp3'
            with tempfile.NamedTemporaryFile(suffix=audio_suffix, delete=False) as temp_audio_file:
                audio_path = temp_audio_file.name
            self._temp_files.append(audio_path)
            
            # 直接使用 OCR 识别出的语言进行合成
            asyncio.run(self.tts_engine.synthesize(text, audio_path, lang=ocr_lang))

            # 4. 播放音频
            self.audio_player.play(audio_path, stop_event=self._stop_event)

        except Exception as e:
            print(f"❌ 处理过程中出现错误: {e}")
        finally:
            self._cleanup_files()
            print("=== (核心) 流程结束 ===")


    def cleanup(self):
        """清理资源"""
        print("🧹 清理处理器资源...")
        self._stop_event.set()
        if self.audio_player:
            self.audio_player.stop()
        self._cleanup_files()
        print("✅ 资源清理完成")

if __name__ == '__main__':
    # 用于直接测试 core.py 的功能
    print("--- 直接测试 OcrAndTtsProcessor ---")
    processor = OcrAndTtsProcessor()
    processor.run_full_process()
    processor.cleanup()
    print("--- 测试结束 ---")
