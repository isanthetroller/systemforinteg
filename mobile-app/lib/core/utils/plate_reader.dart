import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'id_ocr_parser.dart';

/// Reads a licence plate off a photo and compares it with the plate on the pass.
///
/// The comparison folds the usual camera confusions (O/0, I/1, B/8, S/5, Z/2) on BOTH sides, exactly like the
/// server (api/evidence.php), so the guard sees on the spot what will be stored.
class PlateReader {
  PlateReader._();

  static final RegExp _separators = RegExp(r'[^A-Z0-9]');
  static const Map<String, String> _confusions = {'O': '0', 'Q': '0', 'I': '1', 'L': '1', 'B': '8', 'S': '5', 'Z': '2'};

  /// Plate text without spaces / dashes, upper case, confusable characters folded.
  static String fold(String plate) {
    final cleaned = plate.toUpperCase().replaceAll(_separators, '');
    return cleaned.split('').map((c) => _confusions[c] ?? c).join();
  }

  /// True when both plates are the same after folding (empty never matches).
  static bool matches(String? read, String expected) {
    if (read == null) return false;
    final a = fold(read);
    return a.isNotEmpty && a == fold(expected);
  }

  /// Every plate-shaped piece of text in [text] (3 letters + 3-4 digits, 2 letters + 3-5 digits, 3-4 digits + 2-3 letters).
  static List<String> candidates(String text) {
    final clean = text.toUpperCase();
    final found = <String>[];
    void add(String? a, String? b) {
      if (a == null || b == null) return;
      final value = '$a-$b';
      if (!found.contains(value)) found.add(value);
    }

    for (final m in RegExp(r'\b([A-Z]{3})[\s\-]?(\d{3,4})\b').allMatches(clean)) {
      add(m.group(1), m.group(2));
    }
    for (final m in RegExp(r'\b([A-Z]{2})[\s\-]?(\d{3,5})\b').allMatches(clean)) {
      add(m.group(1), m.group(2));
    }
    for (final m in RegExp(r'\b(\d{3,4})[\s\-]?([A-Z]{2,3})\b').allMatches(clean)) {
      add(m.group(1), m.group(2));
    }
    return found;
  }

  /// The plate to report from the recognised [text]: the candidate that matches [expected] if there is one,
  /// otherwise the first plate-shaped text, otherwise null (nothing readable).
  static String? pick(String text, String expected) {
    final all = candidates(text);
    for (final c in all) {
      if (matches(c, expected)) return c;
    }
    if (all.isNotEmpty) return all.first;
    final fallback = IdOcrParser.extractPlateFromOcr(text);
    return fallback.isEmpty ? null : fallback;
  }

  /// Runs ML Kit on the photo at [path]. Returns null when nothing plate-like could be read (or OCR is unavailable).
  static Future<String?> readFromFile(String path, String expected) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(path));
      return pick(result.text, expected);
    } catch (e) {
      debugPrint('[PlateReader] OCR unavailable: $e');
      return null;
    } finally {
      try {
        await recognizer.close();
      } catch (_) {}
    }
  }

  /// Deletes a temporary photo file, ignoring errors.
  static Future<void> deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }
}
