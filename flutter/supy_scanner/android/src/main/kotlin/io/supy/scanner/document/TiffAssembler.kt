package io.supy.scanner.document

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import io.supy.scanner.log.SupyLog
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Pure-Kotlin multi-page baseline TIFF writer for `outputFormat=tiff`. v1.2
 * Phase DC8. Avoids a `libtiff`-in-core dependency (no ABI bump) — Android has
 * no built-in TIFF encoder, so we emit the format by hand.
 *
 * Output is little-endian, uncompressed (compression tag = 1), chunky RGB
 * (8-8-8, one strip per page covering the full image height), one IFD per page
 * chained via the "next IFD" pointer. Uncompressed is the low-risk choice:
 * every page's pixels are correct by construction, at the cost of file size.
 * PackBits (tag 32773) is a future optimization if size ever matters.
 */
internal object TiffAssembler {

    // Baseline tags we emit, in ascending order (TIFF requires sorted IFD entries).
    private const val TAG_IMAGE_WIDTH = 256
    private const val TAG_IMAGE_LENGTH = 257
    private const val TAG_BITS_PER_SAMPLE = 258
    private const val TAG_COMPRESSION = 259
    private const val TAG_PHOTOMETRIC = 262
    private const val TAG_STRIP_OFFSETS = 273
    private const val TAG_SAMPLES_PER_PIXEL = 277
    private const val TAG_ROWS_PER_STRIP = 278
    private const val TAG_STRIP_BYTE_COUNTS = 279

    private const val TYPE_SHORT = 3
    private const val TYPE_LONG = 4

    private const val NUM_TAGS = 9
    // 2 (entry count) + 12 per entry + 4 (next-IFD pointer).
    private const val IFD_SIZE = 2 + 12 * NUM_TAGS + 4
    // BitsPerSample = three SHORTs (6 bytes) — too big for the inline field,
    // so it lives immediately after each IFD.
    private const val BPS_SIZE = 6
    private const val BYTES_PER_PIXEL = 3

    private data class PageLayout(
        val bitmap: Bitmap,
        val ifdOffset: Int,
        val bpsOffset: Int,
        val stripOffset: Int,
        val stripByteCount: Int,
    )

    /**
     * Assemble [pageUris] into a single multi-page TIFF at
     * `context.cacheDir/supy_camx/`. Returns the output [File] or `null` if no
     * page decoded.
     */
    fun assemble(context: Context, pageUris: List<Uri>): File? {
        if (pageUris.isEmpty()) return null

        val bitmaps = pageUris.mapNotNull { decode(context, it) }
        if (bitmaps.isEmpty()) return null

        try {
            // First pass: compute every offset. The IFD's StripOffsets value and
            // the next-IFD pointer both need absolute file positions known up
            // front, so we lay the whole file out before writing a byte.
            var offset = 8 // TIFF header is 8 bytes.
            val layouts = bitmaps.map { bmp ->
                val ifdOffset = offset
                val bpsOffset = ifdOffset + IFD_SIZE
                val stripOffset = bpsOffset + BPS_SIZE
                val stripByteCount = bmp.width * bmp.height * BYTES_PER_PIXEL
                offset = stripOffset + stripByteCount
                PageLayout(bmp, ifdOffset, bpsOffset, stripOffset, stripByteCount)
            }

            val buffer = ByteBuffer.allocate(offset).order(ByteOrder.LITTLE_ENDIAN)

            // Header: "II" (little-endian) + magic 42 + offset of first IFD.
            buffer.put('I'.code.toByte())
            buffer.put('I'.code.toByte())
            buffer.putShort(42)
            buffer.putInt(layouts.first().ifdOffset)

            for ((index, layout) in layouts.withIndex()) {
                val nextIfd = if (index + 1 < layouts.size) layouts[index + 1].ifdOffset else 0
                writeIfd(buffer, layout, nextIfd)
                // BitsPerSample external data (8, 8, 8).
                buffer.putShort(8)
                buffer.putShort(8)
                buffer.putShort(8)
                writeStrip(buffer, layout.bitmap)
            }

            val outDir = File(context.cacheDir, "supy_camx").apply { mkdirs() }
            val outFile = File(outDir, "scan_${System.currentTimeMillis()}.tiff")
            FileOutputStream(outFile).use { it.write(buffer.array()) }
            return outFile
        } catch (t: Throwable) {
            SupyLog.i(message = "TiffAssembler failed: ${t.message}")
            return null
        } finally {
            bitmaps.forEach { it.recycle() }
        }
    }

    private fun writeIfd(buffer: ByteBuffer, layout: PageLayout, nextIfd: Int) {
        val w = layout.bitmap.width
        val h = layout.bitmap.height
        buffer.putShort(NUM_TAGS.toShort())
        writeEntry(buffer, TAG_IMAGE_WIDTH, TYPE_LONG, 1, w)
        writeEntry(buffer, TAG_IMAGE_LENGTH, TYPE_LONG, 1, h)
        writeEntry(buffer, TAG_BITS_PER_SAMPLE, TYPE_SHORT, 3, layout.bpsOffset)
        writeEntry(buffer, TAG_COMPRESSION, TYPE_SHORT, 1, 1) // 1 = uncompressed.
        writeEntry(buffer, TAG_PHOTOMETRIC, TYPE_SHORT, 1, 2) // 2 = RGB.
        writeEntry(buffer, TAG_STRIP_OFFSETS, TYPE_LONG, 1, layout.stripOffset)
        writeEntry(buffer, TAG_SAMPLES_PER_PIXEL, TYPE_SHORT, 1, 3)
        writeEntry(buffer, TAG_ROWS_PER_STRIP, TYPE_LONG, 1, h)
        writeEntry(buffer, TAG_STRIP_BYTE_COUNTS, TYPE_LONG, 1, layout.stripByteCount)
        buffer.putInt(nextIfd)
    }

    /**
     * Writes one 12-byte IFD entry. SHORT values occupy the low 2 bytes of the
     * inline value field (the remaining 2 bytes stay zero); LONG values fill
     * all 4. Both single-value SHORT and LONG fit inline, so [value] is always
     * either the datum or — for BitsPerSample — the offset to external data.
     */
    private fun writeEntry(buffer: ByteBuffer, tag: Int, type: Int, count: Int, value: Int) {
        buffer.putShort(tag.toShort())
        buffer.putShort(type.toShort())
        buffer.putInt(count)
        if (type == TYPE_SHORT && count == 1) {
            buffer.putShort(value.toShort())
            buffer.putShort(0)
        } else {
            buffer.putInt(value)
        }
    }

    /**
     * Writes the page's pixels as chunky RGB, rows top-to-bottom. The source
     * bitmap is ARGB_8888; alpha is dropped (baseline RGB, SamplesPerPixel=3).
     */
    private fun writeStrip(buffer: ByteBuffer, bitmap: Bitmap) {
        val w = bitmap.width
        val h = bitmap.height
        val row = IntArray(w)
        for (y in 0 until h) {
            bitmap.getPixels(row, 0, w, 0, y, w, 1)
            for (x in 0 until w) {
                val px = row[x]
                buffer.put(((px shr 16) and 0xFF).toByte()) // R
                buffer.put(((px shr 8) and 0xFF).toByte()) // G
                buffer.put((px and 0xFF).toByte()) // B
            }
        }
    }

    private fun decode(context: Context, uri: Uri): Bitmap? = runCatching {
        context.contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream)
        }
    }.getOrNull()
}
