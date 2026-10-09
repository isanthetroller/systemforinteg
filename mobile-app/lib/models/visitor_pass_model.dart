import 'dart:convert';

/// Status of a temporary visitor pass
enum VisitorPassStatus {
  active,  // Inside campus / valid
  used,    // Already checked out / exited
  expired, // Stay exceeded validity window (e.g. > 8 hours)
  blocked, // Blacklisted / security hold
}

/// Domain model representing a temporary vehicle entry pass for campus visitors
class VisitorPass {
  final String passId;
  final String visitorName;
  final String plateNumber;
  final String? vehiclePhotoUrl;
  final DateTime entryTime;
  final DateTime expiryTime;
  final DateTime? exitTime;
  final VisitorPassStatus status;
  final String registeredByGuard;
  final String gatePoint;
  final String? notes;
  final String? contactNumber;
  final String? vehicleModel;
  final String? purposeOfVisit;
  final String? personToVisit;
  final List<Map<String, dynamic>> items;
  final String? qrPayload;
  final int? dbId;

  const VisitorPass({
    required this.passId,
    required this.visitorName,
    required this.plateNumber,
    this.vehiclePhotoUrl,
    required this.entryTime,
    required this.expiryTime,
    this.exitTime,
    this.status = VisitorPassStatus.active,
    required this.registeredByGuard,
    required this.gatePoint,
    this.notes,
    this.contactNumber,
    this.vehicleModel,
    this.purposeOfVisit,
    this.personToVisit,
    this.items = const [],
    this.qrPayload,
    this.dbId,
  });

  bool get isActive => status == VisitorPassStatus.active && !isExpired;
  bool get isUsed => status == VisitorPassStatus.used;
  bool get isExpired => status == VisitorPassStatus.expired || DateTime.now().isAfter(expiryTime);
  bool get isBlocked => status == VisitorPassStatus.blocked;

  String get statusDisplay {
    if (isBlocked) return 'BLOCKED';
    if (isUsed) return 'ALREADY CHECKED OUT';
    if (isExpired) return 'EXPIRED';
    return 'ACTIVE PASS';
  }

  /// Encodes pass into a compact structured QR payload for physical or mobile scanning
  String toQrPayload() {
    if (qrPayload != null && qrPayload!.isNotEmpty) {
      return qrPayload!;
    }
    return jsonEncode({
      'type': 'NCST_VISITOR_PASS',
      'passId': passId,
      'visitorName': visitorName,
      'plateNumber': plateNumber,
      'entryTime': entryTime.toIso8601String(),
      'expiryTime': expiryTime.toIso8601String(),
      'gate': gatePoint,
    });
  }

