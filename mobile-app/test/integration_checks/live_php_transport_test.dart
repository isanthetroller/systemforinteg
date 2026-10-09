// Real Dart mobile service/worker against disposable PHP. No phone UI or camera.
// Skipped by the default suite without the isolated wrapper's environment.
// Run via tests/mobile_php_integration.py so credentials/data stay isolated.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:systemforinteg/core/constants/api_constants.dart';
import 'package:systemforinteg/services/api_service.dart';
import 'package:systemforinteg/services/local_cache_service.dart';
import 'package:systemforinteg/services/sync_queue_service.dart';

void main() {
  final base = Platform.environment['SP_TEST_BASE'];
  test(
    'real mobile worker receives remote vehicle changes and revoked session',
    () async {
      final previousBase = ApiConstants.baseUrl;
      final worker = SyncQueueService();
      final token = Platform.environment['SP_TEST_TOKEN']!;
      final admin = Platform.environment['SP_TEST_ADMIN']!;
      ApiConstants.baseUrl = base!;
      ApiService.authToken = token;
      LocalCacheService.clearMemoryCache();
      await worker.clearQueue();
      Future<http.Response> write(
        String endpoint,
        Map<String, dynamic> body, {
        bool put = false,
      }) {
        final url = Uri.parse('$base/$endpoint');
        final headers = {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $admin',
        };
        return put
            ? http.put(url, headers: headers, body: jsonEncode(body))
            : http.post(url, headers: headers, body: jsonEncode(body));
      }

      final arrived = Completer<void>();
      final ended = Completer<void>();
      void changed() {
        if (LocalCacheService.getCachedVehicles().any(
              (v) => v.plateNumber.replaceAll(' ', '') == 'PHONE91',
            ) &&
            !arrived.isCompleted) {
          arrived.complete();
        }
      }

      void revoked() {
        if (ApiService.sessionError.value != null && !ended.isCompleted) {
          ended.complete();
        }
      }

      ApiService.liveRevision.addListener(changed);
      ApiService.sessionError.addListener(revoked);
      try {
        await worker.processQueue();
        expect(ApiService.revisions, isNotNull);
        worker.startAutoSync();
        final created = await write('vehicles.php', {
          'plateNumber': 'PHONE91',
          'vehicleType': '4-Wheel',
          'makeModelColor': 'Blue fixture car',
          'ownerName': 'Mobile fixture owner',
          'ownerRole': 'Student',
          'ownerIdNumber': 'PHONE-OWNER',
          'stickerYear': '2026',
        });
        expect(created.statusCode, 201);
        await arrived.future.timeout(const Duration(seconds: 20));
        expect(worker.statusNotifier.value, SyncStatus.synced);
        final blocked = await write('users.php', {
          'id': int.parse(Platform.environment['SP_TEST_UID']!),
          'action': 'set_status',
          'status': 'Inactive',
        }, put: true);
        expect(blocked.statusCode, 200);
        final refused = await http.get(
          Uri.parse('$base/vehicles.php'),
          headers: {'Authorization': 'Bearer $token'},
        );
        expect(refused.statusCode, 401);
        await ended.future.timeout(const Duration(seconds: 20));
        expect(ApiService.authToken, isNull);
        expect(ApiService.revisions, isNull);
      } finally {
        worker.stopAutoSync();
        ApiService.liveRevision.removeListener(changed);
        ApiService.sessionError.removeListener(revoked);
        ApiService.resetClient();
        ApiConstants.baseUrl = previousBase;
      }
    },
    skip: base == null,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
