import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:systemforinteg/core/constants/api_constants.dart';
import 'package:systemforinteg/services/api_service.dart';
import 'package:systemforinteg/services/local_cache_service.dart';
import 'package:systemforinteg/services/sync_queue_service.dart';

class FailedDiskPreferences implements SharedPreferences {
  @override
  String? getString(String key) => null;
  @override
  Future<bool> setString(String key, String value) async => throw StateError('Injected disk-full failure');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final worker = SyncQueueService();
  final originalBase = ApiConstants.baseUrl;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocalCacheService.setMockPrefs(await SharedPreferences.getInstance());
    LocalCacheService.clearMemoryCache();
    ApiService.authToken = 'queue-fixture';
    ApiConstants.baseUrl = 'http://server-a.invalid/api';
    await worker.clearQueue();
  });
  tearDown(() {
    worker.stopAutoSync();
    ApiConstants.baseUrl = originalBase;
    ApiService.resetClient();
  });
  Future<void> enqueue(String ref) => worker.enqueue(type:'incident',clientRef:ref,payload:{'plate':'ADVERSE','reason':'Fixture observation'});

  for (final mode in ['http503','invalid_json','missing_results','unknown_status','connection_reset']) {
    test('queue survives $mode without false acknowledgement',() async {
      await enqueue('queue-original');
      ApiService.setClientForTesting(MockClient((request) async {
        if (mode == 'connection_reset') throw http.ClientException('Injected disconnect');
        if (mode == 'http503') return http.Response('{"status":"error"}',503);
        if (mode == 'invalid_json') return http.Response('<html>Failure</html>',200);
        if (mode == 'missing_results') return http.Response('{"status":"success","data":{}}',200);
        return http.Response('{"status":"success","data":{"results":[{"client_ref":"queue-original","status":"unexpected"}]}}',200);
      }));
      await worker.processQueue();
      expect(LocalCacheService.getSyncQueue().map((x)=>x['clientRef']),['queue-original']);
      expect(worker.status,SyncStatus.offline);
    });
  }

  test('only explicitly acknowledged events leave a partially answered batch',() async {
    await enqueue('queue-accepted');await enqueue('queue-unanswered');
    ApiService.setClientForTesting(MockClient((request) async => http.Response('{"status":"success","data":{"results":[{"client_ref":"queue-accepted","status":"accepted"}]}}',200)));
    await worker.processQueue();
    expect(LocalCacheService.getSyncQueue().map((x)=>x['clientRef']),['queue-unanswered']);
  });

  test('persisted pending event survives loss of the in-memory cache',() async {
    await enqueue('queue-persisted');
    LocalCacheService.clearMemoryCache();
    expect(LocalCacheService.getSyncQueue().map((x)=>x['clientRef']),['queue-persisted']);
  });

  test('failed persistent write is surfaced before claiming an event was queued',() async {
    LocalCacheService.setMockPrefs(FailedDiskPreferences());
    var reportedFailure = false;
    try { await enqueue('queue-disk-full'); } catch (_) { reportedFailure = true; }
    LocalCacheService.clearMemoryCache(); // Model process death after memory-only acknowledgement.
    expect(reportedFailure || LocalCacheService.getSyncQueue().isNotEmpty,isTrue,
      reason:'enqueue completed normally although a restart would lose the only pending copy');
  });

  test('corrupt queue data is not reported as an empty successful queue',() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LocalCacheService.keySyncQueue,'[{"clientRef":"queue-corrupt"');
    ApiService.setClientForTesting(MockClient((request) async => http.Response('{"status":"success","data":{"revisions":{}}}',200)));
    await worker.processQueue();
    expect(worker.status, isNot(SyncStatus.synced),reason:'Unreadable pending data must surface a recovery problem, not synced success');
  });

  test('one damaged queue element does not hide all other valid events',() async {
    await enqueue('queue-good');
    final good = LocalCacheService.getSyncQueue().single;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LocalCacheService.keySyncQueue,jsonEncode([good,42]));
    expect(LocalCacheService.getSyncQueue().any((x)=>x['clientRef']=='queue-good'),isTrue,
      reason:'A malformed neighbour must not hide a recoverable event');
  });

  test('pending events from server A must not be sent to server B',() async {
    await enqueue('queue-server-a');
    final delivered = <String>[];
    ApiConstants.baseUrl = 'http://server-b.invalid/api';
    await LocalCacheService.setServerBaseUrl(ApiConstants.baseUrl);
    ApiService.authToken = 'server-b-account';
    ApiService.setClientForTesting(MockClient((request) async {
      if (request.url.path.endsWith('/sync.php')) {
        delivered.add(request.url.host);
        final events = jsonDecode(request.body)['events'] as List;
        return http.Response(jsonEncode({'status':'success','data':{'results':events.map((x)=>{'client_ref':x['client_ref'],'status':'accepted'}).toList()}}),200);
      }
      return http.Response('{"status":"success","data":{"revisions":{}}}',200);
    }));
    await worker.processQueue();
    expect(delivered, isEmpty,reason:'Queue storage must retain the originating server/account context');
    expect(LocalCacheService.getSyncQueue(),isNotEmpty);
  });
}
