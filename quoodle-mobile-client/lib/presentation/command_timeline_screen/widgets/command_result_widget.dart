import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/app/di/providers.dart';
import 'package:secure_device_control/core/storage/storage_keys.dart';
import 'package:secure_device_control/features/commands/presentation/providers/commands_api_providers.dart';
import 'package:secure_device_control/features/commands/presentation/result/command_result_parser.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/status_badge_widget.dart';

class CommandResultWidget extends ConsumerStatefulWidget {
  const CommandResultWidget({
    super.key,
    required this.command,
    required this.status,
  });

  final Map<String, dynamic> command;
  final CommandStatus status;

  @override
  ConsumerState<CommandResultWidget> createState() =>
      _CommandResultWidgetState();
}

class _CommandResultWidgetState extends ConsumerState<CommandResultWidget> {
  bool _downloadingArtifact = false;

  bool get _isSuccess => widget.status == CommandStatus.completed;

  bool get _isFailed =>
      widget.status == CommandStatus.failed ||
      widget.status == CommandStatus.expired;

  Future<void> _downloadArtifact(String artifactUrl, {String? checksum}) async {
    if (_downloadingArtifact) {
      return;
    }
    setState(() => _downloadingArtifact = true);
    try {
      final result = await ref.read(commandArtifactDownloaderProvider).download(
            artifactUrl: artifactUrl,
            checksum: checksum,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result.checksumVerified
                  ? 'Saved ${result.fileName} (${result.sizeBytes} bytes)'
                  : 'Saved ${result.fileName}, checksum mismatch detected.',
            ),
            backgroundColor:
                result.checksumVerified ? AppTheme.secondary : AppTheme.warning,
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Download failed: $error'),
            backgroundColor: AppTheme.error,
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _downloadingArtifact = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSuccess && !_isFailed) {
      return const SizedBox.shrink();
    }

    final parsed = parseCommandResult(widget.command);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ResultHeader(command: widget.command, status: widget.status),
          const Divider(height: 1, color: AppTheme.borderLight),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ResultTopMeta(
                  parsed: parsed,
                  status: widget.status,
                ),
                const SizedBox(height: 12),
                _TypedResultBody(
                  parsed: parsed,
                  onDownloadArtifact: _downloadArtifact,
                  downloadingArtifact: _downloadingArtifact,
                ),
                const SizedBox(height: 12),
                _DebugSection(
                  result: parsed.result,
                  params: parsed.params,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({
    required this.command,
    required this.status,
  });

  final Map<String, dynamic> command;
  final CommandStatus status;

  bool get _isSuccess => status == CommandStatus.completed;

  Color get _statusColor => _isSuccess ? AppTheme.secondary : AppTheme.error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        children: [
          Icon(
            _isSuccess ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: _statusColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isSuccess ? 'Command Completed' : 'Command Failed',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _statusColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (command.containsKey('executionTimeMs'))
            _MetaChip(
              label: '${command['executionTimeMs']}ms',
              monospace: true,
            ),
        ],
      ),
    );
  }
}

class _ResultTopMeta extends StatelessWidget {
  const _ResultTopMeta({
    required this.parsed,
    required this.status,
  });

  final ParsedCommandResult parsed;
  final CommandStatus status;

