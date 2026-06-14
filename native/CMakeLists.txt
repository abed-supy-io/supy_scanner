# supy_scanner native core.
#
# Builds a single static/shared library used by both platforms:
#   - Android consumes it as a shared lib loaded via System.loadLibrary.
#   - iOS consumes the same .cpp files directly through the pod source_files.
#
# Sprint 1 shipped the version probe. Sprint 2 lands zxing-cpp (1D + 2D
# decode) behind SUPY_WITH_ZXING_CPP (default OFF) — see docs/V1.1_PLAN.md.

cmake_minimum_required(VERSION 3.22)
project(supy_scanner_core LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(SUPY_WITH_ZXING_CPP "Vendor zxing-cpp for native barcode decode" OFF)

set(SUPY_CORE_SOURCES
  src/supy_scanner_core.cpp
)

# JNI bridge is Android-only and lives in the Flutter plugin tree so iOS
# pods don't pick it up via source_files globs.
if(ANDROID)
  list(APPEND SUPY_CORE_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/supy_scanner_core_jni.cpp
  )
endif()

add_library(supy_scanner_core SHARED ${SUPY_CORE_SOURCES})

target_include_directories(supy_scanner_core PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_compile_options(supy_scanner_core PRIVATE
  -Wall -Wextra -Wpedantic -Werror
  -fvisibility=hidden
)

# Android: link against the bare runtime; we don't need bionic extras yet.
if(ANDROID)
  target_link_libraries(supy_scanner_core PRIVATE log)
endif()

# zxing-cpp — pinned to v2.2.1 (last tag verified on NDK r26 + Xcode 15).
# Brought in via FetchContent so contributors don't need a submodule init.
# Gated behind SUPY_WITH_ZXING_CPP so the Sprint 1 build path stays untouched
# until the Sprint 2 decode integration is wired through.
if(SUPY_WITH_ZXING_CPP)
  include(FetchContent)
  set(BUILD_WRITERS OFF CACHE BOOL "" FORCE)
  set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(BUILD_BLACKBOX_TESTS OFF CACHE BOOL "" FORCE)
  set(BUILD_UNIT_TESTS OFF CACHE BOOL "" FORCE)
  FetchContent_Declare(
    zxing-cpp
    GIT_REPOSITORY https://github.com/zxing-cpp/zxing-cpp.git
    GIT_TAG        v2.2.1
    GIT_SHALLOW    TRUE
  )
  FetchContent_MakeAvailable(zxing-cpp)
  target_link_libraries(supy_scanner_core PRIVATE ZXing::ZXing)
  target_compile_definitions(supy_scanner_core PRIVATE SUPY_WITH_ZXING_CPP=1)
endif()
