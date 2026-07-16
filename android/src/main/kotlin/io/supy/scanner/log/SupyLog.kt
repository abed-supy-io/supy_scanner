package io.supy.scanner.log

import android.util.Log

/**
 * Thin tagged wrapper around [android.util.Log] used by every native
 * diagnostic site inside the plugin. Host apps that want to silence the
 * library entirely flip [enabled] to false (e.g. from a debug menu).
 *
 * Mirror of the Dart `SupyLog` facade (`lib/src/log/supy_log.dart`). Keep
 * the level enum and tag convention in sync.
 *
 * Never log barcode payloads, OCR text, or file URIs through this — see
 * `docs/SECURITY.md` §8.
 */
object SupyLog {
    /** Default tag if a caller doesn't supply one. */
    private const val DEFAULT_TAG = "SupyScanner"

    /** Toggle the entire native log stream. */
    @Volatile
    @JvmStatic
    var enabled: Boolean = true

    @JvmStatic
    fun d(tag: String = DEFAULT_TAG, message: String) {
        if (!enabled) return
        Log.d(tag, message)
    }

    @JvmStatic
    fun i(tag: String = DEFAULT_TAG, message: String) {
        if (!enabled) return
        Log.i(tag, message)
    }

    @JvmStatic
    fun w(tag: String = DEFAULT_TAG, message: String, throwable: Throwable? = null) {
        if (!enabled) return
        if (throwable != null) {
            Log.w(tag, message, throwable)
        } else {
            Log.w(tag, message)
        }
    }

    @JvmStatic
    fun e(tag: String = DEFAULT_TAG, message: String, throwable: Throwable? = null) {
        if (!enabled) return
        if (throwable != null) {
            Log.e(tag, message, throwable)
        } else {
            Log.e(tag, message)
        }
    }
}
