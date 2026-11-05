// Copyright 2023 The Flutter Authors. All rights reserved.
// Copyright 2025 The Anime TUI Native Authors. All rights reserved.

#include "flutter_window.h"

#include <flutter/flutter_engine.h>
#include <windows.h>

#include <iostream>

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() { EnsureRunnerThreadShutdown(); }

bool FlutterWindow::OnCreate() {
  // Instantiate the Flutter engine. If this fails, the window is invalid.
  auto result = project_.CreateEngine(&engine_);
  if (!result.ok()) {
    std::cerr << "Failed to create Flutter engine: " << result.error().message()
              << std::endl;
    return false;
  }

  // Create the window and show it.
  WNDCLASS wc = {};
  wc.lpfnWndProc = WindowProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = L"FlutterWindowClass";
  RegisterClass(&wc);

  hwnd_ = CreateWindow(
      L"FlutterWindowClass", L"Anime TUI",
      WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 800, 600,
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!hwnd_) {
    return false;
  }

  // Show the window.
  ShowWindow(hwnd_, SW_SHOWNORMAL);

  // Initialize the Flutter instance.
  flutter::FlutterEngine::CreateParams params;
  params.project = &project_;
  params.cache_path = nullptr;
  params.entrySet = nullptr;
  params.enable_wayland = false;
  params.enable_skia_direct_bytebuffer = false;
  params.disable_pixel_buffer_discarding = false;
  params.is_ipc_channel_connected = nullptr;

  auto engine_result = flutter::FlutterEngine::Create(params, &engine_);
  if (!engine_result.ok()) {
    std::cerr << "Failed to create Flutter engine: "
              << engine_result.error().message() << std::endl;
    return false;
  }

  // Configure the Flutter engine with the project.
  auto init_result = engine_->Initialize();
  if (!init_result.ok()) {
    std::cerr << "Failed to initialize Flutter engine: "
              << init_result.error().message() << std::endl;
    return false;
  }

  return true;
}

void FlutterWindow::OnDestroy() {
  // Shut down the Flutter engine.
  if (engine_) {
    engine_->Shutdown();
    engine_ = nullptr;
  }

  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }

  UnregisterClass(L"FlutterWindowClass", nullptr);
}

LRESULT CALLBACK FlutterWindow::WindowProc(HWND hwnd, UINT message,
                                           WPARAM wparam,
                                           LPARAM lparam) {
  FlutterWindow* window = reinterpret_cast<FlutterWindow*>(
      GetWindowLongPtr(hwnd, GWLP_USERDATA));

  if (message == WM_CREATE) {
    // Store the window pointer in the user data field.
    CREATESTRUCT* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    window = reinterpret_cast<FlutterWindow*>(create_struct->lpCreateParams);
    SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(window));
    return window->OnCreate() ? 0 : -1;
  } else if (message == WM_DESTROY) {
    window->OnDestroy();
    PostQuitMessage(0);
    return 0;
  }

  // Forward other messages to the Flutter engine.
  if (window && window->engine_) {
    // This is a simplified implementation. A full implementation would
    // forward window messages to the Flutter engine's message loop.
    return DefWindowProc(hwnd, message, wparam, lparam);
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}
