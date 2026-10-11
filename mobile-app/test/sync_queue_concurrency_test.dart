import 'dart:async';
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
    'an event queued during an in-flight sync is retained and delivered',
    () async {
      LocalCacheService.clearMemoryCache();
      final worker = SyncQueueService();
      await worker.clearQueue();
      ApiService.authToken = 'test-guard';
      final started = Completer<void>();
      final release = Completer<void>();
      final delivered = <String>[];
      ApiService.setClientForTesting(
        MockClient((request) async {
          if (request.url.path.endsWith('/sync.php')) {
            final events = (jsonDecode(request.body)['events'] as List);
            if (!started.isCompleted) {
              started.complete();
              await release.future;
            }
            delivered.addAll(events.map((e) => e['client_ref'] as String));
            return http.Response(
              jsonEncode({
                'status': 'success',
                'data': {
                  'results': events
                      .map(
                        (e) => {
                          'client_ref': e['client_ref'],
                          'status': 'accepted',
                        },
                      )
                      .toList(),
                },
              }),
              200,
            );
          }
          return http.Response(
            '{"status":"success","data":{"revisions":{}}}',
            200,
          );
        }),
      );
      await worker.enqueue(
        type: 'incident',
        payload: {'plate': 'RACE-1'},
        clientRef: 'race-first',
      );
      final sync = worker.processQueue();
      await started.future;
      await worker.enqueue(
        type: 'incident',
        payload: {'plate': 'RACE-2'},
        clientRef: 'race-second',
      );
      release.complete();
      await sync;
      expect(delivered, ['race-first', 'race-second']);
      expect(LocalCacheService.getSyncQueue(), isEmpty);
    },
  );
}
