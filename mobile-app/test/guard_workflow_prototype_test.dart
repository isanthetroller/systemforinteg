import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:systemforinteg/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:systemforinteg/models/user_model.dart';
import 'package:systemforinteg/models/vehicle_model.dart';
import 'package:systemforinteg/models/visitor_pass_model.dart';
import 'package:systemforinteg/repositories/auth_repository.dart';
import 'package:systemforinteg/repositories/visitor_repository.dart';
import 'package:systemforinteg/services/auth_service.dart';

void main() {
  setUp(() {
    AuthService().setRepository(MockAuthRepository());
    ApiService.setClientForTesting(
      MockClient(
        (request) async =>
            http.Response(jsonEncode({'status': 'success', 'data': null}), 200),
      ),
    );
  });
  tearDown(ApiService.resetClient);

  group('1. Authentication & Role Determination', () {
    test('Login as Guard 1 routes to Entrance role and Gate 1', () async {
      final authRepo = MockAuthRepository();
      final user = await authRepo.login(
        username: 'guard1',
        password: 'password123',
      );

      expect(user.role, GuardRole.entrance);
      expect(user.isEntranceGuard, isTrue);
      expect(user.isExitGuard, isFalse);
      expect(user.assignedGate, contains('Gate 1'));
    });

    test('Login as Guard 2 routes to Exit role and Gate 2', () async {
      final authRepo = MockAuthRepository();
      final user = await authRepo.login(
        username: 'guard2',
        password: 'password123',
      );

      expect(user.role, GuardRole.exit);
      expect(user.isEntranceGuard, isFalse);
      expect(user.isExitGuard, isTrue);
      expect(user.assignedGate, contains('Gate 2'));
    });

    test('Login with short password throws AuthException', () async {
      final authRepo = MockAuthRepository();
      expect(
        () => authRepo.login(username: 'guard1', password: '12'),
        throwsA(isA<AuthException>()),
      );
    });

    test('AuthService maintains active session state', () async {
      final service = AuthService();
      await service.login(username: 'guard1', password: 'password123');

      expect(service.isAuthenticated, isTrue);
      expect(service.currentUser?.username, 'guard1');

      await service.logout();
      expect(service.isAuthenticated, isFalse);
      expect(service.currentUser, isNull);
    });
  });

  group('2. Visitor Registration & Temporary QR Pass', () {
    test(
      'Create temporary visitor pass with 8-hour expiry and unique ID',
      () async {
        final repo = VisitorRepository();
        final now = DateTime.now();

        final pass = VisitorPass(
          passId: 'NCST-VIS-2026-TEST-99',
          visitorName: 'Juan Dela Cruz',
          plateNumber: 'ABC-9999',
          vehiclePhotoUrl: 'assets/images/kriz_monares.jpg',
          entryTime: now,
          expiryTime: now.add(const Duration(hours: 8)),
          status: VisitorPassStatus.active,
          registeredByGuard: 'Officer J. Hernandez',
          gatePoint: 'Gate 1 (Main Ingress)',
        );

        await repo.registerPass(pass);

        // Verify pass retrieval by ID
        final retrieved = await repo.lookupPass('NCST-VIS-2026-TEST-99');
        expect(retrieved, isNotNull);
        expect(retrieved!.visitorName, 'Juan Dela Cruz');
        expect(retrieved.plateNumber, 'ABC-9999');
        expect(retrieved.isActive, isTrue);
        expect(retrieved.isExpired, isFalse);
      },
    );

    test('Structured QR serialization and parsing preserve integrity', () {
      final now = DateTime.now();
      final pass = VisitorPass(
        passId: 'NCST-VIS-QR-TEST',
        visitorName: 'Maria Elena Santos',
        plateNumber: 'NCR-5544',
        entryTime: now,
        expiryTime: now.add(const Duration(hours: 8)),
        status: VisitorPassStatus.active,
        registeredByGuard: 'Officer Hernandez',
        gatePoint: 'Gate 1 (Main Ingress)',
      );

      final qrPayload = pass.toQrPayload();
      expect(qrPayload, contains('NCST_VISITOR_PASS'));
      expect(qrPayload, contains('NCST-VIS-QR-TEST'));
      expect(qrPayload, contains('Maria Elena Santos'));

      final parsed = VisitorPass.fromQrPayload(qrPayload);
      expect(parsed, isNotNull);
      expect(parsed!.passId, 'NCST-VIS-QR-TEST');
      expect(parsed.visitorName, 'Maria Elena Santos');
      expect(parsed.plateNumber, 'NCR-5544');
    });

    test('Visitor Checkout updates status to used and sets exitTime', () async {
      final repo = VisitorRepository();
      final pass = await repo.lookupPass('NCST-VIS-2026-TEST-99');
      expect(pass, isNotNull);

      final success = await repo.checkoutPass('NCST-VIS-2026-TEST-99');
      expect(success, isTrue);

      final updated = await repo.lookupPass('NCST-VIS-2026-TEST-99');
      expect(updated!.isUsed, isTrue);
      expect(updated.status, VisitorPassStatus.used);
      expect(updated.exitTime, isNotNull);
    });
  });

  group('3. Student/Employee Flagged Feature Constraint Rule', () {
    test('Only Students and Employees can be Flagged', () {
      // 1. Student can be flagged
      const student = VehicleRecord(
        plateNumber: 'WXY-9012',
        vehicleType: 'Sedan',
        makeModelColor: 'Black Honda City',
        ownerName: 'Christian Santos',
        ownerRole: 'Student',
        ownerIdNumber: 'NCST-2022-09412',
        qrPassCode: 'NCST-QR-WXY9012',
        authorizedDrivers: [],
        category: CampusUserCategory.student,
        isFlagged: true,
        flagReason: '2nd Parking Strike',
      );
      expect(student.canBeFlagged, isTrue);
      expect(student.hasActiveFlag, isTrue);

      // 2. Employee can be flagged
      const employee = VehicleRecord(
        plateNumber: 'DEF-5678',
        vehicleType: 'SUV',
        makeModelColor: 'Silver Fortuner',
        ownerName: 'Engr. Danilo Ramos',
        ownerRole: 'Faculty Member',
        ownerIdNumber: 'NCST-FAC-2018-042',
        qrPassCode: 'NCST-QR-DEF5678',
        authorizedDrivers: [],
        category: CampusUserCategory.employee,
        isFlagged: true,
        flagReason: 'Expired Campus Decal',
      );
      expect(employee.canBeFlagged, isTrue);
      expect(employee.hasActiveFlag, isTrue);

      // 3. Visitor MUST NOT have flagged status
      const visitor = VehicleRecord(
        plateNumber: 'VIS-9999',
        vehicleType: 'Sedan',
        makeModelColor: 'White Vios',
        ownerName: 'Guest Visitor',
        ownerRole: 'Campus Visitor',
        ownerIdNumber: 'VIS-001',
        qrPassCode: 'NCST-VIS-001',
        authorizedDrivers: [],
        category: CampusUserCategory.visitor,
        isFlagged: true, // Attempt to set flagged on visitor
      );
      // STRICT RULE VERIFICATION:
      expect(visitor.canBeFlagged, isFalse);
      expect(
        visitor.hasActiveFlag,
        isFalse,
      ); // hasActiveFlag is guarded and evaluates to false!
    });
  });

  group('4. Exit Pass Verification States', () {
    final repo = VisitorRepository();

    test('Valid pass is recognized as active', () async {
      final pass = await repo.lookupPass('NCST-VIS-2026-1001');
      expect(pass, isNotNull);
      expect(pass!.status, VisitorPassStatus.active);
    });

    test('Expired pass is recognized with overtime status', () async {
      final pass = await repo.lookupPass('NCST-VIS-2026-1002');
      expect(pass, isNotNull);
      expect(pass!.isExpired, isTrue);
      expect(pass.status, VisitorPassStatus.expired);
    });

    test('Blocked pass is recognized with access hold', () async {
      final pass = await repo.lookupPass('NCST-VIS-2026-1003');
      expect(pass, isNotNull);
      expect(pass!.isBlocked, isTrue);
      expect(pass.status, VisitorPassStatus.blocked);
    });

    test('Already used pass is recognized with previous checkout', () async {
      final pass = await repo.lookupPass('NCST-VIS-2026-1004');
      expect(pass, isNotNull);
      expect(pass!.isUsed, isTrue);
      expect(pass.status, VisitorPassStatus.used);
    });
  });
}
