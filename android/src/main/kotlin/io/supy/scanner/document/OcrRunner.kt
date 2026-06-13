package io.supy.scanner.document

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
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
        pageUris: List<Uri>,
        onComplete: (pages: List<Map<String, Any?>>, ocrText: String) -> Unit,
    ) {
        if (pageUris.isEmpty()) {
            onComplete(emptyList(), "")
            return
        }

        val results = arrayOfNulls<PageOcr>(pageUris.size)
        var remaining = pageUris.size

        pageUris.forEachIndexed { index, uri ->
            val (width, height) = readDimensions(context, uri)
            val image = try {
                InputImage.fromFilePath(context, uri)
            } catch (e: IOException) {
                results[index] = PageOcr(uri, width, height, "")
                remaining -= 1
                if (remaining == 0) emit(results, onComplete)
                return@forEachIndexed
            }

            recognizer.process(image)
                .addOnSuccessListener { recognized ->
                    results[index] = PageOcr(uri, width, height, recognized.text)
                }
                .addOnFailureListener {
                    // Per-page failure → empty text for that page, partial
                    // result for the rest. Don't surface an error code.
                    results[index] = PageOcr(uri, width, height, "")
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
            mapOf<String, Any?>(
                "uri" to page.uri.toString(),
                "width" to page.width,
                "height" to page.height,
            )
        }
        val text = results.filterNotNull()
            .joinToString(separator = "\n\n") { it.text }
            .trim()
        onComplete(pages, text)
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
    )
}
