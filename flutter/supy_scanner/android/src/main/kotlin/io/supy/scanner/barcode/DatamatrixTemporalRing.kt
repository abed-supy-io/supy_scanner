package io.supy.scanner.barcode

import io.supy.scanner.nativecore.SupyNativeCore
import java.nio.ByteBuffer

/**
 * Two-slot ring of recent libdmtx-located frames used by the V1-S2-06 temporal
 * median-of-3 fusion. Per analyzer thread; not safe for concurrent use across
 * threads. Push the current frame after attempting fusion against the prior
 * two so the next frame can match against this one.
 *
 * The kernel itself lives in native (`SupyNativeCore.temporalMedianLuma3`);
 * this class is the matching + bookkeeping shell around it.
 */
internal class DatamatrixTemporalRing {

    /** Axis-aligned bbox in source-frame pixel coords (inclusive both ends). */
    data class Box(val x0: Int, val y0: Int, val x1: Int, val y1: Int)

    /** Output of a successful fusion: median-fused packed luma + source-frame bounds. */
    data class FusedCrop(
        val luma: ByteBuffer,
        val width: Int,
        val height: Int,
        val srcX0: Int,
        val srcY0: Int,
    )

    private data class Slot(
        val w: Int,
        val h: Int,
        val rowStride: Int,
        val luma: ByteBuffer,
        val boxes: List<Box>,
    )

    private var prev1: Slot? = null
    private var prev2: Slot? = null

    // Pooled scratch buffers — three packed crops + one output, all sized to the
    // union bbox of the current attempt. Grown lazily, never shrunk.
    private var cropA: ByteBuffer? = null
    private var cropB: ByteBuffer? = null
    private var cropC: ByteBuffer? = null
    private var cropOut: ByteBuffer? = null

    // Pooled full-luma copy buffers for ring storage — same lifetime as the
    // ring; reused across frames once stable size is reached.
    private var lumaPoolA: ByteBuffer? = null
    private var lumaPoolB: ByteBuffer? = null

    /**
     * Tries to fuse [curBox] from [curLuma] with IoU-matched boxes from each
     * of the previous two slots. Returns null if either prior slot is missing,
     * geometry differs, or IoU < [iouThreshold] in either slot.
     */
    fun tryFuse(
        curLuma: ByteBuffer,
        curW: Int,
        curH: Int,
        curRowStride: Int,
        curBox: Box,
        iouThreshold: Float = 0.5f,
    ): FusedCrop? {
        val p1 = prev1 ?: return null
        val p2 = prev2 ?: return null
        if (p1.w != curW || p1.h != curH) return null
        if (p2.w != curW || p2.h != curH) return null

        val m1 = bestMatch(curBox, p1.boxes, iouThreshold) ?: return null
        val m2 = bestMatch(curBox, p2.boxes, iouThreshold) ?: return null

        // Union bbox across all three matched boxes — clamped to frame.
        val ux0 = minOf(curBox.x0, m1.x0, m2.x0).coerceAtLeast(0)
        val uy0 = minOf(curBox.y0, m1.y0, m2.y0).coerceAtLeast(0)
        val ux1 = maxOf(curBox.x1, m1.x1, m2.x1).coerceAtMost(curW - 1)
        val uy1 = maxOf(curBox.y1, m1.y1, m2.y1).coerceAtMost(curH - 1)
        val uw = ux1 - ux0 + 1
        val uh = uy1 - uy0 + 1
        if (uw < 12 || uh < 12) return null

        val need = uw * uh
        val a = ensureCapacity(::cropA, need); cropA = a
        val b = ensureCapacity(::cropB, need); cropB = b
        val c = ensureCapacity(::cropC, need); cropC = c
        val o = ensureCapacity(::cropOut, need); cropOut = o

        copyLumaCrop(p2.luma, p2.rowStride, ux0, uy0, uw, uh, a)
        copyLumaCrop(p1.luma, p1.rowStride, ux0, uy0, uw, uh, b)
        copyLumaCrop(curLuma, curRowStride, ux0, uy0, uw, uh, c)

        val ok = try {
            SupyNativeCore.temporalMedianLuma3(a, b, c, o, uw, uh, uw)
        } catch (_: Throwable) {
            false
        }
        if (!ok) return null
        return FusedCrop(o, uw, uh, ux0, uy0)
    }

