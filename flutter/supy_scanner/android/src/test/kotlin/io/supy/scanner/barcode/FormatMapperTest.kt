package io.supy.scanner.barcode

import com.google.mlkit.vision.barcode.common.Barcode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class FormatMapperTest {

    private val wireToConstant = mapOf(
        "qr" to Barcode.FORMAT_QR_CODE,
        "ean13" to Barcode.FORMAT_EAN_13,
        "ean8" to Barcode.FORMAT_EAN_8,
        "upcA" to Barcode.FORMAT_UPC_A,
        "upcE" to Barcode.FORMAT_UPC_E,
        "code39" to Barcode.FORMAT_CODE_39,
        "code93" to Barcode.FORMAT_CODE_93,
        "code128" to Barcode.FORMAT_CODE_128,
        "itf" to Barcode.FORMAT_ITF,
        "pdf417" to Barcode.FORMAT_PDF417,
        "dataMatrix" to Barcode.FORMAT_DATA_MATRIX,
        "aztec" to Barcode.FORMAT_AZTEC,
        "codabar" to Barcode.FORMAT_CODABAR,
    )

    @Test
    fun `empty list returns null so ML Kit falls back to all formats`() {
        assertNull(FormatMapper.toMlKitFormats(emptyList()))
    }

    @Test
    fun `all sentinel returns null so ML Kit falls back to all formats`() {
        assertNull(FormatMapper.toMlKitFormats(listOf("all")))
    }

    @Test
    fun `all sentinel wins even when combined with explicit formats`() {
        assertNull(FormatMapper.toMlKitFormats(listOf("qr", "all", "ean13")))
    }

    @Test
    fun `unknown wire names are filtered out`() {
        val result = FormatMapper.toMlKitFormats(listOf("qr", "bogus"))
        assertEquals(listOf(Barcode.FORMAT_QR_CODE), result?.toList())
    }

    @Test
    fun `all-unknown list returns null rather than an empty IntArray`() {
        assertNull(FormatMapper.toMlKitFormats(listOf("bogus", "nope")))
    }

    @Test
    fun `every wire name maps to its ML Kit constant`() {
        for ((wire, constant) in wireToConstant) {
            val result = FormatMapper.toMlKitFormats(listOf(wire))
            assertEquals("wire=$wire", listOf(constant), result?.toList())
        }
    }

    @Test
    fun `mlKitToWire is the inverse of wireToMlKit for every known constant`() {
        for ((wire, constant) in wireToConstant) {
            assertEquals(wire, FormatMapper.mlKitToWire(constant))
        }
    }

    @Test
    fun `mlKitToWire returns all sentinel for unknown formats`() {
        assertEquals("all", FormatMapper.mlKitToWire(-1))
        assertEquals("all", FormatMapper.mlKitToWire(0))
    }
}
