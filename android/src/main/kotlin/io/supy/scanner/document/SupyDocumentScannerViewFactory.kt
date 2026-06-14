package io.supy.scanner.document

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.supy.scanner.barcode.ActivityHolder

/**
 * Factory for [SupyDocumentScannerView] PlatformViews.
 *
 * Registered against the view-type identifier `io.supy.scanner/v1/document_view`
 * — must match the Dart side in `SupyDocumentScannerView` (Dart).
 */
class SupyDocumentScannerViewFactory(
    private val messenger: BinaryMessenger,
    private val activityHolder: ActivityHolder,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val creationParams = args as? Map<String, Any?>
        return SupyDocumentScannerView(
            context = context,
            viewId = viewId,
            creationParams = creationParams,
            messenger = messenger,
            activityHolder = activityHolder,
        )
    }

    companion object {
        const val VIEW_TYPE_ID = "io.supy.scanner/v1/document_view"
    }
}
