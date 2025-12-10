import 'json_canonicalizer.dart';

String signPayload(Map<String, dynamic> payload) {
  // Placeholder academic signature helper.
  return 'sig-' + canonicalizeJson(payload).hashCode.toString();
}
