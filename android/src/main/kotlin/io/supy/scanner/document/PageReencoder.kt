package io.supy.scanner.document

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
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
        maxDimension: Int = 0,
        filter: DocumentFilter = DocumentFilter.COLOR,
    ): List<ReencodedPage> {
        val clamped = quality.coerceIn(1, 100)
        // GMS already emits high-quality JPEGs; skip the re-encode pass when
        // the consumer asks for ≥95% JPEG to avoid an unnecessary disk
        // round-trip — but only when there is genuinely nothing to do:
        // enhance OFF, no smart-resize, and no color transform (color/original
        // leave pixels untouched). PNG always re-encodes.
        if (format == Format.JPG &&
            clamped >= MAX_PASSTHROUGH_QUALITY &&
            enhanceMode == EnhanceMode.OFF &&
            maxDimension <= 0 &&
            (filter == DocumentFilter.COLOR || filter == DocumentFilter.ORIGINAL)
        ) {
            return sourceUris.map { ReencodedPage(it, quality = null, qualityScore = null) }
        }
        return sourceUris.mapIndexed { index, uri ->
            reencodeOne(context, uri, clamped, format, enhanceMode, maxDimension, filter, index)
                ?: ReencodedPage(uri, quality = null, qualityScore = null)
        }
    }

    private fun reencodeOne(
        context: Context,
        sourceUri: Uri,
        quality: Int,
        format: Format,
        enhanceMode: EnhanceMode,
        maxDimension: Int,
        filter: DocumentFilter,
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

        // Smart-resize → enhance → filter. May return a different bitmap
        // instance than `bitmap` (the original is recycled inside).
        val processed = applyProcessing(bitmap, enhanceMode, maxDimension, filter)
        val score = scorePage(processed)

        val dir = File(context.cacheDir, "supy_scanner")
        if (!dir.exists() && !dir.mkdirs()) {
            processed.recycle()
            return null
        }
        val ext = if (format == Format.PNG) "png" else "jpg"
        val target = File(dir, "supy_scan_${UUID.randomUUID()}_$index.$ext")
        val compress = if (format == Format.PNG) {
            Bitmap.CompressFormat.PNG
        } else {
            Bitmap.CompressFormat.JPEG
        }
        return try {
            FileOutputStream(target).use { out ->
                processed.compress(compress, quality, out)
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
            processed.recycle()
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
        maxDimension: Int = 0,
        filter: DocumentFilter = DocumentFilter.COLOR,
    ): ReencodedPage? {
        val clamped = quality.coerceIn(1, 100)
        // Smart-resize → enhance → filter. May return a different bitmap
        // instance than `bitmap` (the original is recycled inside).
        val processed = applyProcessing(bitmap, enhanceMode, maxDimension, filter)
        val score = scorePage(processed)

        val dir = File(context.cacheDir, "supy_scanner")
        if (!dir.exists() && !dir.mkdirs()) {
            processed.recycle()
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
                processed.compress(compress, clamped, out)
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
            processed.recycle()
        }
    }

    /**
     * The pure-Kotlin post-decode chain shared by both re-encode paths:
     * smart-resize → native enhance → output filter. Mirrors the tail of the
     * iOS `DocumentProcessor` (stages 8–9). May return a **different** bitmap
     * instance than [source] — the resize allocates a fresh bitmap and recycles
     * [source] — so callers must encode/recycle the returned bitmap, not the
     * one they passed in.
     */
    private fun applyProcessing(
        source: Bitmap,
        enhanceMode: EnhanceMode,
        maxDimension: Int,
        filter: DocumentFilter,
    ): Bitmap {
        val bitmap = if (maxDimension > 0) resizeToMax(source, maxDimension) else source
        if (enhanceMode != EnhanceMode.OFF) {
            runEnhance(bitmap, enhanceMode)
        }
        when (filter) {
            DocumentFilter.GRAYSCALE -> applyGrayscale(bitmap)
            DocumentFilter.BLACK_AND_WHITE -> applyBlackAndWhite(bitmap)
            // Color keeps the enhanced pixels; original is the un-enhanced bypass.
            DocumentFilter.COLOR, DocumentFilter.ORIGINAL -> Unit
        }
        return bitmap
    }

    /**
     * Downscales [source] so its longest edge is at most [maxDimension],
     * preserving aspect ratio (bilinear). Returns [source] unchanged when it is
     * already within budget or on an allocation failure. The returned bitmap is
     * always mutable ARGB_8888 so the downstream native enhance can write back
     * in place; [source] is recycled when a smaller copy is produced.
     */
    private fun resizeToMax(source: Bitmap, maxDimension: Int): Bitmap {
        val width = source.width
        val height = source.height
        val longest = maxOf(width, height)
        if (longest <= maxDimension || longest <= 0) return source
        val scale = maxDimension.toDouble() / longest
        val newW = (width * scale).toInt().coerceAtLeast(1)
        val newH = (height * scale).toInt().coerceAtLeast(1)
        val dst = try {
            Bitmap.createBitmap(newW, newH, Bitmap.Config.ARGB_8888)
        } catch (oom: OutOfMemoryError) {
            SupyLog.i(message = "resize createBitmap OOM (${newW}x$newH): ${oom.message}")
            return source
        }
        Canvas(dst).drawBitmap(
            source,
            Rect(0, 0, width, height),
            Rect(0, 0, newW, newH),
            Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG),
        )
        source.recycle()
        return dst
    }

    /** Desaturates [bitmap] in place using Rec.601 luma weights. */
    private fun applyGrayscale(bitmap: Bitmap) {
        val width = bitmap.width
        val height = bitmap.height
        val count = width * height
        if (count <= 0) return
        val pixels = try {
            IntArray(count)
        } catch (oom: OutOfMemoryError) {
            SupyLog.i(message = "grayscale IntArray OOM ($count px): ${oom.message}")
            return
        }
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        for (i in 0 until count) {
            val c = pixels[i]
            val y = luma(c)
            pixels[i] = (c and ALPHA_MASK) or (y shl 16) or (y shl 8) or y
        }
        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
    }

    /**
     * Binarizes [bitmap] in place with a global Otsu threshold over its luma
     * histogram — black ink on white paper. The upstream illumination-flatten
     * from the native enhance pass makes a global threshold hold up across the
     * page; a per-pixel adaptive pass isn't needed here.
     */
    private fun applyBlackAndWhite(bitmap: Bitmap) {
        val width = bitmap.width
        val height = bitmap.height
        val count = width * height
        if (count <= 0) return
        val pixels = try {
            IntArray(count)
        } catch (oom: OutOfMemoryError) {
            SupyLog.i(message = "b&w IntArray OOM ($count px): ${oom.message}")
            return
        }
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        val histogram = IntArray(256)
        val lumaValues = try {
            IntArray(count)
        } catch (oom: OutOfMemoryError) {
            SupyLog.i(message = "b&w luma IntArray OOM ($count px): ${oom.message}")
            return
        }
        for (i in 0 until count) {
            val y = luma(pixels[i])
            lumaValues[i] = y
            histogram[y]++
        }
        val threshold = otsuThreshold(histogram, count)
        for (i in 0 until count) {
            val v = if (lumaValues[i] < threshold) 0 else 255
            pixels[i] = (pixels[i] and ALPHA_MASK) or (v shl 16) or (v shl 8) or v
        }
        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
    }

    /** Rec.601 luma of a packed ARGB pixel, 0..255. */
    private fun luma(color: Int): Int {
        val r = (color ushr 16) and 0xFF
        val g = (color ushr 8) and 0xFF
        val b = color and 0xFF
        return ((r * 299 + g * 587 + b * 114) / 1000).coerceIn(0, 255)
    }

    /** Otsu's between-class-variance threshold over a 256-bin luma [histogram]. */
    private fun otsuThreshold(histogram: IntArray, total: Int): Int {
        var sum = 0.0
        for (t in 0..255) sum += (t * histogram[t]).toDouble()
        var sumB = 0.0
        var weightB = 0
        var maxVariance = -1.0
        var threshold = 127
        for (t in 0..255) {
            weightB += histogram[t]
            if (weightB == 0) continue
            val weightF = total - weightB
            if (weightF == 0) break
            sumB += (t * histogram[t]).toDouble()
            val meanB = sumB / weightB
            val meanF = (sum - sumB) / weightF
            val between = weightB.toDouble() * weightF.toDouble() *
                (meanB - meanF) * (meanB - meanF)
            if (between > maxVariance) {
                maxVariance = between
                threshold = t
            }
        }
        return threshold
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

    /** Preserves the alpha byte when rewriting RGB channels (0xFF000000). */
    private const val ALPHA_MASK = -0x1000000
}
