import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Layer boundaries (migrated features)', () {
    test('domain layers do not import Flutter', () {
      final domainFiles = _findDartFiles('lib/features')
          .where((path) =>
              path.contains('/features/auth/domain/') ||
              path.contains('/features/dashboard/domain/') ||
              path.contains('/features/notifications/domain/') ||
              path.contains('/features/devices/domain/') ||
              path.contains('/features/commands/domain/') ||
              path.contains('/features/alerts/domain/') ||
              path.contains('/features/audit/domain/') ||
              path.contains('/features/settings/domain/'))
          .toList();

      for (final filePath in domainFiles) {
        final source = File(filePath).readAsStringSync();
        expect(
          source.contains("import 'package:flutter") ||
              source.contains('import "package:flutter'),
          isFalse,
          reason: 'Flutter import found in domain file: $filePath',
        );
      }
    });

    test('presentation layers do not import data sources', () {
      final presentationFiles = _findDartFiles('lib/features')
          .where((path) =>
              path.contains('/features/auth/presentation/') ||
              path.contains('/features/dashboard/presentation/') ||
              path.contains('/features/notifications/presentation/') ||
              path.contains('/features/devices/presentation/') ||
              path.contains('/features/commands/presentation/') ||
              path.contains('/features/alerts/presentation/') ||
              path.contains('/features/audit/presentation/') ||
              path.contains('/features/analytics/presentation/') ||
              path.contains('/features/settings/presentation/'))
          .where((path) => !path.endsWith('_providers.dart'))
          .toList();

      final dataImportPattern = RegExp(
        "import\\s+['\\\"].*/features/.*/data/",
      );

      for (final filePath in presentationFiles) {
        final source = File(filePath).readAsStringSync();
        expect(
          dataImportPattern.hasMatch(source),
          isFalse,
          reason: 'Data-layer import found in presentation file: $filePath',
        );
      }
    });
  });

  group('Phase 7 hardening', () {
    test('no app code imports global app_export barrel', () {
      final appFiles = _findDartFiles('lib');
      for (final filePath in appFiles) {
        if (filePath.endsWith('/core/app_export.dart')) {
          continue;
        }

        final source = File(filePath).readAsStringSync();
        expect(
          source.contains('core/app_export.dart'),
          isFalse,
          reason: 'Global barrel import found in: $filePath',
        );
      }
    });

    test('named Navigator push APIs are retired', () {
      final appFiles = _findDartFiles('lib');
      final legacyPushPattern = RegExp(
        r'Navigator\.(pushNamed|pushNamedAndRemoveUntil|pushReplacementNamed)',
      );

      for (final filePath in appFiles) {
        final source = File(filePath).readAsStringSync();
        expect(
          legacyPushPattern.hasMatch(source),
          isFalse,
          reason: 'Legacy named Navigator API found in: $filePath',
        );
      }
    });

    test('app code does not import legacy services facade', () {
      final appFiles = _findDartFiles('lib');
      for (final filePath in appFiles) {
        if (filePath.contains('/lib/services/')) {
          continue;
        }

        final source = File(filePath).readAsStringSync();
        expect(
          source.contains("import 'package:secure_device_control/services/"),
          isFalse,
          reason: 'Legacy services facade import found in: $filePath',
        );
      }
    });
  });
}

Iterable<String> _findDartFiles(String rootPath) sync* {
  final rootDir = Directory(rootPath);
  if (!rootDir.existsSync()) {
    return;
  }

  final entities = rootDir.listSync(recursive: true, followLinks: false);
  for (final entity in entities) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity.path;
    }
  }
}
