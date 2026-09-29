import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vehicle_model.dart';
import '../models/visitor_pass_model.dart';

/// Local Persistent Cache Service using SharedPreferences with in-memory fallback.
/// Ensures all database entities (vehicles, gate logs, visitor passes) persist locally
/// so the app continues full offline operation if Wi-Fi disappears.
class LocalCacheService {
  static SharedPreferences? _prefs;
  static final Map<String, String> _memFallback = {};

  static const String keyVehicles = 'sp_cached_vehicles_v2';
  static const String keyLogs = 'sp_cached_logs_v2';
  static const String keyVisitorPasses = 'sp_cached_visitor_passes_v2';
  static const String keySyncQueue = 'sp_offline_sync_queue_v2';
  static const String keyRejectedSync = 'sp_rejected_sync_events_v1';
  static const String keyVisitorPassValidityHours = 'sp_visitor_pass_validity_hours';
  static const String keyServerBaseUrl = 'sp_server_base_url_v2';

  /// Retrieve persistent backend API base URL
  static String getServerBaseUrl({String defaultUrl = 'http://ncstparking-test.rf.gd/api'}) {
    final stored = _getString(keyServerBaseUrl);
    if (stored != null && stored.trim().isNotEmpty) {
      return stored.trim();
    }
    return defaultUrl;
  }

  /// Store persistent backend API base URL
  static Future<void> setServerBaseUrl(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    await _setString(keyServerBaseUrl, clean);
  }

