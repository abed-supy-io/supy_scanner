package io.supy.scanner.document

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.supy.scanner.log.SupyLog
import io.supy.scanner.nativecore.SupyNativeCore
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

/**
 * Native gallery-import counterpart of [DocumentScannerLauncher].
 *
 * Launches the system photo picker, then runs the same on-device
 * detect → perspective-warp → enhance → persist pipeline the embedded scanner
 * uses (`SupyDocumentScannerView.captureAndRectify`), and resolves the
 * `importDocumentImage` channel call with a single `SupyDocumentPage` payload.
 *
 * On-device only — no bytes cross the channel and nothing leaves the device.
 * A dismissed picker resolves the call with `null`, matching the iOS
 * `DocumentImportPresenter` and the branded capture flow's "user backed out"
 * outcome.
 */
class DocumentImportLauncher : PluginRegistry.ActivityResultListener {

    private var pendingResult: Result? = null
    private var pendingActivity: Activity? = null

    // Enhancement knobs resolved from the current call's args, mirroring the
    // camera path (DocumentScannerLauncher) so an imported page is processed
    // identically to a scanned one. Default to the prior hardcoded behaviour
    // (BALANCED enhance, quality 95, COLOR filter) when no args are supplied.
    private var pendingEnhanceMode: PageReencoder.EnhanceMode = PageReencoder.EnhanceMode.BALANCED
    private var pendingJpegQuality: Int = RECTIFIED_JPEG_QUALITY
    private var pendingMaxDimension: Int = DocumentProcessingOptions.DEFAULT_MAX_DIMENSION
    private var pendingFilter: DocumentFilter = DocumentFilter.COLOR