  @override
  Widget build(BuildContext context) {
    final isFailed =
        status == CommandStatus.failed || status == CommandStatus.expired;
    final notesText = parsed.resultNotes.ifEmpty(
      isFailed ? parsed.errorMessage.ifEmpty('Command execution failed.') : '',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionLabel('BACKEND RESULT'),
            const Spacer(),
            Flexible(
              child: _MetaChip(label: parsed.canonicalMethod, monospace: true),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetaChip(
                label: 'STATE: ${parsed.executionState}', monospace: true),
            if (parsed.resultStatus.isNotEmpty)
              _MetaChip(
                  label: 'RESULT: ${parsed.resultStatus}', monospace: true),
            if (parsed.errorCode.isNotEmpty)
              _MetaChip(
                  label: 'ERROR: ${parsed.errorCode}', color: AppTheme.error),
          ],
        ),
        if (notesText.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isFailed ? AppTheme.errorMuted : AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isFailed
                    ? AppTheme.error.withAlpha(90)
                    : AppTheme.borderLight,
              ),
            ),
            child: Text(
              notesText,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                color: isFailed ? AppTheme.error : AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TypedResultBody extends StatelessWidget {
  const _TypedResultBody({
    required this.parsed,
    required this.onDownloadArtifact,
    required this.downloadingArtifact,
  });

  final ParsedCommandResult parsed;
  final Future<void> Function(String artifactUrl, {String? checksum})
      onDownloadArtifact;
  final bool downloadingArtifact;

  @override
  Widget build(BuildContext context) {
    switch (parsed.kind) {
      case ParsedResultKind.screenshot:
        return _ScreenshotResultView(
          parsed: parsed,
          downloadingArtifact: downloadingArtifact,
          onDownloadArtifact: onDownloadArtifact,
        );
      case ParsedResultKind.processList:
        return _ProcessListResultView(parsed: parsed);
      case ParsedResultKind.fileSystem:
        return _FileSystemResultView(
          parsed: parsed,
          downloadingArtifact: downloadingArtifact,
          onDownloadArtifact: onDownloadArtifact,
        );
      case ParsedResultKind.systemInfo:
        return _SystemInfoResultView(parsed: parsed);
      case ParsedResultKind.generic:
        return _GenericResultView(parsed: parsed);
    }
  }
}

class _ScreenshotResultView extends ConsumerWidget {
  const _ScreenshotResultView({
    required this.parsed,
    required this.downloadingArtifact,
    required this.onDownloadArtifact,
  });

  final ParsedCommandResult parsed;
  final bool downloadingArtifact;
  final Future<void> Function(String artifactUrl, {String? checksum})
      onDownloadArtifact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artifactUrl = parsed.artifactUrl;
    final checksum = parsed.artifactChecksum;
    final dataMap = parsed.resultData is Map
        ? Map<String, dynamic>.from(parsed.resultData as Map)
        : const <String, dynamic>{};
    final capture = _asMap(dataMap['capture']);
    final authMeta = _asMap(dataMap['authorization']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('SCREENSHOT'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetaChip(
              label:
                  'FORMAT: ${_displayValue(dataMap['format']).ifEmpty(_displayValue(capture['format']).ifEmpty('png'))}',
            ),
            _MetaChip(
              label:
                  'RESOLUTION: ${_displayValue(dataMap['resolution']).ifEmpty(_resolutionLabel(capture))}',
            ),
            _MetaChip(
              label:
                  artifactUrl.isEmpty ? 'ARTIFACT: MISSING' : 'ARTIFACT: READY',
              color:
                  artifactUrl.isEmpty ? AppTheme.warning : AppTheme.secondary,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (artifactUrl.isEmpty)
          _InfoCard(
            icon: Icons.image_not_supported_outlined,
            message: 'Artifact not available for this command result.',
            tone: AppTheme.warning,
          )
        else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.borderLight),
            ),
            child: FutureBuilder<String?>(
              future: ref.read(_artifactAuthHeaderProvider.future),
              builder: (context, snapshot) {
                final token = snapshot.data ?? '';
                final headers = token.isEmpty
                    ? const <String, String>{}
                    : <String, String>{'Authorization': 'Bearer $token'};
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    artifactUrl,
                    headers: headers,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        color: AppTheme.surfaceVariant,
                        child: Text(
                          'Preview unavailable. You can still download the image.',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      );
                    },
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) {
                        return child;
                      }
                      return const SizedBox(
                        height: 140,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primary,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.download_rounded,
                  label: downloadingArtifact ? 'Saving...' : 'Download',
                  onPressed: downloadingArtifact
                      ? null
                      : () => onDownloadArtifact(
                            artifactUrl,
                            checksum: checksum,
                          ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.copy_rounded,
                  label: 'Copy URL',
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: artifactUrl),
                  ),
                ),
              ),
            ],
          ),
          if (checksum.isNotEmpty) ...[
            const SizedBox(height: 8),
            _CopyableField(label: 'CHECKSUM', value: checksum),
          ],
        ],
        if (capture.isNotEmpty) ...[
          const SizedBox(height: 10),
          _KeyValueGrid(title: 'Capture Metadata', values: capture),
        ],
        if (authMeta.isNotEmpty) ...[
          const SizedBox(height: 10),
          _KeyValueGrid(title: 'Authorization', values: authMeta),
        ],
      ],
    );
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return const <String, dynamic>{};
  }

  static String _displayValue(Object? value) {
    if (value == null) {
      return '';
    }
    final text = value.toString().trim();
    return text;
  }

  static String _resolutionLabel(Map<String, dynamic> capture) {
    final width = capture['width'];
    final height = capture['height'];
    if (width is num && height is num) {
      return '${width.toInt()}x${height.toInt()}';
    }
    return 'unknown';
  }
}

