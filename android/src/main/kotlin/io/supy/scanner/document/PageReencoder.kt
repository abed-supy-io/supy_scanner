package io.supy.scanner.document

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.core.net.toUri
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.UUID

/**
 * Re-encodes GMS document scanner pages into the requested output format.
 *
 * - [Format.JPG] uses the consumer-supplied `quality` (1..100).
 * - [Format.PNG] is lossless; `quality` is ignored.
 *
 * Failures fall back to the original Uri so the consumer always gets a usable
 * page.
 */
internal object PageReencoder {

    internal enum class Format { JPG, PNG }

    fun reencode(
        context: Context,
        sourceUris: List<Uri>,
        quality: Int,
        format: Format,
    ): List<Uri> {
        val clamped = quality.coerceIn(1, 100)
        // GMS already emits high-quality JPEGs; skip the re-encode pass when
        // the consumer asks for ≥95% JPEG to avoid an unnecessary disk
        // round-trip. PNG always re-encodes (the source is JPEG).
        if (format == Format.JPG && clamped >= MAX_PASSTHROUGH_QUALITY) return sourceUris
        return sourceUris.mapIndexed { index, uri ->
            reencodeOne(context, uri, clamped, format, index) ?: uri
        }
    }

    private fun reencodeOne(
        context: Context,
        sourceUri: Uri,
        quality: Int,
        format: Format,
        index: Int,
    ): Uri? {
        val bitmap = try {
            context.contentResolver.openInputStream(sourceUri)?.use { stream ->
                BitmapFactory.decodeStream(stream)
            }
        } catch (_: IOException) {
            null
        } ?: return null

        val dir = File(context.cacheDir, "supy_scanner")
        if (!dir.exists() && !dir.mkdirs()) return null
        val ext = if (format == Format.PNG) "png" else "jpg"
        val target = File(dir, "supy_scan_${UUID.randomUUID()}_$index.$ext")
        val compress = if (format == Format.PNG) {
            Bitmap.CompressFormat.PNG
        } else {
            Bitmap.CompressFormat.JPEG
        }
        return try {
            FileOutputStream(target).use { out ->
                bitmap.compress(compress, quality, out)
                out.flush()
            }
            target.toUri()
        } catch (_: IOException) {
            null
        } finally {
            bitmap.recycle()
        }
    }

    private const val MAX_PASSTHROUGH_QUALITY = 95
}
