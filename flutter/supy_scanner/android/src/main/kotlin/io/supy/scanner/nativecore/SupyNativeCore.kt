package io.supy.scanner.nativecore

import java.nio.ByteBuffer

/**
 * Thin Kotlin wrapper over libsupy_scanner_core. Sprint 1 (v1.1 plan)
 * scaffold — only the version probe is wired today. Future stages
 * (binarization, deconvolution, decode) bind here.
 */
internal object SupyNativeCore {
    @Volatile private var loaded = false
    @Volatile private var loadFailed = false

    // Returns true if the native lib loaded successfully, false on UnsatisfiedLinkError.
    fun ensureLoaded(): Boolean {
        if (loaded) return true
        if (loadFailed) return false
        synchronized(this) {
            if (loaded) return true
            if (loadFailed) return false
            try {
                System.loadLibrary("supy_scanner_core")
                loaded = true
            } catch (_: UnsatisfiedLinkError) {
                loadFailed = true
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

    /** True iff the native lib was built with SUPY_WITH_ZXING_CPP=ON and loaded successfully. */
    fun hasZxing(): Boolean {
        if (!ensureLoaded()) return false
        return nativeHasZxing() == 1
    }

    /** True iff the native lib was built with SUPY_WITH_LIBDMTX=ON and loaded successfully. */
    fun hasLibdmtx(): Boolean {
        if (!ensureLoaded()) return false
        return nativeHasLibdmtx() == 1
    }

    /**
     * Locates Data Matrix regions in a luma plane (libdmtx). Returns the list
     * of detected quads (TL,TR,BR,BL in input-image pixel space). null means
     * either the locator isn't linked, the JNI call failed, or the input was
     * invalid — callers treat that identically to "nothing found". An empty
     * list means the locator ran and reported zero regions.
     *
     * Decode payload is **not** produced here — callers crop the input frame
     * to the located bbox and feed the crop into [decodeBarcodes] with a
     * Data-Matrix-only format mask. See V1-S2-04a docs in TODO.md.
     */
    fun locateDatamatrix(
        y: ByteBuffer,
        w: Int,
        h: Int,
        rowStride: Int,
        maxRegions: Int = 4,
        timeoutMs: Int = 30,
    ): List<FloatArray>? {
        if (!ensureLoaded()) return null
        val flat = nativeLocateDatamatrix(y, w, h, rowStride, maxRegions, timeoutMs) ?: return null
        if (flat.size % 8 != 0) return emptyList()
        val n = flat.size / 8
        if (n == 0) return emptyList()
        val out = ArrayList<FloatArray>(n)
        for (i in 0 until n) {
            val q = FloatArray(8)
            System.arraycopy(flat, i * 8, q, 0, 8)
            out.add(q)
        }
        return out
    }

    /**
     * Decodes barcodes from a luma plane. Returns null when no detections or
     * native decode is unavailable; an empty list is returned only when the
     * decode ran but produced zero results — callers can treat null and empty
     * identically.
     */
    fun decodeBarcodes(
        y: ByteBuffer,
        w: Int,
        h: Int,
        rowStride: Int,
        formatMask: Int,
        tryHarder: Boolean,
        tryRotate: Boolean,
    ): List<NativeBarcode>? {
        if (!ensureLoaded()) return null
        val packed = nativeDecodeBarcodes(
            y, w, h, rowStride, formatMask,
            if (tryHarder) 1 else 0,
            if (tryRotate) 1 else 0,
        ) ?: return null
        if (packed.size != 3) return null
        @Suppress("UNCHECKED_CAST")
        val texts = packed[0] as? Array<String?> ?: return emptyList()
        val formats = packed[1] as? IntArray ?: return emptyList()
        val corners = packed[2] as? FloatArray ?: return emptyList()
        val n = texts.size
        if (n == 0 || formats.size != n || corners.size != n * 8) return emptyList()
        val out = ArrayList<NativeBarcode>(n)
        for (i in 0 until n) {
            val text = texts[i] ?: continue
            val c = FloatArray(8)
            System.arraycopy(corners, i * 8, c, 0, 8)
            out.add(NativeBarcode(text, formats[i], c))
        }
        return out
    }

    /**
     * Adaptive binarization mode for [binarizeLumaCrop]. Keep in sync with
     * `supy_binarize_mode_t` in native/include/supy_scanner_binarize.h.
     */
    enum class BinarizeMode(val raw: Int) {
        /** Sauvola 2D — best on matrix codes (Data Matrix, QR). */
        Sauvola2D(0),
        /** Wolf-Jolion — best on 1D barcodes with wide stripes. */
        WolfJolion1D(1),
    }

    /**
     * Runs the V1-S2-05 adaptive-binarization kernel in place over a packed
     * luma crop (the libdmtx assist ROI). Returns true on success, false if
     * the native lib isn't loaded or the kernel rejected the input — callers
     * fall back to a non-binarized decode rather than treat false as fatal.
     */
    fun binarizeLumaCrop(
        y: ByteBuffer,
        w: Int,
        h: Int,
        rowStride: Int,
        mode: BinarizeMode,
    ): Boolean {
        if (!ensureLoaded()) return false
        return nativeBinarizeLumaCrop(y, w, h, rowStride, mode.raw) == 1
    }

    /**
     * Runs the V1-S2-06 temporal median-of-3 fusion on three same-geometry
     * packed-luma crops, writing the per-pixel median into [out]. All four
     * buffers must share [w], [h], and [rowStride]; [out] must be a distinct
     * direct buffer (the native side rejects aliasing). Returns true on
     * success, false on validation failure — callers fall back to a raw
     * current-frame decode in that case.
     */
    fun temporalMedianLuma3(
        f0: ByteBuffer,
        f1: ByteBuffer,
        f2: ByteBuffer,
        out: ByteBuffer,
        w: Int,
        h: Int,
        rowStride: Int,
    ): Boolean {
        if (!ensureLoaded()) return false
        return nativeTemporalMedianLuma3(f0, f1, f2, out, w, h, rowStride) == 1
    }

    /**
     * Runs the enhancement pipeline in-place on a direct RGBA8888 ByteBuffer.
     * Returns null if the lib isn't loaded or the JNI call failed. The buffer
     * contents are overwritten on success.
     */
    fun enhanceRgba(
        rgba: ByteBuffer,
        width: Int,
        height: Int,
        rowStride: Int,
        mode: Int,
        minBlurScore: Float = 0f,
    ): NativeEnhanceResult? {
        if (!ensureLoaded()) return null
        val packed = nativeEnhanceRgba(rgba, width, height, rowStride, mode, minBlurScore)
            ?: return null
        if (packed.size != 4) return null
        return NativeEnhanceResult(
            appliedStages = packed[0],
            verdict = packed[1],
            processingMs = packed[2],
            qualityScore = Float.fromBits(packed[3]),
        )
    }

    /**
     * Scores a single page (variance-of-Laplacian + bucket mapping) without
     * running the enhance pipeline. Used by paths where enhance is disabled
     * (e.g. iOS default, JPEG ≥95 passthrough) but a quality bucket still has
     * to surface on the wire. Buffer is NOT mutated.
     */
    fun scorePage(
        rgba: ByteBuffer,
        width: Int,
        height: Int,
        rowStride: Int,
    ): NativePageScore? {
        if (!ensureLoaded()) return null
        val packed = nativeScorePage(rgba, width, height, rowStride) ?: return null
        if (packed.size != 3) return null
        return NativePageScore(
            blurScore = packed[0],
            qualityScore = packed[1],
            bucket = packed[2].toInt(),
        )
    }

    /**
     * Rectifies the detected document quad in a full-res RGBA8888 direct buffer
     * into a flat, axis-aligned page (V1-S6-02). [srcCorners] is eight floats —
     * x,y interleaved in TL,TR,BR,BL order, in **input-image pixel space**.
     * [maxLongSide] caps the longer output dimension (aspect preserved); pass 0
     * for unbounded. Returns null when the lib isn't loaded, the input is
     * invalid, or the quad is degenerate — callers fall back to persisting the
     * un-rectified still. The input buffer is not mutated.
     */
    fun warpPerspective(
        rgba: ByteBuffer,
        width: Int,
        height: Int,
        rowStride: Int,
        srcCorners: FloatArray,
        maxLongSide: Int,
    ): NativeWarpResult? {
        if (!ensureLoaded()) return null
        if (srcCorners.size != 8) return null
        val outWh = IntArray(2)
        val bytes = nativeWarpPerspective(
            rgba, width, height, rowStride, srcCorners, maxLongSide, outWh,
        ) ?: return null
        val w = outWh[0]
        val h = outWh[1]
        if (w <= 0 || h <= 0 || bytes.size != w * h * 4) return null
        return NativeWarpResult(rgba = bytes, width = w, height = h)
    }

    // ───────── CXD auto-snap (Phase 4) ─────────

    /** Allocates a native [GuidanceState]. Returns 0 if the lib isn't loaded. */
    fun guidanceCreate(): Long {
        if (!ensureLoaded()) return 0L
        return nativeGuidanceCreate()
    }

    /** Frees a handle allocated by [guidanceCreate]. No-op on 0. */
    fun guidanceDestroy(handle: Long) {
        if (handle == 0L || !ensureLoaded()) return
        nativeGuidanceDestroy(handle)
    }

    /** Resets the classifier state to its initial NoDocument step. */
    fun guidanceReset(handle: Long) {
        if (handle == 0L || !ensureLoaded()) return
        nativeGuidanceReset(handle)
    }

    /**
     * Classifies a single frame. Returns a [GuidanceClassifyResult] with the
     * resulting [GuidanceFrameState] and the C++-computed `liveQualityScore`
     * (0..1). Falls back to a NoDocument / 0.0 pair when the native lib isn't
     * loaded so callers can degrade gracefully without special-casing a
     * missing-lib branch.
     */
    fun guidanceClassify(
        handle: Long,
        metrics: GuidanceFrameMetrics,
        config: GuidanceConfig,
    ): GuidanceClassifyResult {
        if (handle == 0L || !ensureLoaded()) {
            return GuidanceClassifyResult(GuidanceFrameState.NoDocument, 0.0f)
        }
        val cfg = config.toFloatArray()
        val perCornerLen = if (metrics.hasPerCornerStability) 4 else 0
        val perCorner = if (perCornerLen == 4) metrics.perCornerStability else EMPTY_FLOATS
        val packed = nativeGuidanceClassify(
            handle,
            metrics.hasDocument,
            metrics.clipsEdge,
            metrics.coverageRatio,
            metrics.tiltDegrees,
            metrics.meanLuma,
            metrics.blurScore,
            metrics.quadStability,
            metrics.interiorVariance,
            metrics.glareRatio,
            metrics.cornerVelocity,
            metrics.centerOffsetX,
            metrics.centerOffsetY,
            perCorner,
            cfg,
        ) ?: return GuidanceClassifyResult(GuidanceFrameState.NoDocument, 0.0f)
        if (packed.size < 2) return GuidanceClassifyResult(GuidanceFrameState.NoDocument, 0.0f)
        val state = GuidanceFrameState.fromOrdinal(packed[0].toInt())
        val quality = packed[1]
        return GuidanceClassifyResult(state, quality)
    }

    private val EMPTY_FLOATS = FloatArray(0)

    @JvmStatic private external fun nativeGuidanceCreate(): Long
    @JvmStatic private external fun nativeGuidanceDestroy(handle: Long)
    @JvmStatic private external fun nativeGuidanceReset(handle: Long)
    // Returns float[2] = [stateOrdinal, liveQualityScore], or null on JNI failure.
    @JvmStatic private external fun nativeGuidanceClassify(
        handle: Long,
        hasDocument: Boolean, clipsEdge: Boolean,
        coverage: Float, tilt: Float, luma: Float, blur: Float,
        stability: Float, interior: Float,
        glareRatio: Float, cornerVelocity: Float,
        centerOffsetX: Float, centerOffsetY: Float,
        perCornerStability: FloatArray,
        config: FloatArray,
    ): FloatArray?

    @JvmStatic private external fun nativeVersion(): String
    @JvmStatic private external fun nativeAbiVersion(): Int

    @JvmStatic private external fun nativeDetectQuad(
        yPlane: ByteBuffer,
        width: Int, height: Int, rowStride: Int,
    ): FloatArray? // null when no quad; else [x0..y3, coverage, tilt]

    @JvmStatic private external fun nativeHasZxing(): Int
    @JvmStatic private external fun nativeHasLibdmtx(): Int

    // Returns flat float[8*N] of TL,TR,BR,BL pixel-space corners per detected
    // Data Matrix region. null on JNI / native failure. Empty array (length 0)
    // means "locator ran, no regions".
    @JvmStatic private external fun nativeLocateDatamatrix(
        yPlane: ByteBuffer,
        width: Int, height: Int, rowStride: Int,
        maxRegions: Int, timeoutMs: Int,
    ): FloatArray?

    // Packed return: Object[3] = { String[] texts, int[] formats(SUPY_FORMAT_* bits),
    // float[] corners (8 floats per detection: x0..y3) }. Null on failure / no decode.
    @JvmStatic private external fun nativeDecodeBarcodes(
        yPlane: ByteBuffer,
        width: Int, height: Int, rowStride: Int,
        formats: Int, tryHarder: Int, tryRotate: Int,
    ): Array<Any?>?

    // Returns int[4]: [appliedStagesBitmask, verdict, processingMs, qualityScoreFloatBits].
    // Buffer is mutated in place with enhanced RGBA bytes on success.
    @JvmStatic private external fun nativeEnhanceRgba(
        rgbaBuffer: ByteBuffer,
        width: Int, height: Int, rowStride: Int,
        mode: Int, minBlurScore: Float,
    ): IntArray?

    // Returns float[3]: [blurScore, qualityScore(0..1), bucket(0..4)]. Buffer is not mutated.
    @JvmStatic private external fun nativeScorePage(
        rgbaBuffer: ByteBuffer,
        width: Int, height: Int, rowStride: Int,
    ): FloatArray?

    // V1-S6-02 perspective warp. Returns the packed RGBA8888 bytes of the
    // rectified page (row_stride == width*4) and writes [width, height] into
    // outWh. null on invalid input / degenerate quad. Input buffer not mutated.
    @JvmStatic private external fun nativeWarpPerspective(
        rgbaBuffer: ByteBuffer,
        width: Int, height: Int, rowStride: Int,
        srcCorners: FloatArray, maxLongSide: Int, outWh: IntArray,
    ): ByteArray?

    // V1-S2-05.1 adaptive binarization. Returns 1 on success, 0 on failure.
    // Buffer is mutated in place on success.
    @JvmStatic private external fun nativeBinarizeLumaCrop(
        yPlane: ByteBuffer,
        width: Int, height: Int, rowStride: Int, mode: Int,
    ): Int

    // V1-S2-06.1 temporal median-of-3. Returns 1 on success, 0 on failure.
    // `out` is written; `f0`/`f1`/`f2` are read-only.
    @JvmStatic private external fun nativeTemporalMedianLuma3(
        f0: ByteBuffer, f1: ByteBuffer, f2: ByteBuffer, out: ByteBuffer,
        width: Int, height: Int, rowStride: Int,
    ): Int
}

/**
 * Result of a native perspective warp: the rectified page as packed RGBA8888
 * bytes ([rgba] has length `width * height * 4`, row stride `width * 4`).
 */
internal data class NativeWarpResult(
    val rgba: ByteArray,
    val width: Int,
    val height: Int,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is NativeWarpResult) return false
        return width == other.width && height == other.height &&
            rgba.contentEquals(other.rgba)
    }

    override fun hashCode(): Int {
        var result = rgba.contentHashCode()
        result = 31 * result + width
        result = 31 * result + height
        return result
    }
}

/** Standalone per-page quality score from the native scorer. */
internal data class NativePageScore(
    /** Raw variance-of-Laplacian. */
    val blurScore: Float,
    /** Normalized 0..1 sharpness for the wire. */
    val qualityScore: Float,
    /** 0=veryPoor .. 4=excellent. */
    val bucket: Int,
)

/** Result of a native enhance call. */
internal data class NativeEnhanceResult(
    val appliedStages: Int,
    /** 0 = ok, 1 = marginal, 2 = reject. */
    val verdict: Int,
    val processingMs: Int,
    /** Variance-of-Laplacian on the input. */
    val qualityScore: Float,
)

/** One decoded barcode from the native core. */
internal data class NativeBarcode(
    val rawValue: String,
    /** Single-bit SUPY_FORMAT_* value. */
    val formatBit: Int,
    /** Eight floats: x0,y0, x1,y1, x2,y2, x3,y3 (TL/TR/BR/BL where the decoder provides it). */
    val corners: FloatArray,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is NativeBarcode) return false
        return rawValue == other.rawValue &&
            formatBit == other.formatBit &&
            corners.contentEquals(other.corners)
    }

    override fun hashCode(): Int {
        var result = rawValue.hashCode()
        result = 31 * result + formatBit
        result = 31 * result + corners.contentHashCode()
        return result
    }
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

