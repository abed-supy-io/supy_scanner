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
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import java.io.File
import java.util.ArrayList

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

    private var imageCapture: ImageCapture? = null
    private var cameraProvider: ProcessCameraProvider? = null

    private val capturedUris: MutableList<Uri> = ArrayList()
    private var maxPages: Int = 0
    private var finished: Boolean = false
    private var captureInFlight: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        maxPages = intent.getIntExtra(EXTRA_MAX_PAGES, 0)

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
        cameraProvider?.unbindAll()
        cameraProvider = null
        imageCapture = null
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
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            val provider = try {
                future.get()
            } catch (t: Throwable) {
                finishWith(RESULT_CAMERA_UNAVAILABLE)
                return@addListener
            }
            cameraProvider = provider
            val preview = Preview.Builder().build().also {
                it.setSurfaceProvider(previewView.surfaceProvider)
            }
            val capture = ImageCapture.Builder()
                .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                .build()
            imageCapture = capture
            try {
                provider.unbindAll()
                provider.bindToLifecycle(
                    this,
                    CameraSelector.DEFAULT_BACK_CAMERA,
                    preview,
                    capture,
                )
            } catch (t: Throwable) {
                finishWith(RESULT_CAMERA_UNAVAILABLE)
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun triggerCapture() {
        if (finished || captureInFlight) return
        val capture = imageCapture ?: return
        if (maxPages in 1..capturedUris.size) return

        captureInFlight = true
        captureButton.alpha = DISABLED_ALPHA

        val pagesDir = File(cacheDir, "supy_camx").apply { mkdirs() }
        val outFile = File(pagesDir, "page_${SystemClock.elapsedRealtime()}.jpg")
        val output = ImageCapture.OutputFileOptions.Builder(outFile).build()

        capture.takePicture(
            output,
            ContextCompat.getMainExecutor(this),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(result: ImageCapture.OutputFileResults) {
                    captureInFlight = false
                    val saved = result.savedUri ?: Uri.fromFile(outFile)
                    capturedUris.add(saved)
                    addThumbnail(saved, capturedUris.size - 1)
                    refreshControls()
                }

                override fun onError(exc: ImageCaptureException) {
                    captureInFlight = false
                    refreshControls()
                    // Surface a transient inline error; do not abort the session.
                    android.util.Log.w(
                        "SupyScanner",
                        "CameraX capture failed: ${exc.message}",
                        exc,
                    )
                }
            },
        )
    }

    // ───────── Pages ─────────

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
