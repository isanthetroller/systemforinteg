import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'local_cache_service.dart';

/// One event that happened at the gate and is waiting to reach the server.
class QueueItem {
  final String id;
  final String type; // 'gate_log', 'visitor_pass', 'visitor_exit', 'incident'
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  /// Unique reference of this event. The server ignores a repeat, so sending it twice can never
  /// create a second log (for example when the reply to the first attempt was lost).
  final String clientRef;

  /// When it really happened at the gate. The server records this time, not the time it syncs.
  final DateTime occurredAt;
  int retryCount;

  QueueItem({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    String? clientRef,
    DateTime? occurredAt,
    this.retryCount = 0,
  })  : clientRef = clientRef ?? SyncQueueService.safeRef(id),
        occurredAt = occurredAt ?? createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
        'clientRef': clientRef,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        'retryCount': retryCount,
      };

  /// The shape /api/sync.php expects.
  Map<String, dynamic> toSyncEvent() => {
        'client_ref': clientRef,
        'type': type,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'payload': payload,
      };

  factory QueueItem.fromJson(Map<String, dynamic> json) {
    final created = json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
        : DateTime.now();
    final id = json['id']?.toString() ?? 'q-${DateTime.now().millisecondsSinceEpoch}';
    return QueueItem(
      id: id,
      type: json['type']?.toString() ?? 'gate_log',
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      createdAt: created,
      // Items queued by an older version of the app have neither: fall back to the queue id / creation time
      clientRef: json['clientRef']?.toString(),
      occurredAt: json['occurredAt'] != null ? DateTime.tryParse(json['occurredAt'].toString()) : null,
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
    );
  }
}

enum SyncStatus {
  synced,
  syncing,
  offline,
}

/// Offline queue manager.
///
/// When the connection drops, gate events are saved on the phone with the time they happened.
/// The queue is checked every few seconds (and when the app comes back to the foreground), so the
/// moment a connection is back everything is sent, oldest first, in batches to /api/sync.php.
///
/// - A connection problem, or a temporary server error (the server answers "retry"), keeps an event queued and retried.
/// - An event the server refuses for good (for example older than 24 hours) is taken out of the
///   queue and kept in [LocalCacheService.getRejectedSync] so it can be reviewed, instead of
///   blocking everything behind it.
/// - A resend is harmless: the server recognises the event's [QueueItem.clientRef].
class SyncQueueService {
  static final SyncQueueService _instance = SyncQueueService._internal();
  factory SyncQueueService() => _instance;

  SyncQueueService._internal();

  static const int _batchSize = 50;

  /// An event the server keeps answering "retry" to (or not answering at all) is moved to the review list after this
  /// many attempts, so one poisoned event cannot block the queue for ever.
  static const int _maxRetries = 60;
  static const Duration _fetchEvery = Duration(seconds: 30);
  static final Random _random = Random();

