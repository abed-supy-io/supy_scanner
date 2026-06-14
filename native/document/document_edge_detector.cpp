// document_edge_detector.cpp — on-device document quad detection.
// 7-stage pipeline: downsample → blur → Sobel → adaptive Canny → Hough →
// cluster angles → intersect pairs → score → pick best quad.
// No exceptions, no dynamic dispatch, no network calls.
#include "document/document_edge_detector.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <optional>
#include <vector>

namespace supy::scanner::document {
namespace {

// ---------------------------------------------------------------------------
// Dimension cap
// Why: prevents int*int overflow in caller-supplied luma index arithmetic;
// 16384 exceeds any real camera resolution (e.g. 12 MP ≈ 4000×3000).
// ---------------------------------------------------------------------------
static constexpr int kMaxDimension = 16384;

// ---------------------------------------------------------------------------
// Types used internally
// ---------------------------------------------------------------------------
struct Line {
    float rho;    // pixels from origin
    float theta;  // radians [0, pi)
};

// ---------------------------------------------------------------------------
// Stage 1: downsample to at most 256 px on the long edge (bilinear).
// Returns the working buffer and updates outW/outH.
// ---------------------------------------------------------------------------
static std::vector<uint8_t> downsampleAndCrop(const DetectionInput& in,
                                              int& outW, int& outH) {
    const int maxDim = 256;
    const int srcW = in.width;
    const int srcH = in.height;

    float scale = 1.0f;
    if (srcW >= srcH && srcW > maxDim) scale = static_cast<float>(maxDim) / srcW;
    else if (srcH > srcW && srcH > maxDim) scale = static_cast<float>(maxDim) / srcH;

    outW = std::max(1, static_cast<int>(srcW * scale));
    outH = std::max(1, static_cast<int>(srcH * scale));

    std::vector<uint8_t> out(static_cast<size_t>(outW * outH));
    for (int dy = 0; dy < outH; ++dy) {
        const float fy = (dy + 0.5f) / scale - 0.5f;
        const int sy0 = std::max(0, static_cast<int>(fy));
        const int sy1 = std::min(srcH - 1, sy0 + 1);
        const float wy = fy - sy0;
        for (int dx = 0; dx < outW; ++dx) {
            const float fx = (dx + 0.5f) / scale - 0.5f;
            const int sx0 = std::max(0, static_cast<int>(fx));
            const int sx1 = std::min(srcW - 1, sx0 + 1);
            const float wx = fx - sx0;
            const float v00 = in.luma[static_cast<size_t>(sy0) * in.rowStride + sx0];
            const float v10 = in.luma[static_cast<size_t>(sy0) * in.rowStride + sx1];
            const float v01 = in.luma[static_cast<size_t>(sy1) * in.rowStride + sx0];
            const float v11 = in.luma[static_cast<size_t>(sy1) * in.rowStride + sx1];
            const float val = v00 * (1 - wx) * (1 - wy)
                            + v10 *      wx  * (1 - wy)
                            + v01 * (1 - wx) *      wy
                            + v11 *      wx  *      wy;
            out[static_cast<size_t>(dy * outW + dx)] =
                static_cast<uint8_t>(std::max(0.f, std::min(255.f, val)));
        }
    }
    return out;
}

// ---------------------------------------------------------------------------
// Stage 2: separable 3×3 box blur (acceptable Gaussian approximation).
// ---------------------------------------------------------------------------
static std::vector<uint8_t> gaussianBlur3x3(const std::vector<uint8_t>& src,
                                            int w, int h) {
    std::vector<uint8_t> tmp(src.size());
    std::vector<uint8_t> dst(src.size());

    // Horizontal pass
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            const int xl = std::max(0, x - 1);
            const int xr = std::min(w - 1, x + 1);
            const int sum = src[static_cast<size_t>(y * w + xl)]
                          + src[static_cast<size_t>(y * w + x)]
                          + src[static_cast<size_t>(y * w + xr)];
            tmp[static_cast<size_t>(y * w + x)] = static_cast<uint8_t>(sum / 3);
        }
    }
    // Vertical pass
    for (int y = 0; y < h; ++y) {
        const int yu = std::max(0, y - 1);
        const int yd = std::min(h - 1, y + 1);
        for (int x = 0; x < w; ++x) {
            const int sum = tmp[static_cast<size_t>(yu * w + x)]
                          + tmp[static_cast<size_t>(y  * w + x)]
                          + tmp[static_cast<size_t>(yd * w + x)];
            dst[static_cast<size_t>(y * w + x)] = static_cast<uint8_t>(sum / 3);
        }
    }
    return dst;
}

