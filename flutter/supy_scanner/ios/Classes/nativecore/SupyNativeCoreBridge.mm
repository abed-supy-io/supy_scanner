#import "SupyNativeCoreBridge.h"
#import "supy_scanner_binarize.h"
#import "supy_scanner.h"
#import "supy_scanner_enhance.h"
#import "supy_scanner_temporal.h"

#include "document_guidance_classifier.h"
#include "frame_scorer.h"

#import <CoreGraphics/CoreGraphics.h>

@implementation SupyEnhanceMetrics {
 @public
  uint32_t _appliedStages;
  int32_t _verdict;
  int32_t _processingMs;
  float _qualityScore;
}
- (uint32_t)appliedStages { return _appliedStages; }
- (int32_t)verdict { return _verdict; }
- (int32_t)processingMs { return _processingMs; }
- (float)qualityScore { return _qualityScore; }
@end

@implementation SupyPageScore {
 @public
  float _blurScore;
  float _qualityScore;
  int32_t _bucket;
}
- (float)blurScore { return _blurScore; }
- (float)qualityScore { return _qualityScore; }
- (int32_t)bucket { return _bucket; }
@end

@implementation SupyNativeBarcode {
 @public
  NSString *_rawValue;
  NSString *_format;
  CGPoint _topLeft;
  CGPoint _topRight;
  CGPoint _bottomRight;
  CGPoint _bottomLeft;
}
- (NSString *)rawValue { return _rawValue; }
- (NSString *)format { return _format; }
- (CGPoint)topLeft { return _topLeft; }
- (CGPoint)topRight { return _topRight; }
- (CGPoint)bottomRight { return _bottomRight; }
- (CGPoint)bottomLeft { return _bottomLeft; }
@end

// Mirrors the SUPY_FORMAT_* → wire-name table in
// `android/.../barcode/FormatMapper.kt#supyBitToWire`. Keep in sync with
// `docs/SYMBOLOGIES.md`.
static NSString *SupyFormatBitToWire(uint32_t bit) {
  switch (bit) {
    case SUPY_FORMAT_QR_CODE: return @"qr";
    case SUPY_FORMAT_EAN_13: return @"ean13";
    case SUPY_FORMAT_EAN_8: return @"ean8";
    case SUPY_FORMAT_UPC_A: return @"upcA";
    case SUPY_FORMAT_UPC_E: return @"upcE";
    case SUPY_FORMAT_CODE_39: return @"code39";
    case SUPY_FORMAT_CODE_93: return @"code93";
    case SUPY_FORMAT_CODE_128: return @"code128";
    case SUPY_FORMAT_ITF: return @"itf";
    case SUPY_FORMAT_PDF_417: return @"pdf417";
    case SUPY_FORMAT_DATA_MATRIX: return @"dataMatrix";
    case SUPY_FORMAT_AZTEC: return @"aztec";
    case SUPY_FORMAT_CODABAR: return @"codabar";
    default: return @"all";
  }
}

@implementation SupyDocumentGuidance {
  supy::scanner::document::GuidanceState *_state;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _state = new supy::scanner::document::GuidanceState();
  }
  return self;
}

- (void)dealloc {
  delete _state;
  _state = nullptr;
}

- (void)reset {
  if (_state != nullptr) _state->reset();
}

