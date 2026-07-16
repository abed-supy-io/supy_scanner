package io.supy.scanner.document

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.core.net.toUri
import io.supy.scanner.log.SupyLog
import io.supy.scanner.nativecore.SupyNativeCore
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
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

    /** Wire values match `supy_enhance_mode_t` in `supy_scanner_enhance.h`. */
    internal enum class EnhanceMode(val nativeValue: Int) {
        OFF(0), FAST(1), BALANCED(2), MAX(3),
    }

    /**
     * Per-page output of the re-encode pass. [quality]/[qualityScore] come
     * from the native scorer (V1-S7-02) and are null on the JPEG passthrough
     * fast-path, where no decode happens.
     */
    internal data class ReencodedPage(
        val uri: Uri,
        val quality: String?,
        val qualityScore: Double?,
    )

    fun reencode(
        context: Context,
        sourceUris: List<Uri>,
        quality: Int,
        format: Format,
        enhanceMode: EnhanceMode = EnhanceMode.BALANCED,
    ): List<ReencodedPage> {
        val clamped = quality.coerceIn(1, 100)
        // GMS already emits high-quality JPEGs; skip the re-encode pass when
        // the consumer asks for ≥95% JPEG to avoid an unnecessary disk
        // round-trip — but only when enhance is also OFF, otherwise we still
        // need to decode→enhance→re-encode. PNG always re-encodes.
        if (format == Format.JPG &&
            clamped >= MAX_PASSTHROUGH_QUALITY &&
            enhanceMode == EnhanceMode.OFF
        ) {
            return sourceUris.map { ReencodedPage(it, quality = null, qualityScore = null) }
        }
        return sourceUris.mapIndexed { index, uri ->
            reencodeOne(context, uri, clamped, format, enhanceMode, index)
                ?: ReencodedPage(uri, quality = null, qualityScore = null)
        }
    }

    private fun reencodeOne(
        context: Context,
        sourceUri: Uri,
        quality: Int,
        format: Format,
        enhanceMode: EnhanceMode,
        index: Int,
    ): ReencodedPage? {
        val decoded = try {
            context.contentResolver.openInputStream(sourceUri)?.use { stream ->
                BitmapFactory.decodeStream(stream)
            }
        } catch (_: IOException) {
            null
        } ?: return null

        // copyPixelsToBuffer only emits RGBA bytes when the bitmap is ARGB_8888.
        // GMS pages already are, but defend against decoder fallbacks (eg. RGB_565).
        // `Bitmap.copy` allocates a fresh pixel buffer and can throw OOM on a
        // large page under memory pressure — fall back to skipping the page.
        val bitmap = if (decoded.config != Bitmap.Config.ARGB_8888) {
            val converted = try {
                decoded.copy(Bitmap.Config.ARGB_8888, true)
            } catch (oom: OutOfMemoryError) {
                SupyLog.i(message = "Bitmap.copy ARGB_8888 OOM: ${oom.message}")
                null
            }
            decoded.recycle()
            converted ?: return null
        } else {
            decoded
        }

        if (enhanceMode != EnhanceMode.OFF) {
            runEnhance(bitmap, enhanceMode)
        }
        val score = scorePage(bitmap)

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
            ReencodedPage(
                uri = target.toUri(),
                quality = score?.first,
                qualityScore = score?.second,
            )
        } catch (_: IOException) {
            null
        } finally {
            bitmap.recycle()
        }
    }

    /**
     * Enhances (when [enhanceMode] != OFF), scores, and re-encodes an in-memory
     * [bitmap] to a fresh cache file — the decode-free counterpart of
     * [reencodeOne], used by the embedded scanner's `captureAndRectify` path
     * where the rectified page already lives in memory. [bitmap] **must be
     * mutable** (enhancement writes back in place) and is recycled before this
     * returns. Returns null on an I/O failure.
     */
    internal fun reencodeBitmap(
        context: Context,
        bitmap: Bitmap,
        quality: Int,
        format: Format,
        enhanceMode: EnhanceMode,
    ): ReencodedPage? {
        val clamped = quality.coerceIn(1, 100)
        if (enhanceMode != EnhanceMode.OFF) {
            runEnhance(bitmap, enhanceMode)
        }
        val score = scorePage(bitmap)

        val dir = File(context.cacheDir, "supy_scanner")
        if (!dir.exists() && !dir.mkdirs()) {
            bitmap.recycle()
            return null
        }
        val ext = if (format == Format.PNG) "png" else "jpg"
        val target = File(dir, "supy_scan_${UUID.randomUUID()}.$ext")
        val compress = if (format == Format.PNG) {
            Bitmap.CompressFormat.PNG
        } else {
            Bitmap.CompressFormat.JPEG
        }
        return try {
            FileOutputStream(target).use { out ->
                bitmap.compress(compress, clamped, out)
                out.flush()
            }
            ReencodedPage(
                uri = target.toUri(),
                quality = score?.first,
                qualityScore = score?.second,
            )
        } catch (_: IOException) {
            null
        } finally {
            bitmap.recycle()
        }
    }

    /**
     * Runs the native enhance pipeline in place on [bitmap]. Best-effort:
     * if the native lib isn't loaded or the JNI call returns null the bitmap
     * is left untouched and we log + move on (no exception to the consumer).
     */
    private fun runEnhance(bitmap: Bitmap, enhanceMode: EnhanceMode) {
        val width = bitmap.width
        val height = bitmap.height
        val rowStride = bitmap.rowBytes
        val byteCount = rowStride * height
        if (width <= 0 || height <= 0 || byteCount <= 0) return
        // `allocateDirect` on a multi-megabyte page can throw OOM under
        // memory pressure — fall back to skipping enhancement.
        val buf = try {
            ByteBuffer.allocateDirect(byteCount).order(ByteOrder.nativeOrder())
        } catch (oom: OutOfMemoryError) {
            SupyLog.i(message = "enhance allocateDirect OOM ($byteCount B): ${oom.message}")
            return
        }
        bitmap.copyPixelsToBuffer(buf)
        buf.rewind()
        val result = SupyNativeCore.enhanceRgba(
            rgba = buf,
            width = width,
            height = height,
            rowStride = rowStride,
            mode = enhanceMode.nativeValue,
        )
        if (result == null) {
            SupyLog.i(message = "enhanceRgba returned null (mode=$enhanceMode); skipping enhancement")
            return
        }
        buf.rewind()
        bitmap.copyPixelsFromBuffer(buf)
    }

    /**
     * Scores [bitmap] with the native variance-of-Laplacian gate and maps the
     * bucket back to the wire string ("veryPoor".."excellent"). Returns null
     * if the native lib isn't loaded or the call fails — the consumer then
     * sees `quality == null` on the page, identical to v1.0 behavior.
     */
    /**
     * Public counterpart of [scorePage] for the in-flow CameraX retake gate.
     * Decodes [uri] once, scores it with the native variance-of-Laplacian
     * gate, and returns the wire-string bucket plus raw score. Returns null
     * when the file can't be decoded or the native scorer isn't available.
     */
    internal fun scoreUri(context: Context, uri: Uri): Pair<String, Double>? {
        val decoded = try {
            context.contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream)
            }
        } catch (_: IOException) {
            null
        } ?: return null
        val bitmap = if (decoded.config != Bitmap.Config.ARGB_8888) {
            val converted = try {
                decoded.copy(Bitmap.Config.ARGB_8888, true)
            } catch (oom: OutOfMemoryError) {
                SupyLog.i(message = "scoreUri Bitmap.copy OOM: ${oom.message}")
                null
            }
            decoded.recycle()
            converted ?: return null
        } else {
            decoded
        }
        return try {
            scorePage(bitmap)
        } finally {
            bitmap.recycle()
        }
    }

    private fun scorePage(bitmap: Bitmap): Pair<String, Double>? {
        val width = bitmap.width
        val height = bitmap.height
        val rowStride = bitmap.rowBytes
        val byteCount = rowStride * height
        if (width <= 0 || height <= 0 || byteCount <= 0) return null
        // `allocateDirect` can throw OOM on a large page — score is best-effort,
        // so fall back to no score rather than failing the page.
        val buf = try {
            ByteBuffer.allocateDirect(byteCount).order(ByteOrder.nativeOrder())
        } catch (oom: OutOfMemoryError) {
            SupyLog.i(message = "scorePage allocateDirect OOM ($byteCount B): ${oom.message}")
            return null
        }
        bitmap.copyPixelsToBuffer(buf)
        buf.rewind()
        val score = SupyNativeCore.scorePage(buf, width, height, rowStride) ?: return null
        val wire = bucketToWire(score.bucket) ?: return null
        return wire to score.qualityScore.toDouble()
    }

    private fun bucketToWire(bucket: Int): String? = when (bucket) {
        0 -> "veryPoor"
        1 -> "poor"
        2 -> "ok"
        3 -> "good"
        4 -> "excellent"
        else -> null
    }

    private const val MAX_PASSTHROUGH_QUALITY = 95
}
