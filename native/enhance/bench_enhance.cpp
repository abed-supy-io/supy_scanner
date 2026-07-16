// Host-side micro-benchmark for the document enhancement pipeline.
//
// Synthesizes a configurable-size RGBA8888 fixture (sharp checkerboard
// under a radial vignette — exercises every stage) and times each mode
// over N iterations. Reports min/median/p95/max in milliseconds plus
// throughput (megapixels/sec).
//
// Usage:
//   bench_enhance                       # default: 2400px long edge, 20 iter
//   bench_enhance --long-edge 1600 --iter 50
//   bench_enhance --mode balanced       # restrict to one mode
//   bench_enhance --json --tier low     # perfgate-compatible BENCH_RESULT lines
//
// `--tier <low|mid|high>` selects the per-tier long-edge profile used by the
// perfgate enhance bench harness (`tools/perfgate/enhance/run_enhance_bench.dart`)
// and emits a `BENCH_TIER` line. `--json` swaps the human-readable per-mode
// table for `BENCH_RESULT { "metric": "enhance_<mode>_ms", ... }` lines that
// `tools/perfgate/lib/baseline_compare.dart` parses. Both flags compose.
//
// Acceptance target (see docs/ENHANCEMENT.md):
//   balanced @ 2400 px long edge ≤ 250 ms on a 2020-era mid-tier device.

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "supy_scanner_enhance.h"

namespace {

struct Args {
  int longEdge = 2400;
  int iterations = 20;
  std::string modeFilter;  // empty = all
  std::string tier;        // empty = no tier emit; "low"|"mid"|"high" otherwise
  bool json = false;
};

// Per-tier long-edge profile. Matches the device-tier image budgets used by
// PageReencoder + the perfgate baselines/{low,mid,high}/ layout.
int tierLongEdge(const std::string& tier) {
  if (tier == "low")  return 1280;
  if (tier == "mid")  return 1920;
  if (tier == "high") return 2400;
  return -1;
}

Args parseArgs(int argc, char** argv) {
  Args a;
  for (int i = 1; i < argc; ++i) {
    std::string k = argv[i];
    auto next = [&]() -> const char* {
      if (i + 1 >= argc) {
        std::fprintf(stderr, "missing value for %s\n", k.c_str());
        std::exit(2);
      }
      return argv[++i];
    };
    if (k == "--long-edge") a.longEdge = std::atoi(next());
    else if (k == "--iter") a.iterations = std::atoi(next());
    else if (k == "--mode") a.modeFilter = next();
    else if (k == "--tier") {
      a.tier = next();
      const int le = tierLongEdge(a.tier);
      if (le < 0) {
        std::fprintf(stderr, "unknown tier: %s (expected low|mid|high)\n",
                     a.tier.c_str());
        std::exit(2);
      }
      a.longEdge = le;
    }
    else if (k == "--json") a.json = true;
    else if (k == "--help" || k == "-h") {
      std::printf("usage: bench_enhance [--long-edge N] [--iter N] "
                  "[--mode off|fast|balanced|max] [--tier low|mid|high] [--json]\n");
      std::exit(0);
    } else {
      std::fprintf(stderr, "unknown arg: %s\n", k.c_str());
      std::exit(2);
    }
  }
  return a;
}

std::vector<std::uint8_t> synthesize(int width, int height) {
  std::vector<std::uint8_t> rgba(static_cast<std::size_t>(width) * height * 4);
  const float cx = width * 0.5f;
  const float cy = height * 0.5f;
  const float maxR = std::sqrt(cx * cx + cy * cy);
  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      const float dx = x - cx;
      const float dy = y - cy;
      const float r = std::sqrt(dx * dx + dy * dy) / maxR;
      const float gain = 1.0f - 0.55f * r;
      const std::uint8_t base = ((x / 12 + y / 12) % 2 == 0) ? 230 : 40;
      const float lit = base * gain;
      const auto v = static_cast<std::uint8_t>(
          std::max(0.0f, std::min(255.0f, lit)));
      const std::size_t i = (static_cast<std::size_t>(y) * width + x) * 4;
      rgba[i + 0] = v;
      rgba[i + 1] = v;
      rgba[i + 2] = v;
      rgba[i + 3] = 255;
    }
  }
  return rgba;
}

