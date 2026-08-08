# tools/bench — DSQ quality bench

The DSQ scoreboard: detection quality (quad IoU, detect rate, false
positives) and output quality (sharpness, illumination uniformity,
effective DPI, OCR CER) over the labeled corpus in `bench/corpus/`,
side-by-side with Scanbot reference outputs.

Design: `docs/superpowers/specs/2026-07-16-doc-scan-quality-design.md` (DSQ0).
Sibling harness for perf (latency) gating: `tools/perfgate/`.

## Run

```sh
cd tools/bench && dart pub get && cd ../..
dart tools/bench/run_bench.dart                  # full suite
dart tools/bench/run_bench.dart --suite detect   # detection only
dart tools/bench/run_bench.dart --skip-ocr       # no Vision CER lane
dart tools/bench/run_bench.dart --gate prev      # exit 1 on >2% regression
dart tools/bench/run_bench.dart --pin prev       # snapshot current numbers
```

Report: `tools/bench/report/bench_report.md` (+ `.json`, + rectified pages
under `report/pages/`). OCR needs macOS (Vision.framework); elsewhere the
CER lane is skipped automatically.

## Pieces

| Path | What |
|---|---|
| `lib/corpus.dart` | Scene schema + validator (`validate_corpus.dart` CLI) |
| `lib/quad_iou.dart` | Convex quad IoU |
| `lib/metrics.dart` | Sharpness / uniformity / DPI / CER |
| `lib/report.dart` | Aggregation, markdown scoreboard, ±2% gate |
| `run_bench.dart` | Driver: build tools, replay corpus, write report |
| `gen_seed_corpus.dart` | Regenerates the synthetic `seed-*` scenes |
| `ocr/vision_ocr.swift` | macOS Vision OCR CLI |
| `core/bench/bench_detect.cpp` | Host harness → classical detector |
| `core/bench/bench_pipeline.cpp` | Host harness → warp + enhance replay |

Pixel data reaches native code via raw temp files + argv — never dart:ffi
(`core/include/supy_scanner.h` boundary contract).

## CI

`dsq-bench` job in `.github/workflows/ci.yml` (macos-14): unit tests +
full host replay on the corpus, report uploaded as artifact. Non-blocking
until the real corpus and baselines land.
