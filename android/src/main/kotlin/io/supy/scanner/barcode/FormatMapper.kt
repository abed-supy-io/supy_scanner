package io.supy.scanner.barcode

import com.google.mlkit.vision.barcode.common.Barcode

/**
 * Bidirectional mapper between Dart [SupyBarcodeFormat] wire names and ML Kit
 * [Barcode] format constants.
 *
 * Wire names are the kebab-free camelCase enum names produced by Dart
 * (`SupyBarcodeFormat.wireName`). Keep this table in sync with
 * `docs/SYMBOLOGIES.md` and `SymbologyMapper.swift` on iOS.
 */
internal object FormatMapper {

    /**
     * Translates wire names to an ML Kit format bitmask suitable for
     * `BarcodeScannerOptions.Builder.setBarcodeFormats(...)`.
     *
     * Returns `null` when the caller has asked for `all` (or no specific
     * formats), signalling that we should fall through to ML Kit's default
     * detector which scans every supported symbology.
     */
    fun toMlKitFormats(wireFormats: List<String>): IntArray? {
        if (wireFormats.isEmpty() || wireFormats.contains("all")) {
            return null
        }
        val values = wireFormats.mapNotNull { wireToMlKit(it) }
        if (values.isEmpty()) return null
        return values.toIntArray()
    }

    private fun wireToMlKit(wire: String): Int? = when (wire) {
        "qr" -> Barcode.FORMAT_QR_CODE
        "ean13" -> Barcode.FORMAT_EAN_13
        "ean8" -> Barcode.FORMAT_EAN_8
        "upcA" -> Barcode.FORMAT_UPC_A
        "upcE" -> Barcode.FORMAT_UPC_E
        "code39" -> Barcode.FORMAT_CODE_39
        "code93" -> Barcode.FORMAT_CODE_93
        "code128" -> Barcode.FORMAT_CODE_128
        "itf" -> Barcode.FORMAT_ITF
        "pdf417" -> Barcode.FORMAT_PDF417
        "dataMatrix" -> Barcode.FORMAT_DATA_MATRIX
        "aztec" -> Barcode.FORMAT_AZTEC
        "codabar" -> Barcode.FORMAT_CODABAR
        else -> null
    }

    /** Inverse of [wireToMlKit] — used when emitting detection events. */
    fun mlKitToWire(format: Int): String = when (format) {
        Barcode.FORMAT_QR_CODE -> "qr"
        Barcode.FORMAT_EAN_13 -> "ean13"
        Barcode.FORMAT_EAN_8 -> "ean8"
        Barcode.FORMAT_UPC_A -> "upcA"
        Barcode.FORMAT_UPC_E -> "upcE"
        Barcode.FORMAT_CODE_39 -> "code39"
        Barcode.FORMAT_CODE_93 -> "code93"
        Barcode.FORMAT_CODE_128 -> "code128"
        Barcode.FORMAT_ITF -> "itf"
        Barcode.FORMAT_PDF417 -> "pdf417"
        Barcode.FORMAT_DATA_MATRIX -> "dataMatrix"
        Barcode.FORMAT_AZTEC -> "aztec"
        Barcode.FORMAT_CODABAR -> "codabar"
        else -> "all"
    }
}
