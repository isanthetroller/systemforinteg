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

  /// Dynamic registered vehicles list: Empty in production runtime
  static List<VehicleRecord> get registeredVehicles => _isTestEnv ? _testVehicles : const [];

  /// Initial audit logs: Empty in production runtime
  static List<AuditLogEntry> getInitialAuditLogs() => <AuditLogEntry>[];

  // Internal test fixtures used strictly by offline unit/widget tests
  static final List<VehicleRecord> _testVehicles = [
    VehicleRecord(
      plateNumber: 'ABC-1234',
      vehicleType: 'Sedan',
      makeModelColor: 'White Toyota Vios',
      ownerName: 'Prof. Roberto D. Reyes',
      ownerRole: 'Faculty - College of Computer Studies',
      ownerIdNumber: 'NCST-FAC-2021-019',
      qrPassCode: 'NCST-QR-ABC1234',
      ownerPhotoUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400',
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
    VehicleRecord(
      plateNumber: 'NKM-2024',
      vehicleType: 'Sedan',
      makeModelColor: 'Metallic Gray Honda Civic',
      ownerName: 'Monares, Kriz',
      ownerRole: 'Student - BS Information Technology (3rd Year)',
      ownerIdNumber: 'NCST-2024-05182',
      qrPassCode: 'NCST-QR-NKM2024',
      ownerPhotoUrl: 'assets/images/kriz_monares.jpg',
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
    VehicleRecord(
      plateNumber: 'NCY-8821',
      vehicleType: 'Motorcycle',
      makeModelColor: 'Matte Black Yamaha NMAX',
      ownerName: 'Christian Jay Alcantara',
      ownerRole: 'Student - BS Information Technology (3rd Year)',
      ownerIdNumber: 'NCST-2023-04812',
      qrPassCode: 'NCST-QR-NCY8821',
      ownerPhotoUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400',
      authorizedDrivers: [
        AuthorizedDriver(
          id: 'drv-03',
          fullName: 'Mark Alcantara',
          relationship: 'Brother',
          licenseNo: 'N03-20-449102',
          photoUrl: 'https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?w=400',
        ),
      ],
    ),
    VehicleRecord(
      plateNumber: 'WDX-5901',
      vehicleType: 'SUV',
      makeModelColor: 'Silver Mitsubishi Montero',
      ownerName: 'Dr. Evelyn Santos-Bautista',
      ownerRole: 'Dean - College of Engineering',
      ownerIdNumber: 'NCST-ADM-2015-004',
      qrPassCode: 'NCST-QR-WDX5901',
      ownerPhotoUrl: 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=400',
      authorizedDrivers: [
        AuthorizedDriver(
          id: 'drv-04',
          fullName: 'Rolando Bautista',
          relationship: 'Spouse / Designated Driver',
          licenseNo: 'N01-15-883912',
          photoUrl: 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=400',
        ),
        AuthorizedDriver(
          id: 'drv-05',
          fullName: 'Eunice Bautista',
          relationship: 'Daughter',
          licenseNo: 'N02-23-993811',
          photoUrl: 'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=400',
        ),
      ],
    ),
    VehicleRecord(
      plateNumber: 'TAA-4432',
      vehicleType: 'Van',
      makeModelColor: 'Dark Gray Nissan Urvan',
      ownerName: 'NCST Campus Facilities Department',
      ownerRole: 'Administrative Staff & Logistics',
      ownerIdNumber: 'NCST-STAFF-1002',
      qrPassCode: 'NCST-QR-TAA4432',
      ownerPhotoUrl: 'https://images.unsplash.com/photo-1560250097-0b93528c311a?w=400',
      authorizedDrivers: [
        AuthorizedDriver(
          id: 'drv-06',
          fullName: 'Danilo Cruz',
          relationship: 'Official Campus Driver',
          licenseNo: 'N01-12-384729',
          photoUrl: 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=400',
        ),
        AuthorizedDriver(
          id: 'drv-07',
          fullName: 'Edgar Ramos',
          relationship: 'Backup Maintenance Driver',
          licenseNo: 'N01-14-884712',
          photoUrl: 'https://images.unsplash.com/photo-1522075469751-3a6694fb2f61?w=400',
        ),
      ],
    ),
  ];
}
