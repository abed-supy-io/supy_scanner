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
        LOW -> minOf(requested, 88)
    }

    companion object {
        @Volatile
        private var cached: DeviceTier? = null

        // Debug-only tier override. Honored by `detect()` in debuggable builds
        // so engineers can repro tier-low behaviour on a tier-high CI device.
        // Set via the `debugForceTier` MethodChannel call from Dart, which is
        // itself gated by `kDebugMode` — so this is also gated on the
        // application's `FLAG_DEBUGGABLE` to belt-and-braces strip in release.
        @Volatile
        private var debugOverride: DeviceTier? = null

        fun detect(context: Context): DeviceTier {
            debugOverride?.let { return it }
            cached?.let { return it }
            val resolved = compute(context)
            cached = resolved
            return resolved
        }

        /**
         * Forces [detect] to return [tier] until cleared. No-op on release
         * builds (caller-side `FLAG_DEBUGGABLE` check enforces this).
         * Pass `null` to clear.
         */
        fun setDebugOverride(tier: DeviceTier?) {
            debugOverride = tier
        }

        /** Current debug override or null if none. Test/inspection helper. */
        fun debugOverride(): DeviceTier? = debugOverride

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
