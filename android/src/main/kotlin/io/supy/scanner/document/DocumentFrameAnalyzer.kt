package io.supy.scanner.document

import android.annotation.SuppressLint
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
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
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "quad" to quad,
        "coverageRatio" to coverageRatio,
        "tiltDegrees" to tiltDegrees,
        "meanLuma" to meanLuma,
        "blurScore" to blurScore,
        "clipsEdge" to clipsEdge,
    )
}

/**
 * Per-frame analyzer for the document scanner PlatformView.
 *
 * v1 emits mean luma + variance-of-Laplacian (matches the iOS implementation)
 * over a center-cropped, downsampled Y plane. The edge-detection quad is
 * **not** wired on Android yet — ML Kit has no per-frame rectangle detector,
 * and the GMS Document Scanner is a launcher activity, not a streaming
 * detector. Until an Android edge detector is selected, `quad` is always
 * empty; the Dart state machine will report `noDocument` while still
 * surfacing `tooDark` / `blurry` hints from the luma path.
 *
 * Threading: invoked on the analyzer thread CameraX provides. Results are
 * marshalled to the main thread by the caller (`SupyDocumentScannerView`).
 */
class DocumentFrameAnalyzer(
    private val onMetrics: (DocumentFrameMetrics) -> Unit,
) : ImageAnalysis.Analyzer {

    @SuppressLint("UnsafeOptInUsageError")
    @OptIn(ExperimentalGetImage::class)
    override fun analyze(image: ImageProxy) {
        try {
            val luma = computeLumaMetrics(image)
            onMetrics(
                DocumentFrameMetrics(
                    quad = emptyList(),
                    coverageRatio = 0.0,
                    tiltDegrees = 0.0,
                    meanLuma = luma.meanLuma,
                    blurScore = luma.blurScore,
                    clipsEdge = false,
                )
            )
        } finally {
            image.close()
        }
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
