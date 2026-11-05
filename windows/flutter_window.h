#ifndef FLUTTER_WINDOW_H_
#define FLUTTER_WINDOW_H_

#include <flutter/flutter_engine.h>
#include <windows.h>

class FlutterWindow {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  ~FlutterWindow();

  // Creates the window and initializes the Flutter engine.
  bool OnCreate();

  // Called when the window is destroyed.
  void OnDestroy();

  // Window procedure for message handling.
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message,
                                     WPARAM wparam,
                                     LPARAM lparam);

 private:
  flutter::DartProject project_;
  std::unique_ptr<flutter::FlutterEngine> engine_;
  HWND hwnd_ = nullptr;
};

#endif  // FLUTTER_WINDOW_H_
