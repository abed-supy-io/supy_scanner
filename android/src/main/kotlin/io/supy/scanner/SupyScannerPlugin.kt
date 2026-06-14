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
            "nativeCoreProbe" -> {
                try {
                    result.success(
                        mapOf(
                            "version" to SupyNativeCore.version(),
                            "abiVersion" to SupyNativeCore.abiVersion(),
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
