import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'json_canonicalizer.dart';

/// Sign a canonical JSON payload with Ed25519.
///
/// [privateKeyBytes] must be the 32-byte Ed25519 seed.
/// Returns a base64-encoded detached signature.
Future<String> signPayload(
  Map<String, dynamic> payload,
  List<int> privateKeyBytes,
) async {
  final canonical = canonicalizeJson(payload);
  final message = utf8.encode(canonical);
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPairFromSeed(privateKeyBytes);
  final signature = await algorithm.sign(message, keyPair: keyPair);
  return base64Encode(Uint8List.fromList(signature.bytes));
}