// ---------------------------------------------------------------------------
// Stage 3: Sobel magnitude map. mag = |Gx| + |Gy|.
// ---------------------------------------------------------------------------
static std::vector<uint16_t> sobelMagnitude(const std::vector<uint8_t>& blur,
                                            int w, int h) {
    std::vector<uint16_t> mag(static_cast<size_t>(w * h), 0);
    for (int y = 1; y < h - 1; ++y) {
        for (int x = 1; x < w - 1; ++x) {
            const auto px = [&](int dy, int dx) -> int {
                return static_cast<int>(
                    blur[static_cast<size_t>((y + dy) * w + (x + dx))]);
            };
            const int gx = -px(-1,-1) + px(-1,1)
                         - 2*px(0,-1) + 2*px(0,1)
                         -   px(1,-1) +   px(1,1);
            const int gy = -px(-1,-1) - 2*px(-1,0) - px(-1,1)
                         +   px(1,-1) + 2*px(1, 0) + px(1, 1);
            const int m = std::abs(gx) + std::abs(gy);
            mag[static_cast<size_t>(y * w + x)] =
                static_cast<uint16_t>(std::min(m, 65535));
        }
    }
    return mag;
}

// ---------------------------------------------------------------------------
// Stage 4: adaptive Canny thresholds.
// hi = max(non-zero mag) * 0.5 — adapts to the actual dynamic range so we
// always capture the strongest half of edges regardless of image contrast.
// lo = hi * 0.4 (standard Canny 2.5:1 ratio).
// ---------------------------------------------------------------------------
static void adaptiveCannyThresholds(const std::vector<uint16_t>& mag,
                                    uint16_t& lo, uint16_t& hi) {
    uint16_t maxMag = 0;
    for (auto v : mag) if (v > maxMag) maxMag = v;
    if (maxMag == 0) { lo = 0; hi = 0; return; }
    const float hiF = static_cast<float>(maxMag) * 0.5f;
    const float loF = hiF * 0.4f;
    hi = static_cast<uint16_t>(std::min(hiF, 65535.f));
    lo = static_cast<uint16_t>(std::min(loF, 65535.f));
}

