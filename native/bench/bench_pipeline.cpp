// Host-side DSQ0 "pipeline replay" harness: raw RGBA still + labeled quad →
// supy_core_warp → supy_core_enhance → raw RGBA out. Replays the device
// capture pipeline on corpus stills so the output bench runs in CI without
// a device. One DSQ_PIPELINE JSON line on stdout for run_bench.dart.
//
// Usage:
//   bench_pipeline --rgba <path> --width W --height H \
//     --quad x0,y0,x1,y1,x2,y2,x3,y3 --mode balanced --out <path>
//
// Quad is normalized [0,1] TL,TR,BR,BL; scaled to pixels here (the same
// contract supy_warp_input_t documents for production callers).

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "supy_scanner_core.h"
#include "supy_scanner_enhance.h"

namespace {

struct Args {
  std::string rgba;
  std::string out;
  std::string mode = "balanced";
  int width = 0;
  int height = 0;
  float quad[8] = {0};
  bool haveQuad = false;
};

bool parseQuad(const char* s, float out[8]) {
  int n = 0;
  const char* p = s;
  char* end = nullptr;
  while (n < 8) {
    out[n] = std::strtof(p, &end);
    if (end == p) return false;
    ++n;
    p = end;
    if (*p == ',') ++p;
  }
  return n == 8;
}

Args parseArgs(int argc, char** argv) {
  Args a;
  for (int i = 1; i < argc; ++i) {
    const std::string k = argv[i];
    auto next = [&]() -> const char* {
      if (i + 1 >= argc) {
        std::fprintf(stderr, "bench_pipeline: missing value for %s\n",
                     k.c_str());
        std::exit(2);
      }
      return argv[++i];
    };
    if (k == "--rgba") a.rgba = next();
    else if (k == "--out") a.out = next();
    else if (k == "--mode") a.mode = next();
    else if (k == "--width") a.width = std::atoi(next());
    else if (k == "--height") a.height = std::atoi(next());
    else if (k == "--quad") a.haveQuad = parseQuad(next(), a.quad);
    else {
      std::fprintf(stderr, "bench_pipeline: unknown arg %s\n", k.c_str());
      std::exit(2);
    }
  }
  return a;
}

supy_enhance_mode_t parseMode(const std::string& m) {
  if (m == "off") return SUPY_ENHANCE_OFF;
  if (m == "fast") return SUPY_ENHANCE_FAST;
  if (m == "balanced") return SUPY_ENHANCE_BALANCED;
  if (m == "max") return SUPY_ENHANCE_MAX;
  std::fprintf(stderr, "bench_pipeline: unknown mode %s\n", m.c_str());
  std::exit(2);
}

std::vector<uint8_t> readAll(const std::string& path) {
  std::FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) {
    std::fprintf(stderr, "bench_pipeline: cannot open %s\n", path.c_str());
    std::exit(2);
  }
  std::fseek(f, 0, SEEK_END);
  const long size = std::ftell(f);
  std::fseek(f, 0, SEEK_SET);
  std::vector<uint8_t> buf(size > 0 ? static_cast<size_t>(size) : 0);
  if (!buf.empty() && std::fread(buf.data(), 1, buf.size(), f) != buf.size()) {
    std::fclose(f);
    std::fprintf(stderr, "bench_pipeline: short read on %s\n", path.c_str());
    std::exit(2);
  }
  std::fclose(f);
  return buf;
}

void writeAll(const std::string& path, const uint8_t* data, size_t size) {
  std::FILE* f = std::fopen(path.c_str(), "wb");
  if (!f || std::fwrite(data, 1, size, f) != size) {
    if (f) std::fclose(f);
    std::fprintf(stderr, "bench_pipeline: cannot write %s\n", path.c_str());
    std::exit(2);
  }
  std::fclose(f);
}

