// sauvola_2d_generator.cpp — Halide AOT generator for the Sauvola 2D
// adaptive binarization kernel exposed via `supy_core_binarize_luma`
// (`SAUVOLA_2D` mode).
//
// Built ONLY when SUPY_USE_HALIDE=ON. The generator binary links against
// the vendored `libHalide` under native/third_party/halide-17.0.x/ and is
// invoked at CMake configure time to emit per-target `.o` + `.h` artifacts.
// See docs/V1-S2-05.2-HALIDE.md for the full integration design.
//
// Algorithm reference: `sauvola2d` branch of
// supy::scanner::barcode::binarizeLuma in native/barcode/binarize.cpp.
// This Halide pipeline must produce per-pixel parity within ±1 of the
// integral-image reference (the parity test in
// native/test/binarize_halide_parity_test.cpp enforces this).
//
// Sauvola threshold per pixel:
//     T(x,y) = mean(x,y) · (1 + k · (stdev(x,y)/R − 1))
//     dst(x,y) = src(x,y) < T(x,y) ? 0 : 255
//
// where mean/stdev are over a (2·radius+1)² window.

#include "Halide.h"

namespace {

using namespace Halide;

class Sauvola2DGenerator : public Generator<Sauvola2DGenerator> {
 public:
  // 2-D u8 luma input, packed (stride[0]=1, stride[1]=row_stride).
  Input<Buffer<uint8_t, 2>> src{"src"};

  // Window radius; the C++ caller passes clamp(min(w,h)/16, 5, 25).
  Input<int32_t> radius{"radius"};

  // Sauvola parameters; the C++ ref uses k=0.34, R=128.
  Input<float> k{"k"};
  Input<float> R{"R"};

  // Output: same shape as input, values in {0, 255}.
  Output<Buffer<uint8_t, 2>> dst{"dst"};

  void generate() {
    Var x("x"), y("y");

    // Edge-replicate the input so window sums near the border stay defined.
    // Matches the integral-image impl's behavior at edges.
    Func clamped = BoundaryConditions::repeat_edge(src);

    // Cast once to float for downstream arithmetic — keeps the schedule
    // simple and lets the autoscheduler vectorize over float lanes.
    Func srcf("srcf");
    srcf(x, y) = cast<float>(clamped(x, y));

    Func srcf_sq("srcf_sq");
    srcf_sq(x, y) = srcf(x, y) * srcf(x, y);

    // Separable box-sum via two 1D scans. The horizontal pass produces
    // running window sums along x; the vertical pass sums those rows.
    // After CSE this is O(1) per output pixel regardless of radius —
    // matches the integral-image reference's asymptotic.
    RDom rx(-radius, 2 * radius + 1);
    RDom ry(-radius, 2 * radius + 1);

    Func sum_x("sum_x"), sum_x_sq("sum_x_sq");
    sum_x   (x, y) = sum(srcf   (x + rx, y));
    sum_x_sq(x, y) = sum(srcf_sq(x + rx, y));

    Func sum_xy("sum_xy"), sum_xy_sq("sum_xy_sq");
    sum_xy   (x, y) = sum(sum_x   (x, y + ry));
    sum_xy_sq(x, y) = sum(sum_x_sq(x, y + ry));

    Expr win_w = cast<float>(2 * radius + 1);
    Expr area  = win_w * win_w;

    Func mean("mean"), mean_sq("mean_sq");
    mean   (x, y) = sum_xy   (x, y) / area;
    mean_sq(x, y) = sum_xy_sq(x, y) / area;

    // Numerical guard: float subtraction can produce tiny negatives on a
    // flat region (variance ≈ 0). max(.,0) keeps sqrt happy without
    // changing the result on real images.
    Func variance("variance");
    variance(x, y) = max(mean_sq(x, y) - mean(x, y) * mean(x, y), 0.0f);

    Func stdev("stdev");
    stdev(x, y) = sqrt(variance(x, y));

    Func threshold("threshold");
    threshold(x, y) = mean(x, y) * (1.0f + k * (stdev(x, y) / R - 1.0f));

    dst(x, y) = select(srcf(x, y) < threshold(x, y),
                       cast<uint8_t>(0),
                       cast<uint8_t>(255));
  }

  void schedule() {
    // Estimates feed the Adams2019 autoscheduler in CMake's autoschedule
    // path. The numbers approximate a typical DM crop region after the
    // V1-S2-06.2 temporal-median fusion (union bbox of three matched
    // detections); tune in V1-S2-05.4 once we have real per-target numbers.
    src.set_estimates({{0, 512}, {0, 512}});
    radius.set_estimate(8);
    k.set_estimate(0.34f);
    R.set_estimate(128.0f);
    dst.set_estimates({{0, 512}, {0, 512}});

    if (using_autoscheduler()) {
      // CMake passes -p autoschedule_adams2019 + autoscheduler=Adams2019.
      return;
    }

    // Manual fallback schedule — conservative, target-agnostic. Replaced
    // by autoscheduler output in the CMake-driven build path; this exists
    // for `halide-generator -e schedule` debugging.
    Var xi("xi"), yi("yi");
    dst.tile(_0, _1, xi, yi, 64, 32).vectorize(xi, 8).parallel(_1);
  }
};

}  // namespace

HALIDE_REGISTER_GENERATOR(Sauvola2DGenerator, sauvola_2d)
