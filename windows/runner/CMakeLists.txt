# Windows desktop application.

cmake_minimum_required(VERSION 3.23)

project(anime_tui_native CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find the Flutter Windows SDK.
# The Flutter project should be built with:
#   flutter build windows
# The Flutter SDK provides the engine and embedder.
find_path(FLUTTER_INCLUDE_DIR
    NAMES flutter/flutter_window.h
    PATHS "$ENV{FLUTTER_ROOT}/_internal/Framework"
    PATHS "$ENV{FLUTTER_ROOT}/bin/cache/artifacts/engine/windows"
    PATHS "$ENV{FLUTTER_ROOT}/lib/Flutter"
    DOC "Flutter Windows SDK include directory"
)

find_library(FLUTTER_LIBRARY
    NAMES flutter
    PATHS "$ENV{FLUTTER_ROOT}/_internal/Framework"
    PATHS "$ENV{FLUTTER_ROOT}/bin/cache/artifacts/engine/windows"
    PATHS "$ENV{FLUTTER_ROOT}/lib/Flutter"
    DOC "Flutter Windows SDK library"
)

add_executable(anime_tui_native
    ${CMAKE_CURRENT_LIST_DIR}/flutter_window.cpp
    ${CMAKE_CURRENT_LIST_DIR}/runner/main.cpp
    ${CMAKE_CURRENT_LIST_DIR}/runner/win32_window.cpp
)

target_include_directories(anime_tui_native PRIVATE
    ${FLUTTER_INCLUDE_DIR}
    ${CMAKE_CURRENT_LIST_DIR}
)

target_link_libraries(anime_tui_native PRIVATE
    flutter
    winmm
    ole32
    rpcrt4
    user32
    gdi32
    comdlg32
    shell32
    shlwapi
    urlmon
)

# Enable C++17 and warning-free compilation.
target_compile_features(anime_tui_native PRIVATE cxx_std_20)
target_compile_options(anime_tui_native PRIVATE /W4 /WX)
