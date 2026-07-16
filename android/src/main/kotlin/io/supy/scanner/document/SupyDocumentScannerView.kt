package io.supy.scanner.document

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import androidx.annotation.MainThread
import androidx.annotation.WorkerThread
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.supy.scanner.barcode.ActivityHolder
import io.supy.scanner.nativecore.SupyNativeCore

/**
 * PlatformView hosting the embedded document scanner preview with live
 * frame-quality guidance.
 *
 * Mirrors the iOS `SupyDocumentScannerView`: emits `preview_started`,
 * `frame_metrics`, and `error` events on a per-view EventChannel; honors
 * `pause`/`resume`/`setTorch` on a per-view MethodChannel.
 *
 * Per CLAUDE.md: single analyzer instance per PlatformView; the analyzer
 * runs on a background executor; results marshalled to main only at the
 * EventSink boundary.
 *
 * Edge-detection (the document quad itself) is not wired on Android in this
 * spike — see `DocumentFrameAnalyzer` for the gap and the followup plan.
 */
class SupyDocumentScannerView(
    private val context: Context,
    viewId: Int,
    @Suppress("UNUSED_PARAMETER") creationParams: Map<String, Any?>?,
    messenger: BinaryMessenger,
    private val activityHolder: ActivityHolder,
) : PlatformView, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val container: FrameLayout = FrameLayout(context).apply {
        setBackgroundColor(Color.BLACK)
    }

    private val previewView: PreviewView = PreviewView(context).apply {
        scaleType = PreviewView.ScaleType.FILL_CENTER
        layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        )
    }

    private val methodChannel: MethodChannel = MethodChannel(
        messenger,
        "$DOCUMENT_CHANNEL_PREFIX/$viewId",
    ).also { it.setMethodCallHandler(this) }

    private val eventChannel: EventChannel = EventChannel(
        messenger,
        "$DOCUMENT_CHANNEL_PREFIX/$viewId/events",
    ).also { it.setStreamHandler(this) }

    private val mainHandler: Handler = Handler(Looper.getMainLooper())

    // Single-threaded analyzer executor — CameraX must invoke
    // DocumentFrameAnalyzer.analyze(ImageProxy) off the main thread (see
    // CLAUDE.md / docs/ARCHITECTURE.md "Lifecycle invariants" and the
    // @WorkerThread contract on the analyzer).
    private val analyzerExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "supy-document-analyzer").apply { isDaemon = true }
    }

    // Off-main executor for the captureAndRectify heavy path (JPEG decode +
    // native perspective warp + enhance + re-encode). Kept separate from the
    // analyzer executor so a capture never stalls live frame guidance.
    private val rectifyExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "supy-document-rectify").apply { isDaemon = true }
    }

    private var cameraController: LifecycleCameraController? = null
    private var eventSink: EventChannel.EventSink? = null
    private var previewStartedAnnounced: Boolean = false
    @Volatile private var isCapturing: Boolean = false

    private val analyzer: DocumentFrameAnalyzer = DocumentFrameAnalyzer { metrics ->
        emitFrameMetrics(metrics)
    }

    init {
        container.addView(previewView)
        startCamera()
    }

    private fun startCamera() {
        val activity = activityHolder.activity
        if (activity == null) {
            emitError("camera_unavailable", "Host Activity is not attached yet")
            return
        }
        val lifecycleOwner = activity as? LifecycleOwner
        if (lifecycleOwner == null) {
            emitError("camera_unavailable", "Host Activity is not a LifecycleOwner")
            return
        }

        val controller = LifecycleCameraController(context).apply {
            setImageAnalysisBackpressureStrategy(
                ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST
            )
            setImageAnalysisAnalyzer(
                analyzerExecutor,
                analyzer,
            )
            bindToLifecycle(lifecycleOwner)
        }
        previewView.controller = controller
        cameraController = controller

        previewView.previewStreamState.observe(lifecycleOwner) { state ->
            if (state == PreviewView.StreamState.STREAMING && !previewStartedAnnounced) {
                previewStartedAnnounced = true
                emitPreviewStarted(controller)
            }
        }
    }

    private fun emitPreviewStarted(controller: LifecycleCameraController) {
        val flashAvailable = runCatching {
            controller.cameraInfo?.hasFlashUnit() == true
        }.getOrDefault(false)
        sendEvent(
            mapOf(
                "type" to "preview_started",
                "flashAvailable" to flashAvailable,
            )
        )
    }

    private fun emitFrameMetrics(metrics: DocumentFrameMetrics) {
        val payload = HashMap<String, Any?>(metrics.toMap())
        payload["type"] = "frame_metrics"
        sendEvent(payload)
    }

    private fun emitError(code: String, message: String) {
        sendEvent(
            mapOf(
                "type" to "error",
                "code" to code,
                "message" to message,
            )
        )
    }

    private fun sendEvent(payload: Map<String, Any?>) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            eventSink?.success(payload)
        } else {
            mainHandler.post { eventSink?.success(payload) }
        }
    }

    // ───────── MethodChannel ─────────

    @MainThread
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pause" -> {
                cameraController?.unbind()
                result.success(null)
            }
            "resume" -> {
                val lifecycleOwner = activityHolder.activity as? LifecycleOwner
                if (lifecycleOwner == null) {
                    result.error("camera_unavailable", "No LifecycleOwner", null)
                } else {
                    cameraController?.bindToLifecycle(lifecycleOwner)
                    result.success(null)
                }
            }
            "setTorch" -> {
                val on = call.argument<Boolean>("on") ?: false
                cameraController?.enableTorch(on)
                result.success(null)
            }
            "captureFullFrame" -> {
                if (isCapturing) {
                    result.error("captureFailed", "capture already in progress", null)
                    return
                }
                val controller = cameraController
                if (controller == null) {
                    result.error("camera_unavailable", "Camera controller is not bound", null)
                    return
                }
                val cacheDir = context.cacheDir
                if (cacheDir == null) {
                    result.error("captureFailed", "cache directory unavailable", null)
                    return
                }
                val file = try {
                    File.createTempFile("supy-doc-", ".jpg", cacheDir)
                } catch (e: IOException) {
                    result.error("captureFailed", e.message ?: "could not create temp file", null)
                    return
                }
                isCapturing = true
                val output = ImageCapture.OutputFileOptions.Builder(file).build()
                controller.takePicture(
                    output,
                    ContextCompat.getMainExecutor(context),
                    object : ImageCapture.OnImageSavedCallback {
                        override fun onImageSaved(outputResults: ImageCapture.OutputFileResults) {
                            val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                            BitmapFactory.decodeFile(file.absolutePath, opts)
                            isCapturing = false
                            if (opts.outWidth <= 0 || opts.outHeight <= 0) {
                                file.delete()
                                result.error("captureFailed", "saved JPEG could not be decoded", null)
                                return
                            }
                            result.success(
                                mapOf(
                                    "path" to file.absolutePath,
                                    "widthPx" to opts.outWidth,
                                    "heightPx" to opts.outHeight,
                                )
                            )
                        }
                        override fun onError(exc: ImageCaptureException) {
                            isCapturing = false
                            file.delete()
                            result.error("captureFailed", exc.message ?: "capture failed", null)
                        }
                    }
                )
            }
            "captureAndRectify" -> {
                if (isCapturing) {
                    result.error("captureFailed", "capture already in progress", null)
                    return
                }
                val controller = cameraController
                if (controller == null) {
                    result.error("camera_unavailable", "Camera controller is not bound", null)
                    return
                }
                // Snapshot the last smoothed quad (normalized TL,TR,BR,BL). With
                // no quad we can't rectify — signal `captureUnsupported` so the
                // Dart widget falls back to `captureFullFrame` (parity with iOS).
                val quad = analyzer.lastDetectedQuad()
                if (quad == null || quad.size != 8) {
                    result.error("captureUnsupported", "No document quad detected", null)
                    return
                }
                val cacheDir = context.cacheDir
                if (cacheDir == null) {
                    result.error("captureFailed", "cache directory unavailable", null)
                    return
                }
                val file = try {
                    File.createTempFile("supy-doc-", ".jpg", cacheDir)
                } catch (e: IOException) {
                    result.error("captureFailed", e.message ?: "could not create temp file", null)
                    return
                }
                isCapturing = true
                val output = ImageCapture.OutputFileOptions.Builder(file).build()
                controller.takePicture(
                    output,
                    ContextCompat.getMainExecutor(context),
                    object : ImageCapture.OnImageSavedCallback {
                        override fun onImageSaved(outputResults: ImageCapture.OutputFileResults) {
                            // Decode + warp + enhance + encode is heavy — bounce
                            // off the main thread; result is posted back to main.
                            rectifyExecutor.execute { rectifyCapturedStill(file, quad, result) }
                        }
                        override fun onError(exc: ImageCaptureException) {
                            isCapturing = false
                            file.delete()
                            result.error("captureFailed", exc.message ?: "capture failed", null)
                        }
                    }
                )
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Decodes the full-res still at [srcFile], rectifies it through the native
     * perspective warp using the normalized [quad] (TL,TR,BR,BL), enhances and
     * re-encodes the flat page, and posts the channel [result] back on main.
     * Best-effort: any failure deletes the temp file, clears [isCapturing], and
     * replies with an error. A degenerate quad falls back to `captureUnsupported`
     * so the Dart widget can retry via `captureFullFrame`.
     */
    @WorkerThread
    private fun rectifyCapturedStill(
        srcFile: File,
        quad: FloatArray,
        result: MethodChannel.Result,
    ) {
        fun fail(code: String, message: String) {
            srcFile.delete()
            isCapturing = false
            mainHandler.post { result.error(code, message, null) }
        }

        val decoded = try {
            BitmapFactory.decodeFile(srcFile.absolutePath)
        } catch (oom: OutOfMemoryError) {
            null
        }
        if (decoded == null) {
            fail("captureFailed", "saved JPEG could not be decoded")
            return
        }
        // copyPixelsToBuffer only yields RGBA bytes for ARGB_8888; convert if a
        // decoder fallback handed us something else (mutable so warp output can
        // reuse the in-place enhance path downstream).
        val source = if (decoded.config != Bitmap.Config.ARGB_8888) {
            val converted = try {
                decoded.copy(Bitmap.Config.ARGB_8888, false)
            } catch (oom: OutOfMemoryError) {
                null
            }
            decoded.recycle()
            converted
        } else {
            decoded
        }
        if (source == null) {
            fail("captureFailed", "could not convert still to ARGB_8888")
            return
        }

        val width = source.width
        val height = source.height
        val rowStride = source.rowBytes
        val byteCount = rowStride * height
        if (width <= 0 || height <= 0 || byteCount <= 0) {
            source.recycle()
            fail("captureFailed", "invalid still dimensions")
            return
        }
        val srcBuf = try {
            ByteBuffer.allocateDirect(byteCount).order(ByteOrder.nativeOrder())
        } catch (oom: OutOfMemoryError) {
            source.recycle()
            fail("captureFailed", "out of memory decoding still")
            return
        }
        source.copyPixelsToBuffer(srcBuf)
        srcBuf.rewind()
        source.recycle()

        // Scale the normalized quad into input-image pixel space.
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
            fail("captureUnsupported", "perspective warp failed or quad degenerate")
            return
        }

        val warped = try {
            Bitmap.createBitmap(warp.width, warp.height, Bitmap.Config.ARGB_8888)
        } catch (oom: OutOfMemoryError) {
            null
        }
        if (warped == null) {
            fail("captureFailed", "out of memory building rectified page")
            return
        }
        warped.copyPixelsFromBuffer(ByteBuffer.wrap(warp.rgba))

        val page = PageReencoder.reencodeBitmap(
            context = context,
            bitmap = warped, // recycled inside reencodeBitmap
            quality = RECTIFIED_JPEG_QUALITY,
            format = PageReencoder.Format.JPG,
            enhanceMode = PageReencoder.EnhanceMode.BALANCED,
        )
        srcFile.delete()
        isCapturing = false
        val path = page?.uri?.path
        if (path == null) {
            mainHandler.post {
                result.error("captureFailed", "could not encode rectified page", null)
            }
            return
        }
        val quadPayload = (0 until 4).map {
            mapOf("x" to quad[it * 2].toDouble(), "y" to quad[it * 2 + 1].toDouble())
        }
        val payload = mapOf(
            "path" to path,
            "widthPx" to warp.width,
            "heightPx" to warp.height,
            "quad" to quadPayload,
            // Legacy keys for SupyDocumentPage.fromMap consumers (controller.capture()).
            "uri" to page.uri.toString(),
            "width" to warp.width,
            "height" to warp.height,
        )
        mainHandler.post { result.success(payload) }
    }

    // ───────── EventChannel ─────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        val controller = cameraController ?: return
        if (previewView.previewStreamState.value == PreviewView.StreamState.STREAMING &&
            !previewStartedAnnounced
        ) {
            previewStartedAnnounced = true
            emitPreviewStarted(controller)
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // ───────── PlatformView ─────────

    override fun getView(): View = container

    @MainThread
    override fun dispose() {
        methodChannel.setMethodCallHandler(null)
        // Send `endOfStream` before detaching the handler so the Dart side
        // sees a clean stream completion instead of a silent drop. `dispose()`
        // is invoked on the platform thread (main).
        runCatching { eventSink?.endOfStream() }
        eventSink = null
        eventChannel.setStreamHandler(null)
        cameraController?.clearImageAnalysisAnalyzer()
        cameraController?.unbind()
        previewView.controller = null
        cameraController = null
        runCatching { analyzerExecutor.shutdown() }
        runCatching { rectifyExecutor.shutdown() }
        container.removeAllViews()
    }

    companion object {
        private const val DOCUMENT_CHANNEL_PREFIX = "io.supy.scanner/v1/document"

        // Caps the rectified page's longer side to bound memory while staying
        // ≥300 DPI for a full-page A4 invoice (≈2480×3508). Aspect is preserved
        // by the native warp; 0 would mean unbounded.
        private const val MAX_RECTIFIED_LONG_SIDE = 3508

        // High-fidelity JPEG for the canonical scan output. captureAndRectify
        // takes no per-call quality arg (the Dart controller invokes it bare),
        // so this is the fixed encode quality for the rectified page.
        private const val RECTIFIED_JPEG_QUALITY = 95
    }
}
