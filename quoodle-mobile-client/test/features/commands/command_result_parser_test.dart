import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/features/commands/presentation/result/command_result_parser.dart';

void main() {
  group('command_result_parser', () {
    test('normalizes screenshot payload and artifact URL', () {
      final parsed = parseCommandResult(<String, dynamic>{
        'method': 'screenshot_capture',
        'result': <String, dynamic>{
          'status': 'ok',
          'artifact_url': 'http://10.0.2.2:8088/api/artifact/abc123',
          'artifact_checksum': 'hash',
          'data': <String, dynamic>{
            'capture': <String, dynamic>{'width': 1920, 'height': 1080}
          },
        },
      });

      expect(parsed.canonicalMethod, 'screenshot');
      expect(parsed.kind, ParsedResultKind.screenshot);
      expect(parsed.artifactUrl, 'http://10.0.2.2:8088/api/artifact/abc123');
      expect(parsed.artifactChecksum, 'hash');
    });

    test('extracts process rows from result.data.processes', () {
      final parsed = parseCommandResult(<String, dynamic>{
        'method': 'list_processes',
        'result': <String, dynamic>{
          'data': <String, dynamic>{
            'processes': <Map<String, dynamic>>[
              <String, dynamic>{'pid': 1, 'name': 'init'},
              <String, dynamic>{'pid': 20, 'name': 'bash'},
            ],
          },
        },
      });

      final rows = extractProcessRows(parsed.resultData);
      expect(rows, hasLength(2));
      expect(rows.first['pid'], 1);
      expect(rows.last['name'], 'bash');
    });

    test('extracts filesystem entries from entries array', () {
      final parsed = parseCommandResult(<String, dynamic>{
        'method': 'list_files',
        'result': <String, dynamic>{
          'data': <String, dynamic>{
            'entries': <Map<String, dynamic>>[
              <String, dynamic>{'path': 'tmp', 'is_dir': true},
              <String, dynamic>{'path': 'tmp/log.txt', 'is_dir': false},
            ],
          },
        },
      });

      final entries = extractFileSystemEntries(parsed.resultData);
      expect(entries, hasLength(2));
      expect(entries.first.path, 'tmp');
      expect(entries.first.isDirectory, isTrue);
      expect(entries.last.name, 'log.txt');
      expect(entries.last.parentPath, 'tmp');
    });

    test('extracts system info map from data object', () {
      final parsed = parseCommandResult(<String, dynamic>{
        'method': 'collect_system_info',
        'result': <String, dynamic>{
          'data': <String, dynamic>{
            'schema_version': 'v2',
            'identity': <String, dynamic>{'hostname': 'WKSTN-01'},
            'os': <String, dynamic>{'platform': 'windows'},
          },
        },
      });

      final info = extractSystemInfoData(parsed.resultData);
      expect(info['schema_version'], 'v2');
      expect((info['identity'] as Map)['hostname'], 'WKSTN-01');
      expect((info['os'] as Map)['platform'], 'windows');
    });

    test('normalizes relative artifact URL variants', () {
      expect(normalizeArtifactUrl('/api/artifact/id-1'), '/api/artifact/id-1');
      expect(normalizeArtifactUrl('api/artifact/id-2'), '/api/artifact/id-2');
      expect(normalizeArtifactUrl('  '), '');
    });
  });
}
