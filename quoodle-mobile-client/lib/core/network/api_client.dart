abstract class ApiClient {
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  });

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  });
}
