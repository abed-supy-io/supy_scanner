package io.supy.scanner.document

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.supy.scanner.perf.DeviceTier
import java.io.IOException

/**
 * Runs ML Kit Text Recognition v2 (Latin script) over a list of page URIs and
 * concatenates the per-page text.
 *
 * Arabic OCR is intentionally not supported on Android — ML Kit's text
 * recognizer ships Latin, Chinese, Devanagari, Japanese, and Korean variants
 * only. Arabic-language scans on Android will return an empty `ocrText` for
 * the Arabic portions; the iOS side covers `ar` via `VNRecognizeTextRequest`.
 * See `docs/MIGRATION.md` for the Scanbot-vs-supy_scanner coverage table.
 */
internal class OcrRunner {

    private val recognizer: TextRecognizer =
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

    /**
     * Reads each [Uri], decodes its pixel dimensions, runs OCR, and invokes
     * [onComplete] on the calling thread with an enriched page list and the
     * concatenated text. Always invokes [onComplete] exactly once.
     */
    fun run(
        context: Context,
        pages: List<PageReencoder.ReencodedPage>,
        onComplete: (pages: List<Map<String, Any?>>, ocrText: String) -> Unit,
    ) {
        if (pages.isEmpty()) {
            onComplete(emptyList(), "")
            return
        }

        val results = arrayOfNulls<PageOcr>(pages.size)
        var remaining = pages.size

        val longEdgeCap = DeviceTier.detect(context).ocrLongEdgeCap()

        pages.forEachIndexed { index, page ->
            val uri = page.uri
            val (width, height) = readDimensions(context, uri)
            val image = try {
                buildInputImage(context, uri, width, height, longEdgeCap)
            } catch (e: IOException) {
                results[index] = PageOcr(uri, width, height, "", page.quality, page.qualityScore)
                remaining -= 1
                if (remaining == 0) emit(results, onComplete)
                return@forEachIndexed
            }

            recognizer.process(image)
                .addOnSuccessListener { recognized ->
                    results[index] = PageOcr(uri, width, height, recognized.text, page.quality, page.qualityScore)
                }
                .addOnFailureListener {
                    // Per-page failure → empty text for that page, partial
                    // result for the rest. Don't surface an error code.
                    results[index] = PageOcr(uri, width, height, "", page.quality, page.qualityScore)
                }
                .addOnCompleteListener {
                    remaining -= 1
                    if (remaining == 0) emit(results, onComplete)
                }
        }
    }

    fun close() {
        recognizer.close()
    }

    private fun emit(
        results: Array<PageOcr?>,
        onComplete: (List<Map<String, Any?>>, String) -> Unit,
    ) {
        val pages = results.filterNotNull().map { page ->
            buildMap<String, Any?> {
                put("uri", page.uri.toString())
                put("width", page.width)
                put("height", page.height)
                if (page.quality != null) put("quality", page.quality)
                if (page.qualityScore != null) put("qualityScore", page.qualityScore)
            }
        }
        val text = results.filterNotNull()
            .joinToString(separator = "\n\n") { it.text }
            .trim()
        onComplete(pages, text)
    }

    /**
     * Returns an `InputImage` for [uri], downscaled to roughly [longEdgeCap]
     * pixels on the long edge when a cap applies and the page is larger than
     * it. The persisted JPEG on disk is left untouched — only the in-memory
     * copy fed to ML Kit is reduced.
     */
    private fun buildInputImage(
        context: Context,
        uri: Uri,
        width: Int,
        height: Int,
        longEdgeCap: Int?,
    ): InputImage {
        val longEdge = maxOf(width, height)
        if (longEdgeCap == null || longEdge <= 0 || longEdge <= longEdgeCap) {
            return InputImage.fromFilePath(context, uri)
        }

        var sampleSize = 1
        while (longEdge / (sampleSize * 2) >= longEdgeCap) {
            sampleSize *= 2
        }
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val bitmap = context.contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, options)
        } ?: throw IOException("Failed to decode $uri for OCR downscale")
        return InputImage.fromBitmap(bitmap, 0)
    }

    private fun readDimensions(context: Context, uri: Uri): Pair<Int, Int> {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        try {
            context.contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream, null, options)
            }
        } catch (_: IOException) {
            return 0 to 0
        }
        return options.outWidth to options.outHeight
    }

    private data class PageOcr(
        val uri: Uri,
        val width: Int,
        val height: Int,
        val text: String,
        val quality: String?,
        val qualityScore: Double?,
    )
}
