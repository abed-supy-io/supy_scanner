package io.supy.scanner.barcode

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.view.CameraController
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.lifecycle.LifecycleOwner
import io.supy.scanner.perf.DeviceTier
import io.supy.scanner.perf.IdleDetector
import io.supy.scanner.perf.ThermalGovernor
import java.util.concurrent.Executors
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

/**
 * PlatformView hosting the embedded barcode camera preview + ML Kit analyzer.
 *
 * S1-09 scope: CameraX preview lifecycle + torch + ML Kit barcode detection
 * with format filtering. Per-CLAUDE.md: single ML Kit client per PlatformView,
 * closed in dispose(); detection runs on the analyzer thread; results
 * marshalled to main only at the channel boundary.
 */
class SupyBarcodeScannerView(
    private val context: Context,
    viewId: Int,
    creationParams: Map<String, Any?>?,
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
        "$BARCODE_CHANNEL_PREFIX/$viewId",
    ).also { it.setMethodCallHandler(this) }

    private val eventChannel: EventChannel = EventChannel(
        messenger,
        "$BARCODE_CHANNEL_PREFIX/$viewId/events",
    ).also { it.setStreamHandler(this) }

    private val mainHandler: Handler = Handler(Looper.getMainLooper())

    private var cameraController: LifecycleCameraController? = null
    private var eventSink: EventChannel.EventSink? = null
    private var previewStartedAnnounced: Boolean = false

    // One ML Kit client per PlatformView. Closed in dispose().
    private var barcodeScanner: BarcodeScanner = createScanner(extractFormats(creationParams))

    private val cameraConfig: CameraConfig = CameraConfig.from(creationParams)

    private val deviceTier: DeviceTier = DeviceTier.detect(context)
    private val analyzerExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "supy-barcode-analyzer").apply { isDaemon = true }
    }
    private val frameIntervalNs: Long = deviceTier.analyzerFpsCap()?.let { fps ->
        1_000_000_000L / fps
    } ?: 0L
    private var lastAnalyzedNs: Long = 0L

    private val idleDetector: IdleDetector = IdleDetector(
        thresholdMs = deviceTier.idlePauseThresholdMs(),
    )

    @Volatile
    private var torchOn: Boolean = false

    @Volatile
    private var thermalPaused: Boolean = false

    @Volatile
    private var thermalThrottleIntervalNs: Long = 0L

    private val thermalGovernor: ThermalGovernor = ThermalGovernor(context) { state, pause, throttle ->
        thermalPaused = pause
        // Halve effective FPS on MODERATE+ when a base cap exists; cap-less
        // (HIGH tier) gets a soft ~20fps ceiling so flagships still cool down.
        thermalThrottleIntervalNs = if (throttle) {
            val base = if (frameIntervalNs > 0L) frameIntervalNs else 1_000_000_000L / 20L
            base * 2L
        } else {
            0L
        }
        sendEvent(
            mapOf(
                "type" to "thermal",
                "state" to thermalStateName(state),
                "paused" to pause,
                "throttled" to throttle,
            )
        )
    }

    private fun thermalStateName(state: Int): String = when (state) {
        ThermalGovernor.STATE_NOMINAL -> "nominal"
        ThermalGovernor.STATE_LIGHT -> "light"
        ThermalGovernor.STATE_MODERATE -> "moderate"
        ThermalGovernor.STATE_SEVERE -> "serious"
        else -> "critical"
    }

    init {
        container.addView(previewView)
        startCamera()
        thermalGovernor.start()
    }

    private data class CameraConfig(
        val initialZoom: Float,
        val minFocusDistanceLock: Boolean,
        val scanRange: String,
    ) {
        companion object {
            @Suppress("UNCHECKED_CAST")
            fun from(params: Map<String, Any?>?): CameraConfig {
                val block = params?.get("camera") as? Map<String, Any?>
                val zoom = (block?.get("initialZoom") as? Number)?.toFloat() ?: 1.0f
                val lock = (block?.get("minFocusDistanceLock") as? Boolean) ?: false
                val range = (block?.get("scanRange") as? String) ?: "standard"
                return CameraConfig(zoom, lock, range)
            }
        }
    }

    // ───────── Scanner client ─────────

    private fun extractFormats(params: Map<String, Any?>?): List<String> {
        val raw = params?.get("formats") as? List<*> ?: return emptyList()
        return raw.filterIsInstance<String>()
    }

    private fun createScanner(wireFormats: List<String>): BarcodeScanner {
        val formats = FormatMapper.toMlKitFormats(wireFormats)
        return if (formats == null) {
            BarcodeScanning.getClient()
        } else {
            val builder = BarcodeScannerOptions.Builder()
            // setBarcodeFormats takes a head + vararg tail.
            val head = formats.first()
            val tail = formats.drop(1).toIntArray()
            builder.setBarcodeFormats(head, *tail)
            BarcodeScanning.getClient(builder.build())
        }
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
            emitError(
                "camera_unavailable",
                "Host Activity is not a LifecycleOwner",
            )
            return
        }

        val controller = LifecycleCameraController(context).apply {
            setImageAnalysisBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            deviceTier.barcodeAnalyzerSize()?.let { size ->
                @Suppress("DEPRECATION")
                setImageAnalysisTargetSize(
                    CameraController.OutputSize(size)
                )
            }
            setImageAnalysisAnalyzer(
                analyzerExecutor,
                AnalyzerImpl(),
            )
            bindToLifecycle(lifecycleOwner)
        }
        previewView.controller = controller
        cameraController = controller

        previewView.previewStreamState.observe(lifecycleOwner) { state ->
            if (state == PreviewView.StreamState.STREAMING && !previewStartedAnnounced) {
                previewStartedAnnounced = true
                applyInitialCameraConfig(controller)
                emitPreviewStarted(controller)
            }
        }
    }

    private fun applyInitialCameraConfig(controller: LifecycleCameraController) {
        if (cameraConfig.initialZoom != 1.0f) {
            runCatching { controller.setZoomRatio(cameraConfig.initialZoom) }
        }
        // minFocusDistanceLock + scanRange.extended are wired to the v1.1
        // native CV core (Sprint 2+). Honoring them on Android today requires
        // CameraX Camera2 interop; the wire value is preserved for the native
        // core path.
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
        val sink = eventSink ?: return
        if (Looper.myLooper() == Looper.getMainLooper()) {
            sink.success(payload)
        } else {
            // Re-read eventSink on main to avoid posting to a stream that has
            // since been cancelled/disposed.
            mainHandler.post { eventSink?.success(payload) }
        }
    }

    // ───────── Analyzer ─────────

    private inner class AnalyzerImpl : ImageAnalysis.Analyzer {

        @SuppressLint("UnsafeOptInUsageError")
        @OptIn(ExperimentalGetImage::class)
        override fun analyze(image: ImageProxy) {
            if (thermalPaused) {
                image.close()
                return
            }
            val effectiveIntervalNs = maxOf(frameIntervalNs, thermalThrottleIntervalNs)
            if (effectiveIntervalNs > 0L) {
                val now = System.nanoTime()
                if (now - lastAnalyzedNs < effectiveIntervalNs) {
                    image.close()
                    return
                }
                lastAnalyzedNs = now
            }
            val mediaImage = image.image
            if (mediaImage == null) {
                image.close()
                return
            }

            // Cheap luma-variance gate: skip ML Kit work on a static scene.
            // The variance pass itself is ~1k arithmetic ops, dwarfed by the
            // savings on idle frames.
            val nowMs = System.currentTimeMillis()
            val transitioned = idleDetector.update(image, nowMs)
            if (transitioned) {
                sendEvent(
                    mapOf(
                        "type" to if (idleDetector.isIdle) "idle_pause" else "idle_resume",
                    )
                )
                if (idleDetector.isIdle && torchOn) {
                    sendEvent(mapOf("type" to "torch_idle_suggested"))
                }
            }
            if (idleDetector.isIdle) {
                image.close()
                return
            }

            val input = InputImage.fromMediaImage(
                mediaImage,
                image.imageInfo.rotationDegrees,
            )
            barcodeScanner.process(input)
                .addOnSuccessListener { barcodes ->
                    if (barcodes.isNotEmpty()) {
                        emitDetections(barcodes)
                    }
                }
                .addOnFailureListener { e ->
                    emitError("unknown", e.message ?: "Barcode analysis failed")
                }
                .addOnCompleteListener {
                    image.close()
                }
        }
    }

    private fun emitDetections(barcodes: List<Barcode>) {
        val items = barcodes.mapNotNull { b ->
            val raw = b.rawValue ?: return@mapNotNull null
            val item = mutableMapOf<String, Any?>(
                "rawValue" to raw,
                "format" to FormatMapper.mlKitToWire(b.format),
            )
            b.boundingBox?.let { box ->
                item["boundingBox"] = mapOf(
                    "left" to box.left.toDouble(),
                    "top" to box.top.toDouble(),
                    "width" to box.width().toDouble(),
                    "height" to box.height().toDouble(),
                )
            }
            item
        }
        if (items.isEmpty()) return
        sendEvent(
            mapOf(
                "type" to "detection",
                "items" to items,
            )
        )
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
                val on = (call.argument<Boolean>("on")) ?: false
                cameraController?.enableTorch(on)
                torchOn = on
                result.success(null)
            }
            "setZoom" -> {
                val factor = (call.argument<Number>("factor"))?.toFloat()
                val controller = cameraController
                if (factor == null || controller == null) {
                    // Canonical `unknown`; detail preserved in message.
                    result.error("unknown", "setZoom: factor missing or no camera", null)
                } else {
                    val applyOutcome = runCatching { controller.setZoomRatio(factor) }
                    if (applyOutcome.isFailure) {
                        result.error(
                            "camera_unavailable",
                            applyOutcome.exceptionOrNull()?.message ?: "setZoomRatio failed",
                            null,
                        )
                    } else {
                        val applied = runCatching {
                            controller.zoomState.value?.zoomRatio ?: factor
                        }.getOrDefault(factor)
                        result.success(mapOf("zoom" to applied.toDouble()))
                    }
                }
            }
            "flipCamera" -> {
                val controller = cameraController
                if (controller == null) {
                    result.error("camera_unavailable", "No camera bound", null)
                } else {
                    val nextSelector = if (controller.cameraSelector == CameraSelector.DEFAULT_BACK_CAMERA) {
                        CameraSelector.DEFAULT_FRONT_CAMERA
                    } else {
                        CameraSelector.DEFAULT_BACK_CAMERA
                    }
                    val swapOutcome = runCatching { controller.cameraSelector = nextSelector }
                    if (swapOutcome.isFailure) {
                        result.error(
                            "camera_unavailable",
                            swapOutcome.exceptionOrNull()?.message ?: "flipCamera failed",
                            null,
                        )
                    } else {
                        // The new lens needs the initial config re-applied (zoom resets
                        // when the selector changes) and the host needs a fresh
                        // preview_started so it can refresh flash availability.
                        previewStartedAnnounced = false
                        applyInitialCameraConfig(controller)
                        previewStartedAnnounced = true
                        emitPreviewStarted(controller)
                        val nowFront = nextSelector == CameraSelector.DEFAULT_FRONT_CAMERA
                        result.success(mapOf("position" to if (nowFront) "front" else "back"))
                    }
                }
            }
            "setMinFocusDistanceLock" -> {
                // CameraX has no public min-focus-distance lock API on v1.
                // Surface the gap to Dart so the controller doesn't cache a
                // value that was never applied. The native CV core (v1.1
                // Sprint 2+) will engage close-focus heuristics when wired.
                result.error(
                    "unsupported_operation",
                    "min-focus-distance lock is not supported on Android in supy_scanner v1",
                    null,
                )
            }
            "setFormats" -> {
                @Suppress("UNCHECKED_CAST")
                val raw = call.argument<List<String>>("formats") ?: emptyList()
                val oldScanner = barcodeScanner
                barcodeScanner = createScanner(raw)
                runCatching { oldScanner.close() }
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

    override fun dispose() {
        methodChannel.setMethodCallHandler(null)
        // Send `endOfStream` before tearing down the channel so the Dart side
        // sees a clean stream completion instead of a silent drop. `dispose()`
        // is invoked on the platform thread (main), so the sink call is safe
        // here.
        runCatching { eventSink?.endOfStream() }
        eventSink = null
        eventChannel.setStreamHandler(null)
        cameraController?.clearImageAnalysisAnalyzer()
        cameraController?.unbind()
        previewView.controller = null
        cameraController = null
        runCatching { thermalGovernor.stop() }
        runCatching { barcodeScanner.close() }
        runCatching { analyzerExecutor.shutdown() }
        container.removeAllViews()
    }

    companion object {
        private const val BARCODE_CHANNEL_PREFIX = "io.supy.scanner/v1/barcode"
    }
}