/**
 * Mirror of `supy::scanner::document::FrameState`. Ordinals must match —
 * pinned by [GuidanceFrameState.fromOrdinal] for the JNI return path.
 */
internal enum class GuidanceFrameState {
    // Indices 0..7 are wire-stable; must NOT be reordered.
    NoDocument,
    TooDark,
    TooClose,
    TooFar,
    TooSkewed,
    Blurry,
    HoldSteady,
    Ready,
    // CQG additions — appended only. Match the C++ tail at indices 8..11.
    Glare,
    Occluded,
    HandShake,
    EdgeClipped,
    // Framing passed but the quad sits too far off-center. The arrow direction
    // is a render detail derived from the signed center offset, not the state.
    OffCenter;

    companion object {
        private val VALUES = values()
        fun fromOrdinal(o: Int): GuidanceFrameState =
            if (o in VALUES.indices) VALUES[o] else NoDocument
    }
}

/** Packed result from the C++ classifier: state + opaque 0..1 live quality. */
internal data class GuidanceClassifyResult(
    val state: GuidanceFrameState,
    val liveQualityScore: Float,
)

/**
 * Per-frame raw measurements fed into the classifier. [perCornerStability] is
 * empty when the analyzer has no per-corner signal this frame (the C++ side
 * then holds its prior occlusion judgement); when populated it must have
 * length 4 (TL/TR/BR/BL).
 */