// Unpacks `config` by index exactly as `nativeGuidanceClassify` does in
// `supy_scanner_core_jni.cpp` — the float[18] order is wire-coupled to
// `GuidanceConfig.toFloatArray()` (Kotlin) and `GuidanceConfig.toNumberArray()`
// (Swift). Keep all three in sync.
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
                                      config:(NSArray<NSNumber *> *)config {
  if (_state == nullptr || config.count < 19) {
    return @[ @0, @0 ];
  }

  supy::scanner::document::FrameMetrics raw{};
  raw.hasDocument = hasDocument == YES;
  raw.clipsEdge = clipsEdge == YES;
  raw.coverageRatio = coverage;
  raw.tiltDegrees = tilt;
  raw.meanLuma = luma;
  raw.blurScore = blur;
  raw.quadStability = stability;
  raw.interiorVariance = interior;
  raw.glareRatio = glareRatio;
  raw.cornerVelocity = cornerVelocity;
  raw.centerOffsetX = centerOffsetX;
  raw.centerOffsetY = centerOffsetY;
  if (perCornerStability.count == 4) {
    raw.perCornerStability = {
        perCornerStability[0].floatValue, perCornerStability[1].floatValue,
        perCornerStability[2].floatValue, perCornerStability[3].floatValue};
    raw.hasPerCornerStability = true;
  } else {
    raw.hasPerCornerStability = false;
  }

  supy::scanner::document::GuidanceConfig cfg{};
  cfg.minCoverageRatio = config[0].floatValue;
  cfg.maxCoverageRatio = config[1].floatValue;
  cfg.maxTiltDegrees = config[2].floatValue;
  cfg.minMeanLuma = config[3].floatValue;
  cfg.minBlurScore = config[4].floatValue;
  cfg.readyStabilityFloor = config[5].floatValue;
  cfg.interiorVarianceFloor = config[6].floatValue;
  cfg.exitMargin = config[7].floatValue;
  cfg.smoothingAlpha = config[8].floatValue;
  cfg.readyStableFrames = static_cast<int>(config[9].floatValue);
  cfg.holdSteadyFrames = static_cast<int>(config[10].floatValue);
  cfg.lostDocumentGraceFrames = static_cast<int>(config[11].floatValue);
  cfg.minDwellFrames = static_cast<int>(config[12].floatValue);
  cfg.maxGlareRatio = config[13].floatValue;
  cfg.glareExitMargin = config[14].floatValue;
  cfg.maxCornerVelocity = config[15].floatValue;
  cfg.minPerCornerStability = config[16].floatValue;
  cfg.edgeClipBlocking = config[17].floatValue != 0.0f;
  cfg.maxCenterOffset = config[18].floatValue;

  const auto result =
      supy::scanner::document::classify(raw, cfg, *_state, nullptr);
  return @[ @(static_cast<int>(result)), @(_state->liveQualityScore) ];
}

@end

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

+ (UIImage *)enhanceImage:(UIImage *)image
                     mode:(SupyEnhanceMode)mode
                  metrics:(SupyEnhanceMetrics * _Nullable * _Nullable)outMetrics {
  if (outMetrics != NULL) *outMetrics = nil;
  if (image == nil || mode == SupyEnhanceModeOff) return image;
  CGImageRef cg = image.CGImage;
  if (cg == NULL) return image;
  const size_t width = CGImageGetWidth(cg);
  const size_t height = CGImageGetHeight(cg);
  if (width == 0 || height == 0) return image;

  // Render into a tightly packed RGBA8888 buffer regardless of the source
  // color space / alpha info — the enhance pipeline expects straight RGBA.
  const size_t rowStride = width * 4;
  const size_t byteCount = rowStride * height;
  uint8_t *bytes = (uint8_t *)calloc(byteCount, 1);
  if (bytes == NULL) return image;

  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGContextRef ctx = CGBitmapContextCreate(
      bytes, width, height, 8, rowStride, colorSpace,
      kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
  CGColorSpaceRelease(colorSpace);
  if (ctx == NULL) {
    free(bytes);
    return image;
  }
  CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), cg);

  supy_enhance_input_t in = {0};
  in.rgba = bytes;
  in.width = (int32_t)width;
  in.height = (int32_t)height;
  in.row_stride = (int32_t)rowStride;
  in.mode = (supy_enhance_mode_t)mode;
  in.min_blur_score = 0.0f;

  supy_enhance_result_t *handle = supy_core_enhance(&in);
  if (handle == NULL) {
    CGContextRelease(ctx);
    free(bytes);
    return image;
  }

  // Copy enhanced pixels back into the bitmap context's backing store so the
  // resulting CGImage reflects the enhancement.
  const uint8_t *outRgba = supy_core_enhance_rgba(handle);
  const int32_t outStride = supy_core_enhance_row_stride(handle);
  for (size_t y = 0; y < height; ++y) {
    memcpy(bytes + y * rowStride, outRgba + y * (size_t)outStride, width * 4);
  }

  if (outMetrics != NULL) {
    SupyEnhanceMetrics *m = [[SupyEnhanceMetrics alloc] init];
    m->_appliedStages = supy_core_enhance_applied_stages(handle);
    m->_verdict = supy_core_enhance_verdict(handle);
    m->_processingMs = supy_core_enhance_processing_ms(handle);
    m->_qualityScore = supy_core_enhance_quality_score(handle);
    *outMetrics = m;
  }
  supy_core_enhance_free(handle);

  CGImageRef enhancedCG = CGBitmapContextCreateImage(ctx);
  CGContextRelease(ctx);
  free(bytes);
  if (enhancedCG == NULL) return image;

  UIImage *result = [UIImage imageWithCGImage:enhancedCG
                                        scale:image.scale
                                  orientation:image.imageOrientation];
  CGImageRelease(enhancedCG);
  return result;
}

