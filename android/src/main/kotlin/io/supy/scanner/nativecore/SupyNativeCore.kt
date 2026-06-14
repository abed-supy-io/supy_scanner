package io.supy.scanner.nativecore

import java.nio.ByteBuffer

/**
 * Thin Kotlin wrapper over libsupy_scanner_core. Sprint 1 (v1.1 plan)
 * scaffold — only the version probe is wired today. Future stages
 * (binarization, deconvolution, decode) bind here.
 */
internal object SupyNativeCore {
    @Volatile private var loaded = false

    // Returns true if the native lib loaded successfully, false on UnsatisfiedLinkError.
    fun ensureLoaded(): Boolean {
        if (loaded) return true
        synchronized(this) {
            if (loaded) return true
            try {
                System.loadLibrary("supy_scanner_core")
                loaded = true
            } catch (_: UnsatisfiedLinkError) {
                loaded = false
                return false
            }
        }
        return true
    }

    fun version(): String {
        if (!ensureLoaded()) return ""
        return nativeVersion()
    }

    fun abiVersion(): Int {
        if (!ensureLoaded()) return -1
        return nativeAbiVersion()
    }

    /**
     * Detects a document quad in the given Y-plane buffer.
     * Returns null if the native lib isn't loaded, or if no quad was detected.
     */
    fun detectQuad(y: ByteBuffer, w: Int, h: Int, stride: Int): NativeQuad? {
        if (!ensureLoaded()) return null
        val raw = nativeDetectQuad(y, w, h, stride) ?: return null
        return NativeQuad(
            corners = raw.copyOf(8),
            coverageRatio = raw[8],
            tiltDegrees = raw[9],
        )
    }

    @JvmStatic private external fun nativeVersion(): String
    @JvmStatic private external fun nativeAbiVersion(): Int

    @JvmStatic private external fun nativeDetectQuad(
        yPlane: ByteBuffer,
        width: Int, height: Int, rowStride: Int,
    ): FloatArray? // null when no quad; else [x0..y3, coverage, tilt]
}

/** Detected document quad returned from the native edge detector. */
internal data class NativeQuad(
    /** Corner coordinates in TL/TR/BR/BL order: [x0,y0, x1,y1, x2,y2, x3,y3]. */
    val corners: FloatArray,
    val coverageRatio: Float,
    val tiltDegrees: Float,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is NativeQuad) return false
        return corners.contentEquals(other.corners) &&
            coverageRatio == other.coverageRatio &&
            tiltDegrees == other.tiltDegrees
    }

    override fun hashCode(): Int {
        var result = corners.contentHashCode()
        result = 31 * result + coverageRatio.hashCode()
        result = 31 * result + tiltDegrees.hashCode()
        return result
    }

    override fun toString(): String =
        "NativeQuad(corners=${corners.contentToString()}, coverageRatio=$coverageRatio, tiltDegrees=$tiltDegrees)"
}
