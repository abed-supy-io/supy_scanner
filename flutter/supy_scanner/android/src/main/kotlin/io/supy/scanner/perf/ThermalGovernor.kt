package io.supy.scanner.perf

import android.content.Context
import android.os.Build
import android.os.PowerManager

/**
 * Thread-safe observer of the OS thermal state.
 *
 * Wraps `PowerManager.addThermalStatusListener` on API 29+. On older devices
 * (or when PowerManager isn't available) it stays at `NOMINAL` and never
 * fires — callers degrade gracefully.
 *
 * Emits two derived signals consumers care about:
 *   - `shouldPause()` → analyzer should stop processing frames
 *     (PowerManager THERMAL_STATUS_SEVERE / CRITICAL / EMERGENCY / SHUTDOWN).
 *   - `shouldThrottle()` → analyzer should drop FPS further (MODERATE+).
 *
 * The raw integer state is also published so it can be surfaced over an
 * EventChannel for consumer visibility.
 */
class ThermalGovernor(
    context: Context,
    private val onChange: (state: Int, shouldPause: Boolean, shouldThrottle: Boolean) -> Unit,
) {
    @Volatile
    var state: Int = STATE_NOMINAL
        private set

    private val pm: PowerManager? =
        context.applicationContext.getSystemService(Context.POWER_SERVICE) as? PowerManager

    private val listener: PowerManager.OnThermalStatusChangedListener? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            PowerManager.OnThermalStatusChangedListener { status -> handle(status) }
        } else {
            null
        }

    fun start() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val pm = pm ?: return
        val l = listener ?: return
        pm.addThermalStatusListener(l)
        handle(pm.currentThermalStatus)
    }

    fun stop() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val pm = pm ?: return
        val l = listener ?: return
        runCatching { pm.removeThermalStatusListener(l) }
    }

    fun shouldPause(): Boolean = state >= STATE_SEVERE
    fun shouldThrottle(): Boolean = state >= STATE_MODERATE

    private fun handle(status: Int) {
        state = status
        onChange(status, shouldPause(), shouldThrottle())
    }

    companion object {
        const val STATE_NOMINAL = 0
        const val STATE_LIGHT = 1
        const val STATE_MODERATE = 2
        const val STATE_SEVERE = 3
    }
}
