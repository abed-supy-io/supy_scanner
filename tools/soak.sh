#!/usr/bin/env bash
#
# 24-hour soak harness for supy_scanner. Drives the example app through the
# reliability scenarios on a real device (H3-02 Moto G Power, H3-03 iPhone SE 2)
# while sampling memory/FPS/error rate, then emits a single summary.json.
#
# Usage:
#   tools/soak.sh <device_id> [hours] [output_dir]
#
#   device_id    adb serial (Android) or `flutter devices` id (iOS)
#   hours        wall-clock duration; default 24
#   output_dir   destination for samples + summary; default .build/soak/<ts>
#
# What it does:
#   - Detects platform from `flutter devices --machine`.
#   - Loops `flutter test integration_test/reliability_harness_test.dart
#     --profile -d <device_id>` for the full duration. Each loop pass is one
#     "iteration block" (100 push/pop + 50 pause/resume = 150 cycles).
#   - Every SAMPLE_INTERVAL_SEC (default 60), snapshots:
#       Android: `adb shell dumpsys meminfo <pkg>` — TOTAL PSS column.
#       iOS:     `xcrun devicectl device info processes` — RSS for the app PID.
#   - Streams device logs to logs.txt (logcat / idevicesyslog).
#   - On finish / SIGINT, writes summary.json:
#       { device, platform, started_at, finished_at, duration_seconds,
#         iteration_blocks, total_cycles, peak_rss_kb, final_rss_kb,
#         leak_delta_kb, samples_csv, logs_path, errors }
#   - Exits non-zero if leak_delta_kb exceeds SOAK_LEAK_BUDGET_KB
#     (default 50 MB) — gives an objective pass/fail for the H3 sign-off.
#
# Run on the device side (these are *device* runs, not CI):
#   adb devices                                       # confirm serial
#   tools/soak.sh ZY223QXXXX                          # default 24h
#   tools/soak.sh ZY223QXXXX 2 .build/soak/smoke      # 2-hour smoke
#
# Manual leak verification still requires Xcode Instruments / Studio Profiler
# attached against this binary — soak.sh measures process working set, not
# native-heap fragmentation.

set -euo pipefail

# ---------- args ----------

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <device_id> [hours] [output_dir]" >&2
  exit 64
fi

DEVICE_ID="$1"
HOURS="${2:-24}"
OUTPUT_DIR="${3:-}"

