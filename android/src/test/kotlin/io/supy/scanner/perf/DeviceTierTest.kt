package io.supy.scanner.perf

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class DeviceTierTest {

    @Test
    fun `HIGH leaves every analyzer dial uncapped`() {
        assertNull(DeviceTier.HIGH.barcodeAnalyzerSize())
        assertNull(DeviceTier.HIGH.analyzerFpsCap())
        assertNull(DeviceTier.HIGH.idlePauseThresholdMs())
        assertNull(DeviceTier.HIGH.ocrLongEdgeCap())
    }

    @Test
    fun `MID dials match docs PERFORMANCE policy table`() {
        assertEquals(960, DeviceTier.MID.barcodeAnalyzerSize()?.width)
        assertEquals(720, DeviceTier.MID.barcodeAnalyzerSize()?.height)
        assertEquals(24, DeviceTier.MID.analyzerFpsCap())
        assertEquals(8_000L, DeviceTier.MID.idlePauseThresholdMs())
        assertEquals(1600, DeviceTier.MID.ocrLongEdgeCap())
    }

    @Test
    fun `LOW dials match docs PERFORMANCE policy table`() {
        assertEquals(640, DeviceTier.LOW.barcodeAnalyzerSize()?.width)
        assertEquals(480, DeviceTier.LOW.barcodeAnalyzerSize()?.height)
        assertEquals(20, DeviceTier.LOW.analyzerFpsCap())
        assertEquals(4_000L, DeviceTier.LOW.idlePauseThresholdMs())
        assertEquals(1280, DeviceTier.LOW.ocrLongEdgeCap())
    }

    @Test
    fun `HIGH and MID pass the requested JPEG quality through unchanged`() {
        assertEquals(95, DeviceTier.HIGH.jpegQuality(95))
        assertEquals(95, DeviceTier.MID.jpegQuality(95))
    }

    @Test
    fun `LOW caps JPEG quality at 75 but does not raise lower requests`() {
        assertEquals(75, DeviceTier.LOW.jpegQuality(95))
        assertEquals(60, DeviceTier.LOW.jpegQuality(60))
        assertEquals(75, DeviceTier.LOW.jpegQuality(75))
    }
}
