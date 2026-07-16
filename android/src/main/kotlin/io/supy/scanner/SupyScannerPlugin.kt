package io.supy.scanner

import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.supy.scanner.barcode.ActivityHolder
import io.supy.scanner.barcode.BatchBarcodeScannerLauncher
import io.supy.scanner.barcode.SupyBarcodeScannerViewFactory
import io.supy.scanner.document.DocumentScannerLauncher
import io.supy.scanner.document.SupyDocumentScannerViewFactory
import io.supy.scanner.nativecore.SupyNativeCore
import android.content.pm.ApplicationInfo
import io.supy.scanner.perf.DeviceTier
import io.supy.scanner.permissions.CameraPermissionHandler

/**
 * Entry point for the Supy Scanner Android plugin.
 *
 * Document OCR lands in Sprint 3 (S3-02). `scanDocument` here returns pages
 * with an empty `ocrText` until then.
 */
class SupyScannerPlugin : FlutterPlugin, ActivityAware, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private val activityHolder: ActivityHolder = ActivityHolder()
    private val cameraPermissions: CameraPermissionHandler = CameraPermissionHandler()
    private val documentLauncher: DocumentScannerLauncher = DocumentScannerLauncher()
    private val batchBarcodeLauncher: BatchBarcodeScannerLauncher =
        BatchBarcodeScannerLauncher()
    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)

        binding.platformViewRegistry.registerViewFactory(
            SupyBarcodeScannerViewFactory.VIEW_TYPE_ID,
            SupyBarcodeScannerViewFactory(binding.binaryMessenger, activityHolder),
        )

        binding.platformViewRegistry.registerViewFactory(
            SupyDocumentScannerViewFactory.VIEW_TYPE_ID,
            SupyDocumentScannerViewFactory(binding.binaryMessenger, activityHolder),
        )
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        // ML Kit's TextRecognizer (held inside DocumentScannerLauncher.ocrRunner)
        // is Closeable and pins native resources until released. Engine detach is
        // the last guaranteed teardown signal on the plugin lifecycle.
        documentLauncher.close()
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "requestCameraPermission" -> cameraPermissions.request(activityHolder.activity, result)
            "scanDocument" -> {
                val args = expectMapArgs(call, result) ?: return
                documentLauncher.launch(activityHolder.activity, args, result)
            }
            "scanBarcodesBatch" -> {
                val args = expectMapArgs(call, result) ?: return
                batchBarcodeLauncher.launch(activityHolder.activity, args, result)
            }
            "prewarm" -> {
                documentLauncher.prewarm(activityHolder.activity?.applicationContext)
                result.success(null)
            }
            "getDeviceTier" -> {
                val ctx = activityHolder.activity?.applicationContext
                val tier = if (ctx != null) {
                    when (DeviceTier.detect(ctx)) {
                        DeviceTier.HIGH -> "high"
                        DeviceTier.MID -> "mid"
                        DeviceTier.LOW -> "low"
                    }
                } else {
                    "unknown"
                }
                result.success(mapOf("tier" to tier))
            }
            "debugForceTier" -> {
                // Debug-only tier override. Silently no-ops on non-debuggable
                // builds — Dart side already gates with `kDebugMode`, this is
                // belt-and-braces so a hand-crafted method call from a release
                // build cannot force the tier.
                val ctx = activityHolder.activity?.applicationContext
                val debuggable = ctx != null &&
                    (ctx.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
                if (!debuggable) {
                    result.success(null)
                    return
                }
                val raw = call.argument<String?>("tier")
                val tier = when (raw) {
                    "high" -> DeviceTier.HIGH
                    "mid" -> DeviceTier.MID
                    "low" -> DeviceTier.LOW
                    null -> null
                    else -> {
                        result.error(
                            "unknown",
                            "debugForceTier: unknown tier '$raw' (want high|mid|low|null)",
                            null,
                        )
                        return
                    }
                }
                DeviceTier.setDebugOverride(tier)
                result.success(null)
            }
            "parseInvoice" -> {
                // Phase IXP — iOS-only in v1.2. Surface the canonical
                // `unimplemented` wire code so the Dart side can detect and
                // fall back gracefully (the experimental wrapper translates
                // it into a typed result).
                result.error(
                    "unimplemented",
                    "parseInvoice is iOS-only in v1.2 (Phase IXP)",
                    null,
                )
            }
            "nativeCoreProbe" -> {
                try {
                    val ctx = activityHolder.activity?.applicationContext
                    val gmsAvailable = ctx != null &&
                        io.supy.scanner.document.GmsAvailability.isUsable(ctx)
                    result.success(
                        mapOf(
                            "version" to SupyNativeCore.version(),
                            "abiVersion" to SupyNativeCore.abiVersion(),
                            "gmsDocumentScannerAvailable" to gmsAvailable,
                        ),
                    )
                } catch (t: Throwable) {
                    // Use the canonical `unknown` wire code (see
                    // `lib/src/models/supy_scan_error.dart`); the detail is
                    // preserved in the human-readable message.
                    result.error(
                        "unknown",
                        "Native core unavailable: ${t.message ?: t.javaClass.simpleName}",
                        null,
                    )
                }
            }
            else -> result.notImplemented()
        }
    }

    /// Validates that `call.arguments` is either null or a `Map<String, Any?>`.
    /// A non-null, non-map payload means a malformed caller — surface the
    /// canonical `unknown` error instead of silently dropping args.
    @Suppress("UNCHECKED_CAST")
    private fun expectMapArgs(call: MethodCall, result: Result): Map<String, Any?>? {
        val raw = call.arguments ?: return emptyMap()
        if (raw !is Map<*, *>) {
            result.error(
                "unknown",
                "${call.method}: arguments must be a Map<String, Any?>, " +
                    "got ${raw.javaClass.simpleName}",
                null,
            )
            return null
        }
        return raw as Map<String, Any?>
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityHolder.activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(cameraPermissions)
        binding.addActivityResultListener(documentLauncher)
        binding.addActivityResultListener(batchBarcodeLauncher)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(cameraPermissions)
        activityBinding?.removeActivityResultListener(documentLauncher)
        activityBinding?.removeActivityResultListener(batchBarcodeLauncher)
        activityHolder.activity = null
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityHolder.activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(cameraPermissions)
        binding.addActivityResultListener(documentLauncher)
        binding.addActivityResultListener(batchBarcodeLauncher)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(cameraPermissions)
        activityBinding?.removeActivityResultListener(documentLauncher)
        activityBinding?.removeActivityResultListener(batchBarcodeLauncher)
        activityHolder.activity = null
        activityBinding = null
    }

    companion object {
        private const val CHANNEL_NAME = "io.supy.scanner/v1"
    }
}