if ! [[ "$HOURS" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "error: hours must be a positive number, got '$HOURS'" >&2
  exit 64
fi

DURATION_SEC="$(awk -v h="$HOURS" 'BEGIN { printf "%d", h * 3600 }')"
if [[ "$DURATION_SEC" -le 0 ]]; then
  echo "error: hours resolves to <= 0 seconds" >&2
  exit 64
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.build/soak/$TIMESTAMP}"
mkdir -p "$OUTPUT_DIR"

SAMPLES_CSV="$OUTPUT_DIR/samples.csv"
LOGS_TXT="$OUTPUT_DIR/logs.txt"
ITER_LOG="$OUTPUT_DIR/iterations.log"
SUMMARY_JSON="$OUTPUT_DIR/summary.json"

SAMPLE_INTERVAL_SEC="${SOAK_SAMPLE_INTERVAL_SEC:-60}"
LEAK_BUDGET_KB="${SOAK_LEAK_BUDGET_KB:-51200}"   # 50 MB
APP_PACKAGE="${SOAK_ANDROID_PKG:-io.supy.scanner.example}"
APP_BUNDLE="${SOAK_IOS_BUNDLE:-io.supy.scanner.example}"

# ---------- platform detection ----------

PLATFORM=""
if command -v flutter >/dev/null 2>&1; then
  PLATFORM="$(flutter devices --machine 2>/dev/null \
    | awk -v id="$DEVICE_ID" '
        $0 ~ "\"id\""        { gsub(/[",]/,""); cur_id=$2 }
        $0 ~ "\"targetPlatform\"" && cur_id == id {
          gsub(/[",]/,""); print $2; exit
        }')"
fi

if [[ -z "$PLATFORM" ]]; then
  # Fallback by tool availability.
  if command -v adb >/dev/null 2>&1 && adb -s "$DEVICE_ID" get-state >/dev/null 2>&1; then
    PLATFORM="android-arm64"
  elif command -v xcrun >/dev/null 2>&1; then
    PLATFORM="ios"
  else
    echo "error: could not detect platform for $DEVICE_ID" >&2
    exit 65
  fi
fi

case "$PLATFORM" in
  android*) PLATFORM_KIND="android" ;;
  ios|darwin) PLATFORM_KIND="ios" ;;
  *)
    echo "error: unsupported platform '$PLATFORM'" >&2
    exit 65
    ;;
esac

# ---------- samplers ----------

# Android: TOTAL PSS in KB from `dumpsys meminfo`.
sample_android_rss_kb() {
  adb -s "$DEVICE_ID" shell "dumpsys meminfo $APP_PACKAGE 2>/dev/null" \
    | awk '/TOTAL PSS:/ { print $3; exit }'
}

# iOS: RSS for the app pid via devicectl. Returns KB.
sample_ios_rss_kb() {
  local pid
  pid="$(xcrun devicectl device info processes --device "$DEVICE_ID" 2>/dev/null \
    | awk -v b="$APP_BUNDLE" '$0 ~ b { print $1; exit }')"
  if [[ -z "$pid" ]]; then echo ""; return; fi
  xcrun devicectl device info processes --device "$DEVICE_ID" 2>/dev/null \
    | awk -v p="$pid" '$1 == p { print int($NF / 1024); exit }'
}

sample_rss_kb() {
  case "$PLATFORM_KIND" in
    android) sample_android_rss_kb ;;
    ios)     sample_ios_rss_kb ;;
  esac
}

# ---------- log streaming ----------

LOG_PID=""
start_logs() {
  case "$PLATFORM_KIND" in
    android)
      adb -s "$DEVICE_ID" logcat -c >/dev/null 2>&1 || true
      adb -s "$DEVICE_ID" logcat -v time '*:W' > "$LOGS_TXT" 2>&1 &
      LOG_PID=$!
      ;;
    ios)
      if command -v idevicesyslog >/dev/null 2>&1; then
        idevicesyslog -u "$DEVICE_ID" > "$LOGS_TXT" 2>&1 &
        LOG_PID=$!
      else
        echo "(idevicesyslog not installed — iOS logs skipped)" > "$LOGS_TXT"
      fi
      ;;
  esac
}

# ---------- cleanup ----------

EARLY_STOP=0
stop_logs() {
  if [[ -n "$LOG_PID" ]] && kill -0 "$LOG_PID" 2>/dev/null; then
    kill "$LOG_PID" 2>/dev/null || true
    wait "$LOG_PID" 2>/dev/null || true
  fi
}

on_sigint() {
  EARLY_STOP=1
}
trap on_sigint INT TERM
trap stop_logs EXIT

# ---------- run ----------

echo "iso_ts,uptime_sec,rss_kb,iteration_block" > "$SAMPLES_CSV"
START_EPOCH="$(date -u +%s)"
PEAK_RSS_KB=0
LAST_RSS_KB=0
FIRST_RSS_KB=""
ITERATION_BLOCKS=0
DEADLINE_EPOCH=$((START_EPOCH + DURATION_SEC))

start_logs

# Background sampler.
sampler_loop() {
  while [[ "$EARLY_STOP" -eq 0 ]] && [[ "$(date -u +%s)" -lt "$DEADLINE_EPOCH" ]]; do
    local now uptime rss
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    uptime=$(( $(date -u +%s) - START_EPOCH ))
    rss="$(sample_rss_kb || true)"
    if [[ -n "$rss" ]] && [[ "$rss" =~ ^[0-9]+$ ]]; then
      echo "$now,$uptime,$rss,$ITERATION_BLOCKS" >> "$SAMPLES_CSV"
      LAST_RSS_KB="$rss"
      if [[ -z "$FIRST_RSS_KB" ]]; then FIRST_RSS_KB="$rss"; fi
      if [[ "$rss" -gt "$PEAK_RSS_KB" ]]; then PEAK_RSS_KB="$rss"; fi
    fi
    sleep "$SAMPLE_INTERVAL_SEC"
  done
}
sampler_loop &
SAMPLER_PID=$!

