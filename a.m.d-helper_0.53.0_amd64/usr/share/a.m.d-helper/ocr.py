from abc import ABC, abstractmethod
from pathlib import Path
import re

class OcrEngine(ABC):
    """OCR引擎的抽象基类 (接口)。"""
    @abstractmethod
    def recognize(self, image_path: str) -> tuple[str, str]:
        """
        从给定的图片路径中识别文字。

        :param image_path: 图片文件的路径。
        :return: 一个元组，包含 (识别出的字符串文本, 检测到的语言代码 'zh' 或 'en')。
        """
        pass

class EasyOcrEngine(OcrEngine):
    """使用 EasyOCR 实现的OCR引擎。"""
    def __init__(self, languages: list[str] = None, gpu: bool = False):
        """
        初始化 EasyOCR 引擎。
        首次运行时会自动下载所需语言的模型。
        
        :param languages: 需要识别的语言列表, 例如 ['ch_sim', 'en']。
        :param gpu: 是否使用GPU加速。
        """
        try:
            import easyocr
        except ImportError:
            print("缺少 easyocr 依赖包。")
            print("请运行 'pip install easyocr' 来安装它。")
            raise
            
        if languages is None:
            languages = ['ch_sim', 'en']
        
        print("正在初始化 EasyOCR 引擎... (首次运行需要下载模型，请耐心等待)")
        try:
            self.reader = easyocr.Reader(languages, gpu=gpu)
            
            # --- 创建初始化完成标志 ---
            try:
                import os
                flag_dir = os.path.expanduser("~/.config/a.m.d-helper")
                flag_file = os.path.join(flag_dir, "init_done")
                os.makedirs(flag_dir, exist_ok=True)
                with open(flag_file, "w") as f:
                    f.write("done")
                print("✓ 创建初始化标志文件成功。")
            except Exception as flag_e:
                print(f"✗ 创建初始化标志文件失败: {flag_e}")
            # --- 标志创建结束 ---

            print("✅ EasyOCR 引擎初始化完成。")
        except Exception as e:
            print(f"❌ 初始化EasyOCR失败: {e}")
            print("请检查是否安装了PyTorch。如果没有，请访问 https://pytorch.org/ 安装。")
            raise

    def _detect_language(self, text: str) -> str:
        """
        一个简单的启发式语言检测器。
        如果文本中包含中文字符，则认为是'zh'，否则认为是'en'。
        """
        if re.search(r'[\u4e00-\u9fff]', text):
            return 'zh'
        return 'en'

    def recognize(self, image_path: str) -> tuple[str, str]:
        """
        使用 EasyOCR 从图片中提取文字。
        会将识别出的所有文本段落用换行符连接。
        返回识别的文本和检测到的语言 ('zh' 或 'en')。
        """
        if not image_path or not Path(image_path).exists():
            print(" OCR 输入的图片路径无效。 ")
            return "", "en" # 返回默认值
        try:
            print("🔍 使用 EasyOCR 开始识别...")
            # detail=0 表示只返回文本内容
            # paragraph=True 会将邻近的文本块合并成段落
            result = self.reader.readtext(image_path, detail=0, paragraph=True)
            text = "\n".join(result)
            lang = self._detect_language(text)
            
            if text:
                print(f"✅ 识别到文字 ({lang}): {text}")
            else:
                print("⚠️ 未识别到任何文字。")
            return text, lang
        except Exception as e:
            print(f"❌ EasyOCR 识别失败: {e}")
            return "", "en" # 返回默认值

if __name__ == '__main__':
    # 用于直接测试OCR功能
    # 使用方法: python3 ocr.py /path/to/your/image.png
    import sys
    if len(sys.argv) > 1:
        image_path_for_test = sys.argv[1]
        if not Path(image_path_for_test).exists():
            print(f"错误: 文件 '{image_path_for_test}' 不存在。")
        else:
            try:
                print("--- OCR功能测试 ---")
                ocr_engine = EasyOcrEngine()
                recognized_text, lang = ocr_engine.recognize(image_path_for_test)
                print("\n--- 测试结果 ---")
                print(f"语言: {lang}")
                print(f"文本: {recognized_text}")
                print("--- 测试结束 ---")
            except (ImportError, RuntimeError) as e:
                # 打印已知错误，避免崩溃
                print(f"初始化失败: {e}")
    else:
        print("请提供一个图片文件路径作为参数来测试OCR功能。")
        print("用法: python3 ocr.py /path/to/your/image.png")