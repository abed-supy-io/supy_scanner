package io.supy.scanner.document

/**
 * Output filter applied to a scanned page. Mirrors the Dart `SupyDocumentFilter`
 * and the iOS `SupyDocumentFilter` — wire names are identical across platforms.
 */
internal enum class DocumentFilter(val wireName: String) {
    COLOR("color"),
    GRAYSCALE("grayscale"),
    BLACK_AND_WHITE("blackAndWhite"),
    ORIGINAL("original");

    companion object {
        /** Parses a wire name; unknown / null falls back to [COLOR]. */
        fun parse(wire: String?): DocumentFilter =
            entries.firstOrNull { it.wireName == wire } ?: COLOR
    }
}

/**
 * Kotlin mirror of the Dart `SupyDocumentProcessingOptions` / iOS
 * `DocumentProcessingOptions`. Resolved from the nested `processing` wire map,
 * with the legacy top-level `filter` / `enhanceMode` / `jpegQuality` args as
 * fallbacks so pre-DPX call sites keep working unchanged.
 *
 * Android owns fewer independent knobs than iOS: detection, perspective
 * correction and cropping are performed upstream by GMS (or the CameraX
 * fallback), and the native enhance pass is a single bundled [EnhanceMode]
 * rather than per-stage filters. So [detectDocument] / [perspectiveCorrection] /
 * [autoCrop] / [deskew] / [cropMargin] are parsed for wire parity but are not
 * individually toggleable here; the levers Android actually applies are
 * [enhanceMode] (derived from the enhance-stage toggles + [filter]),
 * [maxDimension] (smart resize) and [filter].
 */
internal data class DocumentProcessingOptions(
    val detectDocument: Boolean,
    val perspectiveCorrection: Boolean,
    val autoCrop: Boolean,
    val cropMargin: Double,
    val deskew: Boolean,
    val shadowRemoval: Boolean,
    val backgroundWhitening: Boolean,
    val denoise: Boolean,
    val sharpen: Boolean,
    val maxDimension: Int,
    val filter: DocumentFilter,
    /** Effective JPEG quality (nested `quality` > top-level `jpegQuality`). */
    val quality: Int,
    /** Base native enhance mode from the legacy `enhanceMode` arg. */
    val baseEnhanceMode: PageReencoder.EnhanceMode,
) {
    /**
     * The native enhance mode to actually run. The bundled pass is skipped
     * (OFF) when the caller picked the [DocumentFilter.ORIGINAL] bypass or
     * turned off every enhance stage; otherwise the [baseEnhanceMode] applies.
     */
    val enhanceMode: PageReencoder.EnhanceMode
        get() = when {
            filter == DocumentFilter.ORIGINAL -> PageReencoder.EnhanceMode.OFF
            !shadowRemoval && !backgroundWhitening && !denoise && !sharpen ->
                PageReencoder.EnhanceMode.OFF
            else -> baseEnhanceMode
        }

    companion object {
        /** Matches the Dart / iOS default longest-edge export cap. */
        const val DEFAULT_MAX_DIMENSION = 2200
        const val DEFAULT_CROP_MARGIN = 0.02

        /**
         * Resolves options from the full `scanDocument` (or embedded capture)
         * args map. [fallbackQuality] is the already-resolved top-level JPEG
         * quality (tier-clamped by the caller); the nested `quality` overrides
         * it when present.
         */
        fun parse(args: Map<String, Any?>?, fallbackQuality: Int): DocumentProcessingOptions {
            val processing = args?.get("processing") as? Map<*, *>
            fun flag(key: String, def: Boolean): Boolean =
                (processing?.get(key) as? Boolean) ?: def

            val legacyFilter = DocumentFilter.parse(args?.get("filter") as? String)
            val enhancement = (processing?.get("enhancement") as? String)
                ?.let { DocumentFilter.parse(it) }

            val baseEnhanceMode = when ((args?.get("enhanceMode") as? String)?.lowercase()) {
                "off" -> PageReencoder.EnhanceMode.OFF
                "fast" -> PageReencoder.EnhanceMode.FAST
                "max" -> PageReencoder.EnhanceMode.MAX
                else -> PageReencoder.EnhanceMode.BALANCED
            }

            return DocumentProcessingOptions(
                detectDocument = flag("detectDocument", true),
                perspectiveCorrection = flag("perspectiveCorrection", true),
                autoCrop = flag("autoCrop", true),
                cropMargin = (processing?.get("cropMargin") as? Number)?.toDouble()
                    ?: DEFAULT_CROP_MARGIN,
                deskew = flag("deskew", true),
                shadowRemoval = flag("shadowRemoval", true),
                backgroundWhitening = flag("backgroundWhitening", true),
                denoise = flag("denoise", true),
                sharpen = flag("sharpen", true),
                maxDimension = (processing?.get("maxDimension") as? Number)?.toInt()
                    ?: DEFAULT_MAX_DIMENSION,
                // enhancement (nested) > top-level filter > color.
                filter = enhancement ?: legacyFilter,
                quality = (processing?.get("quality") as? Number)?.toInt() ?: fallbackQuality,
                baseEnhanceMode = baseEnhanceMode,
            )
        }
    }
}
