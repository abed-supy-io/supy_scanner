// Host-side DSQ0 detection bench harness. Reads a headerless 8-bit luma
// file, runs the classical document detector, prints one DSQ_DETECT JSON
// line for tools/bench/run_bench.dart to parse.
//
// Usage: bench_detect --gray <path> --width W --height H
//
// The file must contain exactly width*height bytes (row stride == width);
// tools/bench/run_bench.dart writes these from decoded corpus PNGs. Raw
// files keep pixel decoding out of C++ (no new vendored deps) and pixels
// out of dart:ffi (per the supy_scanner.h boundary contract).

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "document/document_edge_detector.h"

namespace {

struct Args {
  std::string gray;
  int width = 0;
  int height = 0;
};

Args parseArgs(int argc, char** argv) {
  Args a;
  for (int i = 1; i < argc; ++i) {
    const std::string k = argv[i];
    auto next = [&]() -> const char* {
      if (i + 1 >= argc) {
        std::fprintf(stderr, "bench_detect: missing value for %s\n", k.c_str());
        std::exit(2);
      }
      return argv[++i];
    };
    if (k == "--gray") a.gray = next();
    else if (k == "--width") a.width = std::atoi(next());
    else if (k == "--height") a.height = std::atoi(next());
    else {
      std::fprintf(stderr, "bench_detect: unknown arg %s\n", k.c_str());
      std::exit(2);
    }
  }
  return a;
}

std::vector<uint8_t> readAll(const std::string& path) {
  std::FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) {
    std::fprintf(stderr, "bench_detect: cannot open %s\n", path.c_str());
    std::exit(2);
  }
  std::fseek(f, 0, SEEK_END);
  const long size = std::ftell(f);
  std::fseek(f, 0, SEEK_SET);
  std::vector<uint8_t> buf(size > 0 ? static_cast<size_t>(size) : 0);
  if (!buf.empty() && std::fread(buf.data(), 1, buf.size(), f) != buf.size()) {
    std::fclose(f);
    std::fprintf(stderr, "bench_detect: short read on %s\n", path.c_str());
    std::exit(2);
  }
  std::fclose(f);
  return buf;
}

}  // namespace

int main(int argc, char** argv) {
  const Args a = parseArgs(argc, argv);
  if (a.gray.empty() || a.width <= 0 || a.height <= 0) {
    std::fprintf(stderr,
                 "usage: bench_detect --gray <path> --width W --height H\n");
    return 2;
  }
  const std::vector<uint8_t> luma = readAll(a.gray);
  const size_t expected =
      static_cast<size_t>(a.width) * static_cast<size_t>(a.height);
  if (luma.size() != expected) {
    std::fprintf(stderr, "bench_detect: %s is %zu bytes, expected %zu\n",
                 a.gray.c_str(), luma.size(), expected);
    return 2;
  }

  const supy::scanner::document::DetectionInput input{
      luma.data(), a.width, a.height, a.width};
  const auto quad = supy::scanner::document::detectDocument(input);
  if (!quad.has_value()) {
    std::printf("DSQ_DETECT {\"detected\":false}\n");
    return 0;
  }
  const auto& c = quad->corners;
  std::printf(
      "DSQ_DETECT {\"detected\":true,\"quad\":[%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,"
      "%.6f,%.6f],\"coverage\":%.4f,\"tilt\":%.2f}\n",
      c[0].x, c[0].y, c[1].x, c[1].y, c[2].x, c[2].y, c[3].x, c[3].y,
      quad->coverageRatio, quad->tiltDegrees);
  return 0;
}
