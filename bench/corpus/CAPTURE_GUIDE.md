# Corpus capture guide (manual, ~half a day)

The DSQ program needs ~120 real scenes with Scanbot reference output. This
is the only manual dependency in the program. Per scene:

1. **Stage the scene.** Composition targets (see README.md): thermal /
   crumpled receipts, A4 invoices, glossy menus × {plain, cluttered}
   backgrounds × {good, dim, shadow, glare} lighting. Add ~6 negative
   scenes (no document in frame).
2. **Capture `frame.png`.** Phone on a stand (scene must not move between
   the two captures). Use the plain camera app at max still resolution,
   export PNG (or lossless HEIC→PNG). This is the raw input both pipelines
   will be replayed against.
3. **Capture `scanbot.png`.** Without moving anything, scan the same scene
   with the current retailer app (Scanbot SDK path) and export its final
   processed page image.
4. **Label `scene.json`.** Copy the template from README.md. Mark the four
   document corners in frame.png (any image viewer with pixel readout),
   divide x by width and y by height, order TL,TR,BR,BL. Measure the
   physical document with a ruler for `physicalWidthMm`/`physicalHeightMm`.
5. **Transcribe `truth.txt`.** The document's machine-readable text, top to
   bottom. Skip logos/handwriting. This is the CER ground truth — accuracy
   here matters more than coverage; omit lines you cannot read.
6. **Validate:** `dart tools/bench/validate_corpus.dart` must exit 0.
7. Commit through Git LFS (`git lfs install` once; `.gitattributes` already
   routes `bench/corpus/**/*.png`).

After the corpus lands, pin Scanbot's reference numbers once:

    dart tools/bench/run_bench.dart --suite all
    dart tools/bench/run_bench.dart --suite all --pin scanbot

and commit `tools/bench/baselines/scanbot.json`.