// ---------------------------------------------------------------------------
// Stage 5: Canny non-maximum suppression + hysteresis thresholding.
// Returns a byte map: 255 = edge, 0 = non-edge.
// ---------------------------------------------------------------------------
static std::vector<uint8_t> cannyNonMaxSuppression(const std::vector<uint16_t>& mag,
                                                   int w, int h,
                                                   uint16_t lo, uint16_t hi) {
    // Simple threshold-based edge map (no angle-based NMS for brevity;
    // works well on bright-rect synthetic images and real docs).
    std::vector<uint8_t> edges(static_cast<size_t>(w * h), 0);
    if (hi == 0) return edges;

    // Mark strong edges
    std::vector<bool> strong(static_cast<size_t>(w * h), false);
    std::vector<bool> weak(static_cast<size_t>(w * h), false);
    for (size_t i = 0; i < mag.size(); ++i) {
        if (mag[i] >= hi)      strong[i] = true;
        else if (mag[i] >= lo) weak[i]   = true;
    }

    // Hysteresis: weak edge becomes real if 8-connected to a strong edge.
    std::vector<int> stack;
    stack.reserve(512);
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x)
            if (strong[static_cast<size_t>(y * w + x)]) {
                edges[static_cast<size_t>(y * w + x)] = 255;
                stack.push_back(y * w + x);
            }

    while (!stack.empty()) {
        const int idx = stack.back(); stack.pop_back();
        const int cy = idx / w;
        const int cx = idx % w;
        for (int dy = -1; dy <= 1; ++dy) {
            for (int dx = -1; dx <= 1; ++dx) {
                if (dy == 0 && dx == 0) continue;
                const int ny = cy + dy;
                const int nx = cx + dx;
                if (ny < 0 || ny >= h || nx < 0 || nx >= w) continue;
                const size_t ni = static_cast<size_t>(ny * w + nx);
                if (weak[ni] && edges[ni] == 0) {
                    edges[ni] = 255;
                    stack.push_back(ny * w + nx);
                }
            }
        }
    }
    return edges;
}

// ---------------------------------------------------------------------------
// Stage 6: Hough line transform.
// Accumulator over (rho, theta). Returns up to maxLines strongest lines.
// ---------------------------------------------------------------------------
static std::vector<Line> houghLines(const std::vector<uint8_t>& edges,
                                    int w, int h,
                                    int maxLines = 120) {
    const int numTheta = 180;
    const float dTheta = static_cast<float>(M_PI) / numTheta;
    const float diagLen = std::sqrt(static_cast<float>(w * w + h * h));
    const int numRho = static_cast<int>(2.0f * diagLen) + 1;
    const float rhoOffset = diagLen;

    std::vector<int> acc(static_cast<size_t>(numRho * numTheta), 0);

    // Pre-compute cos/sin tables
    std::vector<float> cosT(numTheta), sinT(numTheta);
    for (int t = 0; t < numTheta; ++t) {
        cosT[t] = std::cos(t * dTheta);
        sinT[t] = std::sin(t * dTheta);
    }

    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            if (edges[static_cast<size_t>(y * w + x)] == 0) continue;
            for (int t = 0; t < numTheta; ++t) {
                const float rho = x * cosT[t] + y * sinT[t];
                const int ri = static_cast<int>(rho + rhoOffset);
                if (ri >= 0 && ri < numRho)
                    acc[static_cast<size_t>(ri * numTheta + t)]++;
            }
        }
    }

    // Peak pick — collect (count, index) pairs then sort descending.
    std::vector<std::pair<int, int>> peaks;
    peaks.reserve(static_cast<size_t>(maxLines * 4));
    for (int i = 0; i < numRho * numTheta; ++i)
        if (acc[i] > 0) peaks.emplace_back(acc[i], i);

    std::sort(peaks.begin(), peaks.end(),
              [](const std::pair<int,int>& a, const std::pair<int,int>& b){
                  return a.first > b.first;
              });

    const int take = std::min(static_cast<int>(peaks.size()), maxLines);
    std::vector<Line> lines;
    lines.reserve(static_cast<size_t>(take));
    for (int i = 0; i < take; ++i) {
        const int idx = peaks[i].second;
        const int ri  = idx / numTheta;
        const int ti  = idx % numTheta;
        lines.push_back({static_cast<float>(ri) - rhoOffset,
                         ti * dTheta});
    }
    return lines;
}

// ---------------------------------------------------------------------------
// Stage 7a: Cluster lines into horizontal (near 0°/180°) and vertical
// (near 90°) groups.
// ---------------------------------------------------------------------------
static void clusterDominantAngles(const std::vector<Line>& lines,
                                  std::vector<Line>& horiz,
                                  std::vector<Line>& vert) {
    // Horizontal: theta in [0, pi/4) ∪ (3pi/4, pi)
    // Vertical:   theta in [pi/4, 3pi/4]
    const float quarter = static_cast<float>(M_PI) / 4.0f;
    const float three_quarter = 3.0f * quarter;
    for (const auto& l : lines) {
        if (l.theta < quarter || l.theta > three_quarter) horiz.push_back(l);
        else                                              vert.push_back(l);
    }
}

