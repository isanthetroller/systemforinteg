enum GateStatus { inside, blocked }

class AuthorizedDriver {
  final String id;
  final String fullName;
  final String relationship;
  final String licenseNo;
  final String? phone;
  final String? photoUrl;

  const AuthorizedDriver({
    required this.id,
    required this.fullName,
    required this.relationship,
    required this.licenseNo,
    this.phone,
    this.photoUrl,
  });

  factory AuthorizedDriver.fromJson(Map<String, dynamic> json, {int index = 0}) {
    return AuthorizedDriver(
      id: json['id']?.toString() ?? 'drv-$index',
      fullName: (json['fullName'] ?? json['full_name'] ?? json['name'] ?? 'Authorized Driver').toString(),
      relationship: (json['relationship'] ?? json['rel'] ?? 'Self (Owner)').toString(),
      licenseNo: (json['licenseNo'] ?? json['license_no'] ?? json['license'] ?? 'N/A').toString(),
      phone: json['phone']?.toString(),
      photoUrl: (json['photoUrl'] ?? json['photo_url'] ?? json['photo'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'fullName': fullName,
    'relationship': relationship,
    'licenseNo': licenseNo,
    if (phone != null) 'phone': phone,
    if (photoUrl != null) 'photoUrl': photoUrl,
  };
}

class VehicleRecord {
  final String plateNumber;
  final String vehicleType;
  final String makeModelColor;
  final String ownerName;
  final String ownerRole;
  final String ownerIdNumber;
  final String qrPassCode;
  final String stickerYear;
  final String? ownerPhotoUrl;
  final String? vehiclePicture;
  final List<AuthorizedDriver> authorizedDrivers;
  final bool isParsedFromQr;
  final String? rawQrPayload;
  final bool isSyncedWithDb;

  const VehicleRecord({
    required this.plateNumber,
    required this.vehicleType,
    required this.makeModelColor,
    required this.ownerName,
    required this.ownerRole,
    required this.ownerIdNumber,
    required this.qrPassCode,
    this.stickerYear = '2026',
    this.ownerPhotoUrl,
    this.vehiclePicture,
    required this.authorizedDrivers,
    this.isParsedFromQr = false,
    this.rawQrPayload,
    this.isSyncedWithDb = false,
  });

  factory VehicleRecord.fromQrJson(Map<String, dynamic> json, {String rawPayload = '', bool isSyncedWithDb = false}) {
    final plate = (json['plateNumber'] ?? json['plate_number'] ?? json['plate'] ?? 'UNKNOWN').toString();
    final ownerName = (json['ownerFullName'] ?? json['owner_name'] ?? json['ownerName'] ?? 'Registered Owner').toString();
    final ownerId = (json['ownerStudentId'] ?? json['owner_id_number'] ?? json['ownerIdNumber'] ?? 'N/A').toString();
    final stickerYear = (json['stickerYear'] ?? json['sticker_year'] ?? '2026').toString();
    final vehicleType = (json['vehicleCategory'] ?? json['vehicle_type'] ?? json['vehicleType'] ?? '4-Wheel').toString();
    final makeModel = (json['makeModelColor'] ?? json['make_model_color'] ?? json['makeModel'] ?? 'Registered Vehicle').toString();
    final vehiclePic = (json['vehiclePicture'] ?? json['vehiclePhoto'] ?? json['vehicle_photo'] ?? json['vehicle_picture'] ?? json['vehicle_photo_url'])?.toString();
    final ownerPhoto = (json['ownerPhoto'] ?? json['owner_photo'] ?? json['owner_photo_url'] ?? json['ownerPhotoUrl'])?.toString();

    final rawRole = (json['ownerRole'] ?? json['owner_role'] ?? '').toString().trim();
    final computedRole = rawRole.isNotEmpty
        ? rawRole
        : (ownerId.toUpperCase().contains('FAC')
            ? 'Faculty Member'
            : (ownerId.toUpperCase().contains('VIS') ? 'Campus Visitor' : 'Student (Campus Registered)'));

    final driversList = <AuthorizedDriver>[];
    final rawDrivers = json['authorizedDrivers'] ?? json['authorized_drivers'];
    if (rawDrivers is List) {
      for (var i = 0; i < rawDrivers.length; i++) {
        final item = rawDrivers[i];
        AuthorizedDriver? driver;
        if (item is Map<String, dynamic>) {
          driver = AuthorizedDriver.fromJson(item, index: i);
        } else if (item is Map) {
          driver = AuthorizedDriver.fromJson(Map<String, dynamic>.from(item), index: i);
        }
        if (driver != null) {
          // If this driver is the owner and has no specific photo, inherit owner photo
          if ((driver.photoUrl == null || driver.photoUrl!.trim().isEmpty) &&
              (driver.fullName.trim().toLowerCase() == ownerName.trim().toLowerCase() ||
               driver.relationship.toLowerCase().contains('self') ||
               driver.relationship.toLowerCase().contains('owner'))) {
            driver = AuthorizedDriver(
              id: driver.id,
              fullName: driver.fullName,
              relationship: driver.relationship,
              licenseNo: driver.licenseNo,
              phone: driver.phone,
              photoUrl: ownerPhoto,
            );
          }
          driversList.add(driver);
        }
      }
    }

    if (driversList.isEmpty) {
      driversList.add(AuthorizedDriver(
        id: 'drv-0',
        fullName: ownerName,
        relationship: 'Self (Owner)',
        licenseNo: 'N/A',
        photoUrl: ownerPhoto,
      ));
    }

    return VehicleRecord(
      plateNumber: plate,
      vehicleType: vehicleType,
      makeModelColor: makeModel,
      ownerName: ownerName,
      ownerRole: computedRole,
      ownerIdNumber: ownerId,
      ownerPhotoUrl: ownerPhoto,
      qrPassCode: rawPayload.isNotEmpty ? rawPayload : 'NCST-QR-$plate',
      stickerYear: stickerYear,
      vehiclePicture: vehiclePic,
      authorizedDrivers: driversList,
      isParsedFromQr: true,
      rawQrPayload: rawPayload,
      isSyncedWithDb: isSyncedWithDb || rawPayload == 'SERVER_DB_RECORD',
    );
  }
}

class AuditLogEntry {
  final String id;
  final String plateNumber;
  final String vehicleType;
  final String ownerName;
  final String driverName;
  final String? driverRelationship;
  final DateTime timeIn;
  final GateStatus status;
  final String? blockReason;

  AuditLogEntry({
    required this.id,
    required this.plateNumber,
    required this.vehicleType,
    required this.ownerName,
    required this.driverName,
    this.driverRelationship,
    required this.timeIn,
    required this.status,
    this.blockReason,
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    GateStatus status = GateStatus.inside;
    final statusStr = (json['status'] ?? '').toString().toLowerCase();
    final actionStr = (json['action'] ?? '').toString().toLowerCase();
    if (statusStr.contains('block') || actionStr.contains('block') || actionStr.contains('hold')) {
      status = GateStatus.blocked;
    }

    DateTime parsedTime = DateTime.now();
    if (json['loggedAt'] != null) {
      try {
        parsedTime = DateTime.parse(json['loggedAt'].toString());
      } catch (_) {}
    }

    return AuditLogEntry(
      id: json['id']?.toString() ?? 'LOG-${DateTime.now().millisecondsSinceEpoch}',
      plateNumber: json['plateNumber']?.toString() ?? 'N/A',
      vehicleType: json['vehicleType']?.toString() ?? '4-Wheel',
      ownerName: json['ownerName']?.toString() ?? 'Unknown',
      driverName: json['driverName']?.toString() ?? 'Driver',
      driverRelationship: json['driverRelationship']?.toString(),
      timeIn: parsedTime,
      status: status,
      blockReason: json['notes']?.toString(),
    );
  }

  bool get isInside => status == GateStatus.inside;
}
