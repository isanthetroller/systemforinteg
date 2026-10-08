import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:vibration/vibration.dart';

import 'local_cache_service.dart';

/// How a scan ended, from the guard's point of view.
enum ScanOutcome { cleared, warning, refused }

/// A beep and a vibration for every scan result, so the guard can keep eyes on the vehicle: one short rising chirp
/// when the vehicle is cleared, two even beeps when it needs a second look, one long low buzz when it is refused.
/// The tones are generated here (no sound files). Everything is best-effort: a phone without a speaker or vibrator,
/// or a test run, simply stays silent.
class ScanFeedback {
  ScanFeedback._();

  /// What was last played (for the screen and for tests).
  static ScanOutcome? lastPlayed;

  /// Replaced in tests to see what would be played without touching the audio or vibration hardware.
  @visibleForTesting
  static Future<void> Function(ScanOutcome outcome)? testSink;

  static AudioPlayer? _player;

  static bool get enabled => LocalCacheService.getScanFeedbackEnabled();

  static Future<void> setEnabled(bool value) => LocalCacheService.setScanFeedbackEnabled(value);

  /// Plays the cue for [outcome] unless the guard turned it off. Returns at once; never throws.
  static Future<void> play(ScanOutcome outcome, {bool force = false}) async {
    if (!force && !enabled) return;
    lastPlayed = outcome;
    final sink = testSink;
    if (sink != null) {
      await sink(outcome);
      return;
    }
    await Future.wait([_beep(outcome), _buzz(outcome)]);
  }

  static Future<void> _beep(ScanOutcome outcome) async {
    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.play(BytesSource(wavFor(outcome), mimeType: 'audio/wav'), volume: 1.0);
    } catch (e) {
      debugPrint('[ScanFeedback] beep note: $e');
    }
  }

  static Future<void> _buzz(ScanOutcome outcome) async {
    try {
      if (await Vibration.hasVibrator() != true) return;
      await Vibration.vibrate(pattern: vibrationFor(outcome));
    } catch (e) {
      debugPrint('[ScanFeedback] vibration note: $e');
    }
  }

  /// Wait, vibrate, wait, vibrate... in milliseconds (Android pattern: starts with the initial pause).
  static List<int> vibrationFor(ScanOutcome outcome) {
    switch (outcome) {
      case ScanOutcome.cleared:
        return [0, 90];
      case ScanOutcome.warning:
        return [0, 140, 110, 140];
      case ScanOutcome.refused:
        return [0, 600, 140, 600];
    }
  }

  /// (frequency in Hz, length in ms, square wave?) tones, in order; a frequency of 0 is a pause.
  static List<(double, int, bool)> tonesFor(ScanOutcome outcome) {
    switch (outcome) {
      case ScanOutcome.cleared:
        return [(880, 90, false), (1320, 140, false)];
      case ScanOutcome.warning:
        return [(660, 170, false), (0, 90, false), (660, 170, false)];
      case ScanOutcome.refused:
        return [(196, 650, true)];
    }
  }

  /// A 16-bit mono WAV file of the cue for [outcome].
  static Uint8List wavFor(ScanOutcome outcome, {int sampleRate = 22050}) {
    final samples = <int>[];
    for (final (freq, ms, square) in tonesFor(outcome)) {
      final count = sampleRate * ms ~/ 1000;
      final fade = math.min(count ~/ 6, sampleRate ~/ 100); // short fade in/out so there is no click
      for (var i = 0; i < count; i++) {
        double v = 0;
        if (freq > 0) {
          final s = math.sin(2 * math.pi * freq * i / sampleRate);
          v = square ? (s >= 0 ? 0.55 : -0.55) : s * 0.9;
          if (i < fade) v *= i / fade;
          if (count - i < fade) v *= (count - i) / fade;
        }
        samples.add((v * 32000).round().clamp(-32768, 32767));
      }
    }
    final dataLength = samples.length * 2;
    final bytes = ByteData(44 + dataLength);
    void tag(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        bytes.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    bytes.setUint32(4, 36 + dataLength, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little); // PCM
    bytes.setUint16(22, 1, Endian.little); // mono
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    bytes.setUint32(40, dataLength, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      bytes.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}

/// Held by a scanner screen. Call [update] from `build` with what the screen is showing; the cue plays once each time the
/// outcome changes to a new result, never again for a rebuild of the same result.
class ScanFeedbackGate {
  ScanOutcome? _current;

  void update(ScanOutcome? now) {
    if (now == _current) return;
    _current = now;
    if (now == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => ScanFeedback.play(now));
  }

  /// Forget the last result, so the next one plays even when it is the same kind.
  void reset() => _current = null;
}
