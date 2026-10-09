import 'dart:async';
import 'dart:convert';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/constants/api_constants.dart';
import '../models/vehicle_model.dart';
import '../models/visitor_pass_model.dart';
import '../data/mock_data.dart';
import 'local_cache_service.dart';
import 'sync_queue_service.dart';

class MovementApiException implements Exception {
  final String message;
  final String code;
  final bool retryable;
  const MovementApiException(this.message, this.code, {this.retryable = false});
  @override
  String toString() => message;
}

/// What happened to a live write (a POST the guard is waiting on).
enum WriteOutcome {
  /// The server recorded it.
  accepted,

  /// The server understood and said no (banned vehicle, unknown plate, duplicate pass...). Do not queue it.
  refused,

  /// No connection, timeout or temporary server error. Queue it and try again later.
  unreachable,
}

/// Central API Service for Flutter Android App communicating with InfinityFree Backend
class ApiService {
  static http.Client _client = http.Client();
  static String? _testCookie;
  static String? authToken;
  static final ValueNotifier<String?> sessionError = ValueNotifier(null);
  static final ValueNotifier<Map<String, dynamic>?> currentSessionUser =
      ValueNotifier(null);
  static final ValueNotifier<int> liveRevision = ValueNotifier(0);
  static bool lastFetchWasLive = false;
  static Map<String, String>? _revisions;
  static Future<Map<String, dynamic>> fetchUpdates() async {
    final res = await _get(Uri.parse('${ApiConstants.baseUrl}/updates.php'));
    if (res.statusCode != 200) {
      throw StateError('Could not refresh the current session.');
    }
    return Map<String, dynamic>.from(
      (jsonDecode(res.body) as Map)['data'] as Map,
    );
  }

