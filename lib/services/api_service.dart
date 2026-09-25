import 'dart:convert';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/constants/api_constants.dart';
import '../models/vehicle_model.dart';

/// Central API Service for Flutter Android App communicating with InfinityFree Backend
class ApiService {
  static http.Client _client = http.Client();
  static String? _testCookie;

  @visibleForTesting
  static void setClientForTesting(http.Client client) {
    _client = client;
  }

  @visibleForTesting
  static void resetClient() {
    _client = http.Client();
    _testCookie = null;
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

        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc, padding: null));
        final decrypted = encrypter.decryptBytes(enc.Encrypted(Uint8List.fromList(cipherBytes)), iv: iv);
        final cookie = decrypted.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toLowerCase();
        debugPrint('[ApiService] Successfully solved InfinityFree bot challenge cookie: $cookie');
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
    return headers;
  }

  /// Specialized headers for image loading (Accept: image/* and anti-bot cookie)
  static Map<String, String> get imageHeaders {
    final headers = <String, String>{
      'User-Agent': ApiConstants.defaultHeaders['User-Agent'] ?? 'SecurePark-GateScanner/2.4',
      'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    };
    if (_testCookie != null && _testCookie!.isNotEmpty) {
      headers['Cookie'] = '__test=$_testCookie';
    }
    return headers;
  }

  /// Memory cache for fetched image bytes to avoid re-requesting
  static final Map<String, Uint8List> _imageCache = {};

  /// Directly fetch image bytes via HTTP, solving any InfinityFree challenge if encountered
  static Future<Uint8List?> fetchImageBytes(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return null;
    if (_imageCache.containsKey(cleanUrl)) {
      return _imageCache[cleanUrl];
    }

    try {
      final uri = Uri.parse(cleanUrl);
      var res = await _client.get(uri, headers: imageHeaders).timeout(ApiConstants.timeout);
      if (res.body.contains('slowAES.decrypt')) {
        final solved = _solveInfinityFreeChallenge(res.body);
        if (solved != null) {
          _testCookie = solved;
          res = await _client.get(uri, headers: imageHeaders).timeout(ApiConstants.timeout);
        }
      }
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        // Validate that response is an image and not an HTML challenge/error page
        if (!res.body.contains('<!DOCTYPE') && !res.body.contains('<html')) {
          _imageCache[cleanUrl] = res.bodyBytes;
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
      var res = await _client.get(uri, headers: _buildHeaders()).timeout(ApiConstants.timeout);
      if (res.body.contains('slowAES.decrypt')) {
        final solved = _solveInfinityFreeChallenge(res.body);
        if (solved != null) {
          _testCookie = solved;
          res = await _client.get(uri, headers: _buildHeaders()).timeout(ApiConstants.timeout);
        }
      }
      return res;
    } catch (_) {
      return http.Response('{"status":"offline"}', 503);
    }
  }

  static Future<http.Response> _post(Uri uri, String body) async {
    try {
      // If not authenticated with InfinityFree test cookie yet, ping status to solve cookie
      if (_testCookie == null && uri.host.contains('rf.gd')) {
        await _get(Uri.parse('${ApiConstants.baseUrl}${ApiConstants.statsEndpoint}'));
      }
      var res = await _client.post(uri, headers: _buildHeaders(), body: body).timeout(ApiConstants.timeout);
      if (res.body.contains('slowAES.decrypt')) {
        final solved = _solveInfinityFreeChallenge(res.body);
        if (solved != null) {
          _testCookie = solved;
          res = await _client.post(uri, headers: _buildHeaders(), body: body).timeout(ApiConstants.timeout);
        }
      }
      return res;
    } catch (_) {
      return http.Response('{"status":"offline"}', 503);
    }
  }

  /// Query backend for a vehicle by plate number or QR code
  static Future<VehicleRecord?> lookupVehicle(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return null;
    if (clean.startsWith('{') || clean.contains('"plateNumber"')) {
      return (await lookupVehicleByQr(clean)) ?? (await lookupVehicleByPlate(clean));
    }
    return lookupVehicleByPlate(clean);
  }

  /// Query backend for a vehicle by QR pass code or payload
  static Future<VehicleRecord?> lookupVehicleByQr(String qr) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.vehiclesEndpoint}?qr=${Uri.encodeComponent(qr)}');
      final res = await _get(uri);

      if (res.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(res.body);
        if (body['status'] == 'success' && body['data'] != null) {
          return VehicleRecord.fromQrJson(body['data'], rawPayload: 'SERVER_DB_RECORD');
        }
      }
    } catch (e) {
      debugPrint('[ApiService] QR lookup failed or offline: $e');
    }
    return null;
  }

  /// Query backend for a vehicle by plate number
  static Future<VehicleRecord?> lookupVehicleByPlate(String plate) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.vehiclesEndpoint}?plate=${Uri.encodeComponent(plate)}');
      final res = await _get(uri);

      if (res.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(res.body);
        if (body['status'] == 'success' && body['data'] != null) {
          return VehicleRecord.fromQrJson(body['data'], rawPayload: 'SERVER_DB_RECORD');
        }
      }
    } catch (e) {
      debugPrint('[ApiService] Lookup failed or offline: $e');
    }
    return null;
  }

  /// Fetch all registered vehicles from the MySQL database
  static Future<List<VehicleRecord>> fetchVehicles() async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.vehiclesEndpoint}');
      final res = await _get(uri);

      if (res.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(res.body);
        if (body['status'] == 'success' && body['data'] is List) {
          final list = body['data'] as List;
          return list.map((item) => VehicleRecord.fromQrJson(item as Map<String, dynamic>)).toList();
        }
      }
    } catch (e) {
      debugPrint('[ApiService] Fetch vehicles failed or offline: $e');
    }
    return [];
  }

  /// Fetch all recent gate audit logs from the MySQL database
  static Future<List<AuditLogEntry>> fetchLogs() async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.logsEndpoint}');
      final res = await _get(uri);

      if (res.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(res.body);
        if (body['status'] == 'success' && body['data'] is List) {
          final list = body['data'] as List;
          return list
              .map((item) => AuditLogEntry.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[ApiService] Fetch logs failed or offline: $e');
    }
    return [];
  }

  /// Post gate passage (Entry or Exit) to the live MySQL audit log
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
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.logsEndpoint}');
      final payload = jsonEncode({
        'plateNumber': plateNumber,
        'driverName': driverName,
        'driverRelationship': driverRelationship,
        'gatePoint': gatePoint,
        'action': action,
        'status': status,
        'guardName': guardName,
        'notes': notes,
        'vehicleType': vehicleType ?? '',
        'ownerName': ownerName ?? '',
      });

      final res = await _post(uri, payload);

      if (res.statusCode == 200 || res.statusCode == 201) {
        debugPrint('[ApiService] Gate passage logged to server for $plateNumber');
        return true;
      }
    } catch (e) {
      debugPrint('[ApiService] Post gate log failed or offline: $e');
    }
    return false;
  }

  /// Post security incident hold to the server
  static Future<bool> reportIncident({
    required String plateNumber,
    required String driverName,
    required String reason,
    String gatePoint = 'Gate 1 (Main Ingress)',
    String officer = 'Gate Security Officer',
    String notes = '',
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.incidentsEndpoint}');
      final payload = jsonEncode({
        'plateNumber': plateNumber,
        'driverName': driverName,
        'reason': reason,
        'gatePoint': gatePoint,
        'officer': officer,
        'notes': notes,
      });

      final res = await _post(uri, payload);

      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('[ApiService] Report incident failed: $e');
    }
    return false;
  }
}
