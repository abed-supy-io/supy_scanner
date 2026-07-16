// Obj-C wrapper over the C ABI of the supy_scanner native core.
// Swift talks to this class instead of calling supy_core_* directly because
// CocoaPods' auto-generated umbrella module doesn't reliably expose C
// symbols declared in parent-directory headers to in-module Swift files.
// An Obj-C class in Classes/ always lands in the umbrella the normal way.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Mirrors `supy_enhance_mode_t` in `supy_scanner_enhance.h`.
typedef NS_ENUM(int32_t, SupyEnhanceMode) {
  SupyEnhanceModeOff      = 0,
  SupyEnhanceModeFast     = 1,
  SupyEnhanceModeBalanced = 2,
  SupyEnhanceModeMax      = 3,
};

/// Diagnostics returned alongside the enhanced image.
@interface SupyEnhanceMetrics : NSObject
@property (nonatomic, readonly) uint32_t appliedStages;
/// 0 = ok, 1 = marginal, 2 = reject.
@property (nonatomic, readonly) int32_t verdict;
@property (nonatomic, readonly) int32_t processingMs;
@property (nonatomic, readonly) float qualityScore;
@end

/// Standalone per-page quality score. Mirrors `supy_score_result_t`.
@interface SupyPageScore : NSObject
@property (nonatomic, readonly) float blurScore;
/// Normalized 0..1 sharpness.
@property (nonatomic, readonly) float qualityScore;
/// 0=veryPoor .. 4=excellent.
@property (nonatomic, readonly) int32_t bucket;
@end

/// Single decoded barcode from `supy_core_decode`. Corners are in input-image
/// pixel space (top-left origin), TL/TR/BR/BL order — matches the C ABI
/// contract documented in `supy_scanner_core.h`.
@interface SupyNativeBarcode : NSObject
@property (nonatomic, readonly) NSString *rawValue;
/// Wire-format name (camelCase, matches `SupyBarcodeFormat`).
@property (nonatomic, readonly) NSString *format;
@property (nonatomic, readonly) CGPoint topLeft;
@property (nonatomic, readonly) CGPoint topRight;
@property (nonatomic, readonly) CGPoint bottomRight;
@property (nonatomic, readonly) CGPoint bottomLeft;
@end

/// Stateful wrapper over the C++ `supy::scanner::document` guidance classifier.
/// Owns a heap-allocated `GuidanceState` for its lifetime — ARC frees it in
/// `-dealloc`, so callers just hold the instance instead of a raw handle. This
/// is the iOS equivalent of Android's Kotlin-owned `jlong` handle
/// (`SupyNativeCore.nativeGuidanceCreate`); behaviour is identical.
@interface SupyDocumentGuidance : NSObject

/// Resets the classifier to its initial NoDocument step.
- (void)reset;

/// Classifies a single frame. Mirrors the JNI signature in
/// `supy_scanner_core_jni.cpp#nativeGuidanceClassify`: discrete metrics plus a
/// 19-element [config] in `GuidanceConfig.toFloatArray()` order, and a
/// [perCornerStability] array of length 0 (no per-corner signal this frame —
/// the classifier holds its prior occlusion judgement) or 4 (TL/TR/BR/BL).
/// Returns `@[stateOrdinal, liveQualityScore]`; returns `@[@0, @0]` on bad
/// input (config shorter than 19), matching the defensive Android path.
- (NSArray<NSNumber *> *)classifyHasDocument:(BOOL)hasDocument
                                   clipsEdge:(BOOL)clipsEdge
                                    coverage:(float)coverage
                                        tilt:(float)tilt
                                        luma:(float)luma
                                        blur:(float)blur
                                   stability:(float)stability
                                    interior:(float)interior
                                  glareRatio:(float)glareRatio
                              cornerVelocity:(float)cornerVelocity
                               centerOffsetX:(float)centerOffsetX
                               centerOffsetY:(float)centerOffsetY
                          perCornerStability:(NSArray<NSNumber *> *)perCornerStability
                                      config:(NSArray<NSNumber *> *)config;

@end

@interface SupyNativeCoreBridge : NSObject

+ (NSString *)version;
+ (int32_t)abiVersion;

