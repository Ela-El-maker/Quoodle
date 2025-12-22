import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MobileIdentityService {
  static const _kSeed = 'mobile.ed25519.seed_b64';

  MobileIdentityService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final Ed25519 _algo = Ed25519();

  Future<void> ensureKeypair() async {
    final existing = await _storage.read(key: _kSeed);
    if (existing != null && existing.isNotEmpty) {
      return;
    }

    final seed = _randomSeed32();
    await _storage.write(key: _kSeed, value: base64Encode(seed));
  }

  Future<String> publicKeyBase64() async {
    final keyPair = await _keyPair();
    final publicKey = await keyPair.extractPublicKey() as SimplePublicKey;
    return base64Encode(publicKey.bytes);
  }

  Future<KeyPair> _keyPair() async {
    final seedB64 = await _storage.read(key: _kSeed);
    if (seedB64 == null || seedB64.isEmpty) {
      // If called before ensureKeypair.
      await ensureKeypair();
    }

    final seed = base64Decode((await _storage.read(key: _kSeed))!);
    return _algo.newKeyPairFromSeed(seed);
  }

  Uint8List _randomSeed32() {
    final bytes = Uint8List(32);
    final rng = Random.secure();
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return bytes;
  }
}
