package io.supy.scanner.document

import android.content.Context
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability

/**
 * Detects whether Google Play services is present and usable on the device.
 *
 * The GMS Document Scanner client depends on Play services. On devices where
 * GMS is missing (Huawei, AOSP, locked-down enterprise images) or in an
 * unrecoverable state, `getStartScanIntent` fails with `model_unavailable`.
 * v1.2 Phase CXD branches to a CameraX-backed capture flow in that case;
 * this helper is the gate.
 */
internal object GmsAvailability {

    /**
     * Returns true when Play services reports [ConnectionResult.SUCCESS] —
     * i.e. the GMS Document Scanner is safe to invoke. Any other status
     * (missing, disabled, updating, version too old) returns false so the
     * caller can fall back to the CameraX path.
     */
    fun isUsable(context: Context): Boolean {
        val status = GoogleApiAvailability.getInstance()
            .isGooglePlayServicesAvailable(context.applicationContext)
        return status == ConnectionResult.SUCCESS
    }
}
