// document_edge_detector.h — on-device document quad detection from a Y-plane.
// No network calls, no dynamic dispatch, no exceptions in detection path.
#pragma once
#include <array>
#include <cstdint>
#include <optional>

namespace supy::scanner::document {

struct Point {
    float x;  // normalized [0,1], left origin
    float y;  // normalized [0,1], top origin
};

struct DetectedQuad {
    std::array<Point, 4> corners;  // TL, TR, BR, BL order
    float coverageRatio;           // quad area / image area
    float tiltDegrees;             // top edge angle from horizontal; 0 = head-on
};

struct DetectionInput {
    const uint8_t* luma;  // Y plane data
    int width;
    int height;
    int rowStride;  // bytes per row (>= width)
};

// Returns std::nullopt if no acceptable quad found.
#if defined(_WIN32)
#  define SUPY_EXPORT __declspec(dllexport)
#else
#  define SUPY_EXPORT __attribute__((visibility("default")))
#endif
SUPY_EXPORT std::optional<DetectedQuad> detectDocument(const DetectionInput& in);

}  // namespace supy::scanner::document
