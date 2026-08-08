// Forces the shared C++ core implementation into the iOS pod's build
// phase. CocoaPods is unreliable about compiling source files via a
// parent-directory glob (`../../../core/src/*.cpp` in source_files), but a
// Classes-local file is always built — and #including the .cpp here
// keeps the single source of truth in native/src/ for Android + dart:ffi.
//
// Under Swift Package Manager the dedicated `supy_scanner_native_core`
// C target compiles the .cpp directly; including it again here would
// produce a duplicate-symbol link error.

#if !SWIFT_PACKAGE
#include "../../../../../core/src/supy_scanner_core.cpp"
#include "../../../../../core/barcode/barcode_decoder.cpp"
#include "../../../../../core/barcode/binarize.cpp"
#include "../../../../../core/barcode/temporal.cpp"
#include "../../../../../core/barcode/datamatrix_locator.cpp"
#include "../../../../../core/document/document_guidance_classifier.cpp"
#include "../../../../../core/quality/frame_scorer.cpp"
#include "../../../../../core/enhance/pipeline.cpp"
#include "../../../../../core/enhance/illumination.cpp"
#include "../../../../../core/enhance/tone.cpp"
#include "../../../../../core/enhance/unsharp.cpp"
#include "../../../../../core/enhance/quality_gate.cpp"
#include "../../../../../core/enhance/morphology.cpp"
#include "../../../../../core/enhance/tophat.cpp"
#include "../../../../../core/enhance/clahe.cpp"
#include "../../../../../core/document/perspective_warp.cpp"
#endif
