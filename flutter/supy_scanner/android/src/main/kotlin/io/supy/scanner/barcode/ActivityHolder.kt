package io.supy.scanner.barcode

import android.app.Activity

/**
 * Mutable holder for the host [Activity], shared between the plugin and the
 * PlatformView factory.
 *
 * The factory is registered at `onAttachedToEngine`, which can fire before
 * `onAttachedToActivity`. The factory therefore receives this holder (not the
 * Activity directly) and reads through it at create time.
 */
class ActivityHolder {
    @Volatile
    var activity: Activity? = null
}
