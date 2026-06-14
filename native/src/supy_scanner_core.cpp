#include "supy_scanner_core.h"

namespace {
constexpr const char* kSupyCoreVersion = "1.1.0-dev.1";
}

extern "C" {

const char* supy_core_version(void) {
  return kSupyCoreVersion;
}

int supy_core_abi_version(void) {
  return SUPY_CORE_ABI_VERSION;
}

}  // extern "C"
