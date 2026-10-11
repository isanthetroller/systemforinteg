import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:systemforinteg/features/guard/screens/guard_shell_screen.dart';
import 'package:systemforinteg/models/user_model.dart';
import 'package:systemforinteg/services/api_service.dart';
import 'package:systemforinteg/services/local_cache_service.dart';
import 'package:systemforinteg/services/sync_queue_service.dart';

void main() {
  testWidgets('mobile shows authoritative totals and changing gate policy; failure retains labelled stale values', (tester) async {
    var event = false;
    var unavailable = false;
    ApiService.authToken = 'fixture';
    LocalCacheService.clearMemoryCache();
    ApiService.setClientForTesting(MockClient((request) async {
      Object data = <String, dynamic>{};
      if (request.url.path.endsWith('/stats.php')) {
        if (unavailable) return http.Response('{"status":"error","message":"Unavailable"}', 503);
        data = {'inside': 321, 'todayEntries': 987, 'todayDenied': 654};
      } else if (request.url.path.endsWith('/gate_policy.php')) {
        if (unavailable) return http.Response('{"status":"error","message":"Unavailable"}', 503);
        data = {'mode':event ? 'event':'normal', 'modeLabel':event ? 'Event operation':'Normal operation', 'checkpoint':'Gate 2', 'allowedDirections':event ? ['Ingress','Egress']:['Egress'], 'message': event ? 'Entry and exit are authorized at both gates.' : 'Gate 1: entry. Gate 2: exit.'};
      } else if (request.url.path.endsWith('/logs.php') || request.url.path.endsWith('/vehicles.php')) {
        data = [];
      }
      return http.Response(jsonEncode({'status':'success','data':data}), 200, headers:{'content-type':'application/json'});
    }));
    final user = GuardUser(id:'2',username:'operator',fullName:'Gate Operator',badgeNumber:'TEST',role:GuardRole.exit,assignedGate:'Gate 2',loginTime:DateTime.now());
    await tester.pumpWidget(MaterialApp(home:GuardShellScreen(user:user)));
    for (var i=0;i<15;i++) { await tester.pump(const Duration(milliseconds:100)); }
    expect(find.text('321'), findsOneWidget);
    expect(find.text('987'), findsOneWidget);
    expect(find.text('654'), findsOneWidget);
    expect(find.textContaining('Normal operation'), findsOneWidget);
    event = true;
    SyncQueueService().lastSyncTimeNotifier.value = DateTime(2026,10,11,10);
    for (var i=0;i<10;i++) { await tester.pump(const Duration(milliseconds:100)); }
    expect(find.textContaining('Event operation'), findsOneWidget);
    unavailable = true;
    SyncQueueService().lastSyncTimeNotifier.value = DateTime(2026,10,11,11);
    for (var i=0;i<10;i++) { await tester.pump(const Duration(milliseconds:100)); }
    expect(find.text('Totals are from the last successful refresh'), findsOneWidget);
    expect(find.textContaining('Last known policy'), findsOneWidget);
    expect(find.text('987'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    ApiService.authToken = null;
    ApiService.resetClient();
  });
}
