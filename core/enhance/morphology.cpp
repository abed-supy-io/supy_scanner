#include "morphology.h"

#include <deque>
#include <vector>

namespace supy::scanner::enhance {

namespace {

// 1D max-filter (dilation) with radius r over a row, using a monotonic deque
// to achieve O(n) regardless of r. Border handling: reflect-clamp.
void maxFilter1D(const std::uint8_t* in, std::uint8_t* out, std::int32_t n, std::int32_t r) {
  std::deque<std::int32_t> dq;  // stores indices, values monotonically decreasing
  const std::int32_t w = 2 * r + 1;
  for (std::int32_t i = 0; i < n + r; ++i) {
    if (i < n) {
      while (!dq.empty() && in[dq.back()] <= in[i]) dq.pop_back();
      dq.push_back(i);
    }
    while (!dq.empty() && dq.front() < i - w + 1) dq.pop_front();
    const std::int32_t outIdx = i - r;
    if (outIdx >= 0 && outIdx < n) {
      out[outIdx] = in[dq.front()];
    }
  }
}

// 1D min-filter (erosion).
void minFilter1D(const std::uint8_t* in, std::uint8_t* out, std::int32_t n, std::int32_t r) {
  std::deque<std::int32_t> dq;
  const std::int32_t w = 2 * r + 1;
  for (std::int32_t i = 0; i < n + r; ++i) {
    if (i < n) {
      while (!dq.empty() && in[dq.back()] >= in[i]) dq.pop_back();
      dq.push_back(i);
    }
    while (!dq.empty() && dq.front() < i - w + 1) dq.pop_front();
    const std::int32_t outIdx = i - r;
    if (outIdx >= 0 && outIdx < n) {
      out[outIdx] = in[dq.front()];
    }
  }
}

// Apply a 1D op horizontally then vertically over `plane`, using `tmp` as
// scratch. The vertical pass needs contiguous column buffers because the
// deque op wants contiguous memory.
void separable2D(std::uint8_t* plane, std::uint8_t* tmp, std::int32_t w, std::int32_t h,
                 std::int32_t r,
                 void (*op)(const std::uint8_t*, std::uint8_t*, std::int32_t, std::int32_t)) {
  for (std::int32_t y = 0; y < h; ++y) {
    op(plane + y * w, tmp + y * w, w, r);
  }
  std::vector<std::uint8_t> colIn(static_cast<std::size_t>(h));
  std::vector<std::uint8_t> colOut(static_cast<std::size_t>(h));
  for (std::int32_t x = 0; x < w; ++x) {
    for (std::int32_t y = 0; y < h; ++y) colIn[y] = tmp[y * w + x];
    op(colIn.data(), colOut.data(), h, r);
    for (std::int32_t y = 0; y < h; ++y) plane[y * w + x] = colOut[y];
  }
}

}  // namespace

void dilate2D(std::uint8_t* plane, std::uint8_t* tmp,
              std::int32_t w, std::int32_t h, std::int32_t r) {
  if (r <= 0) return;
  separable2D(plane, tmp, w, h, r, &maxFilter1D);
}

void erode2D(std::uint8_t* plane, std::uint8_t* tmp,
             std::int32_t w, std::int32_t h, std::int32_t r) {
  if (r <= 0) return;
  separable2D(plane, tmp, w, h, r, &minFilter1D);
}

void close2D(std::uint8_t* plane, std::uint8_t* tmp,
             std::int32_t w, std::int32_t h, std::int32_t r) {
  if (r <= 0) return;
  separable2D(plane, tmp, w, h, r, &maxFilter1D);
  separable2D(plane, tmp, w, h, r, &minFilter1D);
}

void open2D(std::uint8_t* plane, std::uint8_t* tmp,
            std::int32_t w, std::int32_t h, std::int32_t r) {
  if (r <= 0) return;
  separable2D(plane, tmp, w, h, r, &minFilter1D);
  separable2D(plane, tmp, w, h, r, &maxFilter1D);
}

}  // namespace supy::scanner::enhance
