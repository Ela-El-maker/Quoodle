import 'dart:convert';

String canonicalizeJson(Map<String, dynamic> json) {
  final sortedKeys = json.keys.toList()..sort();
  final canonical = <String, dynamic>{};
  for (final key in sortedKeys) {
    canonical[key] = json[key];
  }
  return jsonEncode(canonical);
}