internal data class GuidanceFrameMetrics(
    val hasDocument: Boolean,
    val clipsEdge: Boolean,
    val coverageRatio: Float,
    val tiltDegrees: Float,
    val meanLuma: Float,
    val blurScore: Float,
    val quadStability: Float,
    val interiorVariance: Float,
    // CQG additions.
    val glareRatio: Float = 0.0f,
    val cornerVelocity: Float = 0.0f,
    // Signed quad-centroid offset from preview center, per axis, in half-extent
    // fractions: `(centroid - 0.5) * 2`. Positive X = right of center; positive
    // Y = below center.
    val centerOffsetX: Float = 0.0f,
    val centerOffsetY: Float = 0.0f,
    val perCornerStability: FloatArray = FloatArray(0),
) {
    val hasPerCornerStability: Boolean get() = perCornerStability.size == 4

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is GuidanceFrameMetrics) return false
        return hasDocument == other.hasDocument && clipsEdge == other.clipsEdge &&
            coverageRatio == other.coverageRatio && tiltDegrees == other.tiltDegrees &&
            meanLuma == other.meanLuma && blurScore == other.blurScore &&
            quadStability == other.quadStability && interiorVariance == other.interiorVariance &&
            glareRatio == other.glareRatio && cornerVelocity == other.cornerVelocity &&
            centerOffsetX == other.centerOffsetX && centerOffsetY == other.centerOffsetY &&
            perCornerStability.contentEquals(other.perCornerStability)
    }

    override fun hashCode(): Int {
        var r = hasDocument.hashCode()
        r = 31 * r + clipsEdge.hashCode()
        r = 31 * r + coverageRatio.hashCode()
        r = 31 * r + tiltDegrees.hashCode()
        r = 31 * r + meanLuma.hashCode()
        r = 31 * r + blurScore.hashCode()
        r = 31 * r + quadStability.hashCode()
        r = 31 * r + interiorVariance.hashCode()
        r = 31 * r + glareRatio.hashCode()
        r = 31 * r + cornerVelocity.hashCode()
        r = 31 * r + centerOffsetX.hashCode()
        r = 31 * r + centerOffsetY.hashCode()
        r = 31 * r + perCornerStability.contentHashCode()
        return r
    }
}

