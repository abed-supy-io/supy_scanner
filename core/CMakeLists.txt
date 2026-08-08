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
option(SUPY_WITH_LIBDMTX "Vendor libdmtx for Data Matrix region location" OFF)
option(SUPY_USE_HALIDE "Use Halide AOT kernel for Sauvola 2D binarization" OFF)
option(SUPY_BUILD_TESTS "Build host-side GoogleTest suite" OFF)
option(SUPY_BUILD_TOOLS "Build host-side bench/dev tools" OFF)

set(SUPY_CORE_SOURCES
  src/supy_scanner_core.cpp
  document/document_edge_detector.cpp
  document/document_guidance_classifier.cpp
  document/perspective_warp.cpp
  quality/frame_scorer.cpp
  barcode/barcode_decoder.cpp
  barcode/binarize.cpp
  barcode/datamatrix_locator.cpp
  barcode/temporal.cpp
  enhance/pipeline.cpp
  enhance/illumination.cpp
  enhance/morphology.cpp
  enhance/tophat.cpp
  enhance/clahe.cpp
  enhance/tone.cpp
  enhance/unsharp.cpp
  enhance/quality_gate.cpp
)

# JNI bridge is Android-only and lives in the Flutter plugin tree so iOS
# pods don't pick it up via source_files globs.
if(ANDROID)
  list(APPEND SUPY_CORE_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/../flutter/supy_scanner/android/src/main/cpp/supy_scanner_core_jni.cpp
  )
endif()

add_library(supy_scanner_core SHARED ${SUPY_CORE_SOURCES})

target_include_directories(supy_scanner_core PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/include
  ${CMAKE_CURRENT_SOURCE_DIR}
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
  # Writers are needed by the host gtest suite (synthetic-image fixtures).
  # On the device/xcframework builds where SUPY_BUILD_TESTS is OFF, leave
  # them off so the static lib stays as small as possible.
  if(SUPY_BUILD_TESTS)
    set(BUILD_WRITERS ON CACHE BOOL "" FORCE)
  else()
    set(BUILD_WRITERS OFF CACHE BOOL "" FORCE)
  endif()
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

# libdmtx — pinned to v0.7.7 (last tagged release; CMake build added upstream
# in 0.7.5). Used as a *locator only* — actual Data Matrix payload decode
# still runs through zxing-cpp on the ROI crop. See native/barcode/
# datamatrix_locator.h and the rationale block in supy_scanner.h.
# Gated behind SUPY_WITH_LIBDMTX so contributors who haven't enabled the
# vendor flag keep a green build — identical to the zxing-cpp pattern.
if(SUPY_WITH_LIBDMTX)
  include(FetchContent)
  FetchContent_Declare(
    libdmtx
    GIT_REPOSITORY https://github.com/dmtx/libdmtx.git
    GIT_TAG        v0.7.7
    GIT_SHALLOW    TRUE
  )
  FetchContent_MakeAvailable(libdmtx)
  target_link_libraries(supy_scanner_core PRIVATE dmtx)
  # libdmtx's `dmtx` CMake target exports its include dir, but some
  # generator/cache combinations leave the FetchContent source root off
  # the consumer's include path. Pin it explicitly so `#include <dmtx.h>`
  # in barcode/datamatrix_locator.cpp resolves regardless of layout.
  target_include_directories(supy_scanner_core PRIVATE
    ${libdmtx_SOURCE_DIR})
  target_compile_definitions(supy_scanner_core PRIVATE SUPY_WITH_LIBDMTX=1)
endif()

# Halide AOT — vendored libHalide 17.0.1 under third_party/halide-17.0.x/.
# When ON, swaps the Sauvola 2D path in barcode/binarize.cpp for an AOT
# kernel emitted at configure time. Gated OFF until the vendoring procedure
# in native/third_party/halide-17.0.x/README.md is completed; design lives
# in docs/V1-S2-05.2-HALIDE.md.
if(SUPY_USE_HALIDE)
  include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/FindHalide.cmake)
  include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/HalideAot.cmake)
  include(${CMAKE_CURRENT_SOURCE_DIR}/halide/targets.cmake)
  add_halide_aot_kernel(
    NAME       sauvola_2d
    GENERATOR  halide/sauvola_2d_generator.cpp
    TARGET     ${SUPY_HALIDE_TARGET})
  target_link_libraries(supy_scanner_core PRIVATE supy_halide_sauvola_2d)
  target_compile_definitions(supy_scanner_core PRIVATE SUPY_HAVE_HALIDE_SAUVOLA=1)
endif()

# GoogleTest — fetched from source when building host tests.
# Default OFF so Android NDK and iOS pod builds stay untouched.
if(SUPY_BUILD_TESTS)
  include(FetchContent)
  set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
  set(BUILD_GMOCK   OFF CACHE BOOL "" FORCE)
  FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG        v1.14.0
    GIT_SHALLOW    TRUE
  )
  FetchContent_MakeAvailable(googletest)

  add_executable(supy_scanner_core_tests
    document/document_edge_detector_test.cpp
    document/document_guidance_classifier_test.cpp
    document/perspective_warp_test.cpp
    quality/frame_scorer_test.cpp
    barcode/barcode_decoder_test.cpp
    barcode/datamatrix_locator_test.cpp
    enhance/enhance_test.cpp
  )
  target_link_libraries(supy_scanner_core_tests PRIVATE supy_scanner_core gtest gtest_main)
  target_compile_options(supy_scanner_core_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
  if(SUPY_WITH_ZXING_CPP)
    # supy_scanner_core PRIVATE-links ZXing so the symbol is reachable, but
    # the test TU also #includes zxing-cpp writer headers directly (for
    # synthetic-image fixtures) — give it the same include/link surface.
    target_link_libraries(supy_scanner_core_tests PRIVATE ZXing::ZXing)
    target_compile_definitions(supy_scanner_core_tests PRIVATE SUPY_WITH_ZXING_CPP=1)
  endif()
  if(SUPY_WITH_LIBDMTX)
    # Mirror the zxing pattern: supy_scanner_core PRIVATE-links libdmtx, so
    # the test binary doesn't need an explicit link, but the test TU branches
    # on SUPY_WITH_LIBDMTX so it must see the define.
    target_compile_definitions(supy_scanner_core_tests PRIVATE SUPY_WITH_LIBDMTX=1)
  endif()
endif()

# Host-side dev tools — bench harnesses, fuzzers, etc. Default OFF so device
# builds never pick them up.
if(SUPY_BUILD_TOOLS)
  add_executable(bench_enhance enhance/bench_enhance.cpp)
  target_link_libraries(bench_enhance PRIVATE supy_scanner_core)
  target_compile_options(bench_enhance PRIVATE -O3 -Wall -Wextra -Wpedantic -Werror)

  add_executable(bench_detect bench/bench_detect.cpp)
  target_link_libraries(bench_detect PRIVATE supy_scanner_core)
  target_include_directories(bench_detect PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
  target_compile_options(bench_detect PRIVATE -O3 -Wall -Wextra -Wpedantic -Werror)

  add_executable(bench_pipeline bench/bench_pipeline.cpp)
  target_link_libraries(bench_pipeline PRIVATE supy_scanner_core)
  target_compile_options(bench_pipeline PRIVATE -O3 -Wall -Wextra -Wpedantic -Werror)
endif()
