#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import gi
import time
gi.require_version('Atspi', '2.0')
from gi.repository import Atspi

class AccessibilityEngine:
    """
    Provides access to the text on the screen using the AT-SPI accessibility API.
    This is the same technology used by screen readers like Orca.
    """

    def __init__(self):
        """Initializes the AT-SPI registry."""
        try:
            self._registry = Atspi.Registry()
            print("✅ Accessibility Engine (AT-SPI) initialized.")
        except Exception as e:
            print(f"❌ Failed to initialize AT-SPI registry: {e}")
            print("Please ensure the at-spi2-core daemon is running.")
            raise RuntimeError("Could not connect to Accessibility API.")

    def get_text_at_position(self, x: int, y: int) -> str:
        """
        Gets the text of the accessible object at a given screen position.

        :param x: The x-coordinate.
        :param y: The y-coordinate.
        :return: The text of the component, or an empty string if not found.
        """
        try:
            desktop = self._registry.get_desktop(0)
            if not desktop:
                return ""

            # Find the accessible object directly at the given coordinates
            component = desktop.get_accessible_at_point(x, y, Atspi.CoordType.SCREEN)
            if not component:
                return ""

            # The object at the cursor might not have the text itself, but its parent might.
            # We traverse up the hierarchy to find the most likely candidate containing the text.
            parent = component
            for _ in range(5): # Limit traversal depth to 5 levels
                if not parent:
                    break
                
                # An object with a name and no children is often a good candidate (e.g., a button label)
                if parent.get_name() and parent.get_child_count() == 0:
                    return parent.get_name().strip()

                # Check for a text role
                role = parent.get_role()
                if role == Atspi.Role.TEXT or role == Atspi.Role.PARAGRAPH or role == Atspi.Role.LABEL:
                    try:
                        # Attempt to get text from the object
                        text_iface = parent.get_iface(Atspi.IFACE_TEXT)
                        text = text_iface.get_text(0, -1)
                        if text and text.strip():
                            return text.strip()
                    except gi.repository.GLib.Error:
                        # Interface not supported, fall back to name
                        if parent.get_name():
                            return parent.get_name().strip()

                parent = parent.get_parent()

            return ""

        except Exception as e:
            # This can happen if the UI is updating rapidly. Fail gracefully.
            # print(f"⚠️  Error getting accessible component: {e}")
            return ""

if __name__ == '__main__':
    # Test script to print text under the cursor for 10 seconds
    print("--- Accessibility Engine Test ---")
    print("Move your mouse over different UI elements to see the detected text.")
    print("The test will run for 20 seconds. Press Ctrl+C to stop early.")
    
    try:
        import pyautogui
        engine = AccessibilityEngine()
        last_text = ""
        for i in range(40):
            x, y = pyautogui.position()
            current_text = engine.get_text_at_position(x, y)
            if current_text and current_text != last_text:
                print(f"({x}, {y}) -> Text: '{current_text}'")
                last_text = current_text
            time.sleep(0.5)
    except ImportError:
        print("Please install pyautogui (`pip install pyautogui`) to run the test.")
    except RuntimeError as e:
        print(f"Test failed: {e}")
    except KeyboardInterrupt:
        print("\nTest stopped by user.")
    finally:
        print("--- Test Finished ---")
