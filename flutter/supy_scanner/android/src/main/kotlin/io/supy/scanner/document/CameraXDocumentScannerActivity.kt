package io.supy.scanner.document

import android.Manifest
import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.MainThread
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import io.supy.scanner.nativecore.GuidanceClassifyResult
import io.supy.scanner.nativecore.GuidanceConfig
import io.supy.scanner.nativecore.GuidanceFrameMetrics
import io.supy.scanner.nativecore.GuidanceFrameState
import io.supy.scanner.nativecore.SupyNativeCore
import io.supy.scanner.perf.DeviceTier
import java.io.File
import java.util.ArrayList
import java.util.concurrent.Executors

/**
 * CameraX-backed document capture screen used when Google Play services is
 * unavailable (Phase CXD fallback path). Manual capture only — no edge
 * detection in v1.2. Captured JPEGs are written to `cacheDir/supy_camx/` and
 * returned as URIs in [EXTRA_RESULT_URIS] for [DocumentScannerLauncher] to
 * re-encode + OCR through the same pipeline as the GMS path.
 */
class CameraXDocumentScannerActivity : AppCompatActivity() {

    private lateinit var previewView: PreviewView
    private lateinit var thumbStrip: LinearLayout
    private lateinit var captureButton: TextView
    private lateinit var doneButton: TextView
    private lateinit var pageCounter: TextView
    private lateinit var hintLabel: TextView

    private var cameraController: LifecycleCameraController? = null

    private val capturedUris: MutableList<Uri> = ArrayList()
    private var maxPages: Int = 0
    private var finished: Boolean = false
    @Volatile private var captureInFlight: Boolean = false

