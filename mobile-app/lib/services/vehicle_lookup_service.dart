import 'dart:convert';
import '../models/vehicle_model.dart';

class VehicleLookupService {
  /// Matches a raw QR string against registered vehicles, or decodes
  /// structured JSON QR pass data (with authorized drivers, sticker year, photos),
  /// or generates a visitor pass record if no registered vehicle matches.
  static VehicleRecord resolveVehicleFromQr({
    required String rawQrCode,
    required List<VehicleRecord> registeredVehicles,
  }) {
    final clean = rawQrCode.trim();
    if (clean.isEmpty) {
      return _generateVisitorPass('UNKNOWN');
    }

    // 0. Structured JSON QR Pass Decoder (From Admin Web App Pass Generator)
    if ((clean.startsWith('{') && clean.endsWith('}')) ||
        (clean.contains('"plateNumber"') && clean.contains('"authorizedDrivers"'))) {
      try {
        final dynamic decoded = jsonDecode(clean);
        if (decoded is Map<String, dynamic>) {
          final qrVehicle = VehicleRecord.fromQrJson(decoded, rawPayload: clean);

          // Cross-reference with database to enrich with photos/assets if available
          final normalizedQrPlate = qrVehicle.plateNumber.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
          final dbMatch = registeredVehicles.cast<VehicleRecord?>().firstWhere(
            (v) => v?.plateNumber.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase() == normalizedQrPlate,
            orElse: () => null,
          );

          if (dbMatch != null) {
            // When a matching database record exists, its updated information takes precedence
            // over outdated QR data, while preserving the valid sticker year from the physical pass
            return VehicleRecord(
              plateNumber: dbMatch.plateNumber.isNotEmpty ? dbMatch.plateNumber : qrVehicle.plateNumber,
              vehicleType: dbMatch.vehicleType.isNotEmpty ? dbMatch.vehicleType : qrVehicle.vehicleType,
              makeModelColor: dbMatch.makeModelColor.isNotEmpty ? dbMatch.makeModelColor : qrVehicle.makeModelColor,
              ownerName: dbMatch.ownerName.isNotEmpty ? dbMatch.ownerName : qrVehicle.ownerName,
              ownerRole: dbMatch.ownerRole.isNotEmpty ? dbMatch.ownerRole : qrVehicle.ownerRole,
              ownerIdNumber: dbMatch.ownerIdNumber.isNotEmpty ? dbMatch.ownerIdNumber : qrVehicle.ownerIdNumber,
              qrPassCode: clean,
              // The physical sticker year is preserved!
              stickerYear: qrVehicle.stickerYear.isNotEmpty ? qrVehicle.stickerYear : dbMatch.stickerYear,
              ownerPhotoUrl: (dbMatch.ownerPhotoUrl != null && dbMatch.ownerPhotoUrl!.isNotEmpty)
                  ? dbMatch.ownerPhotoUrl
                  : qrVehicle.ownerPhotoUrl,
              vehiclePicture: dbMatch.vehiclePicture ?? qrVehicle.vehiclePicture,
              // The updated authorized drivers from the database take precedence if available!
              authorizedDrivers: dbMatch.authorizedDrivers.isNotEmpty
                  ? dbMatch.authorizedDrivers
                  : qrVehicle.authorizedDrivers,
              isParsedFromQr: true,
              rawQrPayload: clean,
              isSyncedWithDb: true,
            );
          }

          return qrVehicle;
        }
      } catch (e) {
        // Fallback to plain text lookup below if JSON parsing fails
      }
    }

    // 1. Direct qrPassCode match
    for (final v in registeredVehicles) {
      if (v.qrPassCode.toLowerCase() == clean.toLowerCase()) {
        return v;
      }
    }

    // 2. Direct plate number match or normalized plate match
    final normalized = clean.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
    for (final v in registeredVehicles) {
      final normalizedPlate = v.plateNumber.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
      if (normalizedPlate == normalized) {
        return v;
      }
    }

    // 3. Substring match
    for (final v in registeredVehicles) {
      if (clean.toUpperCase().contains(v.plateNumber.toUpperCase()) ||
          clean.toUpperCase().contains(v.qrPassCode.toUpperCase())) {
        return v;
      }
    }

    // 4. Dynamic unregistered visitor vehicle pass fallback
    return _generateVisitorPass(clean);
  }

  static VehicleRecord _generateVisitorPass(String rawCode) {
    final plate = rawCode.length > 12 ? rawCode.substring(0, 12).toUpperCase() : rawCode.toUpperCase();
    final visitorId = 'VISITOR-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';

    return VehicleRecord(
      plateNumber: plate,
      vehicleType: 'Sedan',
      makeModelColor: 'Unregistered / Visitor Vehicle',
      ownerName: 'Visitor / Unregistered Pass',
      ownerRole: 'Guest Driver (Unverified QR Pass)',
      ownerIdNumber: visitorId,
      qrPassCode: rawCode,
      authorizedDrivers: const [],
      isParsedFromQr: false,
    );
  }
}
