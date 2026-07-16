#include "perspective_warp.h"

#include <algorithm>
#include <cmath>

namespace supy::scanner::document {

namespace {

// Solve an 8x8 linear system A x = b in place via Gaussian elimination with
// partial pivoting. Returns false if the matrix is (near-)singular.
bool solve8(float a[8][8], float b[8], float out[8]) {
    constexpr int N = 8;
    for (int col = 0; col < N; ++col) {
        // Partial pivot: find the largest magnitude in this column.
        int pivot = col;
        float best = std::fabs(a[col][col]);
        for (int r = col + 1; r < N; ++r) {
            const float v = std::fabs(a[r][col]);
            if (v > best) { best = v; pivot = r; }
        }
        if (best < 1e-9f) return false;  // degenerate
        if (pivot != col) {
            for (int c = 0; c < N; ++c) std::swap(a[col][c], a[pivot][c]);
            std::swap(b[col], b[pivot]);
        }
        // Eliminate below.
        const float diag = a[col][col];
        for (int r = col + 1; r < N; ++r) {
            const float f = a[r][col] / diag;
            if (f == 0.0f) continue;
            for (int c = col; c < N; ++c) a[r][c] -= f * a[col][c];
            b[r] -= f * b[col];
        }
    }
    // Back-substitution.
    for (int row = N - 1; row >= 0; --row) {
        float acc = b[row];
        for (int c = row + 1; c < N; ++c) acc -= a[row][c] * out[c];
        out[row] = acc / a[row][row];
    }
    return true;
}

float edgeLen(const Point& a, const Point& b) {
    const float dx = a.x - b.x;
    const float dy = a.y - b.y;
    return std::sqrt(dx * dx + dy * dy);
}

}  // namespace

std::optional<Mat3> computeHomography(
    const std::array<Point, 4>& src, float dstW, float dstH) {
    if (dstW <= 0.0f || dstH <= 0.0f) return std::nullopt;

    // Destination rectangle corners, TL, TR, BR, BL — mapped onto `src`.
    const Point dst[4] = {
        {0.0f, 0.0f}, {dstW, 0.0f}, {dstW, dstH}, {0.0f, dstH},
    };

    // For each correspondence (x,y) -> (u,v):
    //   h0 x + h1 y + h2 - h6 x u - h7 y u = u
    //   h3 x + h4 y + h5 - h6 x v - h7 y v = v
    float a[8][8] = {};
    float b[8] = {};
    for (int i = 0; i < 4; ++i) {
        const float x = dst[i].x, y = dst[i].y;
        const float u = src[i].x, v = src[i].y;
        float* ru = a[2 * i];
        ru[0] = x; ru[1] = y; ru[2] = 1.0f;
        ru[6] = -x * u; ru[7] = -y * u;
        b[2 * i] = u;
        float* rv = a[2 * i + 1];
        rv[3] = x; rv[4] = y; rv[5] = 1.0f;
        rv[6] = -x * v; rv[7] = -y * v;
        b[2 * i + 1] = v;
    }

    float h[8] = {};
    if (!solve8(a, b, h)) return std::nullopt;

    Mat3 out{};
    out.m = {h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], 1.0f};
    return out;
}

void rectifiedSize(
    const std::array<Point, 4>& srcPx, int maxLongSide, int* outW, int* outH) {
    // TL,TR,BR,BL — width from horizontal edges, height from vertical edges.
    const float wTop    = edgeLen(srcPx[0], srcPx[1]);
    const float wBottom = edgeLen(srcPx[3], srcPx[2]);
    const float hLeft   = edgeLen(srcPx[0], srcPx[3]);
    const float hRight  = edgeLen(srcPx[1], srcPx[2]);

    float w = std::max(wTop, wBottom);
    float h = std::max(hLeft, hRight);
    if (w < 1.0f) w = 1.0f;
    if (h < 1.0f) h = 1.0f;

    if (maxLongSide > 0) {
        const float longSide = std::max(w, h);
        if (longSide > static_cast<float>(maxLongSide)) {
            const float scale = static_cast<float>(maxLongSide) / longSide;
            w *= scale;
            h *= scale;
        }
    }

    *outW = std::max(1, static_cast<int>(std::lround(w)));
    *outH = std::max(1, static_cast<int>(std::lround(h)));
}

std::optional<WarpResult> warpToRect(const WarpInput& in, int maxLongSide) {
    if (in.rgba == nullptr) return std::nullopt;
    if (in.width <= 0 || in.height <= 0) return std::nullopt;
    if (in.rowStride < in.width * 4) return std::nullopt;

    int dstW = 0, dstH = 0;
    rectifiedSize(in.srcCorners, maxLongSide, &dstW, &dstH);

    auto homography = computeHomography(
        in.srcCorners, static_cast<float>(dstW), static_cast<float>(dstH));
    if (!homography) return std::nullopt;
    const auto& m = homography->m;

    WarpResult out{};
    out.width = dstW;
    out.height = dstH;
    out.rowStride = dstW * 4;
    out.rgba.assign(static_cast<size_t>(out.rowStride) * dstH, 0);

    const int srcW = in.width;
    const int srcH = in.height;

    for (int y = 0; y < dstH; ++y) {
        uint8_t* dstRow = out.rgba.data() + static_cast<size_t>(y) * out.rowStride;
        const float yf = static_cast<float>(y);
        for (int x = 0; x < dstW; ++x) {
            const float xf = static_cast<float>(x);
            // Map destination pixel -> source (homogeneous divide).
            const float w = m[6] * xf + m[7] * yf + m[8];
            if (w == 0.0f) continue;
            const float inv = 1.0f / w;
            const float su = (m[0] * xf + m[1] * yf + m[2]) * inv;
            const float sv = (m[3] * xf + m[4] * yf + m[5]) * inv;

            // Bilinear sample; skip pixels that fall outside the source.
            if (su < 0.0f || sv < 0.0f ||
                su > static_cast<float>(srcW - 1) ||
                sv > static_cast<float>(srcH - 1)) {
                continue;
            }
            const int x0 = static_cast<int>(su);
            const int y0 = static_cast<int>(sv);
            const int x1 = std::min(x0 + 1, srcW - 1);
            const int y1 = std::min(y0 + 1, srcH - 1);
            const float fx = su - static_cast<float>(x0);
            const float fy = sv - static_cast<float>(y0);
            const float w00 = (1.0f - fx) * (1.0f - fy);
            const float w10 = fx * (1.0f - fy);
            const float w01 = (1.0f - fx) * fy;
            const float w11 = fx * fy;

            const uint8_t* p00 = in.rgba + static_cast<size_t>(y0) * in.rowStride + static_cast<size_t>(x0) * 4;
            const uint8_t* p10 = in.rgba + static_cast<size_t>(y0) * in.rowStride + static_cast<size_t>(x1) * 4;
            const uint8_t* p01 = in.rgba + static_cast<size_t>(y1) * in.rowStride + static_cast<size_t>(x0) * 4;
            const uint8_t* p11 = in.rgba + static_cast<size_t>(y1) * in.rowStride + static_cast<size_t>(x1) * 4;

            uint8_t* d = dstRow + static_cast<size_t>(x) * 4;
            for (int c = 0; c < 4; ++c) {
                const float v = w00 * p00[c] + w10 * p10[c] + w01 * p01[c] + w11 * p11[c];
                d[c] = static_cast<uint8_t>(v < 0.0f ? 0.0f : (v > 255.0f ? 255.0f : v + 0.5f));
            }
        }
    }

    return out;
}

}  // namespace supy::scanner::document
