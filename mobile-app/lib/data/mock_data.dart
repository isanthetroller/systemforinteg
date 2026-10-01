import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import '../models/vehicle_model.dart';

class MockData {
  static bool get _isTestEnv {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  static bool get isTestEnvironment => _isTestEnv;

  // Enabled by default on real devices and emulators; suppressed in test harness
  static bool useNetworkImages = !_isTestEnv;

  /// Dynamic in-memory vehicle store for runtime (starts empty)
  static final List<VehicleRecord> _runtimeVehicles = [];

  /// Dynamic registered vehicles list: Uses live runtime storage by default;
  /// test fixtures are isolated strictly to automated unit test environments.
  static List<VehicleRecord> get registeredVehicles =>
      _isTestEnv ? _testVehiclesFixture : _runtimeVehicles;

  /// Add or update vehicle record in the in-memory registered vehicles list
  static void upsertVehicle(VehicleRecord vehicle) {
    final target = _isTestEnv ? _testVehiclesFixture : _runtimeVehicles;
    final norm = vehicle.plateNumber.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final idx = target.indexWhere(
      (v) => v.plateNumber.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '') == norm,
    );
    if (idx >= 0) {
      target[idx] = vehicle;
    } else {
      target.insert(0, vehicle);
    }
  }

  /// Update vehicle campus status in memory for offline environments
  static void updateVehicleCampusStatus(String plateNumber, String newCampusStatus) {
    final target = _isTestEnv ? _testVehiclesFixture : _runtimeVehicles;
    final norm = plateNumber.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final idx = target.indexWhere(
      (v) => v.plateNumber.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '') == norm,
    );
    if (idx >= 0) {
      target[idx] = target[idx].copyWith(
        campusStatus: newCampusStatus,
        isAntiPassback: newCampusStatus.toLowerCase().contains('inside'),
      );
    }
  }

  /// Initial audit logs for the guard dashboard feed:
  /// Empty by default in production runtime. Test fixtures are only returned in automated test runs.
  static List<AuditLogEntry> getInitialAuditLogs() {
    if (_isTestEnv) {
      return _testAuditLogsFixture;
    }
    return const [];
  }

  static final List<AuditLogEntry> _testAuditLogsFixture = [
    AuditLogEntry(
      id: 'LOG-101',
      plateNumber: 'NKM-2024',
      vehicleType: 'Sedan',
      ownerName: 'Monares, Kriz',
      driverName: 'Monares, Kriz',
      driverRelationship: 'Self (Owner)',
      timeIn: DateTime.now().subtract(const Duration(minutes: 18)),
      status: GateStatus.inside,
    ),
    AuditLogEntry(
      id: 'LOG-102',
      plateNumber: 'ABC-1234',
      vehicleType: 'Sedan',
      ownerName: 'Prof. Roberto D. Reyes',
      driverName: 'Prof. Roberto D. Reyes',
      driverRelationship: 'Faculty Member',
      timeIn: DateTime.now().subtract(const Duration(minutes: 42)),
      status: GateStatus.inside,
    ),
    AuditLogEntry(
      id: 'LOG-103',
      plateNumber: 'NDK-1234',
      vehicleType: 'Sedan',
      ownerName: 'Maria Elena Gomez (Visitor)',
      driverName: 'Maria Elena Gomez',
      driverRelationship: 'Visitor / Temporary Pass',
      timeIn: DateTime.now().subtract(const Duration(hours: 1, minutes: 20)),
      status: GateStatus.inside,
    ),
    AuditLogEntry(
      id: 'LOG-104',
      plateNumber: 'WXY-9012',
      vehicleType: 'Sedan',
      ownerName: 'Christian Santos',
      driverName: 'Christian Santos',
      driverRelationship: 'Student',
      timeIn: DateTime.now().subtract(const Duration(hours: 2, minutes: 10)),
      status: GateStatus.blocked,
      blockReason: 'Flagged Student: 2nd Parking Strike / Fire Lane',
    ),
  ];

  // Internal test fixtures covering Students, Faculty, and Flagged Accounts (Unit tests only)
  static final List<VehicleRecord> _testVehiclesFixture = [
    // 1. Normal Registered Faculty Member
    VehicleRecord(
      plateNumber: 'ABC-1234',
      vehicleType: 'Sedan',
      makeModelColor: 'White Toyota Vios',
      ownerName: 'Prof. Roberto D. Reyes',
      ownerRole: 'Faculty - College of Computer Studies',
      ownerIdNumber: 'NCST-FAC-2021-019',
      qrPassCode: 'NCST-QR-ABC1234',
      ownerPhotoUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400',
      category: CampusUserCategory.employee,
      isFlagged: false,
      authorizedDrivers: [
        AuthorizedDriver(
          id: 'drv-01',
          fullName: 'Maria Elena Reyes',
          relationship: 'Spouse',
          licenseNo: 'N01-18-094821',
          photoUrl: 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=400',
        ),
        AuthorizedDriver(
          id: 'drv-02',
          fullName: 'Kyle Gabriel Reyes',
          relationship: 'Son (NCST Student)',
          licenseNo: 'N02-22-110482',
          photoUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400',
        ),
      ],
    ),

    // 2. Normal Registered Student
    VehicleRecord(
      plateNumber: 'NKM-2024',
      vehicleType: 'Sedan',
      makeModelColor: 'Metallic Gray Honda Civic',
      ownerName: 'Monares, Kriz',
      ownerRole: 'Student - BS Information Technology (3rd Year)',
      ownerIdNumber: 'NCST-2024-05182',
      qrPassCode: 'NCST-QR-NKM2024',
      ownerPhotoUrl: 'assets/images/kriz_monares.jpg',
      category: CampusUserCategory.student,
      isFlagged: false,
      authorizedDrivers: [
        AuthorizedDriver(
          id: 'drv-km-01',
          fullName: 'Monares, Kriz',
          relationship: 'Registered Owner',
          licenseNo: 'N04-24-089123',
          photoUrl: 'assets/images/kriz_monares.jpg',
        ),
        AuthorizedDriver(
          id: 'drv-km-02',
          fullName: 'Danilo Monares',
          relationship: 'Parent / Designated Driver',
          licenseNo: 'N01-19-448291',
          photoUrl: 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=400',
        ),
      ],
    ),

    // 3. Normal Student (Alternative plate NDK-4821)
    VehicleRecord(
      plateNumber: 'NDK-4821',
      vehicleType: 'Sedan',
      makeModelColor: 'White Toyota Vios',
      ownerName: 'Kriz Monares',
      ownerRole: 'Student - BS Information Technology',
      ownerIdNumber: 'NCST-2024-05182',
      qrPassCode: 'NCST-QR-NDK4821',
      ownerPhotoUrl: 'assets/images/kriz_monares.jpg',
      category: CampusUserCategory.student,
      isFlagged: false,
      authorizedDrivers: [
        AuthorizedDriver(
          id: 'drv-ndk-01',
          fullName: 'Kriz Monares',
          relationship: 'Self (Owner)',
          licenseNo: 'N01-19-094821',
          photoUrl: 'assets/images/kriz_monares.jpg',
        ),
      ],
    ),

    // 4. FLAGGED STUDENT (Crucial Requirement: Student flagged for violations)
    VehicleRecord(
      plateNumber: 'WXY-9012',
      vehicleType: 'Sedan',
      makeModelColor: 'Midnight Black Honda City',
      ownerName: 'Christian Santos',
      ownerRole: 'Student - BS Business Administration (4th Year)',
      ownerIdNumber: 'NCST-2022-09412',
      qrPassCode: 'NCST-QR-WXY9012',
      ownerPhotoUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400',
      category: CampusUserCategory.student,
      isFlagged: true,
      flagReason: '2nd Parking Strike: Blocking Campus Emergency Fire Lane',
      flaggedAt: DateTime(2026, 9, 20),
      authorizedDrivers: [
        AuthorizedDriver(
          id: 'drv-wxy-01',
          fullName: 'Christian Santos',
          relationship: 'Self (Owner)',
          licenseNo: 'N02-21-998811',
          photoUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400',
        ),
      ],
    ),

    // 5. FLAGGED EMPLOYEE / FACULTY (Crucial Requirement: Employee flagged status)
    VehicleRecord(
      plateNumber: 'DEF-5678',
      vehicleType: 'SUV',
      makeModelColor: 'Silver Toyota Fortuner',
      ownerName: 'Engr. Danilo Ramos',
      ownerRole: 'Faculty - College of Engineering',
      ownerIdNumber: 'NCST-FAC-2018-042',
      qrPassCode: 'NCST-QR-DEF5678',
      ownerPhotoUrl: 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=400',
      category: CampusUserCategory.employee,
      isFlagged: true,
      flagReason: 'Security Hold: Expired Campus Parking Decal & Reserved Stall Violation',
      flaggedAt: DateTime(2026, 9, 15),
      authorizedDrivers: [
        AuthorizedDriver(
          id: 'drv-def-01',
          fullName: 'Engr. Danilo Ramos',
          relationship: 'Faculty Member',
          licenseNo: 'N01-16-778811',
          photoUrl: 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=400',
        ),
      ],
    ),

    // 6. Registered Staff & Logistics Van
    VehicleRecord(
      plateNumber: 'TAA-4432',
      vehicleType: 'Van',
      makeModelColor: 'Dark Gray Nissan Urvan',
      ownerName: 'NCST Campus Facilities Department',
      ownerRole: 'Administrative Staff & Logistics',
      ownerIdNumber: 'NCST-STAFF-1002',
      qrPassCode: 'NCST-QR-TAA4432',
      ownerPhotoUrl: 'https://images.unsplash.com/photo-1560250097-0b93528c311a?w=400',
      category: CampusUserCategory.employee,
      isFlagged: false,
      authorizedDrivers: [
        AuthorizedDriver(
          id: 'drv-06',
          fullName: 'Danilo Cruz',
          relationship: 'Official Campus Driver',
          licenseNo: 'N01-12-384729',
          photoUrl: 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=400',
        ),
      ],
    ),
  ];
}
