# targets.cmake — maps the active build's ABI to the Halide Target string
# that the AOT generator should emit objects for.
#
# Sets SUPY_HALIDE_TARGET in the parent scope. Errors out for unsupported
# combinations rather than silently producing a host-tuned kernel.
#
# Reference: https://halide-lang.org/docs/struct_halide_1_1_target.html

if(ANDROID)
  if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(SUPY_HALIDE_TARGET "arm-64-android" PARENT_SCOPE)
  elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
    set(SUPY_HALIDE_TARGET "arm-32-android" PARENT_SCOPE)
  elseif(ANDROID_ABI STREQUAL "x86_64")
    set(SUPY_HALIDE_TARGET "x86-64-android" PARENT_SCOPE)
  elseif(ANDROID_ABI STREQUAL "x86")
    # x86 (32-bit) Android is shipped by Flutter but rarely seen on a real
    # device. We emit a target for build-system completeness.
    set(SUPY_HALIDE_TARGET "x86-32-android" PARENT_SCOPE)
  else()
    message(FATAL_ERROR
      "SUPY_USE_HALIDE: unsupported ANDROID_ABI '${ANDROID_ABI}'")
  endif()
elseif(IOS OR (APPLE AND CMAKE_SYSTEM_NAME STREQUAL "iOS"))
  set(SUPY_HALIDE_TARGET "arm-64-ios" PARENT_SCOPE)
elseif(APPLE)
  # Host macOS build (tests + bench). Match host arch.
  if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
    set(SUPY_HALIDE_TARGET "arm-64-osx" PARENT_SCOPE)
  else()
    set(SUPY_HALIDE_TARGET "x86-64-osx" PARENT_SCOPE)
  endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  set(SUPY_HALIDE_TARGET "x86-64-linux" PARENT_SCOPE)
else()
  message(FATAL_ERROR
    "SUPY_USE_HALIDE: unsupported target platform '${CMAKE_SYSTEM_NAME}'")
endif()
