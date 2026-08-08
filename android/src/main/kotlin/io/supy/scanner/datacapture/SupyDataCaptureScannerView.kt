package io.supy.scanner.datacapture

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import androidx.annotation.MainThread
import androidx.annotation.WorkerThread
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.supy.scanner.barcode.ActivityHolder
import io.supy.scanner.perf.DeviceTier
import java.util.concurrent.Executors

/**
 * PlatformView hosting the embedded live text-pattern (generic data-capture)
 * camera preview + per-frame ML Kit text recognizer (DC7).
 *
 * The native side ships recognized-text geometry per frame (`frame_text`
 * events); the Dart side ([SupyTextPatternMatcher]) runs the regex patterns
 * over it. This view therefore exposes only camera lifecycle: torch / pause /
 * resume + a `preview_started` event. Detection runs on the analyzer thread;
 * events are marshalled to main only at the sink boundary. Single ML Kit
 * client per PlatformView, closed in dispose().
 *
 * Arabic OCR is intentionally not supported on Android (ML Kit is Latin-only);
 * iOS covers `ar` via Vision. See `docs/MIGRATION.md`.
 */
class SupyDataCaptureScannerView(
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
        "$DATACAPTURE_CHANNEL_PREFIX/$viewId",
    ).also { it.setMethodCallHandler(this) }

    private val eventChannel: EventChannel = EventChannel(
        messenger,
        "$DATACAPTURE_CHANNEL_PREFIX/$viewId/events",
    ).also { it.setStreamHandler(this) }

    private val mainHandler: Handler = Handler(Looper.getMainLooper())

    // One ML Kit text-recognizer client per PlatformView. Closed in dispose().
    private val recognizer: TextRecognizer =
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

    private var cameraController: LifecycleCameraController? = null
    private var eventSink: EventChannel.EventSink? = null
    private var previewStartedAnnounced: Boolean = false

    private val deviceTier: DeviceTier = DeviceTier.detect(context)
    private val analyzerExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "supy-datacapture-analyzer").apply { isDaemon = true }
    }
    // OCR is heavier than barcode decode, so cap the analyzer cadence on the
    // per-tier FPS ceiling (falls back to ~10fps when the tier is uncapped) to
    // keep the analyzer thread from queueing behind a slow recognition pass.
    private val frameIntervalNs: Long =
        1_000_000_000L / (deviceTier.analyzerFpsCap() ?: 10)
    private var lastAnalyzedNs: Long = 0L

    init {
        container.addView(previewView)
        startCamera()
    }

    // ───────── Camera lifecycle ─────────

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
            setImageAnalysisBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            setImageAnalysisAnalyzer(analyzerExecutor, AnalyzerImpl())
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
            ),
        )
    }

    private fun emitError(code: String, message: String) {
        sendEvent(
            mapOf(
                "type" to "error",
                "code" to code,
                "message" to message,
            ),
        )
    }

    private fun sendEvent(payload: Map<String, Any?>) {
        val sink = eventSink ?: return
        if (Looper.myLooper() == Looper.getMainLooper()) {
            sink.success(payload)
        } else {
            mainHandler.post { eventSink?.success(payload) }
        }
    }

    // ───────── Analyzer ─────────

    private inner class AnalyzerImpl : ImageAnalysis.Analyzer {

        @SuppressLint("UnsafeOptInUsageError")
        @OptIn(ExperimentalGetImage::class)
        @WorkerThread
        override fun analyze(image: ImageProxy) {
            val now = System.nanoTime()
            if (now - lastAnalyzedNs < frameIntervalNs) {
                image.close()
                return
            }
            lastAnalyzedNs = now

            val mediaImage = image.image
            if (mediaImage == null) {
                image.close()
                return
            }

            val rotation = image.imageInfo.rotationDegrees
            // ML Kit reports geometry in the upright (rotation-applied) frame,
            // so the dimensions to normalize against swap for 90/270.
            val imgWidth = if (rotation == 90 || rotation == 270) image.height else image.width
            val imgHeight = if (rotation == 90 || rotation == 270) image.width else image.height

            val input = InputImage.fromMediaImage(mediaImage, rotation)
            recognizer.process(input)
                .addOnSuccessListener { recognized ->
                    val tree = buildTree(recognized, imgWidth, imgHeight)
                    sendEvent(tree + ("type" to "frame_text"))
                }
                .addOnFailureListener { e ->
                    emitError("unknown", e.message ?: "Text recognition failed")
                }
                .addOnCompleteListener {
                    image.close()
                }
        }
    }

    /**
     * Builds the block → line → element tree consumed by
     * `SupyRecognizedText.fromMap`. Boxes normalized to `[0..1]`, top-left
     * origin. Elements are always included on the live path — the Dart matcher
     * only reads block/line/fullText, but shipping elements keeps the wire tree
     * identical to the standalone `recognizeText` shape.
     */
    private fun buildTree(text: Text, imgWidth: Int, imgHeight: Int): Map<String, Any?> {
        val blocks = text.textBlocks.map { block ->
            val lines = block.lines.map { line ->
                val elements = line.elements.map { element ->
                    mapOf(
                        "text" to element.text,
                        "boundingBox" to normRect(element.boundingBox, imgWidth, imgHeight),
                    )
                }
                mapOf(
                    "text" to line.text,
                    "boundingBox" to normRect(line.boundingBox, imgWidth, imgHeight),
                    "elements" to elements,
                )
            }
            mapOf(
                "text" to block.text,
                "boundingBox" to normRect(block.boundingBox, imgWidth, imgHeight),
                "lines" to lines,
            )
        }
        return mapOf("fullText" to text.text, "blocks" to blocks)
    }

    private fun normRect(rect: Rect?, imgWidth: Int, imgHeight: Int): Map<String, Double> {
        if (rect == null || imgWidth <= 0 || imgHeight <= 0) {
            return mapOf("left" to 0.0, "top" to 0.0, "width" to 0.0, "height" to 0.0)
        }
        val w = imgWidth.toDouble()
        val h = imgHeight.toDouble()
        return mapOf(
            "left" to rect.left / w,
            "top" to rect.top / h,
            "width" to rect.width() / w,
            "height" to rect.height() / h,
        )
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

    @MainThread
    override fun dispose() {
        methodChannel.setMethodCallHandler(null)
        runCatching { eventSink?.endOfStream() }
        eventSink = null
        eventChannel.setStreamHandler(null)
        cameraController?.clearImageAnalysisAnalyzer()
        cameraController?.unbind()
        previewView.controller = null
        cameraController = null
        runCatching { recognizer.close() }
        runCatching { analyzerExecutor.shutdown() }
        container.removeAllViews()
    }

    companion object {
        private const val DATACAPTURE_CHANNEL_PREFIX = "io.supy.scanner/v1/datacapture"
    }
}