/**
 * Threshold subset of `supy::scanner::document::GuidanceConfig`. Defaults match
 * the C++ struct's field-initialisers; tier wiring overrides
 * [readyStableFrames] per `CameraXDocumentScannerActivity`.
 */
internal data class GuidanceConfig(
    val minCoverageRatio: Float = 0.30f,
    val maxCoverageRatio: Float = 0.90f,
    val maxTiltDegrees: Float = 20.0f,
    val minMeanLuma: Float = 60.0f,
    val minBlurScore: Float = 80.0f,
    val readyStabilityFloor: Float = 0.75f,
    val interiorVarianceFloor: Float = 5.0f,
    val exitMargin: Float = 0.10f,
    val smoothingAlpha: Float = 0.35f,
    val readyStableFrames: Int = 5,
    val holdSteadyFrames: Int = 6,
    val lostDocumentGraceFrames: Int = 3,
    val minDwellFrames: Int = 4,
    // CQG additions.
    val maxGlareRatio: Float = 0.04f,
    val glareExitMargin: Float = 0.50f,
    val maxCornerVelocity: Float = 0.020f,
    val minPerCornerStability: Float = 0.55f,
    val edgeClipBlocking: Boolean = false,
    // Max allowed quad-centroid offset (half-extent fraction) before kOffCenter
    // fires once framing otherwise passes. A non-positive value disables center
    // guidance — the Dart layer passes -1 when the consumer turns it off.
    val maxCenterOffset: Float = 0.12f,
) {
    fun toFloatArray(): FloatArray = floatArrayOf(
        minCoverageRatio, maxCoverageRatio, maxTiltDegrees,
        minMeanLuma, minBlurScore, readyStabilityFloor,
        interiorVarianceFloor, exitMargin, smoothingAlpha,
        readyStableFrames.toFloat(), holdSteadyFrames.toFloat(),
        lostDocumentGraceFrames.toFloat(), minDwellFrames.toFloat(),
        // CQG additions — packed after the existing 13 floats. The C++ JNI
        // shim unpacks by index, so this ordering is wire-coupled.
        maxGlareRatio, glareExitMargin, maxCornerVelocity, minPerCornerStability,
        if (edgeClipBlocking) 1.0f else 0.0f,
        maxCenterOffset,
    )
}
