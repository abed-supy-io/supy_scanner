# FindHalide.cmake — resolves the vendored libHalide tree under
# native/third_party/halide-17.0.x/<host-triple>/ and exposes it as the
# IMPORTED target Halide::Halide.
#
# Active only when SUPY_USE_HALIDE=ON (see native/CMakeLists.txt). Fails
# loudly with a contributor-actionable message when the vendored tree
# isn't present rather than silently falling back to a system Halide.

set(SUPY_HALIDE_VENDOR_ROOT
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/halide-17.0.x")

# Resolve the host triple — the generator is a host-arch binary built on
# whichever machine is configuring the build (developer laptop or CI).
if(CMAKE_HOST_APPLE)
  if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
    set(_supy_halide_host "darwin-arm64")
  else()
    set(_supy_halide_host "darwin-x86_64")
  endif()
elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
  set(_supy_halide_host "linux-x86_64")
else()
  message(FATAL_ERROR
    "SUPY_USE_HALIDE: unsupported host system '${CMAKE_HOST_SYSTEM_NAME}'."
    " Supported hosts: macOS arm64/x86_64, Linux x86_64.")
endif()

set(SUPY_HALIDE_HOST_ROOT "${SUPY_HALIDE_VENDOR_ROOT}/${_supy_halide_host}")

if(NOT EXISTS "${SUPY_HALIDE_HOST_ROOT}/include/Halide.h")
  message(FATAL_ERROR
    "SUPY_USE_HALIDE=ON but Halide vendor tree is missing:\n"
    "  expected: ${SUPY_HALIDE_HOST_ROOT}/include/Halide.h\n"
    "Run the vendoring procedure documented in\n"
    "  native/third_party/halide-17.0.x/README.md\n"
    "before enabling SUPY_USE_HALIDE.")
endif()

# Locate the shared library. Halide ships .dylib on macOS and .so on Linux.
find_library(SUPY_HALIDE_LIB
  NAMES Halide
  PATHS "${SUPY_HALIDE_HOST_ROOT}/lib"
  NO_DEFAULT_PATH
  REQUIRED)

# Locate the generator-runtime support library `Halide_tools` (provides
# `Halide::Generator` main). Halide 17 ships it as a static archive next
# to libHalide.
find_library(SUPY_HALIDE_GENERATOR_RT
  NAMES Halide_Generator
  PATHS "${SUPY_HALIDE_HOST_ROOT}/lib"
  NO_DEFAULT_PATH)

# Locate the GenGen entry-point object. Halide ships either a static
# `GenGen.o` under `share/Halide/tools/` or a CMake helper that pulls it
# in. We prefer the latter; the former is the fallback.
set(SUPY_HALIDE_GENGEN_CPP
    "${SUPY_HALIDE_HOST_ROOT}/share/Halide/tools/GenGen.cpp")
if(NOT EXISTS "${SUPY_HALIDE_GENGEN_CPP}")
  message(FATAL_ERROR
    "SUPY_USE_HALIDE: expected GenGen.cpp at ${SUPY_HALIDE_GENGEN_CPP}."
    " The vendored Halide tree appears incomplete — re-extract the"
    " release tarball into ${SUPY_HALIDE_HOST_ROOT}.")
endif()

add_library(Halide::Halide SHARED IMPORTED)
set_target_properties(Halide::Halide PROPERTIES
  IMPORTED_LOCATION "${SUPY_HALIDE_LIB}"
  INTERFACE_INCLUDE_DIRECTORIES "${SUPY_HALIDE_HOST_ROOT}/include")

# Halide 17 binaries are built with libc++ on macOS and libstdc++ on Linux.
# The generator binary we build (host-arch) must match — this is automatic
# because we don't override the host toolchain, but record the fact here
# for future debugging.
message(STATUS "Halide vendor tree: ${SUPY_HALIDE_HOST_ROOT}")
message(STATUS "Halide library:     ${SUPY_HALIDE_LIB}")
