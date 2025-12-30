#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import asyncio
import subprocess
import os
import shutil
import sys
import logging
import traceback

# 获取 logger
logger = logging.getLogger("AMD-HELPER")

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
    """使用 edge-tts Python API 合成语音，带重试机制"""
    
    MAX_RETRIES = 3
    RETRY_DELAY = 1.0
    
    async def synthesize(self, text: str, output_path: str, lang: str = 'auto'):
        logger.info("🔄 使用 Edge-TTS 进行语音合成...")
        voice = "zh-CN-XiaoxiaoNeural" if lang == 'zh' else "en-US-JennyNeural"
        logger.debug(f"Edge-TTS 参数: voice={voice}, lang={lang}, output={output_path}")
        logger.debug(f"合成文本: {text[:100]}...")
        
        last_error = None
        
        for attempt in range(1, self.MAX_RETRIES + 1):
            try:
                import edge_tts
                import aiohttp
                logger.debug(f"尝试 {attempt}/{self.MAX_RETRIES}...")
                
                # 创建带超时的 connector
                timeout = aiohttp.ClientTimeout(total=30, connect=10)
                connector = aiohttp.TCPConnector(limit=1, force_close=True)
                
                communicate = edge_tts.Communicate(text, voice)
                await communicate.save(output_path)
                
                # 验证输出文件
                if os.path.exists(output_path):
                    file_size = os.path.getsize(output_path)
                    if file_size > 0:
                        logger.info(f"✅ 语音已保存到: {output_path} (大小: {file_size} bytes)")
                        return
                    else:
                        raise RuntimeError("Edge-TTS 生成的文件为空")
                else:
                    raise RuntimeError("Edge-TTS 输出文件不存在")
                    
            except ImportError as e:
                logger.error(f"无法导入 edge_tts 模块: {e}")
                raise RuntimeError("edge-tts 库未安装")
            except Exception as e:
                last_error = e
                error_msg = str(e)
                logger.warning(f"Edge-TTS 尝试 {attempt} 失败: {error_msg}")
                
                if attempt < self.MAX_RETRIES:
                    import asyncio
                    logger.debug(f"等待 {self.RETRY_DELAY} 秒后重试...")
                    await asyncio.sleep(self.RETRY_DELAY)
                    # 增加重试延迟
                    self.RETRY_DELAY *= 1.5
        
        # 所有重试都失败
        logger.error(f"Edge-TTS 在 {self.MAX_RETRIES} 次尝试后仍然失败")
        logger.error(f"最后一次错误: {last_error}")
        logger.error(f"异常详情:\n{traceback.format_exc()}")
        raise RuntimeError(f"Edge-TTS 合成失败: {last_error}")

import sys

class PiperTtsEngine(TtsEngine):
    """使用 piper 命令行工具合成语音"""
    async def synthesize(self, text: str, output_path: str, lang: str = 'zh'):
        logger.info("🔄 使用 Piper-TTS 进行语音合成...")
        logger.debug(f"Piper-TTS 参数: lang={lang}, output={output_path}")
        
        # --- 自动查找 Piper 可执行文件 ---
        piper_executable = shutil.which('piper')
        logger.debug(f"shutil.which('piper') 结果: {piper_executable}")
        
        if not piper_executable:
            # 兼容 venv 环境
            py_dir = os.path.dirname(sys.executable)
            maybe_path = os.path.join(py_dir, 'piper')
            logger.debug(f"尝试 venv 路径: {maybe_path}, 存在: {os.path.exists(maybe_path)}")
            if os.path.exists(maybe_path):
                piper_executable = maybe_path

        if not piper_executable:
            logger.error("找不到 'piper' 可执行文件")
            raise FileNotFoundError("找不到 'piper' 可执行文件。请确保 'piper-tts' 已通过 pip 安装。")

        # --- 模型路径处理 ---
        model_name = "zh_CN-huayan-medium.onnx" if lang == 'zh' else "en_US-kristin-medium.onnx"
        model_path = os.path.join(SCRIPT_DIR, "models", model_name)
        logger.debug(f"Piper 模型路径: {model_path}, 存在: {os.path.exists(model_path)}")

        if not os.path.exists(model_path):
            logger.error(f"TTS 模型文件未找到: {model_path}")
            raise FileNotFoundError(f"TTS 模型文件未找到: {model_path}")

        command = [
            piper_executable,
            "--model", model_path,
            "--output_file", output_path
        ]
        
        logger.debug(f"Piper command: {' '.join(command)}")
        
        try:
            process = await asyncio.create_subprocess_exec(
                *command,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            
            stdout, stderr = await process.communicate(input=text.encode('utf-8'))
            
            logger.debug(f"Piper 返回码: {process.returncode}")
            if stdout:
                logger.debug(f"Piper stdout: {stdout.decode()}")
            if stderr:
                logger.debug(f"Piper stderr: {stderr.decode()}")

            if process.returncode != 0:
                logger.error(f"Piper-TTS 错误: {stderr.decode()}")
                raise RuntimeError("Piper-TTS synthesis failed")
            else:
                if os.path.exists(output_path):
                    file_size = os.path.getsize(output_path)
                    logger.info(f"✅ 语音已保存到: {output_path} (大小: {file_size} bytes)")
                else:
                    logger.error(f"Piper 声称成功但输出文件不存在: {output_path}")
                    raise RuntimeError("Piper output file not created")
        except Exception as e:
            logger.error(f"Piper-TTS 执行异常: {e}")
            logger.error(f"异常详情:\n{traceback.format_exc()}")
            raise

def _get_config():
    """读取用户配置文件"""
    try:
        # 确保始终读取用户特定的配置文件
        with open(USER_CONFIG_PATH, "r", encoding="utf-8") as f:
            config = json.load(f)
            logger.debug(f"tts.py 读取配置: {config}")
            return config
    except (FileNotFoundError, json.JSONDecodeError) as e:
        # 如果文件不存在或格式错误，返回一个安全的默认值
        logger.warning(f"tts.py: 无法从 '{USER_CONFIG_PATH}' 读取配置 ({e})，将回退到默认引擎。")
        return {"tts_model": "piper"}

def get_tts_engine(config: dict = None) -> TtsEngine:
    """
    根据提供的配置或全局配置文件，返回一个TTS引擎实例。
    """
    # 如果没有直接提供配置，则从文件读取
    if config is None:
        config = _get_config()
    
    model_type = config.get("tts_model", "piper") # 默认使用piper以保证离线可用性

    logger.info(f"ℹ️ 根据配置加载TTS引擎: {model_type}")
    logger.debug(f"完整配置: {config}")

    if model_type == "piper":
        logger.debug("创建 PiperTtsEngine 实例")
        return PiperTtsEngine()
    elif model_type == "edge":
        logger.debug("创建 EdgeTtsEngine 实例")
        return EdgeTtsEngine()
    else:
        logger.warning(f"未知的TTS模型类型 '{model_type}'，将默认使用 Piper-TTS。")
        return PiperTtsEngine()