  /// Initialize persistent storage (safe to call multiple times)
  static Future<void> init() async {
    if (_prefs != null) return;
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('[LocalCacheService] Note: SharedPreferences fallback to memory: $e');
    }
  }

  @visibleForTesting
  static void setMockPrefs(SharedPreferences prefs) {
    _prefs = prefs;
  }

  @visibleForTesting
  static void clearMemoryCache() {
    _memFallback.clear();
  }

  static String? _getString(String key) {
    try {
      if (_prefs != null) {
        final val = _prefs!.getString(key);
        if (val != null) return val;
      }
    } catch (_) {}
    return _memFallback[key];
  }

  static Future<void> _setString(String key, String value) async {
    _memFallback[key] = value;
    try {
      if (_prefs != null) {
        await _prefs!.setString(key, value);
      }
    } catch (_) {}
  }

  // ---- 1. Registered Vehicles Cache ----
  static Future<void> saveVehicles(List<dynamic> jsonList) async {
    try {
      final str = jsonEncode(jsonList);
      await _setString(keyVehicles, str);
    } catch (e) {
      debugPrint('[LocalCacheService] Error saving vehicles cache: $e');
    }
  }

  static List<VehicleRecord> getCachedVehicles() {
    try {
      final raw = _getString(keyVehicles);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        return list
            .map((item) => VehicleRecord.fromQrJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[LocalCacheService] Error reading vehicles cache: $e');
    }
    return [];
  }

  static VehicleRecord? findVehicle(String query) {
    final clean = query.trim();
    if (clean.isEmpty) return null;
    final cached = getCachedVehicles();
    final normQuery = clean.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();

    for (final v in cached) {
      final normPlate = v.plateNumber.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
      if (normPlate == normQuery || v.qrPassCode.toLowerCase() == clean.toLowerCase()) {
        return v;
      }
    }
    return null;
  }

  static Future<void> upsertVehicle(VehicleRecord vehicle) async {
    try {
      final raw = _getString(keyVehicles);
      List<dynamic> list = [];
      if (raw != null && raw.isNotEmpty) {
        list = jsonDecode(raw) as List;
      }
      final normPlate = vehicle.plateNumber.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
      final idx = list.indexWhere((item) {
        if (item is Map) {
          final p = (item['plateNumber'] ?? item['plate_number'] ?? item['plate'] ?? '').toString().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
          return p == normPlate;
        }
        return false;
      });
      final jsonMap = vehicle.toJson();
      if (idx >= 0) {
        list[idx] = jsonMap;
      } else {
        list.insert(0, jsonMap);
      }
      await saveVehicles(list);
    } catch (e) {
      debugPrint('[LocalCacheService] Error upserting vehicle in cache: $e');
    }
  }

  // ---- 2. Gate Audit Logs Cache ----
  static Future<void> saveLogs(List<dynamic> jsonList) async {
    try {
      final str = jsonEncode(jsonList);
      await _setString(keyLogs, str);
    } catch (e) {
      debugPrint('[LocalCacheService] Error saving logs cache: $e');
    }
  }

  static List<AuditLogEntry> getCachedLogs() {
    try {
      final raw = _getString(keyLogs);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        return list
            .map((item) => AuditLogEntry.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[LocalCacheService] Error reading logs cache: $e');
    }
    return [];
  }

  static Future<void> appendLocalLog(AuditLogEntry entry) async {
    try {
      final current = getCachedLogs();
      // Deduplicate by ID
      current.removeWhere((l) => l.id == entry.id);
      current.insert(0, entry);
      if (current.length > 200) {
        current.removeRange(200, current.length);
      }
      final jsonList = current.map((e) => e.toJson()).toList();
      await saveLogs(jsonList);
    } catch (e) {
      debugPrint('[LocalCacheService] Error appending local log: $e');
    }
  }

  /// Removes one entry from the local audit log (for example a passage the server refused).
  static Future<void> removeLocalLog(String id) async {
    try {
      final current = getCachedLogs();
      current.removeWhere((l) => l.id == id);
      await saveLogs(current.map((e) => e.toJson()).toList());
    } catch (e) {
      debugPrint('[LocalCacheService] Error removing local log: $e');
    }
  }

  // ---- 3. Visitor Passes Cache ----
  static Future<void> saveVisitorPasses(List<dynamic> jsonList) async {
    try {
      final str = jsonEncode(jsonList);
      await _setString(keyVisitorPasses, str);
    } catch (e) {
      debugPrint('[LocalCacheService] Error saving visitor passes: $e');
    }
  }

  static List<VisitorPass> getCachedVisitorPasses() {
    try {
      final raw = _getString(keyVisitorPasses);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        return list
            .map((item) => VisitorPass.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[LocalCacheService] Error reading visitor passes cache: $e');
    }
    return [];
  }

  // ---- 4. Offline Sync Queue Storage ----
  static Future<void> saveSyncQueue(List<Map<String, dynamic>> queue) async {
    try {
      await _setString(keySyncQueue, jsonEncode(queue));
    } catch (e) {
      debugPrint('[LocalCacheService] Error saving sync queue: $e');
    }
  }

  static List<Map<String, dynamic>> getSyncQueue() {
    try {
      final raw = _getString(keySyncQueue);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[LocalCacheService] Error reading sync queue: $e');
    }
    return [];
  }

  // Events the server refused for good (for example older than 24 hours). Kept for review, newest first.
  static Future<void> addRejectedSyncEvents(List<Map<String, dynamic>> events) async {
    try {
      final all = [...events, ...getRejectedSync()];
      await _setString(keyRejectedSync, jsonEncode(all.take(100).toList()));
    } catch (e) {
      debugPrint('[LocalCacheService] Error saving rejected sync events: $e');
    }
  }

  static List<Map<String, dynamic>> getRejectedSync() {
    try {
      final raw = _getString(keyRejectedSync);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[LocalCacheService] Error reading rejected sync events: $e');
    }
    return [];
  }

  // ---- 5. System Settings & Pass Validity Rules ----
  static Future<void> saveVisitorPassValidityHours(int hours) async {
    try {
      await _setString(keyVisitorPassValidityHours, hours.toString());
    } catch (e) {
      debugPrint('[LocalCacheService] Error saving visitor pass validity hours: $e');
    }
  }

  static int getVisitorPassValidityHours() {
    try {
      final raw = _getString(keyVisitorPassValidityHours);
      if (raw != null && raw.isNotEmpty) {
        final parsed = int.tryParse(raw);
        if (parsed != null && parsed > 0 && parsed <= 72) {
          return parsed;
        }
      }
    } catch (e) {
      debugPrint('[LocalCacheService] Error reading visitor pass validity hours: $e');
    }
    return 8; // Default 8 hours
  }
}
