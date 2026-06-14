package io.supy.scanner.document

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.io.File
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.supy.scanner.barcode.ActivityHolder

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

    private var cameraController: LifecycleCameraController? = null
    private var eventSink: EventChannel.EventSink? = null
    private var previewStartedAnnounced: Boolean = false

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
                ContextCompat.getMainExecutor(context),
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
                val controller = cameraController
                if (controller == null) {
                    result.error("camera_unavailable", "Camera controller is not bound", null)
                    return
                }
                val file = try {
                    File.createTempFile("supy-doc-", ".jpg", context.cacheDir)
                } catch (e: Exception) {
                    result.error("captureFailed", e.message ?: "could not create temp file", null)
                    return
                }
                val output = ImageCapture.OutputFileOptions.Builder(file).build()
                controller.takePicture(
                    output,
                    ContextCompat.getMainExecutor(context),
                    object : ImageCapture.OnImageSavedCallback {
                        override fun onImageSaved(outputResults: ImageCapture.OutputFileResults) {
                            val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                            BitmapFactory.decodeFile(file.absolutePath, opts)
                            result.success(
                                mapOf(
                                    "path" to file.absolutePath,
                                    "widthPx" to opts.outWidth,
                                    "heightPx" to opts.outHeight,
                                )
                            )
                        }
                        override fun onError(exc: ImageCaptureException) {
                            result.error("captureFailed", exc.message ?: "capture failed", null)
                        }
                    }
                )
            }
            "captureAndRectify" -> {
                // V1-S6-02 stub. Sprint 4 must land `warpPerspective` in the
                // native core before this can return a real page.
                result.error(
                    "UNIMPLEMENTED",
                    "captureAndRectify awaits Sprint 4 warpPerspective",
                    null,
                )
            }
            else -> result.notImplemented()
        }
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
        container.removeAllViews()
    }

    companion object {
        private const val DOCUMENT_CHANNEL_PREFIX = "io.supy.scanner/v1/document"
    }
}
