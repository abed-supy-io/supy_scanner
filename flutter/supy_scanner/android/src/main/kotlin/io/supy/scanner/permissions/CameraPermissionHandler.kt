package io.supy.scanner.permissions

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/**
 * Bridges Android's runtime camera-permission flow to a single
 * `requestCameraPermission` MethodChannel call.
 *
 * Wire payload matches [SupyCameraPermissionStatus] on the Dart side:
 * `{ "status": "granted" | "denied" | "permanentlyDenied" }`.
 */
class CameraPermissionHandler : PluginRegistry.RequestPermissionsResultListener {

    private var pendingResult: Result? = null
    private var requestingActivity: Activity? = null

    fun request(activity: Activity?, result: Result) {
        if (activity == null) {
            result.error("camera_unavailable", "No Activity attached", null)
            return
        }
        val current = ContextCompat.checkSelfPermission(activity, CAMERA)
        if (current == PackageManager.PERMISSION_GRANTED) {
            result.success(mapOf("status" to "granted"))
            return
        }
        if (pendingResult != null) {
            result.error(
                "unknown",
                "A camera permission request is already in progress",
                null,
            )
            return
        }
        pendingResult = result
        requestingActivity = activity
        ActivityCompat.requestPermissions(activity, arrayOf(CAMERA), REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val pending = pendingResult ?: return false
        val activity = requestingActivity
        pendingResult = null
        requestingActivity = null

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        val status = when {
            granted -> "granted"
            // shouldShowRequestPermissionRationale returns `false` after the
            // user has selected "Don't ask again" (or on devices where the
            // OS won't prompt again).
            activity != null &&
                !ActivityCompat.shouldShowRequestPermissionRationale(activity, CAMERA) ->
                "permanentlyDenied"
            else -> "denied"
        }
        pending.success(mapOf("status" to status))
        return true
    }

    companion object {
        private const val CAMERA = Manifest.permission.CAMERA
        private const val REQUEST_CODE = 0x5505 // "SUPY" → 0x5505 (arbitrary)
    }
}
