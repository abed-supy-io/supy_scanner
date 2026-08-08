package io.supy.scanner.perf

import androidx.camera.core.ImageProxy

/**
 * Cheap "is the camera looking at a static scene?" gate.
 *
 * Samples the Y plane on a stride and computes a luma variance per frame. If
 * the variance stays below [varianceThreshold] for [thresholdMs], the
 * detector flips to `idle` and downstream analyzers are expected to skip ML
 * Kit work. Any motion (variance spike) flips it back immediately.
 *
 * Not thread-safe — call from a single analyzer thread.
 */
class IdleDetector(
    private val thresholdMs: Long?,
    private val varianceThreshold: Double = 60.0,
    private val motionVariance: Double = 200.0,
) {

    var isIdle: Boolean = false
        private set

    private var stillSinceMs: Long = 0L

    /**
     * Returns true when the state transitioned this frame (idle ↔ active).
     * Callers should emit an event on transition.
     */
    fun update(image: ImageProxy, nowMs: Long): Boolean {
        val threshold = thresholdMs ?: return false
        val variance = sampleVariance(image)

        if (variance >= motionVariance) {
            stillSinceMs = 0L
            if (isIdle) {
                isIdle = false
                return true
            }
            return false
        }

        if (variance <= varianceThreshold) {
            if (stillSinceMs == 0L) stillSinceMs = nowMs
            if (!isIdle && nowMs - stillSinceMs >= threshold) {
                isIdle = true
                return true
            }
            return false
        }

        // Between thresholds — keep current state, but don't accumulate
        // "still" time on noisy mid-range readings.
        stillSinceMs = 0L
        return false
    }

    private fun sampleVariance(image: ImageProxy): Double {
        val plane = image.planes.firstOrNull() ?: return 0.0
        val buffer = plane.buffer
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride.coerceAtLeast(1)
        val width = image.width
        val height = image.height
        if (width <= 0 || height <= 0) return 0.0

        // Stride covers ~32×32 grid → ≤1024 samples, regardless of resolution.
        val stepX = maxOf(1, width / 32)
        val stepY = maxOf(1, height / 32)

        var count = 0L
        var sum = 0L
        var sumSq = 0L
        var y = 0
        while (y < height) {
            val rowBase = y * rowStride
            var x = 0
            while (x < width) {
                val idx = rowBase + x * pixelStride
                if (idx < buffer.limit()) {
                    val v = buffer.get(idx).toInt() and 0xFF
                    sum += v
                    sumSq += v * v
                    count += 1L
                }
                x += stepX
            }
            y += stepY
        }
        if (count == 0L) return 0.0
        val mean = sum.toDouble() / count
        val meanSq = sumSq.toDouble() / count
        return meanSq - mean * mean
    }
}