  /// Constructs a VisitorPass from structured QR JSON or fallback plain token
  static VisitorPass? fromQrPayload(String rawPayload) {
    try {
      final clean = rawPayload.trim();
      if (clean.startsWith('{') && clean.endsWith('}')) {
        final decoded = jsonDecode(clean);
        if (decoded is Map<String, dynamic>) {
          if (decoded['type'] == 'NCST_VISITOR_PASS') {
            return VisitorPass(
              passId: decoded['passId']?.toString() ?? 'NCST-VIS-${DateTime.now().millisecondsSinceEpoch}',
              visitorName: decoded['visitorName']?.toString() ?? 'Visitor',
              plateNumber: decoded['plateNumber']?.toString() ?? 'N/A',
              entryTime: decoded['entryTime'] != null
                  ? DateTime.tryParse(decoded['entryTime'].toString()) ?? DateTime.now()
                  : DateTime.now(),
              expiryTime: decoded['expiryTime'] != null
                  ? DateTime.tryParse(decoded['expiryTime'].toString()) ?? DateTime.now().add(const Duration(hours: 8))
                  : DateTime.now().add(const Duration(hours: 8)),
              status: VisitorPassStatus.active,
              registeredByGuard: 'Gate Security',
              gatePoint: decoded['gate']?.toString() ?? 'Gate 1 (Main Ingress)',
              qrPayload: clean,
            );
          } else if (decoded['type'] == 'visitor_temp' || (decoded['pid'] != null && decoded['pid'].toString().startsWith('VP-'))) {
            return VisitorPass(
              passId: decoded['pid']?.toString() ?? '',
              visitorName: 'Visitor',
              plateNumber: decoded['plate_number']?.toString() ?? '',
              entryTime: DateTime.now(),
              expiryTime: decoded['valid'] != null
                  ? (DateTime.tryParse('${decoded['valid']} 23:59:59') ?? DateTime.now().add(const Duration(hours: 8)))
                  : DateTime.now().add(const Duration(hours: 8)),
              status: VisitorPassStatus.active,
              registeredByGuard: 'Gate Security',
              gatePoint: 'Gate 1 (Main Ingress)',
              qrPayload: clean,
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> toJson() => {
    'passId': passId,
    'pass_code': passId,
    'visitorName': visitorName,
    'visitor_name': visitorName,
    'plateNumber': plateNumber,
    'plate': plateNumber,
    'plate_number': plateNumber,
    'vehiclePhotoUrl': vehiclePhotoUrl,
    'vehiclePhoto': vehiclePhotoUrl != null && vehiclePhotoUrl!.startsWith('data:image/') ? vehiclePhotoUrl : null,
    'vehicleModel': vehicleModel ?? 'Visitor Vehicle',
    'vehicle_model': vehicleModel ?? 'Visitor Vehicle',
    'contactNumber': contactNumber ?? '09123456789',
    'contact_number': contactNumber ?? '09123456789',
    'purposeOfVisit': purposeOfVisit ?? (notes ?? 'Official Campus Visit'),
    'purpose': purposeOfVisit ?? (notes ?? 'Official Campus Visit'),
    'purpose_of_visit': purposeOfVisit ?? (notes ?? 'Official Campus Visit'),
    'personToVisit': personToVisit ?? 'Campus Department / Office',
    'person_to_visit': personToVisit ?? 'Campus Department / Office',
    'entryTime': entryTime.toIso8601String(),
    'expiryTime': expiryTime.toIso8601String(),
    'exitTime': exitTime?.toIso8601String(),
    'status': status == VisitorPassStatus.active ? 'Active' : (status == VisitorPassStatus.used ? 'Used' : 'Expired'),
    'registeredByGuard': registeredByGuard,
    'gatePoint': gatePoint,
    'notes': notes,
    'items': items,
    if (dbId != null) 'id': dbId,
    if (qrPayload != null) 'qrPayload': qrPayload,
  };

  /// For the phone's own cache: everything except the (large) vehicle photo, which lives on the server.
  Map<String, dynamic> toCacheJson() => {...toJson(), 'vehiclePhotoUrl': null, 'vehiclePhoto': null};

  factory VisitorPass.fromJson(Map<String, dynamic> json) {
    VisitorPassStatus st = VisitorPassStatus.active;
    final statusStr = (json['status'] ?? '').toString().toLowerCase();
    if (statusStr.contains('block') || statusStr.contains('revok')) {
      st = VisitorPassStatus.blocked;
    } else if (statusStr.contains('used') || statusStr.contains('exit')) {
      st = VisitorPassStatus.used;
    } else if (statusStr.contains('expire')) {
      st = VisitorPassStatus.expired;
    }

    final entry = json['entryTime'] != null
        ? DateTime.tryParse(json['entryTime'].toString()) ?? DateTime.now()
        : (json['entry_time'] != null ? DateTime.tryParse(json['entry_time'].toString()) ?? DateTime.now() : DateTime.now());

    final expiry = json['expiryTime'] != null
        ? DateTime.tryParse(json['expiryTime'].toString()) ?? entry.add(const Duration(hours: 8))
        : (json['validDate'] != null || json['valid_date'] != null ? DateTime.now().add(const Duration(hours: 8)) : entry.add(const Duration(hours: 8)));

    List<Map<String, dynamic>> parsedItems = const [];
    if (json['items'] is List) {
      parsedItems = (json['items'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return VisitorPass(
      passId: json['passId']?.toString() ?? json['passCode']?.toString() ?? json['pass_code']?.toString() ?? 'NCST-VIS-${DateTime.now().millisecondsSinceEpoch}',
      visitorName: json['visitorName']?.toString() ?? json['visitor_name']?.toString() ?? 'Visitor',
      plateNumber: json['plateNumber']?.toString() ?? json['plate_number']?.toString() ?? 'N/A',
      vehiclePhotoUrl: json['vehiclePhotoUrl']?.toString() ?? json['vehiclePhoto']?.toString() ?? json['vehicle_photo']?.toString(),
      entryTime: entry,
      expiryTime: expiry,
      exitTime: json['exitTime'] != null
          ? DateTime.tryParse(json['exitTime'].toString())
          : (json['exit_time'] != null ? DateTime.tryParse(json['exit_time'].toString()) : null),
      status: st,
      registeredByGuard: json['registeredByGuard']?.toString() ?? json['createdBy']?.toString() ?? json['created_by']?.toString() ?? 'Gate Officer',
      gatePoint: json['gatePoint']?.toString() ?? 'Gate 1 (Main Ingress)',
      notes: json['notes']?.toString(),
      contactNumber: json['contactNumber']?.toString() ?? json['contact_number']?.toString(),
      vehicleModel: json['vehicleModel']?.toString() ?? json['vehicle_model']?.toString(),
      purposeOfVisit: json['purposeOfVisit']?.toString() ?? json['purpose_of_visit']?.toString(),
      personToVisit: json['personToVisit']?.toString() ?? json['person_to_visit']?.toString(),
      items: parsedItems,
      qrPayload: json['qrPayload']?.toString() ?? json['qr_payload']?.toString(),
      dbId: int.tryParse(json['id']?.toString() ?? ''),
    );
  }

  VisitorPass copyWith({
    String? passId,
    String? visitorName,
    String? plateNumber,
    String? vehiclePhotoUrl,
    DateTime? entryTime,
    DateTime? expiryTime,
    VisitorPassStatus? status,
    DateTime? exitTime,
    String? registeredByGuard,
    String? gatePoint,
    String? notes,
    String? contactNumber,
    String? vehicleModel,
    String? purposeOfVisit,
    String? personToVisit,
    List<Map<String, dynamic>>? items,
    String? qrPayload,
    int? dbId,
  }) {
    return VisitorPass(
      passId: passId ?? this.passId,
      visitorName: visitorName ?? this.visitorName,
      plateNumber: plateNumber ?? this.plateNumber,
      vehiclePhotoUrl: vehiclePhotoUrl ?? this.vehiclePhotoUrl,
      entryTime: entryTime ?? this.entryTime,
      expiryTime: expiryTime ?? this.expiryTime,
      exitTime: exitTime ?? this.exitTime,
      status: status ?? this.status,
      registeredByGuard: registeredByGuard ?? this.registeredByGuard,
      gatePoint: gatePoint ?? this.gatePoint,
      notes: notes ?? this.notes,
      contactNumber: contactNumber ?? this.contactNumber,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      purposeOfVisit: purposeOfVisit ?? this.purposeOfVisit,
      personToVisit: personToVisit ?? this.personToVisit,
      items: items ?? this.items,
      qrPayload: qrPayload ?? this.qrPayload,
      dbId: dbId ?? this.dbId,
    );
  }
}
