import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../repositories/auth_repository.dart';

/// Central Authentication Service managing active guard session
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  AuthService._internal({AuthRepository? repository})
      : _repository = repository ?? ApiAuthRepository();

  AuthRepository _repository;
  final ValueNotifier<GuardUser?> userNotifier = ValueNotifier<GuardUser?>(null);

  GuardUser? get currentUser => userNotifier.value;
  bool get isAuthenticated => userNotifier.value != null;
  GuardRole? get currentRole => userNotifier.value?.role;

  @visibleForTesting
  void setRepository(AuthRepository repository) {
    _repository = repository;
  }

  Future<GuardUser> login({
    required String username,
    required String password,
  }) async {
    final user = await _repository.login(
      username: username,
      password: password,
    );
    userNotifier.value = user;
    return user;
  }

  Future<void> logout() async {
    await _repository.logout();
    userNotifier.value = null;
  }
}
