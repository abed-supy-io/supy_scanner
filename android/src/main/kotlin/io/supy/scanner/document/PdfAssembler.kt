package io.supy.scanner.document

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.pdf.PdfDocument
import android.net.Uri
import java.io.File
import java.io.FileOutputStream

/**
 * Multi-page PDF writer for the CameraX document fallback. v1.2 Phase CXD2:
 * GMS produces a PDF natively; on non-GMS devices we assemble one from the
 * re-encoded JPEG pages so retailer code that requests `outputFormat=pdf`
 * gets shape-parity output across both backends.
 *
 * Pages are written at their native pixel dimensions. No compression knob —
 * the source JPEGs are already device-tier–quality.
 */
internal object PdfAssembler {

    /**
     * Assemble [pageUris] into a single PDF at `context.cacheDir/supy_camx/`.
     * Returns the output [File] or `null` if no decodable page survived.
     */
    fun assemble(context: Context, pageUris: List<Uri>): File? {
        if (pageUris.isEmpty()) return null

        val outDir = File(context.cacheDir, "supy_camx").apply { mkdirs() }
        val outFile = File(outDir, "scan_${System.currentTimeMillis()}.pdf")

        val pdf = PdfDocument()
        var wroteAny = false
        try {
            for ((index, uri) in pageUris.withIndex()) {
                val bitmap = decode(context, uri) ?: continue
                val pageInfo = PdfDocument.PageInfo.Builder(
                    bitmap.width,
                    bitmap.height,
                    index + 1,
                ).create()
                val page = pdf.startPage(pageInfo)
                page.canvas.drawBitmap(
                    bitmap,
                    null,
                    Rect(0, 0, bitmap.width, bitmap.height),
                    Paint(Paint.FILTER_BITMAP_FLAG),
                )
                pdf.finishPage(page)
                bitmap.recycle()
                wroteAny = true
            }

            if (!wroteAny) return null

            FileOutputStream(outFile).use { pdf.writeTo(it) }
            return outFile
        } finally {
            pdf.close()
        }
    }

    /**
     * A recognized word plus its normalized `[0..1]` top-left bounding box —
     * the unit of the invisible text layer drawn by [assembleSearchable].
     */
    data class Word(
        val text: String,
        val left: Double,
        val top: Double,
        val width: Double,
        val height: Double,
    )

    /** A page's image URI paired with the words OCR found on it. */
    data class SearchablePage(val uri: Uri, val words: List<Word>)

    /**
     * Assemble [pages] into a searchable PDF: each page's image is drawn as
     * normal, then every recognized word is stamped on top with a fully
     * transparent paint (`alpha = 0`). The glyphs enter the PDF content stream
     * — invisible on screen but selectable and searchable — mirroring the iOS
     * `UIGraphicsPDFRenderer` invisible-text layer. v1.2 Phase DC8.
     *
     * Word boxes are normalized `[0..1]`, so they map onto the page bitmap
     * regardless of the resolution OCR ran at.
     */
    fun assembleSearchable(context: Context, pages: List<SearchablePage>): File? {
        if (pages.isEmpty()) return null

        val outDir = File(context.cacheDir, "supy_camx").apply { mkdirs() }
        val outFile = File(outDir, "scan_${System.currentTimeMillis()}.pdf")

        val pdf = PdfDocument()
        var wroteAny = false
        try {
            for ((index, page) in pages.withIndex()) {
                val bitmap = decode(context, page.uri) ?: continue
                val pageInfo = PdfDocument.PageInfo.Builder(
                    bitmap.width,
                    bitmap.height,
                    index + 1,
                ).create()
                val pdfPage = pdf.startPage(pageInfo)
                val canvas = pdfPage.canvas
                canvas.drawBitmap(
                    bitmap,
                    null,
                    Rect(0, 0, bitmap.width, bitmap.height),
                    Paint(Paint.FILTER_BITMAP_FLAG),
                )
                drawTextLayer(canvas, page.words, bitmap.width, bitmap.height)
                pdf.finishPage(pdfPage)
                bitmap.recycle()
                wroteAny = true
            }

            if (!wroteAny) return null

            FileOutputStream(outFile).use { pdf.writeTo(it) }
            return outFile
        } finally {
            pdf.close()
        }
    }

    /**
     * Stamps [words] onto [canvas] as an invisible (fully transparent) text
     * layer. Each word's font size is scaled to its box height, and glyphs are
     * horizontally scaled so the selectable region matches the printed word's
     * width. Empty or degenerate boxes are skipped.
     */
    private fun drawTextLayer(
        canvas: android.graphics.Canvas,
        words: List<PdfAssembler.Word>,
        pageWidth: Int,
        pageHeight: Int,
    ) {
        if (words.isEmpty()) return
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.TRANSPARENT // alpha 0 → invisible but selectable.
        }
        for (word in words) {
            if (word.text.isEmpty()) continue
            val boxW = word.width * pageWidth
            val boxH = word.height * pageHeight
            if (boxW <= 0.0 || boxH <= 0.0) continue
            val left = (word.left * pageWidth).toFloat()
            val top = (word.top * pageHeight).toFloat()

            paint.textScaleX = 1f
            paint.textSize = boxH.toFloat()
            val measured = paint.measureText(word.text)
            if (measured > 0f) paint.textScaleX = (boxW / measured).toFloat()
            // drawText places the baseline at y; sit it at the box bottom.
            canvas.drawText(word.text, left, top + boxH.toFloat(), paint)
        }
    }

    private fun decode(context: Context, uri: Uri) = runCatching {
        context.contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream)
        }
    }.getOrNull()
}
