package io.supy.scanner.document

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Canvas
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

    private fun decode(context: Context, uri: Uri) = runCatching {
        context.contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream)
        }
    }.getOrNull()
}
