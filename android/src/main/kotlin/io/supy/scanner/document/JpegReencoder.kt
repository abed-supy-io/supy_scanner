package io.supy.scanner.document

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.core.net.toUri
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.UUID

/**
 * Re-encodes GMS document scanner pages to the consumer-supplied JPEG quality.
 *
 * The scanner picks its own quality internally; this pass writes each page to
 * the app's cache dir at the requested compression. Failures fall back to the
 * original Uri so the consumer always gets a usable page.
 */
internal object JpegReencoder {

    fun reencode(
        context: Context,
        sourceUris: List<Uri>,
        quality: Int,
    ): List<Uri> {
        val clamped = quality.coerceIn(1, 100)
        if (clamped >= MAX_PASSTHROUGH_QUALITY) return sourceUris
        return sourceUris.mapIndexed { index, uri ->
            reencodeOne(context, uri, clamped, index) ?: uri
        }
    }

    private fun reencodeOne(
        context: Context,
        sourceUri: Uri,
        quality: Int,
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
        val target = File(dir, "supy_scan_${UUID.randomUUID()}_$index.jpg")
        return try {
            FileOutputStream(target).use { out ->
                bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, quality, out)
                out.flush()
            }
            target.toUri()
        } catch (_: IOException) {
            null
        } finally {
            bitmap.recycle()
        }
    }

    // The GMS scanner already emits high-quality JPEGs; skip the re-encode pass
    // when the consumer asks for ≥95% to avoid an unnecessary disk round-trip.
    private const val MAX_PASSTHROUGH_QUALITY = 95
}
