// Run only through tests/visitor_web_roundtrip.py against disposable PHP/SQLite.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:systemforinteg/core/constants/api_constants.dart';
import 'package:systemforinteg/models/visitor_pass_model.dart';
import 'package:systemforinteg/services/api_service.dart';
import 'package:systemforinteg/services/sync_queue_service.dart';

void main() {
  final base = Platform.environment['SP_TEST_BASE'];
  test('created guard issues visitor, records entry and exit for web audit', () async {
    final originalBase = ApiConstants.baseUrl;
    final signal = Directory(Platform.environment['SP_TEST_SIGNAL']!);
    final plate = Platform.environment['SP_TEST_PLATE']!;
    final name = Platform.environment['SP_TEST_VISITOR']!;
    Future<void> checkpoint(String phase) async {
      File('${signal.path}/$phase.ready').writeAsStringSync('ready');
      final release = File('${signal.path}/$phase.release');
      for (var i = 0; i < 200 && !release.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(release.existsSync(), isTrue, reason: '$phase web assertion timed out');
    }

    ApiConstants.baseUrl = base!;
    try {
      final login = await ApiService.login(
        username: Platform.environment['SP_TEST_USER']!,
        password: Platform.environment['SP_TEST_PASSWORD']!,
      );
      expect(login, isNotNull);
      expect(ApiService.authToken, isNotNull);

      final now = DateTime.now();
      final pass = VisitorPass(
        passId: 'VP-ROUNDTRIP-${now.millisecondsSinceEpoch}',
        visitorName: name,
        plateNumber: plate,
        entryTime: now,
        expiryTime: now.add(const Duration(hours: 8)),
        registeredByGuard: 'Roundtrip Guard',
        gatePoint: 'Checkpoint 1',
        contactNumber: '09123456789',
        vehicleModel: 'Blue van',
        purposeOfVisit: 'Deliver laboratory supplies',
        personToVisit: 'Science Office',
        items: const [{'name': 'Supply box', 'quantity': 2, 'description': 'Sealed'}],
      );
      expect(await ApiService.postVisitorPass(pass), isTrue);
      expect(ApiService.lastWriteQueued, isFalse);
      final saved = ApiService.lastCreatedVisitorPass!;
      expect(saved.dbId, greaterThan(0));
      expect((await ApiService.lookupVisitorPass(plate))?.passId, saved.passId);
      expect(await ApiService.postVisitorPass(pass), isFalse);
      await checkpoint('created');

      expect(await ApiService.postGateLog(
        plateNumber: plate, driverName: name, visitorPassId: saved.dbId,
        action: 'Entry Recorded', itemsVerified: false,
      ), isFalse, reason: 'declared items must be checked');
      expect(await ApiService.postGateLog(
        plateNumber: plate, driverName: name, visitorPassId: saved.dbId,
        action: 'Entry Recorded', itemsVerified: true,
      ), isTrue);
      await checkpoint('entered');

      expect(await ApiService.postGateLog(
        plateNumber: plate, driverName: name, visitorPassId: saved.dbId,
        action: 'Exit Approved', status: 'Exited', itemsVerified: true,
      ), isTrue);
      await checkpoint('exited');
    } finally {
      await ApiService.logout();
      ApiService.resetClient();
      ApiConstants.baseUrl = originalBase;
      SyncQueueService().stopAutoSync();
    }
  }, skip: base == null, timeout: const Timeout(Duration(seconds: 110)));
}