+ (nullable SupyPageScore *)scoreImage:(UIImage *)image {
  if (image == nil) return nil;
  CGImageRef cg = image.CGImage;
  if (cg == NULL) return nil;
  const size_t width = CGImageGetWidth(cg);
  const size_t height = CGImageGetHeight(cg);
  if (width == 0 || height == 0) return nil;

  const size_t rowStride = width * 4;
  const size_t byteCount = rowStride * height;
  uint8_t *bytes = (uint8_t *)calloc(byteCount, 1);
  if (bytes == NULL) return nil;

  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGContextRef ctx = CGBitmapContextCreate(
      bytes, width, height, 8, rowStride, colorSpace,
      kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
  CGColorSpaceRelease(colorSpace);
  if (ctx == NULL) {
    free(bytes);
    return nil;
  }
  CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), cg);
  CGContextRelease(ctx);

  supy_score_input_t in = {0};
  in.rgba = bytes;
  in.width = (int32_t)width;
  in.height = (int32_t)height;
  in.row_stride = (int32_t)rowStride;

  supy_score_result_t r = {0};
  const int32_t ok = supy_core_score_page(&in, &r);
  free(bytes);
  if (ok != 1) return nil;

  SupyPageScore *score = [[SupyPageScore alloc] init];
  score->_blurScore = r.blur_score;
  score->_qualityScore = r.quality_score;
  score->_bucket = r.bucket;
  return score;
}

+ (NSDictionary<NSString *, NSNumber *> *)
    scoreLumaPlane:(const uint8_t *)luma
             width:(int32_t)width
            height:(int32_t)height
         rowStride:(int32_t)rowStride {
  const auto m = supy::scanner::quality::compute_luma_metrics(
      luma, width, height, rowStride);
  return @{
    @"meanLuma": @(m.mean_luma),
    @"blurScore": @(m.blur_score),
  };
}

+ (BOOL)hasZxing {
  return supy_core_has_zxing() == 1;
}

+ (BOOL)hasLibdmtx {
  return supy_core_has_libdmtx() == 1;
}

+ (BOOL)binarizeLumaInPlace:(uint8_t *)luma
                      width:(int32_t)width
                     height:(int32_t)height
                  rowStride:(int32_t)rowStride
                       mode:(SupyBinarizeMode)mode {
  if (luma == NULL || width <= 0 || height <= 0 || rowStride < width) {
    return NO;
  }
  const int ok = supy_core_binarize_luma(
      luma, width, height, rowStride, (supy_binarize_mode_t)mode);
  return ok == 1 ? YES : NO;
}

+ (BOOL)temporalMedianLuma3:(const uint8_t *)frame0
                     frame1:(const uint8_t *)frame1
                     frame2:(const uint8_t *)frame2
                        out:(uint8_t *)out
                      width:(int32_t)width
                     height:(int32_t)height
                  rowStride:(int32_t)rowStride {
  if (frame0 == NULL || frame1 == NULL || frame2 == NULL || out == NULL) {
    return NO;
  }
  if (width <= 0 || height <= 0 || rowStride < width) {
    return NO;
  }
  const int ok = supy_core_temporal_median_luma(
      frame0, frame1, frame2, out, width, height, rowStride);
  return ok == 1 ? YES : NO;
}

