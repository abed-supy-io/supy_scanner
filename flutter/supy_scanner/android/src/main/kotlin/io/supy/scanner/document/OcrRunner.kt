package io.supy.scanner.document

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.supy.scanner.perf.DeviceTier
import java.io.IOException
import java.util.concurrent.Executors

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

    /** Off-main-thread decode of the source image before handing it to ML Kit. */
    private val ioExecutor = Executors.newSingleThreadExecutor()

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

    /**
     * Like [run], but also collects per-page word boxes for the searchable-PDF
     * text layer (v1.2 Phase DC8). One ML Kit pass per page — the same pass
     * that produces `ocrText` — so `outputFormat=searchablePdf` costs no extra
     * OCR over a plain PDF run. [onComplete] fires exactly once, on the calling
     * thread, with a `wordsPerPage` list index-aligned to the emitted pages.
     */
    fun runWithWords(
        context: Context,
        pages: List<PageReencoder.ReencodedPage>,
        onComplete: (
            pages: List<Map<String, Any?>>,
            ocrText: String,
            wordsPerPage: List<List<PdfAssembler.Word>>,
        ) -> Unit,
    ) {
        if (pages.isEmpty()) {
            onComplete(emptyList(), "", emptyList())
            return
        }

        val results = arrayOfNulls<PageOcrWords>(pages.size)
        var remaining = pages.size
        val longEdgeCap = DeviceTier.detect(context).ocrLongEdgeCap()

        pages.forEachIndexed { index, page ->
            val uri = page.uri
            val (width, height) = readDimensions(context, uri)
            val image = try {
                buildInputImage(context, uri, width, height, longEdgeCap)
            } catch (e: IOException) {
                results[index] = PageOcrWords(uri, width, height, "", page.quality, page.qualityScore, emptyList())
                remaining -= 1
                if (remaining == 0) emitWords(results, onComplete)
                return@forEachIndexed
            }
            val imgWidth = image.width
            val imgHeight = image.height

            recognizer.process(image)
                .addOnSuccessListener { recognized ->
                    val words = collectWords(recognized, imgWidth, imgHeight)
                    results[index] =
                        PageOcrWords(uri, width, height, recognized.text, page.quality, page.qualityScore, words)
                }
                .addOnFailureListener {
                    results[index] =
                        PageOcrWords(uri, width, height, "", page.quality, page.qualityScore, emptyList())
                }
                .addOnCompleteListener {
                    remaining -= 1
                    if (remaining == 0) emitWords(results, onComplete)
                }
        }
    }

    /** Flattens ML Kit elements ("words") into normalized [PdfAssembler.Word]s. */
    private fun collectWords(
        text: com.google.mlkit.vision.text.Text,
        imgWidth: Int,
        imgHeight: Int,
    ): List<PdfAssembler.Word> {
        val words = mutableListOf<PdfAssembler.Word>()
        for (block in text.textBlocks) {
            for (line in block.lines) {
                for (element in line.elements) {
                    val box = normRect(element.boundingBox, imgWidth, imgHeight)
                    words.add(
                        PdfAssembler.Word(
                            text = element.text,
                            left = box.getValue("left"),
                            top = box.getValue("top"),
                            width = box.getValue("width"),
                            height = box.getValue("height"),
                        ),
                    )
                }
            }
        }
        return words
    }

    private fun emitWords(
        results: Array<PageOcrWords?>,
        onComplete: (List<Map<String, Any?>>, String, List<List<PdfAssembler.Word>>) -> Unit,
    ) {
        val present = results.filterNotNull()
        val pages = present.map { page ->
            buildMap<String, Any?> {
                put("uri", page.uri.toString())
                put("width", page.width)
                put("height", page.height)
                if (page.quality != null) put("quality", page.quality)
                if (page.qualityScore != null) put("qualityScore", page.qualityScore)
            }
        }
        val text = present.joinToString(separator = "\n\n") { it.text }.trim()
        val wordsPerPage = present.map { it.words }
        onComplete(pages, text, wordsPerPage)
    }

    /**
     * Runs a single-image structured OCR pass and posts the block → line →
     * element tree consumed by `SupyRecognizedText.fromMap` on the Dart side.
     *
     * ML Kit exposes `textBlocks → lines → elements`, each with a pixel-space
     * `Rect`. Boxes are normalized to `[0..1]` (origin top-left) against the
     * source image dimensions to match `SupyBarcode.boundingBox`. Both
     * callbacks are always invoked exactly once, on the main thread.
     *
     * The `languages` arg is accepted for wire symmetry with iOS but has no
     * effect here — ML Kit's bundled recognizer is Latin-only (see the class
     * doc and `docs/MIGRATION.md`).
     */
    fun recognizeStructured(
        context: Context,
        uri: Uri,
        includeElements: Boolean,
        onComplete: (Map<String, Any?>) -> Unit,
        onError: (code: String, message: String) -> Unit,
    ) {
        val main = Handler(Looper.getMainLooper())
        ioExecutor.execute {
            val (width, height) = readDimensions(context, uri)
            val longEdgeCap = DeviceTier.detect(context).ocrLongEdgeCap()
            val image = try {
                buildInputImage(context, uri, width, height, longEdgeCap)
            } catch (e: IOException) {
                main.post { onError("model_unavailable", "recognizeText: could not decode $uri (${e.message})") }
                return@execute
            }
            // ML Kit sizes its geometry against the (possibly downscaled)
            // InputImage, so normalize against that — not the on-disk dims.
            val imgWidth = image.width
            val imgHeight = image.height
            recognizer.process(image)
                .addOnSuccessListener { recognized ->
                    val tree = buildTree(recognized, imgWidth, imgHeight, includeElements)
                    onComplete(tree)
                }
                .addOnFailureListener { e ->
                    onError("model_unavailable", "recognizeText: ML Kit failed (${e.message})")
                }
        }
    }

    private fun buildTree(
        text: com.google.mlkit.vision.text.Text,
        imgWidth: Int,
        imgHeight: Int,
        includeElements: Boolean,
    ): Map<String, Any?> {
        val blocks = text.textBlocks.map { block ->
            val lines = block.lines.map { line ->
                val elements = if (includeElements) {
                    line.elements.map { element ->
                        mapOf(
                            "text" to element.text,
                            "boundingBox" to normRect(element.boundingBox, imgWidth, imgHeight),
                        )
                    }
                } else {
                    emptyList()
                }
                mapOf(
                    "text" to line.text,
                    "boundingBox" to normRect(line.boundingBox, imgWidth, imgHeight),
                    "elements" to elements,
                )
            }
            mapOf(
                "text" to block.text,
                "boundingBox" to normRect(block.boundingBox, imgWidth, imgHeight),
                "lines" to lines,
            )
        }
        return mapOf("fullText" to text.text, "blocks" to blocks)
    }

    /**
     * Normalizes a pixel-space [Rect] to Supy's `[0..1]` top-left
     * `{left, top, width, height}` convention. A null box (ML Kit may omit it)
     * or a degenerate image size collapses to the zero rect.
     */
    private fun normRect(rect: Rect?, imgWidth: Int, imgHeight: Int): Map<String, Double> {
        if (rect == null || imgWidth <= 0 || imgHeight <= 0) {
            return mapOf("left" to 0.0, "top" to 0.0, "width" to 0.0, "height" to 0.0)
        }
        val w = imgWidth.toDouble()
        val h = imgHeight.toDouble()
        return mapOf(
            "left" to rect.left / w,
            "top" to rect.top / h,
            "width" to rect.width() / w,
            "height" to rect.height() / h,
        )
    }

    fun close() {
        recognizer.close()
        ioExecutor.shutdown()
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

    private data class PageOcrWords(
        val uri: Uri,
        val width: Int,
        val height: Int,
        val text: String,
        val quality: String?,
        val qualityScore: Double?,
        val words: List<PdfAssembler.Word>,
    )
}
