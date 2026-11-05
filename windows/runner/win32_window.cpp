#include "win32_window.h"

#include <windows.h>

Win32Window::~Win32Window() {
  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
}
