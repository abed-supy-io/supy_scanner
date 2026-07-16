package io.supy.scanner.document

import android.annotation.SuppressLint
import androidx.annotation.WorkerThread
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import io.supy.scanner.nativecore.SupyNativeCore
import kotlin.math.max
import kotlin.math.sqrt

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
    val glareRatio: Double = 0.0,
    val cornerVelocity: Double = 0.0,
    // Length 4 (TL/TR/BR/BL) when per-corner signal available; empty otherwise.
    val perCornerStability: List<Double> = emptyList(),
    // C++-computed opaque pre-capture quality estimate in [0,1]. Null if the
    // native classifier didn't run on this frame.
    val liveQualityScore: Double? = null,
) {
    /**
     * Signed quad-centroid offset from preview center, per axis, in half-extent
     * fractions: `(centroid - 0.5) * 2`. Positive X = right of center; positive
     * Y = below center. `(0, 0)` when there's no complete 4-corner quad.
     */
    val centerOffset: Pair<Double, Double>
        get() {
            if (quad.size != 4) return 0.0 to 0.0
            var cx = 0.0
            var cy = 0.0
            for (p in quad) {
                cx += p["x"] ?: 0.0
                cy += p["y"] ?: 0.0
            }
            cx /= 4.0
            cy /= 4.0
            return ((cx - 0.5) * 2.0) to ((cy - 0.5) * 2.0)
        }

    fun toMap(): Map<String, Any?> {
        val (offsetX, offsetY) = centerOffset
        return mapOf(
            "quad" to quad,
            "coverageRatio" to coverageRatio,
            "tiltDegrees" to tiltDegrees,
            "meanLuma" to meanLuma,
            "blurScore" to blurScore,
            "clipsEdge" to clipsEdge,
            "interiorVariance" to interiorVariance,
            "quadStability" to quadStability,
            "glareRatio" to glareRatio,
            "cornerVelocity" to cornerVelocity,
            "perCornerStability" to perCornerStability,
            "liveQualityScore" to liveQualityScore,
            "centerOffsetX" to offsetX,
            "centerOffsetY" to offsetY,
        )
    }
}

// Rolling-window corner-drift tracker; mirrors iOS QuadStabilityTracker.
internal class QuadStabilityTracker(private val windowSize: Int = 6) {
    private val history: ArrayDeque<FloatArray> = ArrayDeque()
    // Per-corner drift, TL/TR/BR/BL — populated by stability(). length 0 when no
    // history has been ingested yet, so callers can detect "no per-corner signal".
    private var perCorner: DoubleArray = DoubleArray(0)

    fun push(corners: FloatArray): Double {
        if (corners.size != 8) { history.clear(); perCorner = DoubleArray(0); return 0.0 }
        history.addLast(corners.copyOf())
        while (history.size > windowSize) history.removeFirst()
        return stability()
    }

    fun stability(): Double {
        if (history.size < 2) { perCorner = DoubleArray(0); return 0.0 }
        val corners = DoubleArray(4)
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
            corners[corner] = (1.0 - drift / 0.1).coerceIn(0.0, 1.0)
            if (drift > maxDrift) maxDrift = drift
        }
        perCorner = corners
        return (1.0 - maxDrift / 0.1).coerceIn(0.0, 1.0)
    }

    /** Latest per-corner stability (TL/TR/BR/BL). Empty when no signal yet. */
    fun perCornerStability(): DoubleArray = perCorner

    fun reset() { history.clear(); perCorner = DoubleArray(0) }
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
    // Previous-frame corners in normalized coords, used to compute cornerVelocity.
    // Null between detection runs (no document last frame).
    private var prevCorners: FloatArray? = null

    // Last detected quad in normalized TL,TR,BR,BL coords (8 floats), retained so
    // captureAndRectify can rectify the full-res still against it. @Volatile: read
    // on the platform/main thread, written on the analyzer thread. Null when no
    // document was detected on the most recent frame.
    @Volatile private var lastQuad: FloatArray? = null

    /**
     * The most recently detected document quad as normalized TL,TR,BR,BL corners
     * (eight floats), or null if the last frame had no document. Thread-safe.
     */
    fun lastDetectedQuad(): FloatArray? = lastQuad?.copyOf()

    @SuppressLint("UnsafeOptInUsageError")
    @OptIn(ExperimentalGetImage::class)
    @WorkerThread
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

            lastQuad = native?.corners?.takeIf { it.size == 8 }?.copyOf()

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

            val perCornerArr = stabilityTracker.perCornerStability()
            val perCorner: List<Double> = if (perCornerArr.size == 4) {
                listOf(perCornerArr[0], perCornerArr[1], perCornerArr[2], perCornerArr[3])
            } else emptyList()

            val glare = if (native != null) {
                computeGlareRatio(buf, w, h, rowStride, pixelStride, native.corners)
            } else 0.0

            val velocity = if (native != null) {
                val prev = prevCorners
                val v = if (prev != null) cornerVelocity(prev, native.corners) else 0.0
                prevCorners = native.corners.copyOf()
                v
            } else {
                prevCorners = null
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
                    glareRatio = glare,
                    cornerVelocity = velocity,
                    perCornerStability = perCorner,
                )
            )
        } catch (t: Throwable) {
            prevCorners = null
            lastQuad = null
            stabilityTracker.reset()
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

    // Fraction of sampled pixels inside the quad bbox whose luma > 245. Matches
    // the iOS implementation. Sampled to ~96 px on the long edge so cost is flat.
    private fun computeGlareRatio(
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
        if (xMax - xMin < 4 || yMax - yMin < 4) return 0.0

        val target = 96
        val longEdge = max(xMax - xMin, yMax - yMin)
        val step = max(1, longEdge / target)
        val cap = buffer.capacity()
        var bright = 0
        var n = 0
        var yy = yMin
        while (yy <= yMax) {
            val rowBase = yy * rowStride
            var xx = xMin
            while (xx <= xMax) {
                val idx = rowBase + xx * pixelStride
                if (idx in 0 until cap) {
                    val v = buffer.get(idx).toInt() and 0xFF
                    if (v > 245) bright += 1
                    n += 1
                }
                xx += step
            }
            yy += step
        }
        return if (n > 0) bright.toDouble() / n.toDouble() else 0.0
    }

    // L2 norm of the per-corner displacement divided by sqrt(2) so a frame-diag
    // jump maps to 1.0. Inputs are normalized [0..1] coords; matches the iOS
    // formula in DocumentDetector.swift.
    private fun cornerVelocity(prev: FloatArray, curr: FloatArray): Double {
        if (prev.size != 8 || curr.size != 8) return 0.0
        var sumSq = 0.0
        for (i in 0 until 4) {
            val dx = (curr[i * 2] - prev[i * 2]).toDouble()
            val dy = (curr[i * 2 + 1] - prev[i * 2 + 1]).toDouble()
            sumSq += dx * dx + dy * dy
        }
        // Average displacement length per corner, normalised by the unit diagonal.
        return sqrt(sumSq / 4.0) / sqrt(2.0)
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
