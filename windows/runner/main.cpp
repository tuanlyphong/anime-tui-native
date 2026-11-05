#include <flutter/flutter_engine.h>
#include <windows.h>

int APIENTRY wWinMain(HINSTANCE instance, HINSTANCE, LPWSTR command_line, int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    ::AllocConsole();
    freopen("CONOUT$", "w", stdout);
    freopen("CONOUT$", "w", stderr);
  }

  // Instantiate the Flutter project.
  flutter::DartProject project(L"data");

  // Create and run the window.
  FlutterWindow window(project);
  if (!window.OnCreate()) {
    return 1;
  }

  // Run the message loop.
  MSG message;
  while (GetMessage(&message, nullptr, 0, 0)) {
    TranslateMessage(&message);
    DispatchMessage(&message);
  }

  return 0;
}