# Iteration loop — one `flutter test` invocation = one block (150 cycles).
cd "$REPO_ROOT/example"
while [[ "$EARLY_STOP" -eq 0 ]] && [[ "$(date -u +%s)" -lt "$DEADLINE_EPOCH" ]]; do
  echo "--- iteration block $ITERATION_BLOCKS at $(date -u +%H:%M:%SZ) ---" >> "$ITER_LOG"
  if flutter test integration_test/reliability_harness_test.dart \
       --profile -d "$DEVICE_ID" \
       --dart-define=SUPY_SCANNER_DEVICE_TEST=true \
       >> "$ITER_LOG" 2>&1; then
    ITERATION_BLOCKS=$((ITERATION_BLOCKS + 1))
  else
    echo "iteration block $ITERATION_BLOCKS FAILED" >> "$ITER_LOG"
    # Soak intentionally continues on per-block failures — the goal is to
    # find drift over time, not to fail-fast on a single flake. Recorded
    # failures roll up into summary.json errors[].
  fi
done

kill "$SAMPLER_PID" 2>/dev/null || true
wait "$SAMPLER_PID" 2>/dev/null || true

FINISH_EPOCH="$(date -u +%s)"
DURATION_ACTUAL=$((FINISH_EPOCH - START_EPOCH))
TOTAL_CYCLES=$((ITERATION_BLOCKS * 150))
LEAK_DELTA_KB=0
if [[ -n "$FIRST_RSS_KB" ]]; then
  LEAK_DELTA_KB=$((LAST_RSS_KB - FIRST_RSS_KB))
fi

ERRORS_JSON='[]'
if grep -q "FAILED" "$ITER_LOG" 2>/dev/null; then
  ERRORS_JSON="$(awk '/FAILED$/ { gsub(/"/,"\\\""); printf "%s\"%s\"", (n++ ? "," : ""), $0 } END { print "" }' "$ITER_LOG")"
  ERRORS_JSON="[$ERRORS_JSON]"
fi

cat > "$SUMMARY_JSON" <<EOF
{
  "device": "$DEVICE_ID",
  "platform": "$PLATFORM_KIND",
  "started_at": "$(date -u -r "$START_EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$START_EPOCH" +%Y-%m-%dT%H:%M:%SZ)",
  "finished_at": "$(date -u -r "$FINISH_EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$FINISH_EPOCH" +%Y-%m-%dT%H:%M:%SZ)",
  "duration_seconds": $DURATION_ACTUAL,
  "duration_target_seconds": $DURATION_SEC,
  "iteration_blocks": $ITERATION_BLOCKS,
  "total_cycles": $TOTAL_CYCLES,
  "first_rss_kb": ${FIRST_RSS_KB:-0},
  "peak_rss_kb": $PEAK_RSS_KB,
  "final_rss_kb": $LAST_RSS_KB,
  "leak_delta_kb": $LEAK_DELTA_KB,
  "leak_budget_kb": $LEAK_BUDGET_KB,
  "samples_csv": "$SAMPLES_CSV",
  "iterations_log": "$ITER_LOG",
  "device_logs": "$LOGS_TXT",
  "errors": $ERRORS_JSON
}
EOF

echo "soak complete — summary at $SUMMARY_JSON"
echo "  blocks=$ITERATION_BLOCKS cycles=$TOTAL_CYCLES peak_rss=${PEAK_RSS_KB}kb leak_delta=${LEAK_DELTA_KB}kb"

if [[ "$LEAK_DELTA_KB" -gt "$LEAK_BUDGET_KB" ]]; then
  echo "FAIL: leak_delta_kb=$LEAK_DELTA_KB exceeds budget $LEAK_BUDGET_KB" >&2
  exit 1
fi