    private val mainHandler = Handler(Looper.getMainLooper())
    // Off-main worker for decode + Vision-parity detect + warp + encode.
    private val ioExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "supy-document-import").apply { isDaemon = true }
    }

    fun launch(activity: Activity?, args: Map<String, Any?>?, result: Result) {
        if (activity == null) {
            result.error("camera_unavailable", "No Activity attached", null)
            return
        }
        if (pendingResult != null) {
            result.error("unknown", "A document import is already in progress", null)
            return
        }
        // Resolve the enhancement knobs up front so the background pipeline just
        // reads the pending fields. `filter` / `enhanceMode` / `quality` fall
        // back to the camera-path defaults, preserving the prior hardcoded
        // BALANCED-`.color`-95 behaviour when no args are supplied.
        val processing = DocumentProcessingOptions.parse(
            args,
            fallbackQuality = (args?.get("jpegQuality") as? Number)?.toInt() ?: RECTIFIED_JPEG_QUALITY,
        )
        pendingEnhanceMode = processing.enhanceMode
        pendingJpegQuality = processing.quality
        pendingMaxDimension = processing.maxDimension
        pendingFilter = processing.filter

        val intent = pickImageIntent()
        pendingResult = result
        pendingActivity = activity
        try {
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (t: Throwable) {
            pendingResult = null
            pendingActivity = null
            result.error(
                "unknown",
                t.message ?: "No photo picker available on this device",
                null,
            )
        }
    }

    /**
     * Photo Picker on API 33+ (no storage permission, single-select), falling
     * back to the Storage Access Framework document picker on older devices —
     * both return a readable content Uri in `data.data` and need no runtime
     * permission.
     */
    private fun pickImageIntent(): Intent =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Intent(MediaStore.ACTION_PICK_IMAGES).apply { type = "image/*" }
        } else {
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "image/*"
            }
        }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val pending = pendingResult ?: return false
        val activity = pendingActivity
        val uri = data?.data

        if (resultCode != Activity.RESULT_OK || uri == null || activity == null) {
            // Dismissed picker == user cancelled → resolve to Dart null, the
            // branded-import contract (parity with iOS finish(success: nil)).
            finishSuccess(null)
            return true
        }

        val appContext = activity.applicationContext
        ioExecutor.execute { process(appContext, uri) }
        return true
    }

    /** Decode → detect → warp → enhance → persist. Runs on [ioExecutor]. */
    private fun process(context: android.content.Context, uri: Uri) {
        val source = decodeUpright(context, uri)
        if (source == null) {
            finishError("unknown", "Could not decode the selected image")
            return
        }

        // Best document quad (normalized TL,TR,BR,BL) on a downscaled luma copy,
        // or null when nothing rectangular is found — an import should never
        // fail to return a page, so a miss falls through to the whole frame.
        val quad = detectQuad(source)

        val page = if (quad != null) {
            rectifyAndEncode(context, source, quad)
        } else {
            // No quad: enhance + persist the upright frame unchanged, mirroring
            // the iOS full-frame fallback. reencodeBitmap recycles `source`.
            PageReencoder.reencodeBitmap(
                context = context,
                bitmap = source,
                quality = pendingJpegQuality,
                format = PageReencoder.Format.JPG,
                enhanceMode = pendingEnhanceMode,
                maxDimension = pendingMaxDimension,
                filter = pendingFilter,
            )
        }

        if (page == null) {
            finishError("unknown", "Could not persist the imported page")
            return
        }
        finishSuccess(buildPayload(context, page))
    }

    /**
     * Warps [source] through the native perspective correction using the
     * normalized [quad], then enhances + persists via [PageReencoder]. Recycles
     * [source]. Returns null (caller surfaces an error) only on an allocation or
     * encode failure; a degenerate warp falls back to enhancing the un-warped
     * frame so an import always yields a page.
     */
    private fun rectifyAndEncode(
        context: android.content.Context,
        source: Bitmap,
        quad: FloatArray,
    ): PageReencoder.ReencodedPage? {
        val width = source.width
        val height = source.height
        val rowStride = source.rowBytes
        val byteCount = rowStride * height
        if (width <= 0 || height <= 0 || byteCount <= 0) {
            source.recycle()
            return null
        }
        val srcBuf = try {
            ByteBuffer.allocateDirect(byteCount).order(ByteOrder.nativeOrder())
        } catch (oom: OutOfMemoryError) {
            SupyLog.i(message = "import warp allocateDirect OOM ($byteCount B): ${oom.message}")
            // Fall back to enhancing the un-warped frame rather than failing.
            return PageReencoder.reencodeBitmap(
                context, source, pendingJpegQuality,
                PageReencoder.Format.JPG, pendingEnhanceMode,
                pendingMaxDimension, pendingFilter,
            )
        }
        source.copyPixelsToBuffer(srcBuf)
        srcBuf.rewind()

        val srcCorners = FloatArray(8)
        for (i in 0 until 4) {
            srcCorners[i * 2] = quad[i * 2] * width
            srcCorners[i * 2 + 1] = quad[i * 2 + 1] * height
        }

        val warp = SupyNativeCore.warpPerspective(
            rgba = srcBuf,
            width = width,
            height = height,
            rowStride = rowStride,
            srcCorners = srcCorners,
            maxLongSide = MAX_RECTIFIED_LONG_SIDE,
        )
        if (warp == null) {
            // Degenerate quad — keep the un-warped frame (recycled downstream).
            return PageReencoder.reencodeBitmap(
                context, source, pendingJpegQuality,
                PageReencoder.Format.JPG, pendingEnhanceMode,
                pendingMaxDimension, pendingFilter,
            )
        }
        source.recycle()

        val warped = try {
            Bitmap.createBitmap(warp.width, warp.height, Bitmap.Config.ARGB_8888)
        } catch (oom: OutOfMemoryError) {
            SupyLog.i(message = "import warped createBitmap OOM: ${oom.message}")
            return null
        }
        warped.copyPixelsFromBuffer(ByteBuffer.wrap(warp.rgba))
        return PageReencoder.reencodeBitmap(
            context = context,
            bitmap = warped, // recycled inside reencodeBitmap
            quality = pendingJpegQuality,
            format = PageReencoder.Format.JPG,
            enhanceMode = pendingEnhanceMode,
            maxDimension = pendingMaxDimension,
            filter = pendingFilter,
        )
    }

    /**
     * Detects the document quad on a downscaled luma copy of [source]. The
     * native detector wants a tightly-packed Y plane; the quad it returns is
     * normalized [0,1], so it maps back onto the full-res still directly.
     * Returns null when the native lib is unavailable or nothing is found.
     */
    private fun detectQuad(source: Bitmap): FloatArray? {
        if (!SupyNativeCore.ensureLoaded()) return null
        val longSide = maxOf(source.width, source.height)
        val scale = if (longSide > DETECT_MAX_SIDE) {
            DETECT_MAX_SIDE.toFloat() / longSide
        } else {
            1f
        }
        val dw = maxOf(1, (source.width * scale).toInt())
        val dh = maxOf(1, (source.height * scale).toInt())
        val scaled = try {
            Bitmap.createScaledBitmap(source, dw, dh, true)
        } catch (oom: OutOfMemoryError) {
            SupyLog.i(message = "import detect scale OOM: ${oom.message}")
            return null
        }

        val pixels = IntArray(dw * dh)
        scaled.getPixels(pixels, 0, dw, 0, 0, dw, dh)
        if (scaled != source) scaled.recycle()

        val yBuf = try {
            ByteBuffer.allocateDirect(dw * dh).order(ByteOrder.nativeOrder())
        } catch (oom: OutOfMemoryError) {
            SupyLog.i(message = "import detect Y-buffer OOM: ${oom.message}")
            return null
        }
        for (p in pixels) {
            val r = (p shr 16) and 0xFF
            val g = (p shr 8) and 0xFF
            val b = p and 0xFF
            // Integer BT.601 luma, matching the analyzer-path Y plane.
            yBuf.put((((r * 77) + (g * 150) + (b * 29)) shr 8).toByte())
        }
        yBuf.rewind()

        val quad = SupyNativeCore.detectQuad(yBuf, dw, dh, dw) ?: return null
        return quad.corners.takeIf { it.size == 8 }?.copyOf()
    }

    /**
     * Decodes [uri] and bakes any EXIF orientation into pixels so the result is
     * upright (camera-roll photos usually carry a rotation tag). Returns a
     * mutable ARGB_8888 bitmap, or null on a decode/convert failure.
     */
    private fun decodeUpright(context: android.content.Context, uri: Uri): Bitmap? {
        val decoded = try {
            context.contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream)
            }
        } catch (_: IOException) {
            null
        } catch (oom: OutOfMemoryError) {
            SupyLog.i(message = "import decode OOM: ${oom.message}")
            null
        } ?: return null

        val orientation = try {
            context.contentResolver.openInputStream(uri)?.use { stream ->
                ExifInterface(stream).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL,
                )
            } ?: ExifInterface.ORIENTATION_NORMAL
        } catch (_: IOException) {
            ExifInterface.ORIENTATION_NORMAL
        }

        val upright = applyExifOrientation(decoded, orientation)
        // Ensure ARGB_8888 + mutable so copyPixelsToBuffer emits RGBA and the
        // in-place enhance pass downstream can write back.
        if (upright.config == Bitmap.Config.ARGB_8888 && upright.isMutable) return upright
        val converted = try {
            upright.copy(Bitmap.Config.ARGB_8888, true)
        } catch (oom: OutOfMemoryError) {
            SupyLog.i(message = "import ARGB copy OOM: ${oom.message}")
            null
        }
        upright.recycle()
        return converted
    }

    private fun applyExifOrientation(bitmap: Bitmap, orientation: Int): Bitmap {
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f); matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f); matrix.postScale(-1f, 1f)
            }
            else -> return bitmap
        }
        return try {
            val rotated = Bitmap.createBitmap(
                bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true,
            )
            if (rotated != bitmap) bitmap.recycle()
            rotated
        } catch (oom: OutOfMemoryError) {
            SupyLog.i(message = "import EXIF rotate OOM: ${oom.message}")
            bitmap
        }
    }

    /** Builds the `SupyDocumentPage` wire map for a persisted [page]. */
    private fun buildPayload(
        context: android.content.Context,
        page: PageReencoder.ReencodedPage,
    ): Map<String, Any?> {
        // width/height from the decoded bounds — cheap, no full pixel decode.
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        try {
            context.contentResolver.openInputStream(page.uri)?.use { stream ->
                BitmapFactory.decodeStream(stream, null, opts)
            }
        } catch (_: IOException) {
            // Fall through with 0/0; consumers still get a usable uri.
        }
        val payload = mutableMapOf<String, Any?>(
            "uri" to page.uri.toString(),
            "width" to opts.outWidth,
            "height" to opts.outHeight,
        )
        if (page.quality != null) payload["quality"] = page.quality
        if (page.qualityScore != null) payload["qualityScore"] = page.qualityScore
        return payload
    }

    private fun finishSuccess(payload: Map<String, Any?>?) {
        val pending = pendingResult ?: return
        pendingResult = null
        pendingActivity = null
        mainHandler.post { pending.success(payload) }
    }

    private fun finishError(code: String, message: String) {
        val pending = pendingResult ?: return
        pendingResult = null
        pendingActivity = null
        mainHandler.post { pending.error(code, message, null) }
    }

    /** Releases the worker thread on engine detach. */
    fun close() {
        runCatching { ioExecutor.shutdown() }
    }

    companion object {
        private const val REQUEST_CODE = 0x5508
        // Long-side cap for the rectified page — parity with the embedded
        // scanner's captureAndRectify output (A4 @ 300dpi ≈ 3508px).
        private const val MAX_RECTIFIED_LONG_SIDE = 3508
        private const val RECTIFIED_JPEG_QUALITY = 95
        // Detection runs on a downscaled luma copy; the quad is normalized so it
        // maps back onto the full-res still. 1024 keeps the Kotlin luma loop and
        // native detect fast without starving the detector of edge detail.
        private const val DETECT_MAX_SIDE = 1024
    }
}