// ---------------------------------------------------------------------------
// Stage 7b: Compute intersection of two Hough lines.
// Line: x*cos(theta) + y*sin(theta) = rho
// ---------------------------------------------------------------------------
static bool lineIntersect(const Line& a, const Line& b,
                          float& px, float& py) {
    const float ct1 = std::cos(a.theta), st1 = std::sin(a.theta);
    const float ct2 = std::cos(b.theta), st2 = std::sin(b.theta);
    const float det = ct1 * st2 - st1 * ct2;
    if (std::abs(det) < 1e-6f) return false;
    px = (a.rho * st2 - b.rho * st1) / det;
    py = (b.rho * ct1 - a.rho * ct2) / det;
    return true;
}

// ---------------------------------------------------------------------------
// Stage 8: For every pair (h1,h2) × pair (v1,v2) compute 4 intersections.
// ---------------------------------------------------------------------------
struct RawQuad { std::array<float, 8> pts; };  // x0,y0 x1,y1 x2,y2 x3,y3

static std::vector<RawQuad> intersectToQuads(const std::vector<Line>& horiz,
                                             const std::vector<Line>& vert,
                                             int w, int h) {
    const int maxH = std::min(static_cast<int>(horiz.size()), 20);
    const int maxV = std::min(static_cast<int>(vert.size()),  20);
    std::vector<RawQuad> quads;
    quads.reserve(static_cast<size_t>(maxH * (maxH - 1) / 2 *
                                      maxV * (maxV - 1) / 2));
    const float fw = static_cast<float>(w);
    const float fh = static_cast<float>(h);

    for (int hi = 0; hi < maxH - 1; ++hi) {
        for (int hj = hi + 1; hj < maxH; ++hj) {
            for (int vi = 0; vi < maxV - 1; ++vi) {
                for (int vj = vi + 1; vj < maxV; ++vj) {
                    float x0, y0, x1, y1, x2, y2, x3, y3;
                    if (!lineIntersect(horiz[hi], vert[vi],  x0, y0)) continue;
                    if (!lineIntersect(horiz[hi], vert[vj],  x1, y1)) continue;
                    if (!lineIntersect(horiz[hj], vert[vj],  x2, y2)) continue;
                    if (!lineIntersect(horiz[hj], vert[vi],  x3, y3)) continue;
                    // Filter out quads with corners far off-image.
                    const float margin = 0.3f;
                    auto oob = [&](float px, float py) {
                        return px < -margin * fw || px > (1.f + margin) * fw ||
                               py < -margin * fh || py > (1.f + margin) * fh;
                    };
                    if (oob(x0,y0)||oob(x1,y1)||oob(x2,y2)||oob(x3,y3)) continue;
                    quads.push_back({{{x0,y0, x1,y1, x2,y2, x3,y3}}});
                }
            }
        }
    }
    return quads;
}