  static Future<List<VisitorPass>> fetchVisitorPasses() async {
    final res = await _get(
      Uri.parse('${ApiConstants.baseUrl}/visitors.php?all=1'),
    );
    if (res.statusCode != 200) {
      throw StateError('Could not refresh visitor passes.');
    }
    return ((jsonDecode(res.body) as Map)['data'] as List)
        .map((p) => VisitorPass.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();
  }

  static void acknowledgeUpdates(Map<String, String> revisions) {
    _revisions = revisions;
    liveRevision.value++;
  }

  static Map<String, String>? get revisions => _revisions;
  static void _rejectSession() {
    if (authToken == null) return;
    authToken = null;
    _revisions = null;
    sessionError.value =
        'Your session has ended or your account was disabled. Sign in again.';
  }

  /// The server's message for the last refused write, or why it could not be sent.
  static String? lastWriteError;

  /// Server id of the gate log written by the last successful postGateLog (null when it was queued offline).
  static int? lastGateLogId;

  /// Server id of the violation created by the last successful issueViolation.
  static int? lastViolationId;

  /// The server's error message for the last pass verification, or network error.
  static String? lastVerifyError;

  /// True when the last visitor pass could not reach the server and was saved on this phone to sync later.
  static bool lastWriteQueued = false;

  /// The parsed response body data from the last accepted write request
  static Map<String, dynamic>? lastResponseData;

  /// The visitor pass record returned by the server upon successful creation
  static VisitorPass? lastCreatedVisitorPass;

  @visibleForTesting
  static void setClientForTesting(http.Client client) {
    _client = client;
  }

  @visibleForTesting
  static void resetClient() {
    _client = http.Client();
    _testCookie = null;
    authToken = null;
    _revisions = null;
    sessionError.value = null;
    currentSessionUser.value = null;
  }

  /// Helper to solve InfinityFree AES anti-bot challenge automatically
  static String? _solveInfinityFreeChallenge(String html) {
    try {
      final regA = RegExp(r'var a=toNumbers\("([0-9a-fA-F]+)"\)');
      final regB = RegExp(r'b=toNumbers\("([0-9a-fA-F]+)"\)');
      final regC = RegExp(r'c=toNumbers\("([0-9a-fA-F]+)"\)');

      final matchA = regA.firstMatch(html);
      final matchB = regB.firstMatch(html);
      final matchC = regC.firstMatch(html);

      if (matchA != null && matchB != null && matchC != null) {
        final keyHex = matchA.group(1)!;
        final ivHex = matchB.group(1)!;
        final cipherHex = matchC.group(1)!;

        final key = enc.Key.fromBase16(keyHex);
        final iv = enc.IV.fromBase16(ivHex);

        final cipherBytes = <int>[];
        for (int i = 0; i < cipherHex.length; i += 2) {
          cipherBytes.add(int.parse(cipherHex.substring(i, i + 2), radix: 16));
        }

        final encrypter = enc.Encrypter(
          enc.AES(key, mode: enc.AESMode.cbc, padding: null),
        );
        final decrypted = encrypter.decryptBytes(
          enc.Encrypted(Uint8List.fromList(cipherBytes)),
          iv: iv,
        );
        final cookie = decrypted
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join('')
            .toLowerCase();
        debugPrint(
          '[ApiService] Successfully solved InfinityFree bot challenge',
        );
        return cookie;
      }
    } catch (e) {
      debugPrint('[ApiService] Error solving InfinityFree challenge: $e');
    }
    return null;
  }

  static Map<String, String> _buildHeaders() {
    final headers = Map<String, String>.from(ApiConstants.defaultHeaders);
    if (_testCookie != null && _testCookie!.isNotEmpty) {
      headers['Cookie'] = '__test=$_testCookie';
    }
    if (authToken != null && authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
      headers['X-Auth-Token'] = authToken!;
    }
    return headers;
  }

  /// Specialized headers for image loading (Accept: image/* and anti-bot cookie)
  static Map<String, String> get imageHeaders {
    final headers = <String, String>{
      'User-Agent':
          ApiConstants.defaultHeaders['User-Agent'] ??
          'SecurePark-GateScanner/2.4',
      'Accept':
          'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    };
    if (_testCookie != null && _testCookie!.isNotEmpty) {
      headers['Cookie'] = '__test=$_testCookie';
    }
    if (authToken != null && authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
      headers['X-Auth-Token'] = authToken!;
    }
    return headers;
  }

  /// Memory cache for fetched image bytes to avoid re-requesting.
  /// Bounded to 20 images to prevent unbounded heap memory retention.
  static final Map<String, Uint8List> _imageCache = {};
  static const int _maxCachedImages = 20;

  static void _cacheImageBytes(String url, Uint8List bytes) {
    if (_imageCache.length >= _maxCachedImages) {
      _imageCache.remove(_imageCache.keys.first);
    }
    _imageCache[url] = bytes;
  }

  /// Directly fetch image bytes via HTTP, solving any InfinityFree challenge if encountered
  static Future<Uint8List?> fetchImageBytes(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return null;
    if (_imageCache.containsKey(cleanUrl)) {
      return _imageCache[cleanUrl];
    }

    try {
      final uri = Uri.parse(cleanUrl);
      var res = await _client
          .get(uri, headers: imageHeaders)
          .timeout(ApiConstants.timeout);
      if (res.body.contains('slowAES.decrypt')) {
        final solved = _solveInfinityFreeChallenge(res.body);
        if (solved != null) {
          _testCookie = solved;
          res = await _client
              .get(uri, headers: imageHeaders)
              .timeout(ApiConstants.timeout);
        }
      }
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        // Validate that response is an image and not an HTML challenge/error page
        if (!res.body.contains('<!DOCTYPE') && !res.body.contains('<html')) {
          _cacheImageBytes(cleanUrl, res.bodyBytes);
          return res.bodyBytes;
        }
      }
    } catch (e) {
      debugPrint('[ApiService] fetchImageBytes note for $cleanUrl: $e');
    }
    return null;
  }

  static Future<http.Response> _get(Uri uri) async {
    try {
      var res = await _client
          .get(uri, headers: _buildHeaders())
          .timeout(ApiConstants.timeout);
      if (res.body.contains('slowAES.decrypt')) {
        final solved = _solveInfinityFreeChallenge(res.body);
        if (solved != null) {
          _testCookie = solved;
          res = await _client
              .get(uri, headers: _buildHeaders())
              .timeout(ApiConstants.timeout);
        }
      }
      if (res.statusCode == 401) _rejectSession();
      return res;
    } catch (_) {
      return http.Response('{"status":"offline"}', 503);
    }
  }

  static Future<http.Response> _post(Uri uri, String body) async {
    try {
      // If not authenticated with InfinityFree test cookie yet, ping status to solve cookie
      if (_testCookie == null &&
          (uri.host.endsWith('rf.gd') || uri.host.endsWith('site.je'))) {
        await _get(
          Uri.parse('${ApiConstants.baseUrl}${ApiConstants.statsEndpoint}'),
        );
      }
      var res = await _client
          .post(uri, headers: _buildHeaders(), body: body)
          .timeout(ApiConstants.timeout);
      if (res.body.contains('slowAES.decrypt')) {
        final solved = _solveInfinityFreeChallenge(res.body);
        if (solved != null) {
          _testCookie = solved;
          res = await _client
              .post(uri, headers: _buildHeaders(), body: body)
              .timeout(ApiConstants.timeout);
        }
      }
      if (res.statusCode == 401) _rejectSession();
      return res;
    } catch (_) {
      return http.Response('{"status":"offline"}', 503);
    }
  }

  /// Query backend for a vehicle by plate number or QR code
  static Future<VehicleRecord?> lookupVehicle(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return null;
    VehicleRecord? record;
    if (clean.startsWith('{') ||
        clean.contains('"plateNumber"') ||
        clean.startsWith('NCST-QR-')) {
      record =
          (await lookupVehicleByQr(clean)) ??
          (await lookupVehicleByPlate(clean));
    } else {
      record =
          (await lookupVehicleByPlate(clean)) ??
          (await lookupVehicleByQr(clean));
    }
    if (record != null) return record;

    // Offline Wi-Fi fallback: query local persistent cache
    return LocalCacheService.findVehicle(clean);
  }

  /// Query backend for a vehicle by QR pass code or payload
  static Future<VehicleRecord?> lookupVehicleByQr(String qr) async {
    try {
      final uri = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.vehiclesEndpoint}?qr=${Uri.encodeComponent(qr)}',
      );
      final res = await _get(uri);

      if (res.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(res.body);
        if (body['status'] == 'success' && body['data'] != null) {
          final record = VehicleRecord.fromQrJson(
            body['data'],
            rawPayload: 'SERVER_DB_RECORD',
            isSyncedWithDb: true,
          );
          await LocalCacheService.upsertVehicle(record);
          MockData.upsertVehicle(record);
          return record;
        }
      } else if (res.statusCode == 404) {
        return null;
      }
    } catch (e) {
      debugPrint('[ApiService] QR lookup failed or offline: $e');
    }
    return LocalCacheService.findVehicle(qr);
  }

  /// Query backend for a vehicle by plate number
  static Future<VehicleRecord?> lookupVehicleByPlate(String plate) async {
    try {
      final uri = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.vehiclesEndpoint}?plate=${Uri.encodeComponent(plate)}',
      );
      final res = await _get(uri);

      if (res.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(res.body);
        if (body['status'] == 'success' && body['data'] != null) {
          final record = VehicleRecord.fromQrJson(
            body['data'],
            rawPayload: 'SERVER_DB_RECORD',
            isSyncedWithDb: true,
          );
          await LocalCacheService.upsertVehicle(record);
          MockData.upsertVehicle(record);
          return record;
        }
      } else if (res.statusCode == 404) {
        return null;
      }
    } catch (e) {
      debugPrint('[ApiService] Lookup failed or offline: $e');
    }
    return LocalCacheService.findVehicle(plate);
  }

  /// Fetch all registered vehicles from the MySQL database
  static Future<List<VehicleRecord>> fetchVehicles({
    bool requireLive = false,
  }) async {
    lastFetchWasLive = false;
    try {
      final uri = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.vehiclesEndpoint}',
      );
      final res = await _get(uri);

      if (res.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(res.body);
        if (body['status'] == 'success' && body['data'] is List) {
          final list = body['data'] as List;
          final records = list
              .map(
                (item) =>
                    VehicleRecord.fromQrJson(item as Map<String, dynamic>),
              )
              .toList();
          await LocalCacheService.saveVehicles(list);
          lastFetchWasLive = true;
          return records;
        }
      }
    } catch (e) {
      debugPrint('[ApiService] Fetch vehicles failed or offline: $e');
    }
    if (requireLive) throw StateError('The server did not return fresh data.');
    // Return cached records if Wi-Fi disappeared
    final cached = LocalCacheService.getCachedVehicles();
    if (cached.isNotEmpty) {
      debugPrint(
        '[ApiService] Wi-Fi offline: loaded ${cached.length} vehicles from local cache',
      );
      return cached;
    }
    return [];
  }

  /// Fetch all recent gate audit logs from the MySQL database
  static Future<List<AuditLogEntry>> fetchLogs({
    bool requireLive = false,
  }) async {
    lastFetchWasLive = false;
    try {
      final uri = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.logsEndpoint}',
      );
      final res = await _get(uri);

      if (res.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(res.body);
        if (body['status'] == 'success' && body['data'] is List) {
          final list = body['data'] as List;
          final logs = list
              .map(
                (item) => AuditLogEntry.fromJson(item as Map<String, dynamic>),
              )
              .toList();
          await LocalCacheService.saveLogs(list);
          lastFetchWasLive = true;
          return logs;
        }
      }
    } catch (e) {
      debugPrint('[ApiService] Fetch logs failed or offline: $e');
    }
    if (requireLive) throw StateError('The server did not return fresh data.');
    // Return cached logs if Wi-Fi disappeared
    final cached = LocalCacheService.getCachedLogs();
    if (cached.isNotEmpty) {
      debugPrint(
        '[ApiService] Wi-Fi offline: loaded ${cached.length} logs from local cache',
      );
      return cached;
    }
    return [];
  }

  /// Test connectivity to a target backend API base URL
  static Future<Map<String, dynamic>> testConnection([
    String? customUrl,
  ]) async {
    final targetUrl = (customUrl != null && customUrl.trim().isNotEmpty)
        ? customUrl.trim()
        : ApiConstants.baseUrl;
    try {
      final uri = Uri.parse('$targetUrl${ApiConstants.statsEndpoint}');
      final res = await _client
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'SecurePark-GateScanner/2.4',
            },
          )
          .timeout(const Duration(seconds: 4));

      final body = res.body;
      if (res.statusCode == 200 ||
          body.contains('"status"') ||
          body.contains('slowAES')) {
        return {
          'success': true,
          'statusCode': res.statusCode,
          'message': 'Connected (HTTP ${res.statusCode})',
        };
      } else {
        return {
          'success': false,
          'statusCode': res.statusCode,
          'message': 'Server returned HTTP ${res.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'statusCode': 0,
        'message': 'Connection failed ($e)',
      };
    }
  }

  /// Authenticate guard against the live backend API (/api/auth.php?action=login)
  static Future<Map<String, dynamic>?> login({
    required String username,
    required String password,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/auth.php?action=login');
      final payload = jsonEncode({
        'username': username,
        'password': password,
        'realm': 'staff',
      });
      final res = await _post(uri, payload);
      if (res.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(res.body);
        if (body['status'] == 'success' && body['data'] != null) {
          final data = body['data'] as Map<String, dynamic>;
          final token = data['token'] as String?;
          if (token != null && token.isNotEmpty) {
            authToken = token;
            sessionError.value = null;
            _revisions = null;
            debugPrint('[ApiService] Session token established.');
            unawaited(fetchSystemSettings());
          }
          return data;
        } else {
          throw Exception(body['message'] ?? 'Authentication failed');
        }
      } else if (res.statusCode == 400 ||
          res.statusCode == 401 ||
          res.statusCode == 403) {
        try {
          final Map<String, dynamic> body = jsonDecode(res.body);
          throw Exception(body['message'] ?? 'Authentication failed');
        } catch (e) {
          if (e is Exception && e.toString().contains('Exception:')) rethrow;
          throw Exception('Authentication failed (HTTP ${res.statusCode})');
        }
      } else if (res.statusCode == 503) {
        throw Exception(
          'Cannot connect to server at ${ApiConstants.baseUrl}. Please verify your network or server URL setting.',
        );
      } else {
        try {
          final Map<String, dynamic> body = jsonDecode(res.body);
          if (body['message'] != null) {
            throw Exception(body['message']);
          }
        } catch (e) {
          if (e is Exception && e.toString().contains('Exception:')) rethrow;
        }
        throw Exception(
          'Server error (HTTP ${res.statusCode}). Unable to sign in.',
        );
      }
    } catch (e) {
      debugPrint('[ApiService] Login exception: $e');
      rethrow;
    }
  }

  /// Logout guard and invalidate session token on backend (/api/auth.php?action=logout)
  static Future<void> logout() async {
    try {
      if (authToken != null) {
        final uri = Uri.parse('${ApiConstants.baseUrl}/auth.php?action=logout');
        await _post(uri, '{}');
      }
    } catch (e) {
      debugPrint('[ApiService] Logout exception: $e');
    } finally {
      authToken = null;
    }
  }

  /// Classifies a server reply to a live write.
  static WriteOutcome _outcomeOf(http.Response res) {
    final looksLikeHtml =
        res.body.contains('<html') || res.body.contains('<!DOCTYPE');
    if ((res.statusCode == 200 || res.statusCode == 201) && !looksLikeHtml) {
      return WriteOutcome.accepted;
    }
    // 5xx (including the synthetic 503 "offline"), timeouts, rate limits, expired session and anti-bot pages: try again later
    if (looksLikeHtml ||
        res.statusCode >= 500 ||
        res.statusCode == 408 ||
        res.statusCode == 429) {
      return WriteOutcome.unreachable;
    }
    return WriteOutcome.refused;
  }

  static String? _messageOf(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['message'] != null) {
        return body['message'].toString();
      }
    } catch (_) {}
    return null;
  }

  static Future<WriteOutcome> _postForOutcome(
    String endpoint,
    Map<String, dynamic> payload,
  ) async {
    try {
      lastResponseData = null;
      final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
      final res = await _post(uri, jsonEncode(payload));
      final outcome = _outcomeOf(res);
      if (outcome == WriteOutcome.accepted) {
        try {
          final body = jsonDecode(res.body);
          if (body is Map && body['data'] is Map) {
            lastResponseData = Map<String, dynamic>.from(body['data']);
          }
        } catch (_) {}
      } else if (outcome == WriteOutcome.refused) {
        lastWriteError =
            _messageOf(res) ??
            'The server refused this request (${res.statusCode}).';
      } else if (outcome == WriteOutcome.unreachable) {
        lastWriteError = 'No connection to the server.';
      }
      return outcome;
    } catch (e) {
      debugPrint('[ApiService] Write to $endpoint failed: $e');
      lastWriteError = 'No connection to the server.';
      return WriteOutcome.unreachable;
    }
  }

  /// Changes the signed-in guard's own password (needed at first sign-in, when the account still has a temporary one).
  /// Returns null on success, otherwise a message the guard can read.
  static Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final uri = Uri.parse(
        '${ApiConstants.baseUrl}/auth.php?action=change_password',
      );
      final res = await _post(
        uri,
        jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      );
      if (res.statusCode == 200) return null;
      if (res.statusCode >= 500) {
        return 'No connection to the server. Try again.';
      }
      return _messageOf(res) ??
          'The password could not be changed (HTTP ${res.statusCode}).';
    } catch (e) {
      debugPrint('[ApiService] changePassword note: $e');
      return 'No connection to the server. Try again.';
    }
  }

  /// Sends queued offline events to /api/sync.php in one request.
  /// Returns one result per event (`accepted`, `duplicate` or `rejected`), or null when the server
  /// could not be reached or could not process the batch, in which case everything stays queued.
  static Future<List<Map<String, dynamic>>?> syncEvents(
    List<Map<String, dynamic>> events,
  ) async {
    try {
      final uri = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.syncEndpoint}',
      );
      final res = await _post(uri, jsonEncode({'events': events}));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      final data = body is Map ? body['data'] : null;
      final results = data is Map ? data['results'] : null;
      if (results is! List) return null;
      return results
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      debugPrint('[ApiService] syncEvents note: $e');
      return null;
    }
  }

  /// Direct HTTP post for a gate log (live write)
  static Future<bool> postGateLogDirect(Map<String, dynamic> payload) async {
    return (await _postForOutcome(ApiConstants.logsEndpoint, payload)) ==
        WriteOutcome.accepted;
  }

  /// Post gate passage (Entry or Exit). It is always cached locally so the guard UI shows it at once.
  /// If the server cannot be reached the passage is queued with the time it happened and sent as soon
  /// as a connection is back. If the server refuses it, it is not queued (retrying cannot change the answer).
  static Future<bool> postGateLog({
    required String plateNumber,
    required String driverName,
    String driverRelationship = 'Self (Owner)',
    String gatePoint = 'Gate 1 (Main Ingress)',
    String action = 'Entry Recorded',
    String status = 'Inside Campus',
    String guardName = 'Gate Officer',
    String notes = '',
    String? vehicleType,
    String? ownerName,
    int? driverId,
    int? visitorPassId,
    bool itemsVerified = false,
    // 'qr' (scanned) or 'manual' (the guard typed the plate): supervisors see how often each guard looks vehicles up by hand
    String lookupMethod = 'qr',
  }) async {
    final gateType = (action.contains('Exit') || action.contains('Egress'))
        ? 'Egress'
        : 'Ingress';
    final clientRef = SyncQueueService.newClientRef();
    final occurredAt = DateTime.now();
    lastGateLogId = null;
    final Map<String, dynamic> payload = {
      'plate': plateNumber,
      'plateNumber': plateNumber,
      'driverName': driverName,
      'driverRelationship': driverRelationship,
      // The server confirms the driver by id: without it a registered vehicle's entry / exit is refused
      if (driverId != null && driverId > 0) 'driver_id': driverId,
      // An existing visitor day pass: the entry is recorded against it, and the server insists the guard has
      // checked the items declared on it (items_verified) before it accepts the entry.
      if (visitorPassId != null && visitorPassId > 0)
        'visitor_pass_id': visitorPassId,
      if (itemsVerified) 'items_verified': true,
      'lookupMethod': lookupMethod,
      'gatePoint': gatePoint,
      'gate_type': gateType,
      'action': action,
      'status': status,
      'guardName': guardName,
      'notes': notes,
      'vehicleType': vehicleType ?? '',
      'ownerName': ownerName ?? '',
      'client_ref': clientRef,
      'occurred_at': occurredAt.toUtc().toIso8601String(),
    };

    GateStatus localStatus = GateStatus.inside;
    if (action.contains('Denied') ||
        status.toLowerCase().contains('denied') ||
        status.toLowerCase().contains('blocked')) {
      localStatus = GateStatus.blocked;
    } else if (action.contains('Exit') ||
        action.contains('Egress') ||
        status.toLowerCase().contains('exit') ||
        status.toLowerCase().contains('depart')) {
      localStatus = GateStatus.exited;
    }

    // 1. Immediately cache in local audit log so the guard UI displays it even offline
    final localEntry = AuditLogEntry(
      id: 'LOG-${occurredAt.millisecondsSinceEpoch}',
      plateNumber: plateNumber,
      vehicleType: vehicleType ?? 'Vehicle',
      ownerName: ownerName ?? driverName,
      driverName: driverName,
      driverRelationship: driverRelationship,
      timeIn: occurredAt,
      action: action,
      status: localStatus,
      blockReason: localStatus == GateStatus.blocked ? notes : null,
    );
    await LocalCacheService.appendLocalLog(localEntry);

    // 2. Live write
    final outcome = await _postForOutcome(ApiConstants.logsEndpoint, payload);
    if (outcome == WriteOutcome.accepted) {
      lastGateLogId = int.tryParse('${lastResponseData?['id'] ?? ''}');
      if (action == 'Entry Recorded' || action == 'Exit Approved') {
        unawaited(flushOwnerNotices());
      }
      debugPrint('[ApiService] Gate passage logged to server for $plateNumber');
      unawaited(
        LocalCacheService.updateVehicleCampusStatus(plateNumber, status),
      );
      MockData.updateVehicleCampusStatus(plateNumber, status);
      unawaited(SyncQueueService().processQueue());
      return true;
    }
    if (outcome == WriteOutcome.refused) {
      debugPrint(
        '[ApiService] Server refused the gate passage for $plateNumber: $lastWriteError',
      );
      // It was NOT recorded: take our own copy back out, so the guard's list and inside-count do not show a
      // passage the server never accepted, and let the dashboard reload from the cache.
      await LocalCacheService.removeLocalLog(localEntry.id);
      SyncQueueService().lastSyncTimeNotifier.value = DateTime.now();
      return false;
    }

    // 3. No connection: queue it with the time it happened; it is sent the moment the connection is back
    debugPrint('[ApiService] Offline: queuing gate passage for $plateNumber');
    unawaited(LocalCacheService.updateVehicleCampusStatus(plateNumber, status));
    MockData.updateVehicleCampusStatus(plateNumber, status);
    await SyncQueueService().enqueue(
      type: 'gate_log',
      payload: payload,
      clientRef: clientRef,
      occurredAt: occurredAt,
    );
    return true;
  }

  /// Direct HTTP post for a security incident (live write)
  static Future<bool> reportIncidentDirect(Map<String, dynamic> payload) async {
    return (await _postForOutcome(ApiConstants.incidentsEndpoint, payload)) ==
        WriteOutcome.accepted;
  }

  /// Issues a violation to a vehicle (the vehicle is then on hold and the owner is notified). Online only: a
  /// violation is never queued. Returns null on success, otherwise a message the guard can read.
  static Future<String?> issueViolation({
    required String plateNumber,
    required String type,
    String notes = '',
  }) async {
    try {
      final uri = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.violationsEndpoint}',
      );
      lastViolationId = null;
      final res = await _post(
        uri,
        jsonEncode({'plate': plateNumber, 'type': type, 'notes': notes}),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        try {
          final body = jsonDecode(res.body);
          final violation = body is Map
              ? (body['data'] is Map ? body['data']['violation'] : null)
              : null;
          if (violation is Map) {
            lastViolationId = int.tryParse('${violation['id']}');
          }
        } catch (_) {}
        return null;
      }
      if (res.statusCode == 401) {
        return 'Your session expired. Sign in again to issue a violation.';
      }
      if (res.statusCode >= 500) {
        return 'No connection to the server. Try again.';
      }
      return _messageOf(res) ??
          'The violation could not be recorded (HTTP ${res.statusCode}).';
    } catch (e) {
      debugPrint('[ApiService] issueViolation note: $e');
      return 'No connection to the server. Try again.';
    }
  }

  /// Post a security incident hold; queued with its real time when offline
  static Future<bool> reportIncident({
    required String plateNumber,
    required String driverName,
    required String reason,
    String gatePoint = 'Gate 1 (Main Ingress)',
    String officer = 'Gate Security Officer',
    String notes = '',
  }) async {
    final clientRef = SyncQueueService.newClientRef();
    final occurredAt = DateTime.now();
    final Map<String, dynamic> payload = {
      'plateNumber': plateNumber,
      'driverName': driverName,
      'reason': reason,
      'gatePoint': gatePoint,
      'officer': officer,
      'notes': notes,
      'client_ref': clientRef,
    };

    final outcome = await _postForOutcome(
      ApiConstants.incidentsEndpoint,
      payload,
    );
    if (outcome == WriteOutcome.accepted) return true;
    if (outcome == WriteOutcome.refused) {
      debugPrint(
        '[ApiService] Server refused the incident for $plateNumber: $lastWriteError',
      );
      return false;
    }

    debugPrint(
      '[ApiService] Offline: queuing security incident for $plateNumber',
    );
    await SyncQueueService().enqueue(
      type: 'incident',
      payload: payload,
      clientRef: clientRef,
      occurredAt: occurredAt,
    );
    return true;
  }

  /// Direct HTTP post for visitor pass creation (live write)
  static Future<bool> postVisitorPassDirect(
    Map<String, dynamic> payload,
  ) async {
    return (await _postForOutcome(ApiConstants.visitorsEndpoint, payload)) ==
        WriteOutcome.accepted;
  }

  /// Issues a visitor pass.
  /// Online, the server records it at once. Offline, the pass stays valid on this phone (the guard hands the visitor the
  /// QR as usual) and is queued with the time it was issued; it reaches the server the moment a connection is back, with
  /// the same pass code, and is dated the day it was issued. Sets [lastWriteQueued] when it was queued.
  /// Returns false only when the server REFUSED the pass (for example the plate belongs to a registered vehicle or
  /// already has a pass today): [lastWriteError] says why.
  static Future<bool> postVisitorPass(VisitorPass pass) async {
    lastWriteQueued = false;
    lastCreatedVisitorPass = null;
    final clientRef = SyncQueueService.newClientRef();
    final occurredAt = DateTime.now();
    final Map<String, dynamic> payload = Map<String, dynamic>.from(
      pass.toJson(),
    );

    final outcome = await _postForOutcome(
      ApiConstants.visitorsEndpoint,
      payload,
    );
    if (outcome == WriteOutcome.accepted) {
      if (lastResponseData != null) {
        try {
          lastCreatedVisitorPass = VisitorPass.fromJson(lastResponseData!);
        } catch (_) {}
      }
      unawaited(SyncQueueService().processQueue());
      return true;
    }
    if (outcome == WriteOutcome.refused) {
      debugPrint(
        '[ApiService] Server refused visitor pass ${pass.passId}: $lastWriteError',
      );
      return false;
    }

    debugPrint(
      '[ApiService] Offline: queuing visitor pass ${pass.passId} for automatic sync',
    );
    await SyncQueueService().enqueue(
      type: 'visitor_pass',
      payload: payload,
      clientRef: clientRef,
      occurredAt: occurredAt,
    );
    lastWriteQueued = true;
    return true;
  }

  /// Direct HTTP post for visitor exit checkout (live write)
  static Future<bool> postVisitorExitDirect(
    String passId,
    String plateNumber,
  ) async {
    final payload = <String, dynamic>{
      'passId': passId,
      'plateNumber': plateNumber,
      'exitTime': DateTime.now().toIso8601String(),
    };
    return (await _postForOutcome(
          '${ApiConstants.visitorsEndpoint}?action=exit',
          payload,
        )) ==
        WriteOutcome.accepted;
  }

  /// Post visitor checkout upon exit; queued with its real time when offline
  static Future<bool> postVisitorExit(String passId, String plateNumber) async {
    final clientRef = SyncQueueService.newClientRef();
    final occurredAt = DateTime.now();
    final Map<String, dynamic> payload = {
      'passId': passId,
      'plateNumber': plateNumber,
      'exitTime': occurredAt.toIso8601String(),
    };

    final outcome = await _postForOutcome(
      '${ApiConstants.visitorsEndpoint}?action=exit',
      payload,
    );
    if (outcome == WriteOutcome.accepted) {
      unawaited(SyncQueueService().processQueue());
      return true;
    }
    if (outcome == WriteOutcome.refused) {
      debugPrint(
        '[ApiService] Server refused the checkout of $passId / $plateNumber: $lastWriteError',
      );
      return false;
    }

    debugPrint(
      '[ApiService] Offline: queuing visitor checkout for $passId / $plateNumber',
    );
    await SyncQueueService().enqueue(
      type: 'visitor_exit',
      payload: payload,
      clientRef: clientRef,
      occurredAt: occurredAt,
    );
    return true;
  }

  /// Query server for a visitor pass by ID or Plate
  static Future<VisitorPass?> lookupVisitorPass(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return null;
    try {
      final uri = Uri.parse(
        '${ApiConstants.baseUrl}/visitors.php?q=${Uri.encodeComponent(clean)}',
      );
      final res = await _get(uri);
      if (res.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(res.body);
        if (body['status'] == 'success' && body['data'] != null) {
          final data = body['data'];
          if (data is Map<String, dynamic>) {
            return VisitorPass.fromJson(data);
          } else if (data is Map) {
            return VisitorPass.fromJson(Map<String, dynamic>.from(data));
          } else if (data is List && data.isNotEmpty && data.first is Map) {
            return VisitorPass.fromJson(Map<String, dynamic>.from(data.first));
          }
        }
      }
    } catch (e) {
      debugPrint('[ApiService] Lookup visitor pass note: $e');
    }
    return null;
  }

  /// Asks the server to send the owner e-mails that are waiting ("is this you?" on entry / exit). Called right after a passage
  /// was recorded, in its own request that nobody waits for: the e-mail is sent there, so the gate is never held up by the mail
  /// server. Failures are ignored (the e-mail then goes out with the next call or maintenance run).
  static Future<void> flushOwnerNotices() async {
    try {
      await _post(Uri.parse('${ApiConstants.baseUrl}/notices_send.php'), '{}');
    } catch (e) {
      debugPrint('[ApiService] flushOwnerNotices note: $e');
    }
  }

  /// Uploads one evidence photo (see api/evidence.php). Returns null on success, otherwise a message to show.
  static Future<String?> uploadEvidence(Map<String, dynamic> payload) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/evidence.php');
      final res = await _post(uri, jsonEncode(payload));
      if (res.statusCode == 200 || res.statusCode == 201) return null;
      if (res.statusCode == 401) {
        return 'Your session expired. Sign in again to send photos.';
      }
      if (res.statusCode >= 500) {
        return 'No connection to the server. The photo was not sent.';
      }
      return _messageOf(res) ??
          'The photo could not be saved (HTTP ${res.statusCode}).';
    } catch (e) {
      debugPrint('[ApiService] uploadEvidence note: $e');
      return 'No connection to the server. The photo was not sent.';
    }
  }

  /// Who is on duty, my open shift and the latest handover note (GET /api/shifts.php). Null when unreachable.
  static Future<Map<String, dynamic>?> fetchShifts() async {
    try {
      final res = await _get(Uri.parse('${ApiConstants.baseUrl}/shifts.php'));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is Map && body['data'] is Map) {
        return Map<String, dynamic>.from(body['data']);
      }
    } catch (e) {
      debugPrint('[ApiService] fetchShifts note: $e');
    }
    return null;
  }

  /// Goes on duty at [gate]. Returns {'shift': .., 'handover': ..} or {'error': message}.
  static Future<Map<String, dynamic>> startShift(String gate) async {
    try {
      final res = await _post(
        Uri.parse('${ApiConstants.baseUrl}/shifts.php'),
        jsonEncode({'action': 'start', 'gate': gate}),
      );
      final body = jsonDecode(res.body);
      if ((res.statusCode == 200 || res.statusCode == 201) &&
          body is Map &&
          body['data'] is Map) {
        return Map<String, dynamic>.from(body['data']);
      }
      return {
        'error':
            _messageOf(res) ?? 'Could not go on duty (HTTP ${res.statusCode}).',
      };
    } catch (e) {
      return {'error': 'No connection to the server.'};
    }
  }

  /// Ends my shift with an optional handover note. Returns null on success, otherwise a message to show.
  static Future<String?> endShift(String notes) async {
    try {
      final res = await _post(
        Uri.parse('${ApiConstants.baseUrl}/shifts.php'),
        jsonEncode({'action': 'end', 'notes': notes}),
      );
      if (res.statusCode == 200) return null;
      if (res.statusCode == 409) return null; // not on duty: nothing to end
      return _messageOf(res) ??
          'Could not end the shift (HTTP ${res.statusCode}).';
    } catch (e) {
      return 'No connection to the server.';
    }
  }

  /// Verify pass against backend /api/verify.php
  /// Automatic movements require a named staff session and are never sent to the offline queue.
  static Future<Map<String, dynamic>> movementRequest(
    Map<String, dynamic> payload,
  ) async {
    http.Response response;
    try {
      response = await _post(
        Uri.parse('${ApiConstants.baseUrl}/movements.php'),
        jsonEncode(payload),
      );
    } catch (_) {
      throw const MovementApiException(
        'The connection was lost. Retry this confirmation to check whether it was saved.',
        'CONNECTION_ERROR',
        retryable: true,
      );
    }
    Map<String, dynamic> body;
    try {
      body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const MovementApiException(
        'The server response was interrupted. Retry this confirmation to check its result.',
        'INVALID_RESPONSE',
        retryable: true,
      );
    }
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    throw MovementApiException(
      body['message']?.toString() ??
          'Could not reach the server. Retry this confirmation.',
      (body['data'] is Map ? body['data']['code'] : null)?.toString() ??
          'SERVER_ERROR',
      retryable: response.statusCode >= 500 || response.statusCode == 429,
    );
  }

  static Future<Map<String, dynamic>?> verifyPassWithServer({
    String? qrCode,
    String? plate,
    String gateType = 'Ingress',
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/verify.php');
      final payload = jsonEncode({
        if (qrCode != null && qrCode.isNotEmpty) 'qr_code': qrCode,
        if (plate != null && plate.isNotEmpty) 'plate': plate,
        'gate_type': gateType,
      });
      final res = await _post(uri, payload);
      if (res.statusCode == 200) {
        lastVerifyError = null;
        final Map<String, dynamic> body = jsonDecode(res.body);
        if (body['status'] == 'success' &&
            body['data'] is Map<String, dynamic>) {
          return body['data'] as Map<String, dynamic>;
        }
        return body;
      } else if (res.statusCode >= 500) {
        lastVerifyError = 'Cannot connect to server (HTTP ${res.statusCode})';
        return {
          'status': 'error',
          'error_type': 'network_error',
          'message': lastVerifyError,
        };
      }
    } catch (e) {
      debugPrint('[ApiService] Verify pass exception: $e');
      lastVerifyError = 'Network connection failure ($e)';
      return {
        'status': 'error',
        'error_type': 'network_error',
        'message': lastVerifyError,
      };
    }
    return null;
  }

  /// Fetch system configuration settings (e.g. visitor pass validity duration)
  /// from the backend API (/api/settings.php).
  static Future<Map<String, dynamic>?> fetchSystemSettings({
    bool requireLive = false,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/settings.php');
      final res = await _get(uri);
      if (res.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(res.body);
        if (body['status'] == 'success' && body['data'] != null) {
          final raw = body['data'];
          final data = raw is List
              ? <String, dynamic>{
                  for (final row in raw)
                    (row as Map)['key'].toString(): row['value'],
                }
              : Map<String, dynamic>.from(raw as Map);
          final hours = int.tryParse(
            data['visitor_pass_validity_hours']?.toString() ?? '',
          );
          if (hours != null && hours > 0) {
            await LocalCacheService.saveVisitorPassValidityHours(hours);
            debugPrint(
              '[ApiService] Updated visitor pass validity duration rule to $hours hours',
            );
          }
          return data;
        }
      }
    } catch (e) {
      if (requireLive) rethrow;
      debugPrint('[ApiService] fetchSystemSettings note: $e');
    }
    if (requireLive) throw StateError('Could not refresh system settings.');
    return null;
  }
}
