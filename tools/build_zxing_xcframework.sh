#!/usr/bin/env bash
# tools/build_zxing_xcframework.sh
#
# Builds a fat static xcframework for zxing-cpp (pinned to the tag in
# core/CMakeLists.txt) covering `iphoneos` + `iphonesimulator` (arm64
# device + arm64/x86_64 simulator slices). Output:
#
#   flutter/supy_scanner/ios/Vendor/ZXing.xcframework
#
# Consumed by flutter/supy_scanner/ios/supy_scanner.podspec via `s.vendored_frameworks` (gated
# on the framework existing on disk — see the podspec for the gate logic).
#
# This script is the V1-S2-02 execution side of the decision logged in
# TODO.md. The Sprint 1 build path stays untouched until the script has
# been run AND the podspec gate flips — building this xcframework does
# NOT by itself wire zxing-cpp into the runtime, see V1-S2-03.
#
# Pre-flight:
#   - macOS host
#   - Xcode 15+ (`xcrun --find xcodebuild` resolves)
#   - CMake 3.22+ on PATH
#
# Idempotency: re-runs short-circuit if the xcframework exists AND the
# stamp file under build/ios-zxing/.stamp matches the pinned zxing-cpp
# tag from core/CMakeLists.txt. Pass --force to rebuild unconditionally.

set -euo pipefail

# Resolve paths from script location so the script works from any CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NATIVE_DIR="${REPO_ROOT}/core"
# The plugin (and its ios/ tree) moved under flutter/supy_scanner/ in the
# monorepo restructure; core/ and tools/ stayed at the repo root. The
# xcframework must land where the podspec (#{__dir__}/Vendor) looks for it.
OUT_DIR="${REPO_ROOT}/flutter/supy_scanner/ios/Vendor"
BUILD_ROOT="${REPO_ROOT}/build/ios-zxing"
XCF_PATH="${OUT_DIR}/ZXing.xcframework"
STAMP="${BUILD_ROOT}/.stamp"

FORCE=0
for arg in "$@"; do
  case "${arg}" in
    --force) FORCE=1 ;;
    -h|--help)
      sed -n '1,40p' "${BASH_SOURCE[0]}" | sed -n 's/^# \{0,1\}//p'
      exit 0
      ;;
    *)
      echo "build_zxing_xcframework.sh: unknown arg: ${arg}" >&2
      exit 2
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "build_zxing_xcframework.sh: macOS host required (uname=$(uname -s))." >&2
  exit 1
fi

for bin in cmake xcrun xcodebuild; do
  if ! command -v "${bin}" >/dev/null 2>&1; then
    echo "build_zxing_xcframework.sh: '${bin}' not on PATH." >&2
    exit 1
  fi
done

