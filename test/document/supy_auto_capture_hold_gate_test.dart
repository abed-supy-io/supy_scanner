import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/document/supy_auto_capture_hold_gate.dart';

/// D3-4 — auto-capture countdown must be driven by the *steady + framed*
/// signal, not raw per-frame `ready` jitter.
///
/// The document view cancels the countdown on the gate's `lost` edge and
/// (re)starts it on `acquired`. Because the FSM demotes out of `ready`
/// immediately (a terminal transition, no min-dwell), a single hand-held blip
/// frame would otherwise tear down the sweeping ring and restart it from zero —
/// on a jittery hold, auto-capture could be starved forever. This gate absorbs
/// a bounded run of non-ready frames so brief flicker rides through.
///
/// Both platforms feed the same per-frame `ready` boolean into this gate (the
/// Android FSM path and the iOS native-`state` path funnel through one Dart
/// event handler), so pinning the gate pins the cross-platform behavior.
void main() {
  group('SupyAutoCaptureHoldGate', () {
    test('first ready frame acquires the hold', () {
      final gate = SupyAutoCaptureHoldGate();
      expect(gate.isHeld, isFalse);
      expect(gate.update(isReady: true), SupyAutoCaptureHoldEdge.acquired);
      expect(gate.isHeld, isTrue);
    });

    test('continued ready frames report no edge (single acquire)', () {
      final gate = SupyAutoCaptureHoldGate();
      expect(gate.update(isReady: true), SupyAutoCaptureHoldEdge.acquired);
      expect(gate.update(isReady: true), SupyAutoCaptureHoldEdge.none);
      expect(gate.update(isReady: true), SupyAutoCaptureHoldEdge.none);
      expect(gate.isHeld, isTrue);
    });

    test('non-ready frames while idle never emit an edge', () {
      final gate = SupyAutoCaptureHoldGate();
      for (var i = 0; i < 10; i++) {
        expect(gate.update(isReady: false), SupyAutoCaptureHoldEdge.none);
      }
      expect(gate.isHeld, isFalse);
    });

    test('a flicker within grace keeps the hold (no cancel, no re-acquire)', () {
      final gate = SupyAutoCaptureHoldGate(); // graceFrames default = 3
      expect(gate.update(isReady: true), SupyAutoCaptureHoldEdge.acquired);

      // Three consecutive non-ready blip frames — all tolerated.
      expect(gate.update(isReady: false), SupyAutoCaptureHoldEdge.none);
      expect(gate.update(isReady: false), SupyAutoCaptureHoldEdge.none);
      expect(gate.update(isReady: false), SupyAutoCaptureHoldEdge.none);
      expect(gate.isHeld, isTrue, reason: 'countdown should still be sweeping');

      // Flicker back to ready must NOT re-fire the lock cue / restart the ring.
      expect(gate.update(isReady: true), SupyAutoCaptureHoldEdge.none);
      expect(gate.isHeld, isTrue);
    });

    test('exceeding grace breaks the hold exactly once', () {
      final gate = SupyAutoCaptureHoldGate();
      gate.update(isReady: true);

      // Frames 1..3 tolerated; the 4th (grace + 1) breaks the hold.
      expect(gate.update(isReady: false), SupyAutoCaptureHoldEdge.none);
      expect(gate.update(isReady: false), SupyAutoCaptureHoldEdge.none);
      expect(gate.update(isReady: false), SupyAutoCaptureHoldEdge.none);
      expect(gate.update(isReady: false), SupyAutoCaptureHoldEdge.lost);
      expect(gate.isHeld, isFalse);

      // Further non-ready frames are quiet once the hold is already broken.
      expect(gate.update(isReady: false), SupyAutoCaptureHoldEdge.none);
    });

    test('a fresh ready run after a genuine loss re-acquires', () {
      final gate = SupyAutoCaptureHoldGate(graceFrames: 1);
      gate.update(isReady: true); // acquired
      expect(
        gate.update(isReady: false),
        SupyAutoCaptureHoldEdge.none,
      ); // grace
      expect(
        gate.update(isReady: false),
        SupyAutoCaptureHoldEdge.lost,
      ); // break
      // Document re-frames → a new countdown must start.
      expect(gate.update(isReady: true), SupyAutoCaptureHoldEdge.acquired);
    });

    test('graceFrames: 0 cancels on the first non-ready frame', () {
      final gate = SupyAutoCaptureHoldGate(graceFrames: 0);
      expect(gate.update(isReady: true), SupyAutoCaptureHoldEdge.acquired);
      expect(gate.update(isReady: false), SupyAutoCaptureHoldEdge.lost);
      expect(gate.isHeld, isFalse);
    });

    test('the loss streak resets after riding through a blip', () {
      // Two separate 3-frame blips, each with a ready frame between them, must
      // both be tolerated — the streak must not accumulate across the recovery.
      final gate = SupyAutoCaptureHoldGate();
      gate.update(isReady: true);
      for (var blip = 0; blip < 2; blip++) {
        expect(gate.update(isReady: false), SupyAutoCaptureHoldEdge.none);
        expect(gate.update(isReady: false), SupyAutoCaptureHoldEdge.none);
        expect(gate.update(isReady: false), SupyAutoCaptureHoldEdge.none);
        expect(gate.update(isReady: true), SupyAutoCaptureHoldEdge.none);
      }
      expect(gate.isHeld, isTrue);
    });

    test('reset clears the hold', () {
      final gate = SupyAutoCaptureHoldGate()..update(isReady: true);
      expect(gate.isHeld, isTrue);
      gate.reset();
      expect(gate.isHeld, isFalse);
      // After reset the next ready frame acquires afresh.
      expect(gate.update(isReady: true), SupyAutoCaptureHoldEdge.acquired);
    });

    test('a jittery hold yields one acquire and no mid-sequence cancel', () {
      // A representative hand-held "steady with jitter" ready-stream: mostly
      // ready with isolated 1-2 frame demotions. The countdown should acquire
      // once and never be cancelled mid-sweep.
      const stream = <bool>[
        true,
        true,
        false,
        true,
        true,
        false,
        false,
        true,
        true,
        true,
      ];
      final gate = SupyAutoCaptureHoldGate();
      final edges = stream.map((r) => gate.update(isReady: r)).toList();
      expect(
        edges.where((e) => e == SupyAutoCaptureHoldEdge.acquired).length,
        1,
      );
      expect(edges.contains(SupyAutoCaptureHoldEdge.lost), isFalse);
      expect(gate.isHeld, isTrue);
    });
  });
}