  Timer? _syncTimer;
  bool _isSyncing = false;
  DateTime _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);
  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> rejectedCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<SyncStatus> statusNotifier = ValueNotifier<SyncStatus>(SyncStatus.synced);
  final ValueNotifier<DateTime?> lastSyncTimeNotifier = ValueNotifier<DateTime?>(null);

  int get pendingCount => pendingCountNotifier.value;
  int get rejectedCount => rejectedCountNotifier.value;
  SyncStatus get status => statusNotifier.value;
  DateTime? get lastSyncTime => lastSyncTimeNotifier.value;

  /// A new unique reference for an event (letters, digits and dashes; 8 to 64 characters).
  static String newClientRef() {
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = _random.nextInt(1 << 30).toRadixString(36);
    return 'm-$time-$salt';
  }

  /// Turns an old queue id into a reference the server accepts.
  static String safeRef(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9._:-]'), '_');
    final padded = cleaned.length < 8 ? cleaned.padRight(8, '_') : cleaned;
    return padded.length > 64 ? padded.substring(padded.length - 64) : padded;
  }

  /// Start the background worker. It ticks every few seconds; a tick with nothing to send does no network work.
  void startAutoSync({Duration interval = const Duration(seconds: 5)}) {
    _updatePendingCount();
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(interval, (_) => processQueue());
    debugPrint('[SyncQueueService] Offline sync worker started (checks every ${interval.inSeconds}s)');
  }

  /// Ask for a refresh of the local cache on the next pass (for example right after a guard signs in), instead of
  /// waiting for the normal 30-second window.
  void requestRefresh() {
    _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  @visibleForTesting
  Future<void> clearQueue() async {
    await LocalCacheService.saveSyncQueue([]);
    _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);
    _updatePendingCount();
  }

  void _updatePendingCount() {
    final queue = LocalCacheService.getSyncQueue();
    pendingCountNotifier.value = queue.length;
    rejectedCountNotifier.value = LocalCacheService.getRejectedSync().length;
    if (!_isSyncing) {
      statusNotifier.value = queue.isNotEmpty ? SyncStatus.offline : SyncStatus.synced;
    }
  }

  /// Save an event that could not be sent because the server was unreachable.
  Future<void> enqueue({
    required String type,
    required Map<String, dynamic> payload,
    String? clientRef,
    DateTime? occurredAt,
  }) async {
    final plateStr = payload['plate'] ?? payload['plateNumber'] ?? 'item';
    final now = DateTime.now();
    final item = QueueItem(
      id: 'q-${now.millisecondsSinceEpoch}-$plateStr',
      type: type,
      payload: payload,
      createdAt: now,
      clientRef: clientRef ?? newClientRef(),
      occurredAt: occurredAt ?? now,
    );

    final currentQueue = LocalCacheService.getSyncQueue();
    currentQueue.add(item.toJson());
    await LocalCacheService.saveSyncQueue(currentQueue);
    _updatePendingCount();
    debugPrint('[SyncQueueService] Queued offline $type for $plateStr (pending: ${currentQueue.length})');
  }

  /// Sends everything waiting, oldest first, then (at most every 30 s) refreshes the local cache.
  /// Returns true when nothing is left in the queue.
  Future<bool> processQueue() async {
    if (_isSyncing) return false;

    // The worker ticks every few seconds: with nothing queued and no refresh due there is nothing to do, and the
    // status (and anything listening to it) must not flicker to "syncing" for no reason.
    final nothingQueued = LocalCacheService.getSyncQueue().isEmpty;
    // The lists are only fetched for a signed-in guard: before sign-in the request would just be refused
    final refreshDue = ApiService.authToken != null && DateTime.now().difference(_lastFetch) >= _fetchEvery;
    if (nothingQueued && !refreshDue) return true;

    _isSyncing = true;
    statusNotifier.value = SyncStatus.syncing;

    var connectionHealthy = true;
    var delivered = false;

    try {
      var pending = LocalCacheService.getSyncQueue();
      while (pending.isNotEmpty && connectionHealthy) {
        final batchRaw = pending.take(_batchSize).toList();
        final rest = pending.skip(batchRaw.length).toList();
        final items = batchRaw.map(QueueItem.fromJson).toList();

        final results = await ApiService.syncEvents(items.map((i) => i.toSyncEvent()).toList());
        if (results == null) {
          // No connection (or the server could not process the batch): keep everything, try again next tick
          connectionHealthy = false;
          break;
        }

        final byRef = <String, Map<String, dynamic>>{};
        for (final r in results) {
          final ref = r['client_ref']?.toString();
          if (ref != null) byRef[ref] = r;
        }

        final unanswered = <Map<String, dynamic>>[];
        final refused = <Map<String, dynamic>>[];
        for (final item in items) {
          final result = byRef[item.clientRef];
          final status = result?['status']?.toString();
          if (status == 'accepted' || status == 'duplicate') {
            delivered = true;
            continue;
          }
          if (status == 'rejected') {
            // The server will never take this one: keep it for review instead of retrying forever
            refused.add({
              'clientRef': item.clientRef,
              'type': item.type,
              'occurredAt': item.occurredAt.toUtc().toIso8601String(),
              'code': result?['code']?.toString() ?? 'REJECTED',
              'message': result?['message']?.toString() ?? '',
              'payload': item.payload,
              'rejectedAt': DateTime.now().toIso8601String(),
            });
            continue;
          }
          // 'retry' (temporary server problem) or no answer for this event: keep it queued, but not for ever
          item.retryCount++;
          if (item.retryCount >= _maxRetries) {
            refused.add({
              'clientRef': item.clientRef,
              'type': item.type,
              'occurredAt': item.occurredAt.toUtc().toIso8601String(),
              'code': 'GAVE_UP',
              'message': 'Still failing after $_maxRetries attempts: ${result?['message'] ?? 'no answer from the server'}',
              'payload': item.payload,
              'rejectedAt': DateTime.now().toIso8601String(),
            });
            continue;
          }
          unanswered.add(item.toJson());
        }

        if (refused.isNotEmpty) {
          await LocalCacheService.addRejectedSyncEvents(refused);
          debugPrint('[SyncQueueService] Server refused ${refused.length} event(s): ${refused.map((r) => r['code']).join(', ')}');
        }
        pending = [...unanswered, ...rest];
        await LocalCacheService.saveSyncQueue(pending);
        pendingCountNotifier.value = pending.length;
        if (unanswered.isNotEmpty) connectionHealthy = false;
      }
    } catch (e) {
      connectionHealthy = false;
      debugPrint('[SyncQueueService] Sync error: $e');
    }

    var fetched = false;
    if (connectionHealthy && ApiService.authToken != null && DateTime.now().difference(_lastFetch) >= _fetchEvery) {
      try {
        final freshVehicles = await ApiService.fetchVehicles();
        if (freshVehicles.isNotEmpty) {
          debugPrint('[SyncQueueService] Auto-fetched ${freshVehicles.length} vehicles from web app');
        }
      } catch (e) {
        debugPrint('[SyncQueueService] Auto-fetch vehicles notice: $e');
      }

      try {
        final freshLogs = await ApiService.fetchLogs();
        if (freshLogs.isNotEmpty) {
          debugPrint('[SyncQueueService] Auto-fetched ${freshLogs.length} logs from web app');
        }
      } catch (e) {
        debugPrint('[SyncQueueService] Auto-fetch logs notice: $e');
      }
      _lastFetch = DateTime.now();
      fetched = true;
    }

    // Listeners (the dashboard) refresh only when something was actually delivered or fetched
    if (connectionHealthy && (delivered || fetched)) {
      lastSyncTimeNotifier.value = DateTime.now();
    }

    _isSyncing = false;
    _updatePendingCount();

    final remaining = LocalCacheService.getSyncQueue();
    statusNotifier.value = (!connectionHealthy || remaining.isNotEmpty) ? SyncStatus.offline : SyncStatus.synced;
    return remaining.isEmpty;
  }
}
