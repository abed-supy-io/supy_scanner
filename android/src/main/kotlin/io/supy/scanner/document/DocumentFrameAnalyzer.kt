package io.supy.scanner.document

import android.annotation.SuppressLint
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import io.supy.scanner.nativecore.SupyNativeCore
import kotlin.math.max

/**
 * One frame's worth of measurements emitted to the Dart state machine.
 *
 * Matches the iOS `DocumentFrameMetrics` wire shape exactly. The quad is
 * normalized to preview coordinates with the **top-left origin** convention
 * the Flutter side expects. An empty quad signals "no document detected"
 * (the state machine reports `noDocument`).
 */
data class DocumentFrameMetrics(
    /** List of `{"x": Double, "y": Double}` maps — empty when no quad found. */
    val quad: List<Map<String, Double>>,
    val coverageRatio: Double,
    val tiltDegrees: Double,
    val meanLuma: Double,
    val blurScore: Double,
    val clipsEdge: Boolean,
    val interiorVariance: Double = 0.0,
    val quadStability: Double = 0.0,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "quad" to quad,
        "coverageRatio" to coverageRatio,
        "tiltDegrees" to tiltDegrees,
        "meanLuma" to meanLuma,
        "blurScore" to blurScore,
        "clipsEdge" to clipsEdge,
        "interiorVariance" to interiorVariance,
        "quadStability" to quadStability,
    )
}

// Rolling-window corner-drift tracker; mirrors iOS QuadStabilityTracker.
internal class QuadStabilityTracker(private val windowSize: Int = 6) {
    private val history: ArrayDeque<FloatArray> = ArrayDeque()

    fun push(corners: FloatArray): Double {
        if (corners.size != 8) { history.clear(); return 0.0 }
        history.addLast(corners.copyOf())
        while (history.size > windowSize) history.removeFirst()
        return stability()
    }

    fun stability(): Double {
        if (history.size < 2) return 0.0
        var maxDrift = 0.0
        for (corner in 0 until 4) {
            var minX = Double.POSITIVE_INFINITY
            var maxX = Double.NEGATIVE_INFINITY
            var minY = Double.POSITIVE_INFINITY
            var maxY = Double.NEGATIVE_INFINITY
            for (frame in history) {
                val x = frame[corner * 2].toDouble()
                val y = frame[corner * 2 + 1].toDouble()
                if (x < minX) minX = x
                if (x > maxX) maxX = x
                if (y < minY) minY = y
                if (y > maxY) maxY = y
            }
            val drift = kotlin.math.max(maxX - minX, maxY - minY)
            if (drift > maxDrift) maxDrift = drift
        }
        return (1.0 - maxDrift / 0.1).coerceIn(0.0, 1.0)
    }

    fun reset() { history.clear() }
}

/**
 * Per-frame analyzer for the document scanner PlatformView.
 *
 * Runs the JNI document quad detector (`SupyNativeCore.detectQuad`) on each
 * frame's Y plane and emits full `DocumentFrameMetrics` including coverage,
 * tilt, interior variance, and quad stability. Falls back gracefully when the
 * native lib is unavailable: luma metrics are always computed; quad-derived
 * fields are zero/empty.
 *
 * Threading: invoked on the analyzer thread CameraX provides. Results are
 * marshalled to the main thread by the caller (`SupyDocumentScannerView`).
 */