/// Runs the native enhance pipeline on [image]. Returns the original image
/// (and nil metrics) when [mode] is Off or the native call fails.
+ (UIImage *)enhanceImage:(UIImage *)image
                     mode:(SupyEnhanceMode)mode
                  metrics:(SupyEnhanceMetrics * _Nullable * _Nullable)outMetrics;

/// Scores [image] with the native variance-of-Laplacian gate. Returns nil if
/// the image can't be rasterized or the native call fails — callers then
/// emit `quality == null` on the page, matching v1.0 behavior.
+ (nullable SupyPageScore *)scoreImage:(UIImage *)image;

/// 1 if the build linked zxing-cpp (mirror of `supy_core_has_zxing`).
+ (BOOL)hasZxing;

/// 1 if the build linked libdmtx (mirror of `supy_core_has_libdmtx`).
+ (BOOL)hasLibdmtx;

/// Mirrors `supy_binarize_mode_t`.
typedef NS_ENUM(int32_t, SupyBinarizeMode) {
  SupyBinarizeModeSauvola2D     = 0,
  SupyBinarizeModeWolfJolion1D  = 1,
};

/// In-place adaptive binarization on a packed (or padded) luma buffer.
/// Returns YES on success. Output bytes are 0 or 255. Caller owns [luma].
+ (BOOL)binarizeLumaInPlace:(uint8_t *)luma
                      width:(int32_t)width
                     height:(int32_t)height
                  rowStride:(int32_t)rowStride
                       mode:(SupyBinarizeMode)mode;

/// Per-pixel median-of-three across same-geometry luma crops. All four buffers
/// MUST share width, height, and row_stride; [out] may not alias any input.
/// Returns YES on success.
+ (BOOL)temporalMedianLuma3:(const uint8_t *)frame0
                     frame1:(const uint8_t *)frame1
                     frame2:(const uint8_t *)frame2
                        out:(uint8_t *)out
                      width:(int32_t)width
                     height:(int32_t)height
                  rowStride:(int32_t)rowStride;

/// Scans the luma plane for Data Matrix regions. Returns one quad per region
/// (8 floats: TL.x, TL.y, TR.x, TR.y, BR.x, BR.y, BL.x, BL.y) in input-image
/// pixel space. Returns nil if the build did not link libdmtx, the input is
/// invalid, or the native call fails. An empty array means the locate ran
/// successfully and found no regions.
+ (nullable NSArray<NSArray<NSNumber *> *> *)
    locateDatamatrixFromLuma:(const uint8_t *)luma
                       width:(int32_t)width
                      height:(int32_t)height
                   rowStride:(int32_t)rowStride
                  maxRegions:(int32_t)maxRegions
                   timeoutMs:(int32_t)timeoutMs;

/// Per-frame luma quality scoring — Phase FQS.
///
/// Computes mean luma + variance-of-Laplacian (`blurScore`) over a center-crop
/// downsample of [luma], matching the algorithm previously inlined in
/// `DocumentDetector.computeLumaMetrics`. Single source of truth so Android
/// (via JNI) and iOS see identical numbers feeding the C++ guidance classifier.
///
/// Returns a dictionary with two `NSNumber` doubles:
///   - `@"meanLuma"`:  0..255 arithmetic mean of sampled Y values.
///   - `@"blurScore"`: variance-of-Laplacian, ≥ 0. Higher = sharper.
/// Both keys are always present. Returns zeros on degenerate input
/// (null buffer, sub-3×3 sample grid, bad dimensions).
+ (NSDictionary<NSString *, NSNumber *> *)
    scoreLumaPlane:(const uint8_t *)luma
             width:(int32_t)width
            height:(int32_t)height
         rowStride:(int32_t)rowStride;

/// Decodes barcodes from a luminance plane. The caller owns [luma] and must
/// keep it valid for the duration of the call (e.g. lock the CVPixelBuffer
/// Y-plane base address and unlock after this method returns).
///
/// Returns an empty array on no detections (steady state) and nil if the
/// build did not link zxing-cpp or the input is invalid.
+ (nullable NSArray<SupyNativeBarcode *> *)
    decodeBarcodesFromLuma:(const uint8_t *)luma
                     width:(int32_t)width
                    height:(int32_t)height
                 rowStride:(int32_t)rowStride
                   formats:(uint32_t)formatMask
                 tryHarder:(BOOL)tryHarder
                 tryRotate:(BOOL)tryRotate;

@end

NS_ASSUME_NONNULL_END
