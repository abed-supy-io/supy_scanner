// Obj-C wrapper over the C ABI of the supy_scanner native core.
// Swift talks to this class instead of calling supy_core_* directly because
// CocoaPods' auto-generated umbrella module doesn't reliably expose C
// symbols declared in parent-directory headers to in-module Swift files.
// An Obj-C class in Classes/ always lands in the umbrella the normal way.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SupyNativeCoreBridge : NSObject

+ (NSString *)version;
+ (int32_t)abiVersion;

@end

NS_ASSUME_NONNULL_END
