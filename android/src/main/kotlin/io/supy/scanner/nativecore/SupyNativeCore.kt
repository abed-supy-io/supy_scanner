package io.supy.scanner.nativecore

/**
 * Thin Kotlin wrapper over libsupy_scanner_core. Sprint 1 (v1.1 plan)
 * scaffold — only the version probe is wired today. Future stages
 * (binarization, deconvolution, decode) bind here.
 */
internal object SupyNativeCore {
    @Volatile private var loaded = false

    fun ensureLoaded() {
        if (loaded) return
        synchronized(this) {
            if (loaded) return
            System.loadLibrary("supy_scanner_core")
            loaded = true
        }
    }

    fun version(): String {
        ensureLoaded()
        return nativeVersion()
    }

    fun abiVersion(): Int {
        ensureLoaded()
        return nativeAbiVersion()
    }

    @JvmStatic private external fun nativeVersion(): String
    @JvmStatic private external fun nativeAbiVersion(): Int
}
