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
import androidx.annotation.MainThread
import androidx.annotation.WorkerThread
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.lifecycle.LifecycleOwner
import io.supy.scanner.nativecore.NativeBarcode
import io.supy.scanner.nativecore.SupyNativeCore
import java.nio.ByteBuffer
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

    private val wireFormats: List<String> = extractFormats(creationParams)

    // One ML Kit client per PlatformView. Closed in dispose().
    private var barcodeScanner: BarcodeScanner = createScanner(wireFormats)

    private val cameraConfig: CameraConfig = CameraConfig.from(creationParams)

    // Native-core decode opts in via creationParams.useNativeCore. Three-layer gate:
    //   (1) Dart caller passed useNativeCore=true,
    //   (2) the .so loaded,
    //   (3) the build linked zxing-cpp (supy_core_has_zxing() == 1).
    // Any miss → ML Kit. Result is cached at construction; flips require a new view.
    private val nativeCoreEnabled: Boolean =
        (creationParams?.get("useNativeCore") as? Boolean == true) && SupyNativeCore.hasZxing()

    // libdmtx ROI assist: only run when (a) native decode is on, (b) the build
    // linked libdmtx. Whether to engage the locator on a given frame still
    // depends on the per-call format mask including Data Matrix.
    private val nativeDmLocateEnabled: Boolean =
        nativeCoreEnabled && SupyNativeCore.hasLibdmtx()

    @Volatile
    private var nativeFormatMask: Int = FormatMapper.toSupyFormatMask(wireFormats)

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
        @WorkerThread
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

            if (nativeCoreEnabled && tryNativeDecode(image)) {
                // Native path consumed the frame (decoded or cleanly empty).
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

        /**
         * Attempts a native-core decode on the frame's Y plane. Returns true when
         * the native path handled the frame (image already closed). Returns false
         * when we couldn't safely use the native path — the caller must fall back
         * to ML Kit on the same ImageProxy and is responsible for closing it.
         */
        private fun tryNativeDecode(image: ImageProxy): Boolean {
            val plane = image.planes.getOrNull(0) ?: return false
            // YUV_420_888 normally has pixelStride==1 on Y. Some packed formats
            // (NV12 with interleaved Y? unlikely, but defensive) report >1; bail.
            if (plane.pixelStride != 1) return false
            val buf = plane.buffer
            if (!buf.isDirect) return false
            val w = image.width
            val h = image.height
            val rowStride = plane.rowStride
            if (w <= 0 || h <= 0 || rowStride < w) return false

            val mask = nativeFormatMask
            val dmHits: List<NativeBarcode> = if (
                nativeDmLocateEnabled && FormatMapper.maskIncludesDataMatrix(mask)
            ) {
                tryDatamatrixRoiAssist(buf, w, h, rowStride)
            } else {
                emptyList()
            }

            // After the assist, run the full-frame decode for the remaining
            // formats. If only DM was requested we can skip — but only when
            // the assist actually ran (mask had DM and locator was enabled).
            val fullMask = if (dmHits.isNotEmpty() || nativeDmLocateEnabled) {
                FormatMapper.maskWithoutDataMatrix(mask)
            } else {
                mask
            }

            val full: List<NativeBarcode>? = if (fullMask != 0) {
                try {
                    SupyNativeCore.decodeBarcodes(
                        y = buf,
                        w = w,
                        h = h,
                        rowStride = rowStride,
                        formatMask = fullMask,
                        tryHarder = false,
                        tryRotate = true,
                    )
                } catch (_: Throwable) {
                    null
                }
            } else {
                emptyList()
            }
            if (full == null && dmHits.isEmpty()) {
                // Nothing ran successfully — fall back to ML Kit.
                return false
            }
            val merged: List<NativeBarcode> = if (full == null || full.isEmpty()) {
                dmHits
            } else if (dmHits.isEmpty()) {
                full
            } else {
                ArrayList<NativeBarcode>(dmHits.size + full.size).also {
                    it.addAll(dmHits); it.addAll(full)
                }
            }
            if (merged.isNotEmpty()) {
                emitNativeDetections(merged)
            }
            image.close()
            return true
        }

        // V1-S2-06.2: ring of the last two locator-hit frames used for
        // temporal median-of-3 luma fusion. Owned by the analyzer; never
        // touched off-thread.
        private val temporalRing = DatamatrixTemporalRing()

        // Runs the libdmtx locator on the luma plane, then re-feeds each region's
        // axis-aligned bbox crop into the native decode with a DM-only mask.
        // Returns an empty list on miss / locator failure — callers treat empty
        // and "locator off" identically and continue to the full-frame decode.
        private fun tryDatamatrixRoiAssist(
            buf: ByteBuffer,
            w: Int,
            h: Int,
            rowStride: Int,
        ): List<NativeBarcode> {
            val regions = try {
                SupyNativeCore.locateDatamatrix(buf, w, h, rowStride)
            } catch (_: Throwable) {
                null
            } ?: return emptyList()
            if (regions.isEmpty()) return emptyList()

            val hits = ArrayList<NativeBarcode>(regions.size)
            val frameBoxes = ArrayList<DatamatrixTemporalRing.Box>(regions.size)
            for (q in regions) {
                if (q.size != 8) continue
                var minX = q[0]; var maxX = q[0]
                var minY = q[1]; var maxY = q[1]
                var i = 2
                while (i < 8) {
                    val x = q[i]; val y = q[i + 1]
                    if (x < minX) minX = x; if (x > maxX) maxX = x
                    if (y < minY) minY = y; if (y > maxY) maxY = y
                    i += 2
                }
                // Pad ~6% on each side to give zxing-cpp quiet-zone slack,
                // then clamp to the frame.
                val padX = ((maxX - minX) * 0.06f).coerceAtLeast(2f)
                val padY = ((maxY - minY) * 0.06f).coerceAtLeast(2f)
                val rx0 = (minX - padX).toInt().coerceAtLeast(0)
                val ry0 = (minY - padY).toInt().coerceAtLeast(0)
                val rx1 = (maxX + padX).toInt().coerceAtMost(w - 1)
                val ry1 = (maxY + padY).toInt().coerceAtMost(h - 1)
                if (rx1 - rx0 + 1 < 12 || ry1 - ry0 + 1 < 12) continue
                val box = DatamatrixTemporalRing.Box(rx0, ry0, rx1, ry1)
                frameBoxes.add(box)

                // V1-S2-06.2: prefer the temporal-median fusion when this
                // region IoU-matched bboxes in BOTH prior frames. Otherwise
                // fall back to the raw current-frame luma — the same path
                // V1-S2-05.1 shipped with.
                val fused = temporalRing.tryFuse(buf, w, h, rowStride, box)
                val cropBuf: ByteBuffer
                val cw: Int
                val ch: Int
                val srcX0: Int
                val srcY0: Int
                if (fused != null) {
                    cropBuf = fused.luma
                    cw = fused.width
                    ch = fused.height
                    srcX0 = fused.srcX0
                    srcY0 = fused.srcY0
                } else {
                    cw = rx1 - rx0 + 1
                    ch = ry1 - ry0 + 1
                    srcX0 = rx0
                    srcY0 = ry0
                    val raw = ensureCropCapacity(cw * ch)
                    copyLumaCrop(buf, rowStride, srcX0, srcY0, cw, ch, raw)
                    cropBuf = raw
                }
                // V1-S2-05.1: Sauvola adaptive binarization on the DM crop
                // before zxing-cpp sees it. Soft fallback — failure means we
                // hand the un-binarized luma straight to decode.
                try {
                    SupyNativeCore.binarizeLumaCrop(
                        y = cropBuf,
                        w = cw,
                        h = ch,
                        rowStride = cw,
                        mode = SupyNativeCore.BinarizeMode.Sauvola2D,
                    )
                } catch (_: Throwable) {
                    // ignore — proceed with raw luma
                }
                val dm = try {
                    SupyNativeCore.decodeBarcodes(
                        y = cropBuf,
                        w = cw,
                        h = ch,
                        rowStride = cw,
                        formatMask = FormatMapper.SUPY_FORMAT_DATA_MATRIX_BIT,
                        tryHarder = true,
                        tryRotate = true,
                    )
                } catch (_: Throwable) {
                    null
                } ?: continue
                if (dm.isEmpty()) continue
                // Translate corners back into the source frame so the emitted
                // bounding box is in input-image pixel space (matching the
                // existing emitNativeDetections contract).
                for (b in dm) {
                    val translated = FloatArray(8)
                    var j = 0
                    while (j < 8) {
                        translated[j]     = b.corners[j] + srcX0
                        translated[j + 1] = b.corners[j + 1] + srcY0
                        j += 2
                    }
                    hits.add(NativeBarcode(b.rawValue, b.formatBit, translated))
                }
            }

            // Push this frame into the ring AFTER per-region fusion attempts
            // so the next frame can match against today's located bboxes.
            if (frameBoxes.isNotEmpty()) {
                temporalRing.push(buf, w, h, rowStride, frameBoxes)
            }
            return hits
        }

        // Reusable packed luma crop buffer — direct, grown lazily.
        private var cropBuffer: ByteBuffer? = null

        private fun ensureCropCapacity(needed: Int): ByteBuffer {
            val cur = cropBuffer
            if (cur != null && cur.capacity() >= needed) {
                cur.clear()
                return cur
            }
            // Grow with slack so subsequent frames don't reallocate.
            val grown = ByteBuffer.allocateDirect(needed + (needed shr 1))
            cropBuffer = grown
            return grown
        }

        private fun copyLumaCrop(
            src: ByteBuffer,
            srcStride: Int,
            x0: Int,
            y0: Int,
            cw: Int,
            ch: Int,
            dst: ByteBuffer,
        ) {
            // ImageProxy planes expose a direct ByteBuffer positioned at 0; we
            // rely on absolute get/put via duplicated views so the original
            // position is untouched.
            val srcView = src.duplicate()
            dst.position(0).limit(dst.capacity())
            val row = ByteArray(cw)
            for (yy in 0 until ch) {
                val srcOff = (y0 + yy) * srcStride + x0
                srcView.position(srcOff)
                srcView.get(row, 0, cw)
                dst.put(row, 0, cw)
            }
            dst.flip()
        }
    }

    private fun emitNativeDetections(results: List<NativeBarcode>) {
        val items = results.map { r ->
            val c = r.corners
            // Derive axis-aligned bbox from the four corner pairs.
            var minX = c[0]; var maxX = c[0]
            var minY = c[1]; var maxY = c[1]
            var i = 2
            while (i < 8) {
                val x = c[i]; val y = c[i + 1]
                if (x < minX) minX = x; if (x > maxX) maxX = x
                if (y < minY) minY = y; if (y > maxY) maxY = y
                i += 2
            }
            mapOf(
                "rawValue" to r.rawValue,
                "format" to FormatMapper.supyBitToWire(r.formatBit),
                "boundingBox" to mapOf(
                    "left" to minX.toDouble(),
                    "top" to minY.toDouble(),
                    "width" to (maxX - minX).toDouble(),
                    "height" to (maxY - minY).toDouble(),
                ),
            )
        }
        if (items.isEmpty()) return
        sendEvent(mapOf("type" to "detection", "items" to items))
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
                nativeFormatMask = FormatMapper.toSupyFormatMask(raw)
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

    @MainThread
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