# Extract the pinned tag from core/CMakeLists.txt so the script and CMake
# can't drift. Single source of truth is the FetchContent_Declare GIT_TAG.
ZXING_TAG="$(awk '
  /FetchContent_Declare\(\s*$/      { in_decl = 1 }
  in_decl && /zxing-cpp/            { is_zxing = 1 }
  in_decl && is_zxing && /GIT_TAG/  { print $2; exit }
' "${NATIVE_DIR}/CMakeLists.txt" | tr -d '[:space:]')"

if [[ -z "${ZXING_TAG}" ]]; then
  echo "build_zxing_xcframework.sh: could not extract GIT_TAG for zxing-cpp from ${NATIVE_DIR}/CMakeLists.txt." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Idempotency short-circuit
# ---------------------------------------------------------------------------

if [[ ${FORCE} -eq 0 && -d "${XCF_PATH}" && -f "${STAMP}" ]]; then
  if [[ "$(cat "${STAMP}")" == "${ZXING_TAG}" ]]; then
    echo "build_zxing_xcframework.sh: up to date (tag=${ZXING_TAG}). Pass --force to rebuild."
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Build per-arch static libs
# ---------------------------------------------------------------------------
#
# We build TWO CMake trees (one per Apple sysroot) and let CMake's iOS
# toolchain handle the multi-arch within the simulator tree. iOS 16 deploy
# target matches the podspec floor.

DEPLOY_TARGET="16.0"

build_arch() {
  local arch_label="$1"   # device | simulator
  local sysroot="$2"      # iphoneos | iphonesimulator
  local archs="$3"        # CMAKE_OSX_ARCHITECTURES value (";"-separated)
  local build_dir="${BUILD_ROOT}/${arch_label}"

  echo "==> Configuring ${arch_label} (sysroot=${sysroot}, archs=${archs})"
  cmake -S "${NATIVE_DIR}" -B "${build_dir}" \
    -G "Unix Makefiles" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="${sysroot}" \
    -DCMAKE_OSX_ARCHITECTURES="${archs}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${DEPLOY_TARGET}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DSUPY_WITH_ZXING_CPP=ON \
    -DSUPY_BUILD_TESTS=OFF \
    -DBUILD_WRITERS=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_BLACKBOX_TESTS=OFF \
    -DBUILD_UNIT_TESTS=OFF

  echo "==> Building ZXing (${arch_label})"
  cmake --build "${build_dir}" --target ZXing --config Release -- -j "$(sysctl -n hw.ncpu)"

  # The static lib path inside zxing-cpp's FetchContent populate is
  # _deps/zxing-cpp-build/core/libZXing.a — tested against v2.2.1. If the
  # upstream layout changes, this script breaks loudly (file-not-found),
  # which is what we want.
  local lib="${build_dir}/_deps/zxing-cpp-build/core/libZXing.a"
  if [[ ! -f "${lib}" ]]; then
    echo "build_zxing_xcframework.sh: expected static lib not produced: ${lib}" >&2
    echo "                            (zxing-cpp tag ${ZXING_TAG} may have changed its build layout — verify and update the path)." >&2
    exit 1
  fi
  echo "${lib}"
}

DEVICE_LIB="$(build_arch device     iphoneos        'arm64')"
SIM_LIB="$(   build_arch simulator  iphonesimulator 'arm64;x86_64')"

# zxing-cpp installs its public headers into _deps/zxing-cpp-src/core/src.
# For an xcframework we want one stable include root; copy them into a
# clean staging dir so the xcframework manifest can point at it.
HEADERS_SRC="${BUILD_ROOT}/device/_deps/zxing-cpp-src/core/src"
HEADERS_STAGED="${BUILD_ROOT}/Headers"
rm -rf "${HEADERS_STAGED}"
mkdir -p "${HEADERS_STAGED}"
# Copy only the public ZXing/*.h surface — internal headers stay in the
# build tree. Upstream keeps the public API directly under core/src so a
# top-level *.h copy is the right scope; if upstream restructures, this
# script will surface that as a missing-include at podspec-consume time.
cp -R "${HEADERS_SRC}/." "${HEADERS_STAGED}/"

# ---------------------------------------------------------------------------
# Assemble xcframework
# ---------------------------------------------------------------------------

echo "==> Creating ${XCF_PATH}"
mkdir -p "${OUT_DIR}"
rm -rf "${XCF_PATH}"
xcodebuild -create-xcframework \
  -library "${DEVICE_LIB}" -headers "${HEADERS_STAGED}" \
  -library "${SIM_LIB}"    -headers "${HEADERS_STAGED}" \
  -output "${XCF_PATH}"

echo "${ZXING_TAG}" > "${STAMP}"

echo
echo "build_zxing_xcframework.sh: built ${XCF_PATH} for tag ${ZXING_TAG}."
echo "Next:"
echo "  1. cd example/ios && pod install   # pod picks up Vendor/ZXing.xcframework"
echo "  2. Build the example app — confirms the linker resolves ZXing symbols."
echo "  3. Wire the decode path (V1-S2-03)."
