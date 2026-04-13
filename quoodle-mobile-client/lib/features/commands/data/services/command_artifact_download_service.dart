import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DownloadedArtifact {
  const DownloadedArtifact({
    required this.filePath,
    required this.fileName,
    required this.sizeBytes,
    required this.checksumVerified,
  });

  final String filePath;
  final String fileName;
  final int sizeBytes;
  final bool checksumVerified;
}

abstract class CommandArtifactDownloader {
  Future<DownloadedArtifact> download({
    required String artifactUrl,
    String? checksum,
  });
}

class CommandArtifactDownloadService implements CommandArtifactDownloader {
  CommandArtifactDownloadService(this._dio);

  final Dio _dio;

  @override
  Future<DownloadedArtifact> download({
    required String artifactUrl,
    String? checksum,
  }) async {
    final normalized = artifactUrl.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Artifact URL is empty.');
    }

    final bytes = await _fetchBytes(normalized);
    final artifactsDir = await _resolveArtifactsDir();
    final fileName = _buildFileName(normalized, checksum);
    final filePath = p.join(artifactsDir.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);

    final trimmedChecksum = checksum?.trim() ?? '';
    final hasChecksum = trimmedChecksum.isNotEmpty;
    final checksumVerified =
        !hasChecksum || await _verifyChecksum(bytes, trimmedChecksum);

    return DownloadedArtifact(
      filePath: filePath,
      fileName: fileName,
      sizeBytes: bytes.length,
      checksumVerified: checksumVerified,
    );
  }

  Future<Uint8List> _fetchBytes(String artifactUrl) async {
    final uri = Uri.tryParse(artifactUrl);
    final options = Options(responseType: ResponseType.bytes);
    final Response<List<int>> response;
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      response = await _dio.getUri<List<int>>(uri, options: options);
    } else {
      response = await _dio.get<List<int>>(artifactUrl, options: options);
    }

    final data = response.data;
    if (data == null) {
      throw const FileSystemException('Artifact payload is empty.');
    }
    return Uint8List.fromList(data);
  }

  Future<Directory> _resolveArtifactsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'downloads'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _buildFileName(String artifactUrl, String? checksum) {
    final parsed = Uri.tryParse(artifactUrl);
    var name = parsed == null
        ? p.basename(artifactUrl)
        : p.basename(parsed.path.trim());
    if (name.isEmpty || name == '/' || name == '.') {
      name = 'artifact';
    }

    if (!name.contains('.')) {
      final suffix = checksum == null || checksum.isEmpty
          ? DateTime.now().millisecondsSinceEpoch.toString()
          : checksum.substring(0, checksum.length.clamp(0, 8));
      name = '$name-$suffix.bin';
    }
    return name;
  }

  Future<bool> _verifyChecksum(Uint8List bytes, String checksum) async {
    final digest = await Sha256().hash(bytes);
    final hex = digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toLowerCase();
    return hex == checksum.toLowerCase();
  }
}
