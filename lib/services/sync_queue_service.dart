import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'local_cache_service.dart';

/// Represents a pending outbound database operation queued while offline
class QueueItem {
  final String id;
  final String type; // 'gate_log', 'visitor_pass', 'visitor_exit', 'incident'
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  int retryCount;

  QueueItem({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
        'retryCount': retryCount,
      };

  factory QueueItem.fromJson(Map<String, dynamic> json) => QueueItem(
        id: json['id']?.toString() ?? 'q-${DateTime.now().millisecondsSinceEpoch}',
        type: json['type']?.toString() ?? 'gate_log',
        payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
        retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      );
}

enum SyncStatus {
  synced,
  syncing,
  offline,
}

/// Automated offline queue manager.
/// When Wi-Fi disconnects or backend calls fail, mutations are saved to persistent disk.
/// As soon as Wi-Fi returns, the queue automatically syncs everything in order to the database,
/// and fetches back the latest database records from the web application.
class SyncQueueService {
  static final SyncQueueService _instance = SyncQueueService._internal();
  factory SyncQueueService() => _instance;

  SyncQueueService._internal();

  Timer? _syncTimer;
  bool _isSyncing = false;
  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<SyncStatus> statusNotifier = ValueNotifier<SyncStatus>(SyncStatus.synced);
  final ValueNotifier<DateTime?> lastSyncTimeNotifier = ValueNotifier<DateTime?>(null);

  int get pendingCount => pendingCountNotifier.value;
  SyncStatus get status => statusNotifier.value;
  DateTime? get lastSyncTime => lastSyncTimeNotifier.value;

  /// Start automated background sync polling (e.g. every 10 seconds)
  void startAutoSync({Duration interval = const Duration(seconds: 10)}) {
    _updatePendingCount();
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(interval, (_) => processQueue());
    debugPrint('[SyncQueueService] Automated offline sync worker started (interval: ${interval.inSeconds}s)');
  }

  void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  @visibleForTesting
  Future<void> clearQueue() async {
    await LocalCacheService.saveSyncQueue([]);
    _updatePendingCount();
  }

  void _updatePendingCount() {
    final queue = LocalCacheService.getSyncQueue();
    pendingCountNotifier.value = queue.length;
    if (!_isSyncing) {
      if (queue.isNotEmpty) {
        statusNotifier.value = SyncStatus.offline;
      } else {
        statusNotifier.value = SyncStatus.synced;
      }
    }
  }

  /// Enqueue an action when offline or network write failed
  Future<void> enqueue({
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    final plateStr = payload['plate'] ?? payload['plateNumber'] ?? 'item';
    final item = QueueItem(
      id: 'q-${DateTime.now().millisecondsSinceEpoch}-$plateStr',
      type: type,
      payload: payload,
      createdAt: DateTime.now(),
    );

    final currentQueue = LocalCacheService.getSyncQueue();
    currentQueue.add(item.toJson());
    await LocalCacheService.saveSyncQueue(currentQueue);
    _updatePendingCount();
    debugPrint('[SyncQueueService] Queued offline $type for $plateStr (Total pending in queue: ${currentQueue.length})');
  }

  /// Automatically drains and transmits all pending offline items to the live database/web app,
  /// then automatically fetches back the latest records from the web application.
  Future<bool> processQueue() async {
    if (_isSyncing) return false;
    _isSyncing = true;
    statusNotifier.value = SyncStatus.syncing;

    final rawQueue = LocalCacheService.getSyncQueue();
    final remaining = <Map<String, dynamic>>[];
    bool connectionHealthy = true;

    // 1. PUSH: Drain pending queue items to the web application
    if (rawQueue.isNotEmpty) {
      debugPrint('[SyncQueueService] Wi-Fi sync triggered: pushing ${rawQueue.length} pending items to web app...');

      for (int i = 0; i < rawQueue.length; i++) {
        final raw = rawQueue[i];
        final item = QueueItem.fromJson(raw);

        if (!connectionHealthy) {
          // If connection dropped during processing, retain remaining items for next cycle
          remaining.add(raw);
          continue;
        }

        final success = await _dispatchItem(item);
        if (success) {
          debugPrint('[SyncQueueService] Successfully synced offline ${item.type} [ID: ${item.id}]');
        } else {
          item.retryCount++;
          connectionHealthy = false;
          remaining.add(item.toJson());
        }
      }

      await LocalCacheService.saveSyncQueue(remaining);
    }

    // 2. FETCH: Automatically pull fresh records from web application if network is active
    if (connectionHealthy) {
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

      lastSyncTimeNotifier.value = DateTime.now();
    }

    _isSyncing = false;
    _updatePendingCount();

    if (!connectionHealthy || remaining.isNotEmpty) {
      statusNotifier.value = SyncStatus.offline;
    } else {
      statusNotifier.value = SyncStatus.synced;
    }

    return remaining.isEmpty;
  }

  Future<bool> _dispatchItem(QueueItem item) async {
    try {
      switch (item.type) {
        case 'gate_log':
          return await ApiService.postGateLogDirect(item.payload);
        case 'visitor_pass':
          return await ApiService.postVisitorPassDirect(item.payload);
        case 'visitor_exit':
          return await ApiService.postVisitorExitDirect(
            item.payload['passId']?.toString() ?? '',
            item.payload['plateNumber']?.toString() ?? '',
          );
        case 'incident':
          return await ApiService.reportIncidentDirect(item.payload);
        default:
          return true; // Unknown type, drop to avoid blocking queue
      }
    } catch (e) {
      debugPrint('[SyncQueueService] Dispatch error for ${item.type}: $e');
      return false;
    }
  }
}
