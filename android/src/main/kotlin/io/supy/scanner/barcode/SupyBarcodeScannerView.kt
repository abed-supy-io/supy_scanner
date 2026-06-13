package io.supy.scanner.barcode

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
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

    init {
        container.addView(previewView)
        startCamera()
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
            setImageAnalysisAnalyzer(
                ContextCompat.getMainExecutor(context),
                AnalyzerImpl(),
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
            mainHandler.post { eventSink?.success(payload) }
        }
    }

    // ───────── Analyzer ─────────

    private inner class AnalyzerImpl : ImageAnalysis.Analyzer {

        @SuppressLint("UnsafeOptInUsageError")
        @OptIn(ExperimentalGetImage::class)
        override fun analyze(image: ImageProxy) {
            val mediaImage = image.image
            if (mediaImage == null) {
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
                result.success(null)
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
        eventChannel.setStreamHandler(null)
        eventSink = null
        cameraController?.clearImageAnalysisAnalyzer()
        cameraController?.unbind()
        previewView.controller = null
        cameraController = null
        runCatching { barcodeScanner.close() }
        container.removeAllViews()
    }

    companion object {
        private const val BARCODE_CHANNEL_PREFIX = "io.supy.scanner/v1/barcode"
    }
}
