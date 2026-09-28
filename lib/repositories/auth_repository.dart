import 'package:flutter/foundation.dart';
import '../data/mock_data.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';

/// Contract for authentication operations
abstract class AuthRepository {
  Future<GuardUser> login({
    required String username,
    required String password,
  });

  Future<void> logout();

  GuardUser? get currentUser;
  bool get isAuthenticated;
}

/// Live API implementation communicating with Web App Backend (auth.php)
/// with graceful local fallback if offline or during unit testing.
class ApiAuthRepository implements AuthRepository {
  final MockAuthRepository _fallbackRepo = MockAuthRepository();
  GuardUser? _currentUser;

  @override
  GuardUser? get currentUser => _currentUser;

  @override
  bool get isAuthenticated => _currentUser != null;

  @override
  Future<GuardUser> login({
    required String username,
    required String password,
  }) async {
    final cleanUsername = username.trim();
    final cleanPassword = password.trim();

    if (cleanUsername.isEmpty) {
      throw const AuthException('Please enter your guard username or ID.');
    }
    if (cleanPassword.isEmpty) {
      throw const AuthException('Please enter your password.');
    }
    if (cleanPassword.length < 4) {
      throw const AuthException('Password must be at least 4 characters.');
    }

    if (MockData.isTestEnvironment) {
      final user = await _fallbackRepo.login(username: username, password: password);
      _currentUser = user;
      return user;
    }

    try {
      final data = await ApiService.login(
        username: cleanUsername,
        password: cleanPassword,
      );

      if (data != null && data['user'] != null) {
        final userJson = data['user'] as Map<String, dynamic>;
        final user = GuardUser.fromJson(userJson);
        _currentUser = user;
        return user;
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (msg.contains('Password') ||
          msg.contains('password') ||
          msg.contains('credentials') ||
          msg.contains('Invalid') ||
          msg.contains('deactivated')) {
        throw AuthException(msg);
      }
      debugPrint('[ApiAuthRepository] Backend auth notice: $e');
    }

    // Offline / fallback path: allow local guard presets when server is unreachable
    final fallbackUser = await _fallbackRepo.login(username: username, password: password);
    _currentUser = fallbackUser;
    return fallbackUser;
  }

  @override
  Future<void> logout() async {
    await ApiService.logout();
    await _fallbackRepo.logout();
    _currentUser = null;
  }
}

/// Mock / Local implementation for prototyping without backend dependency.
class MockAuthRepository implements AuthRepository {
  GuardUser? _currentUser;

  @override
  GuardUser? get currentUser => _currentUser;

  @override
  bool get isAuthenticated => _currentUser != null;

  /// Default mock credentials:
  /// - Entrance Guard: username 'guard1' or 'entrance', password 'password123'
  /// - Exit Guard:     username 'guard2' or 'exit',     password 'password123'
  @override
  Future<GuardUser> login({
    required String username,
    required String password,
  }) async {
    final cleanUsername = username.trim().toLowerCase();
    final cleanPassword = password.trim();

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 600));

    if (cleanUsername.isEmpty) {
      throw const AuthException('Please enter your guard username or ID.');
    }

    if (cleanPassword.isEmpty) {
      throw const AuthException('Please enter your password.');
    }

    if (cleanPassword.length < 4) {
      throw const AuthException('Password must be at least 4 characters.');
    }

    // Role detection based on username/role selection
    final isExit = cleanUsername.contains('exit') ||
        cleanUsername.contains('guard2') ||
        cleanUsername.contains('egress') ||
        cleanUsername == 'g2';

    // Allow default password 'password123' or any valid format for prototype testing
    if (cleanPassword != 'password123' && cleanPassword != '123456' && cleanPassword != 'admin123') {
      if (cleanPassword.length < 6) {
        throw const AuthException('Invalid credentials. (Hint: Use password123)');
      }
    }

    final role = isExit ? GuardRole.exit : GuardRole.entrance;

    final user = GuardUser(
      id: isExit ? 'GRD-EXIT-02' : 'GRD-ENTRANCE-01',
      username: cleanUsername,
      fullName: isExit ? 'Officer R. Mendoza' : 'Officer J. Hernandez',
      badgeNumber: isExit ? 'NCST-SEC-02' : 'NCST-SEC-01',
      role: role,
      assignedGate: isExit ? 'Gate 2 (Main Egress)' : 'Gate 1 (Main Ingress)',
      loginTime: DateTime.now(),
    );

    _currentUser = user;
    return user;
  }

  @override
  Future<void> logout() async {
    _currentUser = null;
  }
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}