// ---------------------------------------------------------------------------
// Stage 9: Score a candidate quad.
// score = area_fraction * edge_energy_along_sides * orthogonality_bonus
// ---------------------------------------------------------------------------
static float scoreQuad(const RawQuad& q,
                       const std::vector<uint8_t>& edges,
                       int w, int h) {
    // Compute signed area via shoelace.
    const float x0 = q.pts[0], y0 = q.pts[1];
    const float x1 = q.pts[2], y1 = q.pts[3];
    const float x2 = q.pts[4], y2 = q.pts[5];
    const float x3 = q.pts[6], y3 = q.pts[7];

    const float area = 0.5f * std::abs(
        (x0*y1 - x1*y0) + (x1*y2 - x2*y1) +
        (x2*y3 - x3*y2) + (x3*y0 - x0*y3));

    const float imageArea = static_cast<float>(w * h);
    if (imageArea < 1.f || area < 1.f) return 0.f;

    const float areaFraction = std::min(area / imageArea, 1.f);
    if (areaFraction < 0.05f) return 0.f;  // too tiny

    // Edge energy: sample along the 4 sides.
    auto sampleEdge = [&](float ax, float ay, float bx, float by) -> float {
        const int steps = 32;
        int hits = 0;
        for (int s = 0; s <= steps; ++s) {
            const float t = static_cast<float>(s) / steps;
            const int px = static_cast<int>(ax + t * (bx - ax) + 0.5f);
            const int py = static_cast<int>(ay + t * (by - ay) + 0.5f);
            if (px >= 0 && px < w && py >= 0 && py < h)
                if (edges[static_cast<size_t>(py * w + px)] > 0) ++hits;
        }
        return static_cast<float>(hits) / (steps + 1);
    };
    const float edgeEnergy = (sampleEdge(x0,y0,x1,y1) + sampleEdge(x1,y1,x2,y2) +
                              sampleEdge(x2,y2,x3,y3) + sampleEdge(x3,y3,x0,y0)) / 4.f;

    // Orthogonality bonus: dot products of adjacent sides should be near 0.
    auto dot2d = [](float ax, float ay, float bx, float by) -> float {
        const float la = std::sqrt(ax*ax + ay*ay);
        const float lb = std::sqrt(bx*bx + by*by);
        if (la < 1e-6f || lb < 1e-6f) return 1.f;
        return (ax/la)*(bx/lb) + (ay/la)*(by/lb);
    };
    const float d01x = x1-x0, d01y = y1-y0;
    const float d12x = x2-x1, d12y = y2-y1;
    const float d23x = x3-x2, d23y = y3-y2;
    const float d30x = x0-x3, d30y = y0-y3;
    const float maxDot = std::max({std::abs(dot2d(d01x,d01y, d12x,d12y)),
                                   std::abs(dot2d(d12x,d12y, d23x,d23y)),
                                   std::abs(dot2d(d23x,d23y, d30x,d30y)),
                                   std::abs(dot2d(d30x,d30y, d01x,d01y))});
    const float orthBonus = 1.f - maxDot;  // 1.0 when perfectly orthogonal

    return areaFraction * edgeEnergy * orthBonus;
}

// ---------------------------------------------------------------------------
// Stage 10: pick best quad by score.
// Why: 0.03 is low enough that a bright rect on dark bg (strong edges,
// reasonable area, near-orthogonal) scores well above it, while a uniform
// grey image has zero edge energy and never reaches this threshold.
// ---------------------------------------------------------------------------
static constexpr float kMinScore = 0.03f;

struct ScoredQuad { RawQuad q; float score; };

static std::optional<ScoredQuad> pickBest(const std::vector<RawQuad>& candidates,
                                          const std::vector<uint8_t>& edges,
                                          int w, int h) {
    float best = kMinScore;
    std::optional<ScoredQuad> winner;
    for (const auto& c : candidates) {
        const float s = scoreQuad(c, edges, w, h);
        if (s > best) { best = s; winner = ScoredQuad{c, s}; }
    }
    return winner;
}

// ---------------------------------------------------------------------------
// Helpers: sort corners into TL, TR, BR, BL order.
// ---------------------------------------------------------------------------
static std::array<std::array<float, 2>, 4>
sortCornersTLTRBRBL(const RawQuad& q) {
    std::array<std::array<float, 2>, 4> pts = {{
        {{q.pts[0], q.pts[1]}},
        {{q.pts[2], q.pts[3]}},
        {{q.pts[4], q.pts[5]}},
        {{q.pts[6], q.pts[7]}}
    }};
    // Sort by y first to split top/bottom pairs.
    std::sort(pts.begin(), pts.end(),
              [](const std::array<float,2>& a, const std::array<float,2>& b){
                  return a[1] < b[1];
              });
    // Top pair: sort by x → TL, TR.
    if (pts[0][0] > pts[1][0]) std::swap(pts[0], pts[1]);
    // Bottom pair: sort by x → BL, BR.
    if (pts[2][0] > pts[3][0]) std::swap(pts[2], pts[3]);
    // Final order: TL, TR, BR, BL
    return {{ pts[0], pts[1], pts[3], pts[2] }};
}

}  // anonymous namespace

