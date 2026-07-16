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

    // ---------------------------------------------------------------------------
    // Native-core (zxing-cpp) format mapping — SUPY_FORMAT_* bits.
    // Keep in sync with native/include/supy_scanner_core.h.
    // ---------------------------------------------------------------------------

    private const val SUPY_FORMAT_AZTEC        = 1 shl 0
    private const val SUPY_FORMAT_CODABAR      = 1 shl 1
    private const val SUPY_FORMAT_CODE_39      = 1 shl 2
    private const val SUPY_FORMAT_CODE_93      = 1 shl 3
    private const val SUPY_FORMAT_CODE_128     = 1 shl 4
    private const val SUPY_FORMAT_DATA_MATRIX  = 1 shl 5
    private const val SUPY_FORMAT_EAN_8        = 1 shl 6
    private const val SUPY_FORMAT_EAN_13       = 1 shl 7
    private const val SUPY_FORMAT_ITF          = 1 shl 8
    private const val SUPY_FORMAT_PDF_417      = 1 shl 9
    private const val SUPY_FORMAT_QR_CODE      = 1 shl 10
    private const val SUPY_FORMAT_UPC_A        = 1 shl 11
    private const val SUPY_FORMAT_UPC_E        = 1 shl 12

    /**
     * Translates wire names to a SUPY_FORMAT_* bitmask for the native core.
     * `["all"]` or empty → 0xFFFFFFFF (all formats). Unknown names are dropped.
     */
    fun toSupyFormatMask(wireFormats: List<String>): Int {
        if (wireFormats.isEmpty() || wireFormats.contains("all")) {
            return -1 // 0xFFFFFFFF as Int = SUPY_FORMAT_ALL
        }
        var mask = 0
        for (w in wireFormats) {
            mask = mask or (wireToSupyBit(w) ?: 0)
        }
        return if (mask == 0) -1 else mask
    }

    private fun wireToSupyBit(wire: String): Int? = when (wire) {
        "qr" -> SUPY_FORMAT_QR_CODE
        "ean13" -> SUPY_FORMAT_EAN_13
        "ean8" -> SUPY_FORMAT_EAN_8
        "upcA" -> SUPY_FORMAT_UPC_A
        "upcE" -> SUPY_FORMAT_UPC_E
        "code39" -> SUPY_FORMAT_CODE_39
        "code93" -> SUPY_FORMAT_CODE_93
        "code128" -> SUPY_FORMAT_CODE_128
        "itf" -> SUPY_FORMAT_ITF
        "pdf417" -> SUPY_FORMAT_PDF_417
        "dataMatrix" -> SUPY_FORMAT_DATA_MATRIX
        "aztec" -> SUPY_FORMAT_AZTEC
        "codabar" -> SUPY_FORMAT_CODABAR
        else -> null
    }

    /** Single-bit accessor for Data Matrix — used by the libdmtx ROI assist gate. */
    const val SUPY_FORMAT_DATA_MATRIX_BIT: Int = 1 shl 5

    /** True iff the mask requests Data Matrix (or is SUPY_FORMAT_ALL = -1). */
    fun maskIncludesDataMatrix(mask: Int): Boolean =
        (mask and SUPY_FORMAT_DATA_MATRIX_BIT) != 0

    /** Returns the input mask with the Data Matrix bit cleared. */
    fun maskWithoutDataMatrix(mask: Int): Int =
        mask and SUPY_FORMAT_DATA_MATRIX_BIT.inv()

    /** Maps a single SUPY_FORMAT_* bit back to its wire name. Unknown → "all". */
    fun supyBitToWire(bit: Int): String = when (bit) {
        SUPY_FORMAT_QR_CODE -> "qr"
        SUPY_FORMAT_EAN_13 -> "ean13"
        SUPY_FORMAT_EAN_8 -> "ean8"
        SUPY_FORMAT_UPC_A -> "upcA"
        SUPY_FORMAT_UPC_E -> "upcE"
        SUPY_FORMAT_CODE_39 -> "code39"
        SUPY_FORMAT_CODE_93 -> "code93"
        SUPY_FORMAT_CODE_128 -> "code128"
        SUPY_FORMAT_ITF -> "itf"
        SUPY_FORMAT_PDF_417 -> "pdf417"
        SUPY_FORMAT_DATA_MATRIX -> "dataMatrix"
        SUPY_FORMAT_AZTEC -> "aztec"
        SUPY_FORMAT_CODABAR -> "codabar"
        else -> "all"
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
