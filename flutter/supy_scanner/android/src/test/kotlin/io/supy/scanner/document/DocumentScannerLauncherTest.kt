package io.supy.scanner.document

import org.junit.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Unit coverage for the v1.2 Phase CXD1 backend gate. Activity/Intent paths
 * still need instrumentation tests (Phase CXD2); this asserts only the
 * branching contract.
 */
class DocumentScannerLauncherTest {

    @Test
    fun `cameraX is forced when preferredBackend is cameraX even with GMS usable`() {
        assertTrue(
            DocumentScannerLauncher.shouldUseCameraX(
                preferredBackend = DocumentScannerLauncher.BACKEND_CAMERAX,
                gmsUsable = true,
            ),
        )
    }

    @Test
    fun `cameraX is used when GMS is unusable regardless of preference`() {
        assertTrue(
            DocumentScannerLauncher.shouldUseCameraX(
                preferredBackend = null,
                gmsUsable = false,
            ),
        )
        assertTrue(
            DocumentScannerLauncher.shouldUseCameraX(
                preferredBackend = DocumentScannerLauncher.BACKEND_GMS,
                gmsUsable = false,
            ),
        )
    }

    @Test
    fun `gms is selected when usable and not overridden`() {
        assertFalse(
            DocumentScannerLauncher.shouldUseCameraX(
                preferredBackend = null,
                gmsUsable = true,
            ),
        )
        assertFalse(
            DocumentScannerLauncher.shouldUseCameraX(
                preferredBackend = DocumentScannerLauncher.BACKEND_GMS,
                gmsUsable = true,
            ),
        )
    }

    @Test
    fun `unknown or junk preference falls back to availability`() {
        assertFalse(
            DocumentScannerLauncher.shouldUseCameraX(
                preferredBackend = DocumentScannerLauncher.BACKEND_UNKNOWN,
                gmsUsable = true,
            ),
        )
        assertTrue(
            DocumentScannerLauncher.shouldUseCameraX(
                preferredBackend = "wat",
                gmsUsable = false,
            ),
        )
    }
}
