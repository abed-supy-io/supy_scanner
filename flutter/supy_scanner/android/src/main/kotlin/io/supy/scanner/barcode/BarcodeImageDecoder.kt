package io.supy.scanner.barcode

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import io.supy.scanner.nativecore.SupyNativeCore
import java.io.IOException
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * One-shot still-image barcode decode backing the `decodeImage` channel method.
 *
 * Loads an image already on disk and decodes it with ML Kit (default) or the
 * bundled zxing-cpp core (`useNativeCore`). Emits maps identical in shape to
 * the live-preview detections (`SupyBarcodeScannerView.emitDetections`).
 */
internal class BarcodeImageDecoder {

    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun decode(
        context: Context?,
        uri: Uri,
        wireFormats: List<String>,
        useNativeCore: Boolean,
        onComplete: (List<Map<String, Any?>>) -> Unit,
        onError: (code: String, message: String) -> Unit,
    ) {
        if (context == null) {
            onError("unknown", "decodeImage: no application context available")
            return
        }
        ioExecutor.execute {
            val bitmap = try {
                loadBitmap(context, uri)
            } catch (e: IOException) {
                main.post {
                    onError("unknown", "decodeImage: could not load image at $uri (${e.message})")
                }
                return@execute
            }
            // Native core is preferred when requested AND linked; on a null
            // (JNI failure) result we fall back to the platform decoder.
            if (useNativeCore && SupyNativeCore.hasZxing()) {
                val results = decodeWithNativeCore(bitmap, wireFormats)
                if (results != null) {
                    main.post { onComplete(results) }
                    return@execute
                }
            }
            // ML Kit listeners fire on the main thread by default.
            decodeWithMlKit(bitmap, wireFormats, onComplete, onError)
        }
    }

    fun close() {
        ioExecutor.shutdown()
    }

    private fun loadBitmap(context: Context, uri: Uri): Bitmap {
        val options = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        return context.contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, options)
        } ?: throw IOException("BitmapFactory.decodeStream returned null")
    }

    private fun decodeWithMlKit(
        bitmap: Bitmap,
        wireFormats: List<String>,
        onComplete: (List<Map<String, Any?>>) -> Unit,
        onError: (String, String) -> Unit,
    ) {
        val formats = FormatMapper.toMlKitFormats(wireFormats)
        val scanner = if (formats == null) {
            BarcodeScanning.getClient()
        } else {
            val builder = BarcodeScannerOptions.Builder()
                .setBarcodeFormats(formats.first(), *formats.drop(1).toIntArray())
            BarcodeScanning.getClient(builder.build())
        }
        scanner.process(InputImage.fromBitmap(bitmap, 0))
            .addOnSuccessListener { barcodes ->
                val out = barcodes.mapNotNull { b ->
                    val raw = b.rawValue ?: return@mapNotNull null
                    val map = hashMapOf<String, Any?>(
                        "rawValue" to raw,
                        "format" to FormatMapper.mlKitToWire(b.format),
                    )
                    b.boundingBox?.let { box ->
                        map["boundingBox"] = mapOf(
                            "left" to box.left.toDouble(),
                            "top" to box.top.toDouble(),
                            "width" to box.width().toDouble(),
                            "height" to box.height().toDouble(),
                        )
                    }
                    map
                }
                onComplete(out)
            }
            .addOnFailureListener { e ->
                onError("unknown", "decodeImage: ML Kit failed (${e.message})")
            }
            .addOnCompleteListener { scanner.close() }
    }

    private fun decodeWithNativeCore(
        bitmap: Bitmap,
        wireFormats: List<String>,
    ): List<Map<String, Any?>>? {
        val w = bitmap.width
        val h = bitmap.height
        if (w <= 0 || h <= 0) return null
        val luma = bitmapToLuma(bitmap, w, h)
        val mask = FormatMapper.toSupyFormatMask(wireFormats)
        val results = SupyNativeCore.decodeBarcodes(
            luma,
            w,
            h,
            w,
            mask,
            tryHarder = true,
            tryRotate = true,
        ) ?: return null
        return results.map { r ->
            val c = r.corners
            var minX = c[0]
            var maxX = c[0]
            var minY = c[1]
            var maxY = c[1]
            var i = 2
            while (i < c.size - 1) {
                val x = c[i]
                val y = c[i + 1]
                if (x < minX) minX = x
                if (x > maxX) maxX = x
                if (y < minY) minY = y
                if (y > maxY) maxY = y
                i += 2
            }
            mapOf(
                "rawValue" to r.rawValue,
                "format" to FormatMapper.supyBitToWire(r.formatBit),
                "boundingBox" to mapOf(
                    "left" to minX.toDouble(),
                    "top" to minY.toDouble(),
                    "width" to (maxX - minX).toDouble(),
                    "height" to (maxY - minY).toDouble(),
                ),
            )
        }
    }

    /** BT.601 luma into a direct buffer with `rowStride == width`. */
    private fun bitmapToLuma(bitmap: Bitmap, w: Int, h: Int): ByteBuffer {
        val pixels = IntArray(w * h)
        bitmap.getPixels(pixels, 0, w, 0, 0, w, h)
        val buffer = ByteBuffer.allocateDirect(w * h)
        for (idx in pixels.indices) {
            val p = pixels[idx]
            val r = (p shr 16) and 0xFF
            val g = (p shr 8) and 0xFF
            val b = p and 0xFF
            buffer.put(idx, ((r * 77 + g * 150 + b * 29) shr 8).toByte())
        }
        return buffer
    }
}