+ (nullable NSArray<NSArray<NSNumber *> *> *)
    locateDatamatrixFromLuma:(const uint8_t *)luma
                       width:(int32_t)width
                      height:(int32_t)height
                   rowStride:(int32_t)rowStride
                  maxRegions:(int32_t)maxRegions
                   timeoutMs:(int32_t)timeoutMs {
  if (supy_core_has_libdmtx() != 1) return nil;
  if (luma == NULL || width <= 0 || height <= 0 || rowStride < width) {
    return nil;
  }

  supy_core_locate_input_t in = {0};
  in.luma = luma;
  in.width = width;
  in.height = height;
  in.row_stride = rowStride;
  in.max_regions = maxRegions > 0 ? maxRegions : 4;
  in.timeout_ms = timeoutMs > 0 ? timeoutMs : 0;

  supy_core_locate_result_t *handle = supy_core_locate_datamatrix(&in);
  if (handle == NULL) return nil;

  const int32_t count = supy_core_locate_count(handle);
  NSMutableArray<NSArray<NSNumber *> *> *out =
      [NSMutableArray arrayWithCapacity:(NSUInteger)count];
  for (int32_t i = 0; i < count; ++i) {
    float xy[8] = {0};
    if (supy_core_locate_corners(handle, i, xy) != 1) continue;
    NSArray<NSNumber *> *quad = @[
      @(xy[0]), @(xy[1]),
      @(xy[2]), @(xy[3]),
      @(xy[4]), @(xy[5]),
      @(xy[6]), @(xy[7]),
    ];
    [out addObject:quad];
  }
  supy_core_locate_results_free(handle);
  return out;
}

+ (nullable NSArray<SupyNativeBarcode *> *)
    decodeBarcodesFromLuma:(const uint8_t *)luma
                     width:(int32_t)width
                    height:(int32_t)height
                 rowStride:(int32_t)rowStride
                   formats:(uint32_t)formatMask
                 tryHarder:(BOOL)tryHarder
                 tryRotate:(BOOL)tryRotate {
  if (supy_core_has_zxing() != 1) return nil;
  if (luma == NULL || width <= 0 || height <= 0 || rowStride < width) {
    return nil;
  }

  supy_core_decode_input_t in = {0};
  in.luma = luma;
  in.width = width;
  in.height = height;
  in.row_stride = rowStride;
  in.formats = formatMask == SUPY_FORMAT_NONE ? SUPY_FORMAT_ALL : formatMask;
  in.try_harder = tryHarder ? 1 : 0;
  in.try_rotate = tryRotate ? 1 : 0;

  supy_core_decode_result_t *handle = supy_core_decode(&in);
  if (handle == NULL) return nil;

  const int32_t count = supy_core_decode_count(handle);
  NSMutableArray<SupyNativeBarcode *> *out = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
  for (int32_t i = 0; i < count; ++i) {
    const char *cstr = supy_core_decode_text(handle, i);
    if (cstr == NULL) continue;
    NSString *raw = [NSString stringWithUTF8String:cstr];
    if (raw == nil) continue;

    const uint32_t bit = supy_core_decode_format(handle, i);
    float xy[8] = {0};
    const int32_t okCorners = supy_core_decode_corners(handle, i, xy);

    SupyNativeBarcode *b = [[SupyNativeBarcode alloc] init];
    b->_rawValue = raw;
    b->_format = SupyFormatBitToWire(bit);
    if (okCorners == 1) {
      b->_topLeft = CGPointMake(xy[0], xy[1]);
      b->_topRight = CGPointMake(xy[2], xy[3]);
      b->_bottomRight = CGPointMake(xy[4], xy[5]);
      b->_bottomLeft = CGPointMake(xy[6], xy[7]);
    } else {
      const CGPoint zero = CGPointZero;
      b->_topLeft = zero;
      b->_topRight = zero;
      b->_bottomRight = zero;
      b->_bottomLeft = zero;
    }
    [out addObject:b];
  }

  supy_core_decode_results_free(handle);
  return out;
}

@end
