import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:systemforinteg/services/api_service.dart';
import 'package:systemforinteg/services/local_cache_service.dart';
import 'package:systemforinteg/services/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(ApiService.resetClient);
  test(
    '401 revision request ends session without scanner fallback retry',
    () async {
      var requests = 0;
      ApiService.authToken = 'isolated-test-token';
      ApiService.setClientForTesting(
        MockClient((request) async {
          requests++;
          expect(
            request.headers['Authorization'],
            'Bearer isolated-test-token',
          );
          return http.Response(
            '{"status":"error","message":"Session revoked"}',
            401,
          );
        }),
      );
      await expectLater(ApiService.fetchUpdates(), throwsStateError);
      expect(requests, 1);
      expect(ApiService.authToken, isNull);
      expect(ApiService.sessionError.value, isNotNull);
    },
  );
  test(
    'authenticated revision snapshot preserves domain permissions',
    () async {
      ApiService.authToken = 'isolated-test-token';
      ApiService.setClientForTesting(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'status': 'success',
              'data': {
                'revisions': {'vehicles': 'v1', 'session': 's1'},
                'user': {'role': 'guard'},
              },
            }),
            200,
          ),
        ),
      );
      final update = await ApiService.fetchUpdates();
      expect(update['revisions']['vehicles'], 'v1');
      expect(update['revisions'].containsKey('staff'), isFalse);
    },
  );
  test('revision acknowledgement notifies subscribed views', () {
    final before = ApiService.liveRevision.value;
    ApiService.acknowledgeUpdates({'vehicles': 'v2'});
    expect(ApiService.revisions!['vehicles'], 'v2');
    expect(ApiService.liveRevision.value, before + 1);
  });
  test(
    'strict vehicle fetch rejects failed response instead of stale cache',
    () async {
      ApiService.setClientForTesting(
        MockClient((_) async => http.Response('{}', 503)),
      );
      await expectLater(
        ApiService.fetchVehicles(requireLive: true),
        throwsA(isA<StateError>()),
      );
    },
  );
  test(
    'strict log fetch rejects failed response instead of stale cache',
    () async {
      ApiService.setClientForTesting(
        MockClient((_) async => http.Response('{}', 503)),
      );
      await expectLater(
        ApiService.fetchLogs(requireLive: true),
        throwsA(isA<StateError>()),
      );
    },
  );
  test('empty successful log response is authoritative', () async {
    ApiService.setClientForTesting(
      MockClient(
        (_) async => http.Response('{"status":"success","data":[]}', 200),
      ),
    );
    expect(await ApiService.fetchLogs(requireLive: true), isEmpty);
  });
  test('strict settings fetch rejects unavailable backend', () async {
    ApiService.setClientForTesting(
      MockClient((_) async => http.Response('{}', 503)),
    );
    await expectLater(
      ApiService.fetchSystemSettings(requireLive: true),
      throwsStateError,
    );
  });
  test('strict settings fetch rejects malformed successful response', () async {
    ApiService.setClientForTesting(
      MockClient(
        (_) async => http.Response('{"status":"success","data":null}', 200),
      ),
    );
    await expectLater(
      ApiService.fetchSystemSettings(requireLive: true),
      throwsStateError,
    );
  });
  test(
    'worker retries an unacknowledged revision after settings failure',
    () async {
      LocalCacheService.clearMemoryCache();
      final worker = SyncQueueService();
      await worker.clearQueue();
      ApiService.authToken = 'isolated-test-token';
      var settingsAvailable = false;
      var polls = 0;
      final previousSyncTime = worker.lastSyncTimeNotifier.value;
      ApiService.setClientForTesting(
        MockClient((request) async {
          if (request.url.path.endsWith('/updates.php')) {
            polls++;
            return http.Response(
              jsonEncode({
                'status': 'success',
                'data': {
                  'revisions': {
                    'vehicles': 'v1',
                    'movements': 'm1',
                    'visitors': 'vp1',
                    'settings': 's1',
                  },
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/settings.php')) {
            return settingsAvailable
                ? http.Response(
                    '{"status":"success","data":{"visitor_pass_validity_hours":8}}',
                    200,
                  )
                : http.Response('{}', 503);
          }
          return http.Response('{"status":"success","data":[]}', 200);
        }),
      );
      await worker.processQueue();
      expect(ApiService.revisions, isNull);
      expect(worker.statusNotifier.value, SyncStatus.offline);
      expect(worker.lastSyncTimeNotifier.value, previousSyncTime);
      settingsAvailable = true;
      await worker.processQueue();
      expect(polls, 2);
      expect(ApiService.revisions!['settings'], 's1');
      expect(worker.statusNotifier.value, SyncStatus.synced);
      expect(worker.lastSyncTimeNotifier.value, isNotNull);
    },
  );
}
