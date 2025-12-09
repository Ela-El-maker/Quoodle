import 'dart:async';

import '../config/environment.dart';

class ApiService {
  Future<void> login({
    required String email,
    required String password,
    String? twoFactorCode,
    String? deviceFingerprint,
    String? pushToken,
  }) async {
    // Phase 8 skeleton: no network call, only placeholder to show intent.
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<void> register({
    required String displayName,
    required String email,
    required String password,
    required String pubkey,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<void> listDevices() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  String get apiBaseUrl => Environment.apiBaseUrl;
}
