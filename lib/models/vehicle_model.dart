enum GateStatus { inside, exited, blocked }

/// Distinct user categories in NCST campus access management
enum CampusUserCategory {
  student,
  employee, // Faculty or staff member
  visitor,  // Temporary guest with visitor pass
}

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

  // Role, Banned, and Status attributes
  final CampusUserCategory category;
  final bool isFlagged;
  final String? flagReason;
  final DateTime? flaggedAt;
  final bool isBanned;
  final String? campusStatus;
  final bool isAntiPassback;

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
    this.category = CampusUserCategory.student,
    this.isFlagged = false,
    this.flagReason,
    this.flaggedAt,
    this.isBanned = false,
    this.campusStatus,
    this.isAntiPassback = false,
  });

  /// IMPORTANT ARCHITECTURAL CONSTRAINT:
  /// Only student and employee records can have the flagged status.
  /// Visitors using temporary QR passes should never receive student/employee flagged status.
  bool get canBeFlagged => category == CampusUserCategory.student || category == CampusUserCategory.employee;
  bool get hasActiveFlag => canBeFlagged && isFlagged;

  /// Operational security rule: Banned, suspended, revoked, or forged vehicles/passes must be blocked at gate
  bool get isAccessDenied => isBanned ||
      (campusStatus != null && (
          campusStatus!.toLowerCase().contains('ban') ||
          campusStatus!.toLowerCase().contains('suspend') ||
          campusStatus!.toLowerCase().contains('revok') ||
          campusStatus!.toLowerCase().contains('forg')));

  /// Pass validity evaluation: Is this an unverified or unregistered visitor vehicle?
  bool get isUnregistered =>
      ownerRole.contains('Unverified') ||
      ownerRole.contains('Unregistered') ||
      ownerName.contains('Unregistered') ||
      ownerIdNumber == 'UNKNOWN';

  String get categoryDisplay {
    switch (category) {
      case CampusUserCategory.student:
        return 'Student';
      case CampusUserCategory.employee:
        return 'Faculty / Employee';
      case CampusUserCategory.visitor:
        return 'Campus Visitor';
    }
  }

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

    // Categorization logic
    CampusUserCategory category = CampusUserCategory.student;
    final lowerRole = computedRole.toLowerCase();
    final upperId = ownerId.toUpperCase();
    if (upperId.contains('FAC') || lowerRole.contains('facult') || lowerRole.contains('employee') || lowerRole.contains('staff') || lowerRole.contains('prof')) {
      category = CampusUserCategory.employee;
    } else if (upperId.contains('VIS') || lowerRole.contains('visitor') || lowerRole.contains('guest')) {
      category = CampusUserCategory.visitor;
    }

    // Flagged status evaluation: strictly restricted to students and employees!
    final rawIsFlagged = json['isFlagged'] == true ||
        json['is_flagged'] == 1 ||
        json['is_flagged'] == '1' ||
        json['is_flagged'] == true ||
        (json['flagReason'] != null && json['flagReason'].toString().trim().isNotEmpty);

    final isFlagged = (category == CampusUserCategory.student || category == CampusUserCategory.employee) && rawIsFlagged;
    final flagReason = isFlagged
        ? (json['flagReason'] ?? json['flag_reason'] ?? 'Security Alert / Violation on Record').toString()
        : null;

    DateTime? flaggedAt;
    if (json['flaggedAt'] != null) {
      flaggedAt = DateTime.tryParse(json['flaggedAt'].toString());
    }

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

    final isBanned = json['isBanned'] == true ||
        json['is_banned'] == 1 ||
        json['is_banned'] == '1' ||
        json['is_banned'] == true ||
        (json['status'] ?? '').toString().toLowerCase().contains('suspend') ||
        (json['status'] ?? '').toString().toLowerCase().contains('ban');

    final campusStatus = (json['status'] ?? json['campusStatus'] ?? json['campus_status'])?.toString();
    final isAntiPassback = json['currentlyInside'] == true ||
        (campusStatus != null && campusStatus.toLowerCase().contains('inside'));

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
      category: category,
      isFlagged: isFlagged,
      flagReason: flagReason,
      flaggedAt: flaggedAt,
      isBanned: isBanned,
      campusStatus: campusStatus,
      isAntiPassback: isAntiPassback,
    );
  }

  VehicleRecord copyWith({
    String? plateNumber,
    String? vehicleType,
    String? makeModelColor,
    String? ownerName,
    String? ownerRole,
    String? ownerIdNumber,
    String? qrPassCode,
    String? stickerYear,
    String? ownerPhotoUrl,
    String? vehiclePicture,
    List<AuthorizedDriver>? authorizedDrivers,
    bool? isParsedFromQr,
    String? rawQrPayload,
    bool? isSyncedWithDb,
    CampusUserCategory? category,
    bool? isFlagged,
    String? flagReason,
    DateTime? flaggedAt,
    bool? isBanned,
    String? campusStatus,
    bool? isAntiPassback,
  }) {
    return VehicleRecord(
      plateNumber: plateNumber ?? this.plateNumber,
      vehicleType: vehicleType ?? this.vehicleType,
      makeModelColor: makeModelColor ?? this.makeModelColor,
      ownerName: ownerName ?? this.ownerName,
      ownerRole: ownerRole ?? this.ownerRole,
      ownerIdNumber: ownerIdNumber ?? this.ownerIdNumber,
      qrPassCode: qrPassCode ?? this.qrPassCode,
      stickerYear: stickerYear ?? this.stickerYear,
      ownerPhotoUrl: ownerPhotoUrl ?? this.ownerPhotoUrl,
      vehiclePicture: vehiclePicture ?? this.vehiclePicture,
      authorizedDrivers: authorizedDrivers ?? this.authorizedDrivers,
      isParsedFromQr: isParsedFromQr ?? this.isParsedFromQr,
      rawQrPayload: rawQrPayload ?? this.rawQrPayload,
      isSyncedWithDb: isSyncedWithDb ?? this.isSyncedWithDb,
      category: category ?? this.category,
      isFlagged: isFlagged ?? this.isFlagged,
      flagReason: flagReason ?? this.flagReason,
      flaggedAt: flaggedAt ?? this.flaggedAt,
      isBanned: isBanned ?? this.isBanned,
      campusStatus: campusStatus ?? this.campusStatus,
      isAntiPassback: isAntiPassback ?? this.isAntiPassback,
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
  final String action;
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
    this.action = 'Entry Recorded',
    required this.status,
    this.blockReason,
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    GateStatus status = GateStatus.inside;
    final statusStr = (json['status'] ?? '').toString().toLowerCase();
    final actionStr = (json['action'] ?? '').toString().toLowerCase();
    if (statusStr.contains('block') || actionStr.contains('block') || actionStr.contains('hold') || actionStr.contains('denied')) {
      status = GateStatus.blocked;
    } else if (statusStr.contains('exit') || statusStr.contains('depart') || actionStr.contains('exit') || actionStr.contains('egress')) {
      status = GateStatus.exited;
    }

    final action = (json['action'] ?? (status == GateStatus.exited ? 'Exit Approved' : (status == GateStatus.blocked ? 'Entry Denied' : 'Entry Recorded'))).toString();

    DateTime parsedTime = DateTime.now();
    if (json['loggedAt'] != null) {
      try {
        parsedTime = DateTime.parse(json['loggedAt'].toString());
      } catch (_) {}
    }

    return AuditLogEntry(
      id: json['id']?.toString() ?? 'LOG-${DateTime.now().millisecondsSinceEpoch}',
      plateNumber: (json['plateNumber'] ?? json['plate_number'] ?? json['plate'])?.toString() ?? 'N/A',
      vehicleType: (json['vehicleType'] ?? json['vehicle_type'])?.toString() ?? '4-Wheel',
      ownerName: (json['ownerName'] ?? json['owner_name'])?.toString() ?? 'Unknown',
      driverName: (json['driverName'] ?? json['driver_name'])?.toString() ?? 'Driver',
      driverRelationship: (json['driverRelationship'] ?? json['driver_relationship'])?.toString(),
      timeIn: parsedTime,
      action: action,
      status: status,
      blockReason: (json['notes'] ?? json['blockReason'])?.toString(),
    );
  }

  bool get isInside => status == GateStatus.inside;
  bool get isExited => status == GateStatus.exited;
  bool get isBlocked => status == GateStatus.blocked;

  Map<String, dynamic> toJson() => {
    'id': id,
    'plateNumber': plateNumber,
    'vehicleType': vehicleType,
    'ownerName': ownerName,
    'driverName': driverName,
    if (driverRelationship != null) 'driverRelationship': driverRelationship,
    'loggedAt': timeIn.toIso8601String(),
    'action': action,
    'status': status == GateStatus.blocked
        ? 'Blocked'
        : (status == GateStatus.exited ? 'Exited' : 'Inside Campus'),
    if (blockReason != null) 'notes': blockReason,
  };
}
