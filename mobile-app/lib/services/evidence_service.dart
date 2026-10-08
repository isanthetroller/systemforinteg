import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../core/utils/plate_reader.dart';
import 'api_service.dart';

/// One photo a guard took, not yet sent to the server.
class PendingEvidence {
  final Uint8List bytes;

  /// What the phone read off the photo (null: nothing readable, or OCR unavailable).
  final String? plateRead;

  /// null = not checked, true = the plate on the photo is the plate on the pass, false = it is not.
  final bool? matches;

  const PendingEvidence({required this.bytes, this.plateRead, this.matches});
}

/// Takes evidence photos (vehicle / plate at entry, violation evidence) and sends them to the server, where they are
/// stored with the gate log or violation they belong to. Photos are optional: nothing here blocks a gate decision.
class EvidenceService {
  EvidenceService._();

  static final ImagePicker _picker = ImagePicker();

  /// The server accepts 600 KB; stay well under it.
  static const int maxBytes = 550000;

  /// Opens the camera, reads the plate, and returns the photo with the result. Null when the guard cancelled.
  static Future<PendingEvidence?> capture({required String expectedPlate}) async {
    try {
      XFile? file = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1280, imageQuality: 70);
      if (file == null) return null;
      var bytes = await file.readAsBytes();
      if (bytes.length > maxBytes) {
        // Retake smaller instead of failing the upload later
        final smaller = await _picker.pickImage(source: ImageSource.camera, maxWidth: 960, imageQuality: 45);
        if (smaller != null) {
          bytes = await smaller.readAsBytes();
          file = smaller;
        }
      }
      final read = await PlateReader.readFromFile(file.path, expectedPlate);
      await PlateReader.deleteQuietly(file.path);
      return PendingEvidence(
        bytes: bytes,
        plateRead: read,
        matches: read == null ? null : PlateReader.matches(read, expectedPlate),
      );
    } catch (e) {
      debugPrint('[EvidenceService] capture failed: $e');
      return null;
    }
  }

  /// Sends the photo. Exactly one of [gateLogId] / [violationId] / [incidentId] says what it belongs to.
  /// Returns null on success, otherwise a message the guard can read.
  static Future<String?> upload(
    PendingEvidence photo, {
    required String kind,
    required String plate,
    int? gateLogId,
    int? violationId,
    int? incidentId,
  }) {
    return ApiService.uploadEvidence({
      'kind': kind,
      'plate': plate,
      'gateLogId': ?gateLogId,
      'violationId': ?violationId,
      'incidentId': ?incidentId,
      'plateRead': ?photo.plateRead,
      'image': base64Encode(photo.bytes),
    });
  }
}
