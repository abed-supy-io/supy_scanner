#import "SupyNativeCoreBridge.h"
#import "supy_scanner_core.h"

@implementation SupyNativeCoreBridge

+ (NSString *)version {
  const char *cstr = supy_core_version();
  if (cstr == NULL) {
    return @"";
  }
  return [NSString stringWithUTF8String:cstr];
}

+ (int32_t)abiVersion {
  return supy_core_abi_version();
}

@end