struct ModeSpec {
  const char* name;
  supy_enhance_mode_t mode;
};

constexpr ModeSpec kModes[] = {
    {"off",       SUPY_ENHANCE_OFF},
    {"fast",      SUPY_ENHANCE_FAST},
    {"balanced",  SUPY_ENHANCE_BALANCED},
    {"max",       SUPY_ENHANCE_MAX},
};

double percentile(std::vector<double>& xs, double p) {
  std::sort(xs.begin(), xs.end());
  const std::size_t idx = std::min(xs.size() - 1,
      static_cast<std::size_t>(p * (xs.size() - 1)));
  return xs[idx];
}

void runMode(const ModeSpec& spec, const std::vector<std::uint8_t>& rgba,
             int width, int height, int iterations, bool jsonOut) {
  std::vector<double> samples;
  samples.reserve(iterations);

  supy_enhance_input_t in{};
  in.rgba = rgba.data();
  in.width = width;
  in.height = height;
  in.row_stride = width * 4;
  in.mode = spec.mode;
  in.min_blur_score = 0.0f;

  // Warm-up — not counted; primes allocator + caches.
  if (auto* h = supy_core_enhance(&in)) supy_core_enhance_free(h);

  for (int i = 0; i < iterations; ++i) {
    const auto t0 = std::chrono::steady_clock::now();
    auto* h = supy_core_enhance(&in);
    const auto t1 = std::chrono::steady_clock::now();
    if (!h) {
      std::fprintf(stderr, "supy_core_enhance returned NULL\n");
      std::exit(1);
    }
    samples.push_back(
        std::chrono::duration<double, std::milli>(t1 - t0).count());
    supy_core_enhance_free(h);
  }

  const double mn = *std::min_element(samples.begin(), samples.end());
  const double mx = *std::max_element(samples.begin(), samples.end());
  const double p50 = percentile(samples, 0.50);
  const double p95 = percentile(samples, 0.95);
  const double mpps = (static_cast<double>(width) * height) / 1e6 / (p50 / 1000.0);

  if (jsonOut) {
    // BenchSample fields are ints (ms). Round to nearest to match the existing
    // baseline JSON shape under tools/perfgate/baselines/.
    auto r = [](double v) { return static_cast<long long>(v + 0.5); };
    std::printf(
        "BENCH_RESULT {\"metric\":\"enhance_%s_ms\","
        "\"runs\":%d,\"min\":%lld,\"max\":%lld,\"p50\":%lld,\"p95\":%lld}\n",
        spec.name, iterations, r(mn), r(mx), r(p50), r(p95));
  } else {
    std::printf("%-9s  min=%7.2f  p50=%7.2f  p95=%7.2f  max=%7.2f ms   %6.1f MP/s\n",
                spec.name, mn, p50, p95, mx, mpps);
  }
}

}  // namespace

int main(int argc, char** argv) {
  const Args args = parseArgs(argc, argv);
  const int longEdge = args.longEdge;
  const int width = longEdge;
  const int height = longEdge * 3 / 4;  // 4:3 page-ish.

  if (args.json) {
    if (!args.tier.empty()) {
      std::printf("BENCH_TIER {\"tier\":\"%s\"}\n", args.tier.c_str());
    }
  } else {
    std::printf("# supy_scanner enhance benchmark\n");
    std::printf("# image %dx%d, %d iterations per mode\n",
                width, height, args.iterations);
    if (!args.tier.empty()) std::printf("# tier %s\n", args.tier.c_str());
    std::printf("# acceptance: balanced ≤ 250 ms @ 2400 px on a 2020-era mid-tier device\n\n");
  }

  const auto rgba = synthesize(width, height);

  for (const auto& spec : kModes) {
    if (!args.modeFilter.empty() && args.modeFilter != spec.name) continue;
    runMode(spec, rgba, width, height, args.iterations, args.json);
  }
  return 0;
}
