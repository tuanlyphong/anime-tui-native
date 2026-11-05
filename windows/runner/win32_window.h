#ifndef WIN32_WINDOW_H_
#define WIN32_WINDOW_H_

#include <windows.h>

class Win32Window {
 public:
  Win32Window() {}
  virtual ~Win32Window() {}

  // Creates the window and shows it.
  virtual bool Create() = 0;

  // Destroys the window.
  virtual void Destroy() = 0;

  // Returns the window handle.
  HWND GetHandle() const { return hwnd_; }

 protected:
  HWND hwnd_ = nullptr;

  // Window procedure for message handling.
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message,
                                     WPARAM wparam,
                                     LPARAM lparam);

  // Virtual methods for derived classes to override.
  virtual void OnCreate() {}
  virtual void OnDestroy() {}
};

#endif  // WIN32_WINDOW_H_
