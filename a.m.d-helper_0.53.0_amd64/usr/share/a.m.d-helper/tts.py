#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import asyncio
import subprocess
import os
import shutil
import sys

# --- 路径处理 ---
# 获取脚本所在的目录
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
# 用户特定的配置文件路径（确保与 tray.py 和 core.py 一致）
USER_CONFIG_DIR = os.path.expanduser(os.path.join("~", ".config", "a.m.d-helper"))
USER_CONFIG_PATH = os.path.join(USER_CONFIG_DIR, "config.json")

# 定义一个基础的TTS引擎接口 (可选，但良好实践)
class TtsEngine:
    async def synthesize(self, text: str, output_path: str, lang: str = 'auto'):
        raise NotImplementedError

class EdgeTtsEngine(TtsEngine):
    """使用 edge-tts 命令行工具合成语音"""
    async def synthesize(self, text: str, output_path: str, lang: str = 'auto'):
        # Edge TTS v6+ 可以自动检测语言，因此 lang 参数在这里主要用于日志或未来可能的特定逻辑
        print("🔄 使用 Edge-TTS 进行语音合成...")
        voice = "zh-CN-XiaoxiaoNeural" if lang == 'zh' else "en-US-JennyNeural"
        
        command = [
            "edge-tts",
            "--voice", voice,
            "--text", text,
            "--write-media", output_path
        ]
        process = await asyncio.create_subprocess_exec(
            *command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        stdout, stderr = await process.communicate()

        if process.returncode != 0:
            print(f"❌ Edge-TTS 错误: {stderr.decode()}")
            raise RuntimeError("Edge-TTS synthesis failed")
        else:
            print(f"✅ 语音已保存到: {output_path}")

import sys

class PiperTtsEngine(TtsEngine):
    """使用 piper 命令行工具合成语音"""
    async def synthesize(self, text: str, output_path: str, lang: str = 'zh'):
        print("🔄 使用 Piper-TTS 进行语音合成...")
        
        # --- 自动查找 Piper 可执行文件 ---
        piper_executable = shutil.which('piper')
        if not piper_executable:
            # 兼容 venv 环境
            py_dir = os.path.dirname(sys.executable)
            maybe_path = os.path.join(py_dir, 'piper')
            if os.path.exists(maybe_path):
                piper_executable = maybe_path

        if not piper_executable:
            raise FileNotFoundError("找不到 'piper' 可执行文件。请确保 'piper-tts' 已通过 pip 安装。")

        # --- 模型路径处理 ---
        model_name = "zh_CN-huayan-medium.onnx" if lang == 'zh' else "en_US-kristin-medium.onnx"
        model_path = os.path.join(SCRIPT_DIR, "models", model_name)

        if not os.path.exists(model_path):
            raise FileNotFoundError(f"TTS 模型文件未找到: {model_path}")

        command = [
            piper_executable,
            "--model", model_path,
            "--output_file", output_path
        ]
        
        print(f"Piper command: {' '.join(command)}")
        
        process = await asyncio.create_subprocess_exec(
            *command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        stdout, stderr = await process.communicate(input=text.encode('utf-8'))

        if process.returncode != 0:
            print(f"❌ Piper-TTS 错误: {stderr.decode()}")
            raise RuntimeError("Piper-TTS synthesis failed")
        else:
            print(f"✅ 语音已保存到: {output_path}")

def _get_config():
    """读取用户配置文件"""
    try:
        # 确保始终读取用户特定的配置文件
        with open(USER_CONFIG_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        # 如果文件不存在或格式错误，返回一个安全的默认值
        print(f"⚠️ tts.py: 无法从 '{USER_CONFIG_PATH}' 读取配置，将回退到默认引擎。")
        return {"tts_model": "piper"}

def get_tts_engine(config: dict = None) -> TtsEngine:
    """
    根据提供的配置或全局配置文件，返回一个TTS引擎实例。
    """
    # 如果没有直接提供配置，则从文件读取
    if config is None:
        config = _get_config()
    
    model_type = config.get("tts_model", "piper") # 默认使用piper以保证离线可用性

    print(f"ℹ️ 根据配置加载TTS引擎: {model_type}")

    if model_type == "piper":
        return PiperTtsEngine()
    elif model_type == "edge":
        return EdgeTtsEngine()
    else:
        print(f"⚠️ 未知的TTS模型类型 '{model_type}'，将默认使用 Piper-TTS。")
        return PiperTtsEngine()
