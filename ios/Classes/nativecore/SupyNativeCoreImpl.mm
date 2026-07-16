// Forces the shared C++ core implementation into the iOS pod's build
// phase. CocoaPods is unreliable about compiling source files via a
// parent-directory glob (`../native/src/*.cpp` in source_files), but a
// Classes-local file is always built — and #including the .cpp here
// keeps the single source of truth in native/src/ for Android + dart:ffi.
//
// Under Swift Package Manager the dedicated `supy_scanner_native_core`
// C target compiles the .cpp directly; including it again here would
// produce a duplicate-symbol link error.

#if !SWIFT_PACKAGE
#include "../../../native/src/supy_scanner_core.cpp"
#include "../../../native/barcode/barcode_decoder.cpp"
#include "../../../native/barcode/binarize.cpp"
#include "../../../native/barcode/temporal.cpp"
#include "../../../native/barcode/datamatrix_locator.cpp"
#include "../../../native/document/document_guidance_classifier.cpp"
#include "../../../native/quality/frame_scorer.cpp"
#include "../../../native/enhance/pipeline.cpp"
#include "../../../native/enhance/illumination.cpp"
#include "../../../native/enhance/tone.cpp"
#include "../../../native/enhance/unsharp.cpp"
#include "../../../native/enhance/quality_gate.cpp"
#include "../../../native/enhance/morphology.cpp"
#include "../../../native/enhance/tophat.cpp"
#include "../../../native/enhance/clahe.cpp"
#include "../../../native/document/perspective_warp.cpp"
#endif
