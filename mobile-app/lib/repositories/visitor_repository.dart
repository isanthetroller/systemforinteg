import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/visitor_pass_model.dart';
import '../services/api_service.dart';
import '../services/local_cache_service.dart';

/// Repository managing temporary visitor passes with dual in-memory and backend synchronization.
class VisitorRepository {
  static final VisitorRepository _instance = VisitorRepository._internal();
  factory VisitorRepository() => _instance;

  VisitorRepository._internal() {
    _seedTestPasses();
  }

  final List<VisitorPass> _passes = [];
  final ValueNotifier<List<VisitorPass>> passesNotifier = ValueNotifier<List<VisitorPass>>([]);

  /// Initial test dataset covering all operational pass states:
  /// - Active pass (ready for exit checkout)
  /// - Expired pass (overtime stay on campus)
  /// - Blocked pass (security blacklist hold)
  /// - Used pass (already checked out)
  void _seedTestPasses() {
    final cached = LocalCacheService.getCachedVisitorPasses();
    if (cached.isNotEmpty) {
      _passes.addAll(cached);
      passesNotifier.value = List.unmodifiable(_passes);
      return;
    }

    final now = DateTime.now();

    _passes.addAll([
      // 1. Valid Active Pass
      VisitorPass(
        passId: 'NCST-VIS-2026-1001',
        visitorName: 'Maria Elena Gomez',
        plateNumber: 'NDK-1234',
        vehiclePhotoUrl: 'assets/images/kriz_monares.jpg',
        entryTime: now.subtract(const Duration(hours: 1, minutes: 20)),
        expiryTime: now.add(const Duration(hours: 6, minutes: 40)),
        status: VisitorPassStatus.active,
        registeredByGuard: 'Officer J. Hernandez',
        gatePoint: 'Gate 1 (Main Ingress)',
        notes: 'Campus Registrar Appointment',
      ),

      // 2. Expired Pass (Overtime stay > 8 hours ago)
      VisitorPass(
        passId: 'NCST-VIS-2026-1002',
        visitorName: 'Pedro Santos Jr.',
        plateNumber: 'VIS-EXPIRED',
        vehiclePhotoUrl: null,
        entryTime: now.subtract(const Duration(hours: 9, minutes: 45)),
        expiryTime: now.subtract(const Duration(hours: 1, minutes: 45)), // Expired
        status: VisitorPassStatus.expired,
        registeredByGuard: 'Officer J. Hernandez',
        gatePoint: 'Gate 1 (Main Ingress)',
        notes: 'Overtime Visitor Stay',
      ),

      // 3. Blocked Pass (Security Incident / Blacklisted)
      VisitorPass(
        passId: 'NCST-VIS-2026-1003',
        visitorName: 'Juan Carlos Reyes',
        plateNumber: 'VIS-BLOCKED',
        vehiclePhotoUrl: null,
        entryTime: now.subtract(const Duration(hours: 2)),
        expiryTime: now.add(const Duration(hours: 6)),
        status: VisitorPassStatus.blocked,
        registeredByGuard: 'Officer J. Hernandez',
        gatePoint: 'Gate 1 (Main Ingress)',
        notes: 'Security Blacklist: Trespassing / Reckless driving',
      ),

      // 4. Used Pass (Already checked out previously)
      VisitorPass(
        passId: 'NCST-VIS-2026-1004',
        visitorName: 'Ana Patricia Lim',
        plateNumber: 'VIS-USED',
        vehiclePhotoUrl: null,
        entryTime: now.subtract(const Duration(hours: 4)),
        expiryTime: now.add(const Duration(hours: 4)),
        exitTime: now.subtract(const Duration(hours: 1)),
        status: VisitorPassStatus.used,
        registeredByGuard: 'Officer J. Hernandez',
        gatePoint: 'Gate 1 (Main Ingress)',
        notes: 'Regular Campus Visit - Completed',
      ),
    ]);

    passesNotifier.value = List.unmodifiable(_passes);
  }

  List<VisitorPass> getAllPasses() => List.unmodifiable(_passes);

  List<VisitorPass> getActivePasses() {
    return _passes.where((p) => p.isActive).toList();
  }

  /// Registers a newly created visitor pass, saves to local repository,
  /// and forwards to backend API when online.
  Future<VisitorPass> registerPass(VisitorPass pass) async {
    _passes.insert(0, pass);
    passesNotifier.value = List.unmodifiable(_passes);
    await LocalCacheService.saveVisitorPasses(_passes.map((p) => p.toJson()).toList());

    // Forward to backend service
    await ApiService.postVisitorPass(pass);

    return pass;
  }

  /// Look up visitor pass by Pass ID, raw QR code string, or License Plate
  Future<VisitorPass?> lookupPass(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return null;

    // 1. Try structured QR payload parsing
    final parsed = VisitorPass.fromQrPayload(clean);
    if (parsed != null) {
      // Find matching in local registry
      final existing = _passes.cast<VisitorPass?>().firstWhere(
        (p) => p?.passId == parsed.passId || p?.plateNumber.toUpperCase() == parsed.plateNumber.toUpperCase(),
        orElse: () => null,
      );
      return existing ?? parsed;
    }

    // 2. Direct Pass ID match
    for (final p in _passes) {
      if (p.passId.toLowerCase() == clean.toLowerCase()) {
        return p;
      }
    }

    // 3. Normalized plate match
    final normQuery = clean.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
    for (final p in _passes) {
      final normPlate = p.plateNumber.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
      if (normPlate == normQuery) {
        return p;
      }
    }

    // 4. Fallback query to backend API if not found in memory
    return await ApiService.lookupVisitorPass(clean);
  }

  /// Process visitor checkout upon campus exit
  Future<bool> checkoutPass(String passId, {String? notes}) async {
    final idx = _passes.indexWhere((p) => p.passId == passId);
    if (idx != -1) {
      final updated = _passes[idx].copyWith(
        status: VisitorPassStatus.used,
        exitTime: DateTime.now(),
        notes: notes ?? _passes[idx].notes,
      );
      _passes[idx] = updated;
      passesNotifier.value = List.unmodifiable(_passes);
      await LocalCacheService.saveVisitorPasses(_passes.map((p) => p.toJson()).toList());

      // Notify backend
      unawaited(ApiService.postVisitorExit(passId, updated.plateNumber));
      return true;
    }
    return false;
  }

  /// Flag/block a visitor pass
  Future<bool> blockPass(String passId, {required String reason}) async {
    final idx = _passes.indexWhere((p) => p.passId == passId);
    if (idx != -1) {
      final updated = _passes[idx].copyWith(
        status: VisitorPassStatus.blocked,
        notes: reason,
      );
      _passes[idx] = updated;
      passesNotifier.value = List.unmodifiable(_passes);
      await LocalCacheService.saveVisitorPasses(_passes.map((p) => p.toJson()).toList());
      return true;
    }
    return false;
  }
}
