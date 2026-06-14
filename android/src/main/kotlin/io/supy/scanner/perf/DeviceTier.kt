package io.supy.scanner.perf

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.util.Size

/**
 * Device performance tier used by perf-adaptive code paths (analyzer
 * resolution, FPS caps, OCR downscaling, idle thresholds).
 *
 * See docs/PERFORMANCE.md → "Device-class adaptive — flagships keep their
 * power" for the policy table this implements.
 */
enum class DeviceTier {
    HIGH, MID, LOW;

    /** Target analyzer resolution for the embedded barcode pipeline. */
    fun barcodeAnalyzerSize(): Size? = when (this) {
        HIGH -> null
        MID -> Size(960, 720)
        LOW -> Size(640, 480)
    }

    /** Cap analyzer dispatch FPS. `null` = uncapped (use camera native). */
    fun analyzerFpsCap(): Int? = when (this) {
        HIGH -> null
        MID -> 24
        LOW -> 20
    }

    /** Idle pause threshold in milliseconds, or `null` to disable. */
    fun idlePauseThresholdMs(): Long? = when (this) {
        HIGH -> null
        MID -> 8_000
        LOW -> 4_000
    }

    /** Long-edge cap (px) for OCR input images. `null` = no downscale. */
    fun ocrLongEdgeCap(): Int? = when (this) {
        HIGH -> null
        MID -> 1600
        LOW -> 1280
    }

    /** Tier-adjusted persisted-page JPEG quality. */
    fun jpegQuality(requested: Int): Int = when (this) {
        HIGH -> requested
        MID -> requested
        LOW -> minOf(requested, 75)
    }

    companion object {
        @Volatile
        private var cached: DeviceTier? = null

        fun detect(context: Context): DeviceTier {
            cached?.let { return it }
            val resolved = compute(context)
            cached = resolved
            return resolved
        }

        private fun compute(context: Context): DeviceTier {
            val am = context.applicationContext
                .getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                ?: return MID

            val info = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
            val totalGb = info.totalMem.toDouble() / (1024.0 * 1024.0 * 1024.0)

            if (am.isLowRamDevice || totalGb < 4.0) return LOW

            val sdkOk = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
            if (sdkOk && totalGb >= 6.0) return HIGH

            return MID
        }
    }
}