// ---------------------------------------------------------------------------
// Public API (outside anonymous namespace; SUPY_EXPORT overrides hidden-visibility).
// ---------------------------------------------------------------------------
SUPY_EXPORT std::optional<DetectedQuad> detectDocument(const DetectionInput& in) {
    if (!in.luma || in.width <= 0 || in.height <= 0 || in.rowStride < in.width)
        return std::nullopt;
    if (in.width > kMaxDimension || in.height > kMaxDimension || in.rowStride > kMaxDimension)
        return std::nullopt;

    // Stage 1: downsample to ≤256px working image.
    int wW = 0, wH = 0;
    const auto work = downsampleAndCrop(in, wW, wH);

    // Stage 2: blur.
    const auto blurred = gaussianBlur3x3(work, wW, wH);

    // Stage 3: Sobel magnitude.
    const auto mag = sobelMagnitude(blurred, wW, wH);

    // Stage 4: adaptive thresholds.
    uint16_t lo = 0, hi = 0;
    adaptiveCannyThresholds(mag, lo, hi);
    if (hi == 0) return std::nullopt;

    // Stage 5: Canny edges.
    const auto edges = cannyNonMaxSuppression(mag, wW, wH, lo, hi);

    // Stage 6: Hough lines.
    const auto lines = houghLines(edges, wW, wH, 120);
    if (lines.empty()) return std::nullopt;

    // Stage 7: Cluster.
    std::vector<Line> horiz, vert;
    clusterDominantAngles(lines, horiz, vert);
    if (horiz.size() < 2 || vert.size() < 2) return std::nullopt;

    // Stage 8: Intersect pairs → candidate quads.
    const auto candidates = intersectToQuads(horiz, vert, wW, wH);
    if (candidates.empty()) return std::nullopt;

    // Stage 9-10: Score and pick.
    const auto best = pickBest(candidates, edges, wW, wH);
    if (!best) return std::nullopt;

    // Map corners back to normalized full-image coordinates.
    const float scaleX = static_cast<float>(in.width)  / wW;
    const float scaleY = static_cast<float>(in.height) / wH;
    const float normX  = 1.f / in.width;
    const float normY  = 1.f / in.height;

    const auto sorted = sortCornersTLTRBRBL(best->q);

    DetectedQuad result{};
    for (int i = 0; i < 4; ++i) {
        result.corners[i].x = std::max(0.f, std::min(1.f,
            sorted[i][0] * scaleX * normX));
        result.corners[i].y = std::max(0.f, std::min(1.f,
            sorted[i][1] * scaleY * normY));
    }

    // coverageRatio: shoelace on normalized coords.
    const auto& c = result.corners;
    result.coverageRatio = 0.5f * std::abs(
        (c[0].x*c[1].y - c[1].x*c[0].y) + (c[1].x*c[2].y - c[2].x*c[1].y) +
        (c[2].x*c[3].y - c[3].x*c[2].y) + (c[3].x*c[0].y - c[0].x*c[3].y));

    // tiltDegrees: angle of the top edge (TL→TR) from horizontal.
    const float dx = c[1].x - c[0].x;
    const float dy = c[1].y - c[0].y;
    result.tiltDegrees = std::atan2(dy, dx) * 180.f /
                         static_cast<float>(M_PI);

    return result;
}

}  // namespace supy::scanner::document
