// Per-analyzer ring of the last two libdmtx-located frames used by the
// V1-S2-06 temporal median-of-3 fusion. Mirrors the Android
// `DatamatrixTemporalRing.kt` shell — fusion kernel itself lives in native
// (`SupyNativeCore.temporalMedianLuma3`). Analyzer-thread only.

import Foundation

final class DatamatrixTemporalRing {

  /// Axis-aligned bbox in source-frame pixel coords (inclusive both ends).
  struct Box {
    let x0: Int
    let y0: Int
    let x1: Int
    let y1: Int
  }

  /// Result of a successful fusion: median-fused packed luma + bounds in the
  /// current frame's source coords. `luma` points into one of the ring's
  /// pooled output buffers and is valid until the next `tryFuse` / `push`.
  struct FusedCrop {
    let luma: UnsafePointer<UInt8>
    let width: Int
    let height: Int
    let srcX0: Int
    let srcY0: Int
  }

  private struct Slot {
    let w: Int
    let h: Int
    let rowStride: Int
    var luma: [UInt8]
    let boxes: [Box]
  }

  private var prev1: Slot?
  private var prev2: Slot?

  // Pooled crop buffers — three packed inputs + one fused output. Grown
  // lazily, never shrunk. Layout: packed rowStride == width.
  private var cropA: [UInt8] = []
  private var cropB: [UInt8] = []
  private var cropC: [UInt8] = []
  private var cropOut: [UInt8] = []

  /// IoU-gated 3-frame fusion. Returns nil if either prior is missing,
  /// geometry differs, or IoU < `iouThreshold` in either slot. On success the
  /// returned `FusedCrop.luma` pointer is valid until the next call.
  func tryFuse(
    curLuma: UnsafePointer<UInt8>,
    curW: Int,
    curH: Int,
    curRowStride: Int,
    curBox: Box,
    iouThreshold: Float = 0.5
  ) -> FusedCrop? {
    guard let p1 = prev1, let p2 = prev2 else { return nil }
    if p1.w != curW || p1.h != curH { return nil }
    if p2.w != curW || p2.h != curH { return nil }

    guard let m1 = Self.bestMatch(target: curBox, candidates: p1.boxes, threshold: iouThreshold) else { return nil }
    guard let m2 = Self.bestMatch(target: curBox, candidates: p2.boxes, threshold: iouThreshold) else { return nil }

    let ux0 = max(0, min(curBox.x0, min(m1.x0, m2.x0)))
    let uy0 = max(0, min(curBox.y0, min(m1.y0, m2.y0)))
    let ux1 = min(curW - 1, max(curBox.x1, max(m1.x1, m2.x1)))
    let uy1 = min(curH - 1, max(curBox.y1, max(m1.y1, m2.y1)))
    let uw = ux1 - ux0 + 1
    let uh = uy1 - uy0 + 1
    if uw < 12 || uh < 12 { return nil }

    let need = uw * uh
    Self.ensureCapacity(&cropA, need: need)
    Self.ensureCapacity(&cropB, need: need)
    Self.ensureCapacity(&cropC, need: need)
    Self.ensureCapacity(&cropOut, need: need)

    p2.luma.withUnsafeBufferPointer { src in
      cropA.withUnsafeMutableBufferPointer { dst in
        Self.copyLumaCrop(src: src.baseAddress!, srcStride: p2.rowStride, x0: ux0, y0: uy0, cw: uw, ch: uh, dst: dst.baseAddress!)
      }
    }
    p1.luma.withUnsafeBufferPointer { src in
      cropB.withUnsafeMutableBufferPointer { dst in
        Self.copyLumaCrop(src: src.baseAddress!, srcStride: p1.rowStride, x0: ux0, y0: uy0, cw: uw, ch: uh, dst: dst.baseAddress!)
      }
    }
    cropC.withUnsafeMutableBufferPointer { dst in
      Self.copyLumaCrop(src: curLuma, srcStride: curRowStride, x0: ux0, y0: uy0, cw: uw, ch: uh, dst: dst.baseAddress!)
    }

    let ok: Bool = cropA.withUnsafeBufferPointer { a in
      cropB.withUnsafeBufferPointer { b in
        cropC.withUnsafeBufferPointer { c in
          cropOut.withUnsafeMutableBufferPointer { o in
            SupyNativeCore.temporalMedianLuma3(
              frame0: a.baseAddress!,
              frame1: b.baseAddress!,
              frame2: c.baseAddress!,
              out: o.baseAddress!,
              width: Int32(uw),
              height: Int32(uh),
              rowStride: Int32(uw)
            )
          }
        }
      }
    }
    if !ok { return nil }
    return cropOut.withUnsafeBufferPointer { buf in
      FusedCrop(luma: buf.baseAddress!, width: uw, height: uh, srcX0: ux0, srcY0: uy0)
    }
  }