class DocumentFrameAnalyzer(
    private val onMetrics: (DocumentFrameMetrics) -> Unit,
) : ImageAnalysis.Analyzer {

    private val nativeAvailable: Boolean = SupyNativeCore.ensureLoaded()
    private val stabilityTracker = QuadStabilityTracker()

    @SuppressLint("UnsafeOptInUsageError")
    @OptIn(ExperimentalGetImage::class)
    override fun analyze(image: ImageProxy) {
        try {
            val yPlane = image.planes.getOrNull(0)
            if (yPlane == null) {
                onMetrics(DocumentFrameMetrics(emptyList(), 0.0, 0.0, 0.0, 0.0, false, 0.0, 0.0))
                return
            }

            val buf = yPlane.buffer
            val w = image.width
            val h = image.height
            val rowStride = yPlane.rowStride
            val pixelStride = yPlane.pixelStride

            // Native detector requires a tightly packed Y plane (pixelStride == 1).
            // IMAGE_FORMAT_YUV_420_888 guarantees this for the Y plane in practice,
            // but guard explicitly to avoid feeding interleaved data to the C code.
            val native = if (nativeAvailable && pixelStride == 1) {
                SupyNativeCore.detectQuad(buf, w, h, rowStride)
            } else null

            val quad: List<Map<String, Double>> = if (native != null) {
                val c = native.corners
                listOf(
                    mapOf("x" to c[0].toDouble(), "y" to c[1].toDouble()),
                    mapOf("x" to c[2].toDouble(), "y" to c[3].toDouble()),
                    mapOf("x" to c[4].toDouble(), "y" to c[5].toDouble()),
                    mapOf("x" to c[6].toDouble(), "y" to c[7].toDouble()),
                )
            } else emptyList()

            val coverage = native?.coverageRatio?.toDouble() ?: 0.0
            val tilt = native?.tiltDegrees?.toDouble() ?: 0.0
            val clipsEdge = native?.let { detectsEdgeClip(it.corners) } ?: false
            val interior = if (native != null) {
                computeInteriorVariance(buf, w, h, rowStride, pixelStride, native.corners)
            } else 0.0
            val stability = if (native != null) {
                stabilityTracker.push(native.corners)
            } else {
                stabilityTracker.reset()
                0.0
            }

            val luma = computeLumaMetrics(image)
            onMetrics(
                DocumentFrameMetrics(
                    quad = quad,
                    coverageRatio = coverage,
                    tiltDegrees = tilt,
                    meanLuma = luma.meanLuma,
                    blurScore = luma.blurScore,
                    clipsEdge = clipsEdge,
                    interiorVariance = interior,
                    quadStability = stability,
                )
            )
        } catch (t: Throwable) {
            onMetrics(DocumentFrameMetrics(emptyList(), 0.0, 0.0, 0.0, 0.0, false, 0.0, 0.0))
        } finally {
            image.close()
        }
    }

    /**
     * Returns true when any corner is within 0.02 of any normalized frame edge.
     * Mirrors the iOS implementation in `DocumentDetector.swift`.
     */
    private fun detectsEdgeClip(corners: FloatArray): Boolean {
        val eps = 0.02f
        for (i in 0 until 4) {
            val x = corners[i * 2]
            val y = corners[i * 2 + 1]
            if (x <= eps || x >= 1f - eps || y <= eps || y >= 1f - eps) return true
        }
        return false
    }

    // Variance-of-Laplacian inside the quad bbox, sampled to ~96px on the long edge; uses absolute ByteBuffer.get() so rowStride padding doesn't matter.
    private fun computeInteriorVariance(
        buffer: java.nio.ByteBuffer,
        width: Int,
        height: Int,
        rowStride: Int,
        pixelStride: Int,
        corners: FloatArray,
    ): Double {
        if (corners.size != 8) return 0.0
        val xs = intArrayOf(
            (corners[0] * width).toInt(), (corners[2] * width).toInt(),
            (corners[4] * width).toInt(), (corners[6] * width).toInt(),
        )
        val ys = intArrayOf(
            (corners[1] * height).toInt(), (corners[3] * height).toInt(),
            (corners[5] * height).toInt(), (corners[7] * height).toInt(),
        )
        val xMin = max(0, xs.min())
        val yMin = max(0, ys.min())
        val xMax = kotlin.math.min(width - 1, xs.max())
        val yMax = kotlin.math.min(height - 1, ys.max())

        val target = 96
        val longEdge = max(xMax - xMin, yMax - yMin)
        val step = max(1, longEdge / target)
        if ((xMax - xMin) < 2 * step + 1 || (yMax - yMin) < 2 * step + 1) return 0.0

        var sumLap = 0.0
        var sumLap2 = 0.0
        var n = 0
        val cap = buffer.capacity()
        var yy = yMin + step
        while (yy < yMax - step) {
            val rowBase = yy * rowStride
            val rowUp = (yy - step) * rowStride
            val rowDn = (yy + step) * rowStride
            var xx = xMin + step
            while (xx < xMax - step) {
                val idxC = rowBase + xx * pixelStride
                val idxL = rowBase + (xx - step) * pixelStride
                val idxR = rowBase + (xx + step) * pixelStride
                val idxU = rowUp + xx * pixelStride
                val idxD = rowDn + xx * pixelStride
                if (idxC in 0 until cap && idxL in 0 until cap && idxR in 0 until cap &&
                    idxU in 0 until cap && idxD in 0 until cap
                ) {
                    val c = buffer.get(idxC).toInt() and 0xFF
                    val l = buffer.get(idxL).toInt() and 0xFF
                    val r = buffer.get(idxR).toInt() and 0xFF
                    val u = buffer.get(idxU).toInt() and 0xFF
                    val d = buffer.get(idxD).toInt() and 0xFF
                    val lap = (4 * c - l - r - u - d).toDouble()
                    sumLap += lap
                    sumLap2 += lap * lap
                    n += 1
                }
                xx += step
            }
            yy += step
        }
        if (n == 0) return 0.0
        val mean = sumLap / n
        return kotlin.math.max(0.0, sumLap2 / n - mean * mean)
    }

    private data class LumaMetrics(val meanLuma: Double, val blurScore: Double)

    /**
     * Mean luma + variance-of-Laplacian over a downsampled center crop of the
     * Y plane. Center crop avoids letterbox artifacts; downsampling keeps the
     * cost flat regardless of camera resolution.
     */
    private fun computeLumaMetrics(image: ImageProxy): LumaMetrics {
        val yPlane = image.planes.getOrNull(0) ?: return LumaMetrics(0.0, 0.0)
        val buffer = yPlane.buffer
        val rowStride = yPlane.rowStride
        val pixelStride = yPlane.pixelStride
        val width = image.width
        val height = image.height
        if (width <= 0 || height <= 0 || buffer.capacity() <= 0) {
            return LumaMetrics(0.0, 0.0)
        }

        val cropFraction = 0.6
        val cropW = (width * cropFraction).toInt()
        val cropH = (height * cropFraction).toInt()
        val xOffset = (width - cropW) / 2
        val yOffset = (height - cropH) / 2
        val targetLong = 96
        val strideStep = max(1, max(cropW, cropH) / targetLong)

        val sampleRows = (cropH + strideStep - 1) / strideStep
        val sampleCols = (cropW + strideStep - 1) / strideStep
        if (sampleRows < 3 || sampleCols < 3) return LumaMetrics(0.0, 0.0)

        val samples = ShortArray(sampleRows * sampleCols)
        var lumaSum = 0L
        var lumaCount = 0
        var sampledCols = 0

        var y = yOffset
        var rowIndex = 0
        while (rowIndex < sampleRows && y < yOffset + cropH) {
            val rowBase = y * rowStride
            var x = xOffset
            var colIndex = 0
            while (colIndex < sampleCols && x < xOffset + cropW) {
                val idx = rowBase + x * pixelStride
                if (idx in 0 until buffer.capacity()) {
                    val v = buffer.get(idx).toInt() and 0xFF
                    samples[rowIndex * sampleCols + colIndex] = v.toShort()
                    lumaSum += v
                    lumaCount += 1
                }
                x += strideStep
                colIndex += 1
            }
            if (rowIndex == 0) sampledCols = colIndex
            y += strideStep
            rowIndex += 1
        }

        if (lumaCount == 0 || sampledCols < 3) return LumaMetrics(0.0, 0.0)
        val meanLuma = lumaSum.toDouble() / lumaCount.toDouble()

        var laplacianSum = 0.0
        var laplacianSqSum = 0.0
        var laplacianN = 0
        for (ry in 1 until (sampleRows - 1)) {
            for (rx in 1 until (sampledCols - 1)) {
                val i = ry * sampleCols + rx
                val center = samples[i].toInt()
                val up = samples[i - sampleCols].toInt()
                val down = samples[i + sampleCols].toInt()
                val left = samples[i - 1].toInt()
                val right = samples[i + 1].toInt()
                val l = (4 * center) - up - down - left - right
                laplacianSum += l.toDouble()
                laplacianSqSum += (l.toLong() * l.toLong()).toDouble()
                laplacianN += 1
            }
        }
        if (laplacianN == 0) return LumaMetrics(meanLuma, 0.0)
        val mean = laplacianSum / laplacianN.toDouble()
        val variance = (laplacianSqSum / laplacianN.toDouble()) - (mean * mean)
        return LumaMetrics(meanLuma, max(0.0, variance))
    }
}