    /**
     * Push the current frame's full luma + located bboxes into the ring. Call
     * once per frame that had locator hits, AFTER all per-region [tryFuse]
     * attempts for that frame. Frames without locator hits should not be
     * pushed — the ring is meant to capture stable held-region streaks.
     */
    fun push(
        luma: ByteBuffer,
        w: Int,
        h: Int,
        rowStride: Int,
        boxes: List<Box>,
    ) {
        if (boxes.isEmpty()) return
        // Evict slots whose geometry no longer matches — they can't be fused.
        if (prev1 != null && (prev1!!.w != w || prev1!!.h != h)) prev1 = null
        if (prev2 != null && (prev2!!.w != w || prev2!!.h != h)) prev2 = null

        // Recycle: the slot we're about to overwrite donates its luma buffer
        // back to the pool, slots shift, new slot consumes a pool buffer.
        val needed = h * rowStride
        val recycledFromPrev2 = prev2?.luma
        prev2 = prev1
        val poolBuf = ensureLumaPool(recycledFromPrev2, needed)
        copyFullLuma(luma, rowStride, h, poolBuf)
        prev1 = Slot(w, h, rowStride, poolBuf, boxes)
    }

    /** Drop all slots and free pool refs. Call from analyzer shutdown / dispose. */
    fun reset() {
        prev1 = null
        prev2 = null
    }

    private fun ensureLumaPool(recycled: ByteBuffer?, needed: Int): ByteBuffer {
        // Prefer the recycled buffer if it fits; else grow one of the pool refs.
        if (recycled != null && recycled.capacity() >= needed) return recycled
        val a = lumaPoolA
        val b = lumaPoolB
        if (a != null && a !== prev1?.luma && a !== prev2?.luma && a.capacity() >= needed) return a
        if (b != null && b !== prev1?.luma && b !== prev2?.luma && b.capacity() >= needed) return b
        val grown = ByteBuffer.allocateDirect(needed + (needed shr 2))
        if (lumaPoolA == null) lumaPoolA = grown else lumaPoolB = grown
        return grown
    }

    private fun ensureCapacity(ref: () -> ByteBuffer?, needed: Int): ByteBuffer {
        val cur = ref()
        if (cur != null && cur.capacity() >= needed) {
            cur.clear()
            return cur
        }
        return ByteBuffer.allocateDirect(needed + (needed shr 1))
    }

    companion object {
        /**
         * Returns the best-IoU box in [candidates] against [target] if it
         * meets [threshold]; null otherwise.
         */
        fun bestMatch(target: Box, candidates: List<Box>, threshold: Float): Box? {
            var best: Box? = null
            var bestIou = threshold
            for (c in candidates) {
                val v = iou(target, c)
                if (v >= bestIou) {
                    bestIou = v
                    best = c
                }
            }
            return best
        }

        private fun iou(a: Box, b: Box): Float {
            val ix0 = maxOf(a.x0, b.x0)
            val iy0 = maxOf(a.y0, b.y0)
            val ix1 = minOf(a.x1, b.x1)
            val iy1 = minOf(a.y1, b.y1)
            if (ix1 < ix0 || iy1 < iy0) return 0f
            val inter = (ix1 - ix0 + 1).toLong() * (iy1 - iy0 + 1).toLong()
            val areaA = (a.x1 - a.x0 + 1).toLong() * (a.y1 - a.y0 + 1).toLong()
            val areaB = (b.x1 - b.x0 + 1).toLong() * (b.y1 - b.y0 + 1).toLong()
            val union = areaA + areaB - inter
            if (union <= 0) return 0f
            return (inter.toDouble() / union.toDouble()).toFloat()
        }

        private fun copyLumaCrop(
            src: ByteBuffer,
            srcStride: Int,
            x0: Int,
            y0: Int,
            cw: Int,
            ch: Int,
            dst: ByteBuffer,
        ) {
            val srcView = src.duplicate()
            dst.position(0).limit(dst.capacity())
            val row = ByteArray(cw)
            for (yy in 0 until ch) {
                val srcOff = (y0 + yy) * srcStride + x0
                srcView.position(srcOff)
                srcView.get(row, 0, cw)
                dst.put(row, 0, cw)
            }
            dst.flip()
        }

        private fun copyFullLuma(src: ByteBuffer, rowStride: Int, h: Int, dst: ByteBuffer) {
            val srcView = src.duplicate()
            srcView.position(0)
            dst.position(0).limit(dst.capacity())
            val bytes = h * rowStride
            val chunk = ByteArray(rowStride)
            var remaining = bytes
            while (remaining > 0) {
                val take = minOf(chunk.size, remaining)
                srcView.get(chunk, 0, take)
                dst.put(chunk, 0, take)
                remaining -= take
            }
        }
    }
}
