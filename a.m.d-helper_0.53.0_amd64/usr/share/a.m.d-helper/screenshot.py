"""
负责截图操作，统一使用 libshot 库的交互式截图功能。
"""

import os
import tempfile
from pathlib import Path

# libshot is expected to be in the project structure
import libshot

class Screenshotter:
    """使用 libshot.capture_interactive() 提供最佳的交互式截图体验。"""

    def __init__(self):
        """初始化截图工具。libshot 会自动选择最佳后端。"""
        # The print statement from libshot's __init__ is now the source of truth
        pass

    def take_screenshot(self) -> str | None:
        """
        执行交互式截图操作，返回截图文件的绝对路径。
        如果截图失败或取消，则返回 None。
        """
        print("🖼️  请选择截图区域...")
        try:
            # The single, unified entry point for the best interactive experience
            image = libshot.capture_interactive()

            if image is None:
                print("❌ 截图取消或失败。")
                return None

            # Save the Pillow Image object to a temporary file
            with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as temp_image_file:
                file_path = temp_image_file.name
            
            image.save(file_path, 'PNG')

            if Path(file_path).stat().st_size > 0:
                print(f"✅ 截图成功，文件保存在: {file_path}")
                return file_path
            else:
                print("❌ 截图失败，未生成有效的图片文件。")
                if Path(file_path).exists():
                    os.remove(file_path)
                return None
        except Exception as e:
            print(f"❌ 截图过程中出现未知错误: {e}")
            return None

if __name__ == '__main__':
    # 用于直接测试截图功能
    print("正在测试新的交互式截图功能...")
    try:
        screenshotter = Screenshotter()
        screenshot_path = screenshotter.take_screenshot()
        if screenshot_path:
            print(f"✅ 测试成功，截图路径: {screenshot_path}")
        else:
            print("⏹️  测试结束，未获取到截图或操作被取消。")
    except Exception as e:
        print(f"🔥 测试失败: {e}")