// Copies a possibly-strided RGBA buffer into a packed vector.
std::vector<uint8_t> packRows(const uint8_t* src, int w, int h, int stride) {
  std::vector<uint8_t> out(static_cast<size_t>(w) * h * 4);
  for (int y = 0; y < h; ++y) {
    std::memcpy(out.data() + static_cast<size_t>(y) * w * 4,
                src + static_cast<size_t>(y) * stride,
                static_cast<size_t>(w) * 4);
  }
  return out;
}

}  // namespace

int main(int argc, char** argv) {
  const Args a = parseArgs(argc, argv);
  if (a.rgba.empty() || a.out.empty() || a.width <= 0 || a.height <= 0 ||
      !a.haveQuad) {
    std::fprintf(stderr,
                 "usage: bench_pipeline --rgba <path> --width W --height H "
                 "--quad x0,y0,...,x3,y3 --mode <off|fast|balanced|max> "
                 "--out <path>\n");
    return 2;
  }
  const std::vector<uint8_t> rgba = readAll(a.rgba);
  const size_t expected =
      static_cast<size_t>(a.width) * static_cast<size_t>(a.height) * 4;
  if (rgba.size() != expected) {
    std::fprintf(stderr, "bench_pipeline: %s is %zu bytes, expected %zu\n",
                 a.rgba.c_str(), rgba.size(), expected);
    return 2;
  }

  supy_warp_input_t warpIn;
  std::memset(&warpIn, 0, sizeof(warpIn));
  warpIn.rgba = rgba.data();
  warpIn.width = a.width;
  warpIn.height = a.height;
  warpIn.row_stride = a.width * 4;
  for (int i = 0; i < 8; ++i) {
    warpIn.src_corners[i] =
        a.quad[i] * static_cast<float>(i % 2 == 0 ? a.width : a.height);
  }
  warpIn.max_long_side = 0;  // unbounded; bench measures full-res output

  supy_warp_result_t* warp = supy_core_warp(&warpIn);
  if (!warp) {
    std::fprintf(stderr, "bench_pipeline: supy_core_warp failed\n");
    return 3;
  }
  const int outW = supy_core_warp_width(warp);
  const int outH = supy_core_warp_height(warp);
  const int outStride = supy_core_warp_row_stride(warp);
  const uint8_t* warped = supy_core_warp_rgba(warp);

  supy_enhance_input_t enhIn;
  std::memset(&enhIn, 0, sizeof(enhIn));
  enhIn.rgba = warped;
  enhIn.width = outW;
  enhIn.height = outH;
  enhIn.row_stride = outStride;
  enhIn.mode = parseMode(a.mode);
  enhIn.min_blur_score = 0.0f;

  supy_enhance_result_t* enh = supy_core_enhance(&enhIn);
  if (!enh) {
    // Mirror production policy: enhance failure → un-enhanced warp output.
    const std::vector<uint8_t> packed = packRows(warped, outW, outH, outStride);
    writeAll(a.out, packed.data(), packed.size());
    std::printf(
        "DSQ_PIPELINE {\"outWidth\":%d,\"outHeight\":%d,\"enhanced\":false,"
        "\"appliedStages\":0,\"qualityScore\":0.0,\"verdict\":-1,"
        "\"processingMs\":0}\n",
        outW, outH);
    supy_core_warp_free(warp);
    return 0;
  }

  const std::vector<uint8_t> packed =
      packRows(supy_core_enhance_rgba(enh), supy_core_enhance_width(enh),
               supy_core_enhance_height(enh), supy_core_enhance_row_stride(enh));
  writeAll(a.out, packed.data(), packed.size());
  std::printf(
      "DSQ_PIPELINE {\"outWidth\":%d,\"outHeight\":%d,\"enhanced\":true,"
      "\"appliedStages\":%u,\"qualityScore\":%.2f,\"verdict\":%d,"
      "\"processingMs\":%d}\n",
      supy_core_enhance_width(enh), supy_core_enhance_height(enh),
      supy_core_enhance_applied_stages(enh),
      static_cast<double>(supy_core_enhance_quality_score(enh)),
      supy_core_enhance_verdict(enh), supy_core_enhance_processing_ms(enh));

  supy_core_enhance_free(enh);
  supy_core_warp_free(warp);
  return 0;
}