  /// Push this frame's full luma + located bboxes into the ring. Call once
  /// per frame that had locator hits, AFTER all per-region `tryFuse` attempts.
  /// Frames without hits are not pushed — the ring captures held-region streaks.
  func push(
    luma: UnsafePointer<UInt8>,
    width: Int,
    height: Int,
    rowStride: Int,
    boxes: [Box]
  ) {
    if boxes.isEmpty { return }
    if let p1 = prev1, (p1.w != width || p1.h != height) { prev1 = nil }
    if let p2 = prev2, (p2.w != width || p2.h != height) { prev2 = nil }

    let needed = height * rowStride
    var recycled = prev2?.luma ?? []
    if recycled.count < needed {
      recycled = [UInt8](repeating: 0, count: needed + (needed >> 2))
    }
    recycled.withUnsafeMutableBufferPointer { dst in
      memcpy(dst.baseAddress, luma, needed)
    }

    prev2 = prev1
    prev1 = Slot(w: width, h: height, rowStride: rowStride, luma: recycled, boxes: boxes)
  }

  func reset() {
    prev1 = nil
    prev2 = nil
  }

  private static func ensureCapacity(_ buf: inout [UInt8], need: Int) {
    if buf.count < need {
      buf = [UInt8](repeating: 0, count: need + (need >> 1))
    }
  }

  static func bestMatch(target: Box, candidates: [Box], threshold: Float) -> Box? {
    var best: Box?
    var bestIou = threshold
    for c in candidates {
      let v = iou(target, c)
      if v >= bestIou {
        bestIou = v
        best = c
      }
    }
    return best
  }

  private static func iou(_ a: Box, _ b: Box) -> Float {
    let ix0 = max(a.x0, b.x0)
    let iy0 = max(a.y0, b.y0)
    let ix1 = min(a.x1, b.x1)
    let iy1 = min(a.y1, b.y1)
    if ix1 < ix0 || iy1 < iy0 { return 0 }
    let inter = Int64(ix1 - ix0 + 1) * Int64(iy1 - iy0 + 1)
    let areaA = Int64(a.x1 - a.x0 + 1) * Int64(a.y1 - a.y0 + 1)
    let areaB = Int64(b.x1 - b.x0 + 1) * Int64(b.y1 - b.y0 + 1)
    let union = areaA + areaB - inter
    if union <= 0 { return 0 }
    return Float(Double(inter) / Double(union))
  }

  private static func copyLumaCrop(
    src: UnsafePointer<UInt8>,
    srcStride: Int,
    x0: Int,
    y0: Int,
    cw: Int,
    ch: Int,
    dst: UnsafeMutablePointer<UInt8>
  ) {
    for yy in 0..<ch {
      let srcRow = src.advanced(by: (y0 + yy) * srcStride + x0)
      let dstRow = dst.advanced(by: yy * cw)
      dstRow.update(from: srcRow, count: cw)
    }
  }
}