    // Auto-snap config & state.
    private var autoCaptureDelayMs: Int = 0
    private var effectiveDwellMs: Int = 0
    private var locale: String = "en"
    // Ordinal in [0..4] matching `SupyDocumentPageQuality` wire order. Pages
    // whose post-capture score falls below this prompt a retake dialog.
    private var minPageQualityOrdinal: Int = 0
    private var deviceTier: DeviceTier = DeviceTier.MID
    private var guidanceConfig: GuidanceConfig = GuidanceConfig()
    private var guidanceHandle: Long = 0L
    @Volatile private var lastGuidanceState: GuidanceFrameState = GuidanceFrameState.NoDocument
    @Volatile private var readyDwellStartMs: Long = 0L
    private val analyzerExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "supy-cxd-analyzer").apply { isDaemon = true }
    }
    private val analyzer: DocumentFrameAnalyzer = DocumentFrameAnalyzer { metrics ->
        onAnalyzerMetrics(metrics)
    }

    @MainThread
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        maxPages = intent.getIntExtra(EXTRA_MAX_PAGES, 0)
        autoCaptureDelayMs = intent.getIntExtra(EXTRA_AUTO_CAPTURE_DELAY_MS, 0)
        locale = intent.getStringExtra(EXTRA_LOCALE) ?: "en"
        minPageQualityOrdinal = wireToQualityOrdinal(intent.getStringExtra(EXTRA_MIN_PAGE_QUALITY))
        deviceTier = DeviceTier.detect(this)
        guidanceConfig = configForTier(deviceTier)
        effectiveDwellMs = if (autoCaptureDelayMs > 0) {
            maxOf(autoCaptureDelayMs, autoSnapFloorMsForTier(deviceTier))
        } else {
            0
        }
        if (autoCaptureDelayMs > 0) {
            guidanceHandle = SupyNativeCore.guidanceCreate()
        }

        setContentView(buildUi())

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            finishWith(RESULT_PERMISSION_DENIED)
            return
        }

        startCamera()
    }

    override fun onDestroy() {
        cameraController?.unbind()
        cameraController = null
        analyzerExecutor.shutdown()
        if (guidanceHandle != 0L) {
            SupyNativeCore.guidanceDestroy(guidanceHandle)
            guidanceHandle = 0L
        }
        super.onDestroy()
    }

    override fun onBackPressed() {
        finishCancelled()
    }

    // ───────── UI ─────────

    @SuppressLint("SetTextI18n")
    private fun buildUi(): View {
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }

        previewView = PreviewView(this).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
        }
        root.addView(previewView)

        val cancelButton = TextView(this).apply {
            text = "Cancel"
            setTextColor(Color.WHITE)
            background = pillBackground(SCRIM_BLACK_055, dp(22))
            setPadding(dp(22), dp(10), dp(22), dp(10))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            isClickable = true
            isFocusable = true
            setOnClickListener { finishCancelled() }
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                topMargin = dp(16) + statusBarInset()
                leftMargin = dp(20)
            }
        }
        root.addView(cancelButton)

        pageCounter = TextView(this).apply {
            text = formatCounter()
            setTextColor(Color.WHITE)
            background = pillBackground(SCRIM_BLACK_055, dp(14))
            setPadding(dp(16), dp(8), dp(16), dp(8))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            typeface = Typeface.create(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                topMargin = dp(16) + statusBarInset()
            }
        }
        root.addView(pageCounter)

        hintLabel = TextView(this).apply {
            text = hintFor(GuidanceFrameState.NoDocument)
            setTextColor(Color.WHITE)
            background = pillBackground(SCRIM_BLACK_055, dp(14))
            setPadding(dp(16), dp(8), dp(16), dp(8))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            gravity = Gravity.CENTER
            visibility = if (autoCaptureDelayMs > 0) View.VISIBLE else View.GONE
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                topMargin = dp(64) + statusBarInset()
                leftMargin = dp(20)
                rightMargin = dp(20)
            }
        }
        root.addView(hintLabel)

        // Thumbnail strip sits above the bottom action bar.
        thumbStrip = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(12), dp(8), dp(12), dp(8))
        }
        val thumbScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(thumbStrip)
            background = pillBackground(SCRIM_BLACK_055, dp(12))
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                dp(THUMB_STRIP_HEIGHT_DP),
            ).apply {
                gravity = Gravity.BOTTOM
                bottomMargin = dp(96)
                leftMargin = dp(12)
                rightMargin = dp(12)
            }
        }
        root.addView(thumbScroll)

        captureButton = TextView(this).apply {
            text = "Capture"
            setTextColor(Color.BLACK)
            background = pillBackground(Color.WHITE, dp(28))
            setPadding(dp(32), dp(14), dp(32), dp(14))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            typeface = Typeface.create(typeface, Typeface.BOLD)
            isClickable = true
            isFocusable = true
            setOnClickListener { triggerCapture() }
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                bottomMargin = dp(24)
            }
        }
        root.addView(captureButton)

        doneButton = TextView(this).apply {
            text = "Done"
            setTextColor(Color.WHITE)
            background = pillBackground(SUPY_PRIMARY, dp(22))
            setPadding(dp(28), dp(10), dp(28), dp(10))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            typeface = Typeface.create(typeface, Typeface.BOLD)
            isClickable = true
            isFocusable = true
            alpha = DISABLED_ALPHA
            setOnClickListener {
                if (capturedUris.isNotEmpty()) finishOk()
            }
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.END
                bottomMargin = dp(32)
                rightMargin = dp(20)
            }
        }
        root.addView(doneButton)

        return root
    }

    // ───────── Camera ─────────

    private fun startCamera() {
        val controller = try {
            LifecycleCameraController(this).apply {
                setEnabledUseCases(
                    androidx.camera.view.CameraController.IMAGE_CAPTURE or
                        androidx.camera.view.CameraController.IMAGE_ANALYSIS
                )
                setImageCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                setImageAnalysisBackpressureStrategy(
                    ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST
                )
                if (autoCaptureDelayMs > 0) {
                    setImageAnalysisAnalyzer(analyzerExecutor, analyzer)
                }
                bindToLifecycle(this@CameraXDocumentScannerActivity)
            }
        } catch (t: Throwable) {
            finishWith(RESULT_CAMERA_UNAVAILABLE)
            return
        }
        previewView.controller = controller
        cameraController = controller
    }

    private fun triggerCapture() {
        if (finished || captureInFlight) return
        val controller = cameraController ?: return
        if (maxPages in 1..capturedUris.size) return

        captureInFlight = true
        captureButton.alpha = DISABLED_ALPHA
        readyDwellStartMs = 0L

        val pagesDir = File(cacheDir, "supy_camx").apply { mkdirs() }
        val outFile = File(pagesDir, "page_${SystemClock.elapsedRealtime()}.jpg")
        val output = ImageCapture.OutputFileOptions.Builder(outFile).build()

        controller.takePicture(
            output,
            ContextCompat.getMainExecutor(this),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(result: ImageCapture.OutputFileResults) {
                    captureInFlight = false
                    val saved = result.savedUri ?: Uri.fromFile(outFile)
                    if (shouldGatePage(saved)) {
                        promptRetake(saved, outFile)
                    } else {
                        acceptCapturedPage(saved)
                    }
                }

                override fun onError(exc: ImageCaptureException) {
                    captureInFlight = false
                    refreshControls()
                    io.supy.scanner.log.SupyLog.w(
                        message = "CameraX capture failed: ${exc.message}",
                        throwable = exc,
                    )
                }
            },
        )
    }

    // ───────── Auto-snap ─────────

    // Worker thread: analyzer executor.
    private fun onAnalyzerMetrics(metrics: DocumentFrameMetrics) {
        if (finished || guidanceHandle == 0L) return
        val result: GuidanceClassifyResult = SupyNativeCore.guidanceClassify(
            guidanceHandle,
            GuidanceFrameMetrics(
                hasDocument = metrics.quad.isNotEmpty(),
                clipsEdge = metrics.clipsEdge,
                coverageRatio = metrics.coverageRatio.toFloat(),
                tiltDegrees = metrics.tiltDegrees.toFloat(),
                meanLuma = metrics.meanLuma.toFloat(),
                blurScore = metrics.blurScore.toFloat(),
                quadStability = metrics.quadStability.toFloat(),
                interiorVariance = metrics.interiorVariance.toFloat(),
                glareRatio = metrics.glareRatio.toFloat(),
                cornerVelocity = metrics.cornerVelocity.toFloat(),
                centerOffsetX = metrics.centerOffset.first.toFloat(),
                centerOffsetY = metrics.centerOffset.second.toFloat(),
                perCornerStability = metrics.perCornerStability
                    .map(Double::toFloat)
                    .toFloatArray(),
            ),
            guidanceConfig,
        )
        val state = result.state
        val now = SystemClock.elapsedRealtime()
        val shouldFire = if (state == GuidanceFrameState.Ready) {
            if (readyDwellStartMs == 0L) {
                readyDwellStartMs = now
                false
            } else {
                (now - readyDwellStartMs) >= effectiveDwellMs
            }
        } else {
            readyDwellStartMs = 0L
            false
        }
        lastGuidanceState = state
        runOnUiThread {
            if (!finished) hintLabel.text = hintFor(state)
            if (shouldFire && !captureInFlight &&
                (maxPages == 0 || capturedUris.size < maxPages)
            ) {
                triggerCapture()
            }
        }
    }

    private fun configForTier(tier: DeviceTier): GuidanceConfig = when (tier) {
        // Slower dwell on low-end devices — fewer frames per second so we need
        // more of them to be confident. See backlog risk register.
        DeviceTier.LOW -> GuidanceConfig(readyStableFrames = 18)
        DeviceTier.MID -> GuidanceConfig(readyStableFrames = 12)
        DeviceTier.HIGH -> GuidanceConfig(readyStableFrames = 9)
    }

    // Tier-aware floor on the auto-snap dwell window. Applied as
    // max(consumer-requested delay, floor) so low-end devices can't auto-fire
    // before motion has truly settled. See core-cxd-auto-snap backlog.
    private fun autoSnapFloorMsForTier(tier: DeviceTier): Int = when (tier) {
        DeviceTier.LOW -> 1200
        DeviceTier.MID -> 800
        DeviceTier.HIGH -> 600
    }

    private fun hintFor(state: GuidanceFrameState): String {
        val ar = locale.startsWith("ar", ignoreCase = true)
        return when (state) {
            GuidanceFrameState.NoDocument -> if (ar) "ضع المستند في الإطار" else "Place document in frame"
            GuidanceFrameState.TooDark -> if (ar) "الإضاءة منخفضة جداً" else "Too dark"
            GuidanceFrameState.TooClose -> if (ar) "ابتعد قليلاً" else "Move farther"
            GuidanceFrameState.TooFar -> if (ar) "اقترب قليلاً" else "Move closer"
            GuidanceFrameState.TooSkewed -> if (ar) "اضبط زاوية الكاميرا" else "Hold camera level"
            GuidanceFrameState.Blurry -> if (ar) "ثبّت الكاميرا" else "Hold steady"
            GuidanceFrameState.HoldSteady -> if (ar) "ثبّت قليلاً" else "Almost there — hold steady"
            GuidanceFrameState.Ready -> if (ar) "جاهز للالتقاط" else "Ready"
            GuidanceFrameState.Glare -> if (ar) "وهج على المستند — غيّر الزاوية" else "Glare on page — change angle"
            GuidanceFrameState.Occluded -> if (ar) "ابعد إصبعك عن المستند" else "Move your finger off the document"
            GuidanceFrameState.HandShake -> if (ar) "ثبّت يدك" else "Steady your hand"
            GuidanceFrameState.EdgeClipped -> if (ar) "حافة المستند خارج الإطار" else "Edge of document is cut off"
            GuidanceFrameState.OffCenter -> if (ar) "وسّط المستند في الإطار" else "Center the document"
        }
    }

    private fun wireToQualityOrdinal(wire: String?): Int = when (wire) {
        "veryPoor" -> 0
        "poor" -> 1
        "ok" -> 2
        "good" -> 3
        "excellent" -> 4
        else -> 0
    }

    // ───────── Pages ─────────

    private fun acceptCapturedPage(uri: Uri) {
        capturedUris.add(uri)
        addThumbnail(uri, capturedUris.size - 1)
        refreshControls()
    }

    // Re-score the captured JPEG with the static-image scorer (variance of
    // Laplacian). The launcher pipeline will score the page a second time on
    // re-encode — we accept that double-decode to keep the retake gate
    // synchronous and in-flow. minPageQualityOrdinal==0 ("veryPoor") admits
    // everything, matching the non-breaking default on the Dart side.
    private fun shouldGatePage(uri: Uri): Boolean {
        if (minPageQualityOrdinal <= 0) return false
        val score = PageReencoder.scoreUri(this, uri) ?: return false
        val bucket = wireToQualityOrdinal(score.first)
        return bucket < minPageQualityOrdinal
    }

    private fun promptRetake(uri: Uri, file: File) {
        if (finished) return
        val ar = locale.startsWith("ar", ignoreCase = true)
        AlertDialog.Builder(this)
            .setTitle(if (ar) "جودة الصفحة منخفضة" else "Page quality looks low")
            .setMessage(
                if (ar) "هل تريد إعادة الالتقاط أو الاحتفاظ بها على أي حال؟"
                else "Retake for a clearer scan, or keep this page anyway?",
            )
            .setPositiveButton(if (ar) "إعادة الالتقاط" else "Retake") { dialog, _ ->
                runCatching { file.delete() }
                dialog.dismiss()
                refreshControls()
            }
            .setNegativeButton(if (ar) "احتفظ" else "Keep") { dialog, _ ->
                acceptCapturedPage(uri)
                dialog.dismiss()
            }
            .setCancelable(false)
            .show()
    }

    private fun addThumbnail(uri: Uri, index: Int) {
        val size = dp(THUMB_SIZE_DP)
        val thumb = ImageView(this).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            background = pillBackground(Color.DKGRAY, dp(8))
            layoutParams = LinearLayout.LayoutParams(size, size).apply {
                rightMargin = dp(8)
            }
            isClickable = true
            isFocusable = true
            contentDescription = "Captured page ${index + 1}"
            setOnClickListener { showPageMenu(uri) }
            decodeThumb(uri)?.let { setImageBitmap(it) }
        }
        thumbStrip.addView(thumb)
    }

    private fun decodeThumb(uri: Uri): Bitmap? = runCatching {
        contentResolver.openInputStream(uri)?.use { stream ->
            val opts = BitmapFactory.Options().apply { inSampleSize = THUMB_SAMPLE_SIZE }
            BitmapFactory.decodeStream(stream, null, opts)
        }
    }.getOrNull()

    private fun showPageMenu(uri: Uri) {
        if (finished) return
        AlertDialog.Builder(this)
            .setTitle("Page options")
            .setItems(arrayOf("Delete", "Cancel")) { dialog, which ->
                if (which == 0) deletePage(uri)
                dialog.dismiss()
            }
            .show()
    }

    private fun deletePage(uri: Uri) {
        val idx = capturedUris.indexOf(uri)
        if (idx < 0) return
        capturedUris.removeAt(idx)
        thumbStrip.removeViewAt(idx)
        // Re-tag remaining thumbnails so contentDescription stays accurate.
        for (i in 0 until thumbStrip.childCount) {
            thumbStrip.getChildAt(i).contentDescription = "Captured page ${i + 1}"
        }
        runCatching { uri.path?.let { File(it).delete() } }
        refreshControls()
    }

    @SuppressLint("SetTextI18n")
    private fun refreshControls() {
        pageCounter.text = formatCounter()
        val capAllowsMore = maxPages == 0 || capturedUris.size < maxPages
        val canCapture = capAllowsMore && !captureInFlight
        captureButton.isEnabled = canCapture
        captureButton.alpha = if (canCapture) ENABLED_ALPHA else DISABLED_ALPHA
        val canDone = capturedUris.isNotEmpty()
        doneButton.isEnabled = canDone
        doneButton.alpha = if (canDone) ENABLED_ALPHA else DISABLED_ALPHA
    }

    @SuppressLint("SetTextI18n")
    private fun formatCounter(): String =
        if (maxPages > 0) "${capturedUris.size} / $maxPages" else "${capturedUris.size}"

    // ───────── Helpers ─────────

    private fun pillBackground(color: Int, radius: Int): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radius.toFloat()
            setColor(color)
        }

    private fun statusBarInset(): Int {
        val id = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) resources.getDimensionPixelSize(id) else 0
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    // ───────── Exits ─────────

    private fun finishOk() {
        if (finished) return
        finished = true
        val data = Intent().apply {
            putStringArrayListExtra(
                EXTRA_RESULT_URIS,
                ArrayList(capturedUris.map { it.toString() }),
            )
        }
        setResult(RESULT_OK, data)
        finish()
    }

    private fun finishCancelled() {
        if (finished) return
        finished = true
        setResult(RESULT_CANCELED)
        finish()
    }

    private fun finishWith(resultCode: Int) {
        if (finished) return
        finished = true
        setResult(resultCode)
        finish()
    }

    companion object {
        const val EXTRA_MAX_PAGES = "io.supy.scanner.camx.maxPages"
        const val EXTRA_RESULT_URIS = "io.supy.scanner.camx.result.uris"
        const val EXTRA_AUTO_CAPTURE_DELAY_MS = "io.supy.scanner.camx.autoCaptureDelayMs"
        const val EXTRA_LOCALE = "io.supy.scanner.camx.locale"
        /** Wire string from `SupyDocumentPageQuality.name` (veryPoor..excellent). */
        const val EXTRA_MIN_PAGE_QUALITY = "io.supy.scanner.camx.minPageQuality"

        /** Set by the Activity when `CAMERA` permission is missing at start. */
        const val RESULT_PERMISSION_DENIED = 0x5601

        /** Set when CameraX provider binding fails. */
        const val RESULT_CAMERA_UNAVAILABLE = 0x5602

        private const val SUPY_PRIMARY: Int = 0xFF1AC0E5.toInt()
        private const val SCRIM_BLACK_055: Int = 0x8C000000.toInt()

        private const val THUMB_STRIP_HEIGHT_DP = 84
        private const val THUMB_SIZE_DP = 64
        private const val THUMB_SAMPLE_SIZE = 8

        private const val ENABLED_ALPHA = 1.0f
        private const val DISABLED_ALPHA = 0.45f
    }
}