class _ProcessListResultView extends StatefulWidget {
  const _ProcessListResultView({required this.parsed});

  final ParsedCommandResult parsed;

  @override
  State<_ProcessListResultView> createState() => _ProcessListResultViewState();
}

class _ProcessListResultViewState extends State<_ProcessListResultView> {
  final TextEditingController _searchController = TextEditingController();
  String _sortColumn = 'pid';
  bool _sortAscending = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = extractProcessRows(widget.parsed.resultData);
    final columns = _resolveColumns(rows);
    final filtered = _applySearch(rows);
    final sorted = _applySort(filtered);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('PROCESS LIST'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _SearchField(
                controller: _searchController,
                hint: 'Search process name, pid, user...',
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            _MetaChip(
              label: '${rows.length} rows',
              monospace: true,
              color: AppTheme.secondary,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          const _InfoCard(
            icon: Icons.list_alt_rounded,
            message: 'No process rows were returned by the backend.',
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.borderLight),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: MediaQuery.of(context).size.width - 64,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        color: AppTheme.surfaceVariant,
                        child: Row(
                          children: columns
                              .map(
                                (column) => _HeaderCell(
                                  label: column,
                                  active: _sortColumn == column,
                                  ascending: _sortAscending,
                                  onTap: () => setState(() {
                                    if (_sortColumn == column) {
                                      _sortAscending = !_sortAscending;
                                    } else {
                                      _sortColumn = column;
                                      _sortAscending = true;
                                    }
                                  }),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                      ...sorted.map(
                        (row) => Row(
                          children: columns
                              .map(
                                (column) => _BodyCell(
                                  value: _displayValue(row[column]),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                      if (sorted.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'No process rows match your search.',
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<String> _resolveColumns(List<Map<String, dynamic>> rows) {
    final preferred = ['pid', 'name', 'ppid', 'threads', 'user', 'path'];
    final discovered = <String>{};
    for (final row in rows) {
      discovered.addAll(row.keys);
    }
    final ordered = <String>[];
    for (final key in preferred) {
      if (discovered.contains(key)) {
        ordered.add(key);
        discovered.remove(key);
      }
    }
    final extra = discovered.toList()..sort();
    ordered.addAll(extra.take(8 - ordered.length.clamp(0, 8)));
    if (ordered.isEmpty) {
      ordered.add('value');
    }
    return ordered;
  }

  List<Map<String, dynamic>> _applySearch(List<Map<String, dynamic>> rows) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return rows;
    }
    return rows.where((row) {
      return row.values.any((value) {
        final text = value?.toString().toLowerCase() ?? '';
        return text.contains(query);
      });
    }).toList(growable: false);
  }

  List<Map<String, dynamic>> _applySort(List<Map<String, dynamic>> rows) {
    final sorted = [...rows];
    sorted.sort((a, b) {
      final av = _displayValue(a[_sortColumn]);
      final bv = _displayValue(b[_sortColumn]);
      final compare = av.compareTo(bv);
      return _sortAscending ? compare : -compare;
    });
    return sorted;
  }

  String _displayValue(Object? value) {
    if (value == null) {
      return '-';
    }
    return value.toString();
  }
}

class _FileSystemResultView extends StatefulWidget {
  const _FileSystemResultView({
    required this.parsed,
    required this.downloadingArtifact,
    required this.onDownloadArtifact,
  });

  final ParsedCommandResult parsed;
  final bool downloadingArtifact;
  final Future<void> Function(String artifactUrl, {String? checksum})
      onDownloadArtifact;

  @override
  State<_FileSystemResultView> createState() => _FileSystemResultViewState();
}

class _FileSystemResultViewState extends State<_FileSystemResultView> {
  final TextEditingController _searchController = TextEditingController();
  String _currentPath = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = extractFileSystemEntries(widget.parsed.resultData);
    final systemInfoData = extractSystemInfoData(widget.parsed.resultData);
    final windowsStyle = inferWindowsStylePaths(
      entries,
      systemInfoData: systemInfoData,
    );

    final byParent = _indexByParent(entries);
    final currentEntries = byParent[_currentPath] ?? const <FileSystemEntry>[];
    final filtered = _applySearch(currentEntries);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('FILESYSTEM'),
        const SizedBox(height: 8),
        _ExplorerToolbar(
          currentPath: _currentPath,
          windowsStyle: windowsStyle,
          onBack: () => setState(() {
            _currentPath = _parentPath(_currentPath);
          }),
          canGoBack: _currentPath.isNotEmpty,
          onRoot: () => setState(() {
            _currentPath = '';
          }),
        ),
        const SizedBox(height: 8),
        _SearchField(
          controller: _searchController,
          hint: 'Search files and folders in current view...',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          const _InfoCard(
            icon: Icons.folder_off_rounded,
            message: 'No filesystem entries were returned in this snapshot.',
          )
        else
          _Breadcrumbs(
            currentPath: _currentPath,
            windowsStyle: windowsStyle,
            onTapPath: (path) => setState(() => _currentPath = path),
          ),
        const SizedBox(height: 8),
        if (entries.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.borderLight),
            ),
            child: Column(
              children: [
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'No entries found in this folder for your search.',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  )
                else
                  ...filtered.map(
                    (entry) => _FileRow(
                      entry: entry,
                      onOpen: entry.isDirectory
                          ? () => setState(() => _currentPath = entry.path)
                          : null,
                      artifactUrl: widget.parsed.artifactUrl,
                      downloadingArtifact: widget.downloadingArtifact,
                      onDownloadArtifact: widget.onDownloadArtifact,
                      checksum: widget.parsed.artifactChecksum,
                    ),
                  ),
                if (widget.parsed.artifactUrl.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: _InfoCard(
                      icon: Icons.info_outline_rounded,
                      message:
                          'File download is unavailable for this snapshot. Control plane did not return an artifact URL.',
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Map<String, List<FileSystemEntry>> _indexByParent(
      List<FileSystemEntry> entries) {
    final byParent = <String, List<FileSystemEntry>>{};
    for (final entry in entries) {
      final parent = entry.parentPath;
      byParent.putIfAbsent(parent, () => <FileSystemEntry>[]).add(entry);
    }
    for (final list in byParent.values) {
      list.sort((a, b) {
        if (a.isDirectory != b.isDirectory) {
          return a.isDirectory ? -1 : 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }
    return byParent;
  }

  List<FileSystemEntry> _applySearch(List<FileSystemEntry> entries) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return entries;
    }
    return entries
        .where(
          (entry) =>
              entry.name.toLowerCase().contains(query) ||
              entry.path.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  String _parentPath(String path) {
    if (path.isEmpty) {
      return '';
    }
    final normalized = path.replaceAll('\\', '/');
    final chunks = normalized.split('/').where((e) => e.isNotEmpty).toList();
    if (chunks.length <= 1) {
      return '';
    }
    if (chunks.length == 2 && RegExp(r'^[A-Za-z]:$').hasMatch(chunks.first)) {
      return '';
    }
    return chunks.sublist(0, chunks.length - 1).join('/');
  }
}

class _SystemInfoResultView extends StatelessWidget {
  const _SystemInfoResultView({required this.parsed});

  final ParsedCommandResult parsed;

  @override
  Widget build(BuildContext context) {
    final info = extractSystemInfoData(parsed.resultData);
    final sections = <_InfoSectionData>[
      _InfoSectionData('Identity', _mapOf(info['identity'])),
      _InfoSectionData('OS', _mapOf(info['os'])),
      _InfoSectionData('Hardware', _mapOf(info['hardware'])),
      _InfoSectionData('Runtime', _mapOf(info['runtime'])),
      _InfoSectionData('Storage', _mapOf(info['storage'])),
      _InfoSectionData('Network', _mapOf(info['network'])),
      _InfoSectionData('Security', _mapOf(info['security'])),
    ];

    final diagnostics = _buildDiagnostics(info);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('SYSTEM INFO'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetaChip(
              label:
                  'SNAPSHOT: ${_displayValue(info['snapshot_type']).ifEmpty('collect_system_info')}',
              monospace: true,
            ),
            _MetaChip(
              label:
                  'SCHEMA: ${_displayValue(info['schema_version']).ifEmpty('unknown')}',
            ),
            _MetaChip(
              label: 'KERNEL MODE: ${_toYesNo(info['kernel_mode'])}',
              color: AppTheme.secondary,
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...sections.where((s) => s.values.isNotEmpty).map(
              (section) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child:
                    _KeyValueGrid(title: section.title, values: section.values),
              ),
            ),
        if (sections.every((s) => s.values.isEmpty))
          const _InfoCard(
            icon: Icons.info_outline_rounded,
            message: 'No structured system info fields were returned.',
          ),
        const SizedBox(height: 2),
        const _SectionLabel('DIAGNOSTICS'),
        const SizedBox(height: 8),
        if (diagnostics.isEmpty)
          const _InfoCard(
            icon: Icons.verified_rounded,
            message: 'No diagnostics reported.',
            tone: AppTheme.secondary,
          )
        else
          ...diagnostics.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _InfoCard(
                icon: entry.tone == AppTheme.warning
                    ? Icons.warning_amber_rounded
                    : Icons.info_outline_rounded,
                message: entry.message,
                tone: entry.tone,
              ),
            ),
          ),
      ],
    );
  }

  static Map<String, dynamic> _mapOf(Object? value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return const <String, dynamic>{};
  }

  static String _displayValue(Object? value) {
    if (value == null) {
      return '';
    }
    if (value is bool) {
      return value ? 'true' : 'false';
    }
    return value.toString();
  }

  static String _toYesNo(Object? value) {
    if (value is bool) {
      return value ? 'YES' : 'NO';
    }
    return 'UNKNOWN';
  }

  static List<_DiagnosticEntry> _buildDiagnostics(Map<String, dynamic> info) {
    final diagnostics = <_DiagnosticEntry>[];

    final failures = info['collection_failures'];
    if (failures is List) {
      for (final item in failures) {
        if (item is Map) {
          final field = item['field']?.toString() ?? 'field';
          final reason = item['reason']?.toString() ?? 'unknown';
          diagnostics.add(
            _DiagnosticEntry(
              message: '$field: $reason',
              tone: AppTheme.warning,
            ),
          );
        }
      }
    }

    final masked = info['masked_fields'];
    if (masked is List && masked.isNotEmpty) {
      diagnostics.add(
        _DiagnosticEntry(
          message: '${masked.length} field(s) were masked by policy.',
          tone: AppTheme.warning,
        ),
      );
    }

    final included = info['included_fields'];
    if (included is List && included.isNotEmpty) {
      diagnostics.add(
        _DiagnosticEntry(
          message: 'Included sections: ${included.join(', ')}',
          tone: AppTheme.primary,
        ),
      );
    }

    return diagnostics;
  }
}

class _GenericResultView extends StatelessWidget {
  const _GenericResultView({required this.parsed});

  final ParsedCommandResult parsed;

  @override
  Widget build(BuildContext context) {
    final data = parsed.resultData;
    if (data is Map && data.isNotEmpty) {
      return _KeyValueGrid(
        title: 'Result',
        values: data.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    if (data is List && data.isNotEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.borderLight),
        ),
        child: Text(
          '${data.length} item(s) returned.',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
      );
    }
    return const _InfoCard(
      icon: Icons.notes_rounded,
      message: 'No structured result data available for this command.',
    );
  }
}

class _DebugSection extends StatelessWidget {
  const _DebugSection({
    required this.result,
    required this.params,
  });

  final Map<String, dynamic> result;
  final Object? params;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 0),
        childrenPadding: const EdgeInsets.only(bottom: 6),
        iconColor: AppTheme.textMuted,
        collapsedIconColor: AppTheme.textMuted,
        title: Text(
          'Debug JSON',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          const _SectionLabel('RESULT JSON'),
          const SizedBox(height: 6),
          _JsonBlock(content: _prettyJson(result)),
          if (params != null) ...[
            const SizedBox(height: 10),
            const _SectionLabel('PARAMS JSON'),
            const SizedBox(height: 6),
            _JsonBlock(content: _prettyJson(params)),
          ],
        ],
      ),
    );
  }

  static String _prettyJson(Object? value) {
    const encoder = JsonEncoder.withIndent('  ');
    if (value == null) {
      return '{}';
    }
    try {
      return encoder.convert(value);
    } catch (_) {
      return value.toString();
    }
  }
}

class _ExplorerToolbar extends StatelessWidget {
  const _ExplorerToolbar({
    required this.currentPath,
    required this.windowsStyle,
    required this.onBack,
    required this.canGoBack,
    required this.onRoot,
  });

  final String currentPath;
  final bool windowsStyle;
  final VoidCallback onBack;
  final bool canGoBack;
  final VoidCallback onRoot;

  @override
  Widget build(BuildContext context) {
    final rootLabel = windowsStyle ? 'Computer' : '/';
    return Row(
      children: [
        _ActionButton(
          icon: Icons.arrow_back_ios_new_rounded,
          label: 'Up',
          onPressed: canGoBack ? onBack : null,
          compact: true,
        ),
        const SizedBox(width: 8),
        _ActionButton(
          icon: Icons.home_rounded,
          label: rootLabel,
          onPressed: onRoot,
          compact: true,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.borderLight),
            ),
            child: Text(
              currentPath.isEmpty ? rootLabel : currentPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.ibmPlexMono(
                fontSize: 10,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({
    required this.currentPath,
    required this.windowsStyle,
    required this.onTapPath,
  });

  final String currentPath;
  final bool windowsStyle;
  final ValueChanged<String> onTapPath;

  @override
  Widget build(BuildContext context) {
    final chunks = currentPath
        .replaceAll('\\', '/')
        .split('/')
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    final chips = <Widget>[
      GestureDetector(
        onTap: () => onTapPath(''),
        child: _BreadChip(label: windowsStyle ? 'Computer' : '/'),
      ),
    ];

    var cursor = '';
    for (final chunk in chunks) {
      cursor = cursor.isEmpty ? chunk : '$cursor/$chunk';
      chips
        ..add(const Icon(Icons.chevron_right_rounded,
            size: 14, color: AppTheme.textMuted))
        ..add(
          GestureDetector(
            onTap: () => onTapPath(cursor),
            child: _BreadChip(label: chunk),
          ),
        );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: chips),
    );
  }
}

class _BreadChip extends StatelessWidget {
  const _BreadChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primaryDim,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.ibmPlexSans(
          fontSize: 11,
          color: AppTheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.entry,
    required this.onOpen,
    required this.artifactUrl,
    required this.downloadingArtifact,
    required this.onDownloadArtifact,
    required this.checksum,
  });

  final FileSystemEntry entry;
  final VoidCallback? onOpen;
  final String artifactUrl;
  final bool downloadingArtifact;
  final Future<void> Function(String artifactUrl, {String? checksum})
      onDownloadArtifact;
  final String checksum;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.borderLight)),
        ),
        child: Row(
          children: [
            Icon(
              entry.isDirectory
                  ? Icons.folder_rounded
                  : Icons.insert_drive_file_rounded,
              size: 16,
              color:
                  entry.isDirectory ? AppTheme.warning : AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!entry.isDirectory)
              IconButton(
                onPressed: artifactUrl.isEmpty || downloadingArtifact
                    ? null
                    : () => onDownloadArtifact(artifactUrl, checksum: checksum),
                icon: Icon(
                  downloadingArtifact
                      ? Icons.downloading_rounded
                      : Icons.download_rounded,
                  size: 16,
                  color: artifactUrl.isEmpty
                      ? AppTheme.textDisabled
                      : AppTheme.primary,
                ),
                tooltip:
                    artifactUrl.isEmpty ? 'Artifact unavailable' : 'Download',
              ),
            if (entry.isDirectory)
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: AppTheme.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    required this.active,
    required this.ascending,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool ascending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 130,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (active)
              Icon(
                ascending
                    ? Icons.arrow_drop_up_rounded
                    : Icons.arrow_drop_down_rounded,
                size: 16,
                color: AppTheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  const _BodyCell({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.borderLight)),
      ),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.ibmPlexMono(
          fontSize: 10,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.ibmPlexSans(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: AppTheme.textMuted,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
    this.color,
    this.monospace = false,
  });

  final String label;
  final Color? color;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: textColor.withAlpha(20),
        borderRadius: BorderRadius.circular(5),
      ),
      constraints: const BoxConstraints(maxWidth: 260),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: monospace
            ? GoogleFonts.ibmPlexMono(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: textColor,
              )
            : GoogleFonts.ibmPlexSans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
      ),
    );
  }
}

class _CopyableField extends StatelessWidget {
  const _CopyableField({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 10,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.ibmPlexMono(
                fontSize: 10,
                color: AppTheme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Clipboard.setData(ClipboardData(text: value)),
            child: const Icon(
              Icons.copy_rounded,
              size: 14,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 34 : 36,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppTheme.primaryDim,
          foregroundColor: AppTheme.primary,
          disabledBackgroundColor: AppTheme.surface,
          disabledForegroundColor: AppTheme.textDisabled,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppTheme.borderLight),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: compact ? 14 : 15),
        label: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.ibmPlexSans(
            fontSize: compact ? 11 : 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.message,
    this.tone = AppTheme.textMuted,
  });

  final IconData icon;
  final String message;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tone.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tone.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                color: tone,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style:
            GoogleFonts.ibmPlexSans(fontSize: 12, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            color: AppTheme.textMuted,
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 16),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
    );
  }
}

class _KeyValueGrid extends StatelessWidget {
  const _KeyValueGrid({
    required this.title,
    required this.values,
  });

  final String title;
  final Map<String, dynamic> values;

  @override
  Widget build(BuildContext context) {
    final entries = values.entries.toList(growable: false);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          ...entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      _toLabel(entry.key),
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 5,
                    child: Text(
                      _display(entry.value),
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 10,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _toLabel(String value) {
    return value
        .replaceAll('_', ' ')
        .replaceFirstMapped(RegExp(r'^.'), (m) => m.group(0)!.toUpperCase());
  }

  static String _display(Object? value) {
    if (value == null) {
      return 'Not collected';
    }
    if (value is Map || value is List) {
      try {
        return const JsonEncoder.withIndent('  ').convert(value);
      } catch (_) {
        return value.toString();
      }
    }
    return value.toString();
  }
}

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: SelectableText(
        content,
        style: GoogleFonts.ibmPlexMono(
          fontSize: 10,
          color: AppTheme.textSecondary,
          height: 1.4,
        ),
      ),
    );
  }
}

final _artifactAuthHeaderProvider = FutureProvider<String?>((ref) async {
  final secureStorage = ref.read(secureStorageServiceProvider);
  return secureStorage.read(StorageKeys.authToken);
});

class _InfoSectionData {
  const _InfoSectionData(this.title, this.values);

  final String title;
  final Map<String, dynamic> values;
}

class _DiagnosticEntry {
  const _DiagnosticEntry({
    required this.message,
    required this.tone,
  });

  final String message;
  final Color tone;
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
