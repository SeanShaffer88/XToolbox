import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The kind of package action a history entry records.
enum HistoryAction { install, uninstall, upgrade }

extension HistoryActionLabel on HistoryAction {
  String get label => switch (this) {
    HistoryAction.install => 'Install',
    HistoryAction.uninstall => 'Uninstall',
    HistoryAction.upgrade => 'Upgrade',
  };
}

/// One recorded package action: what was done to which tool, by
/// which install method, whether it worked, and when.
class HistoryEntry {
  /// Catalog id of the tool, when the action came from the catalog
  /// (empty for anything else). Lets the history screen find the
  /// tool again, e.g. to retry a failed install.
  final String assetId;
  final String appName;
  final HistoryAction action;

  /// `InstallType.name` of the method used (e.g. `winget`).
  final String methodType;

  /// The catalog label of the method used (e.g. `Installer`).
  final String methodLabel;
  final bool success;
  final DateTime timestamp;

  const HistoryEntry({
    required this.assetId,
    required this.appName,
    required this.action,
    required this.methodType,
    required this.methodLabel,
    required this.success,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'asset_id': assetId,
    'app_name': appName,
    'action': action.name,
    'method_type': methodType,
    'method_label': methodLabel,
    'success': success,
    'timestamp': timestamp.toUtc().toIso8601String(),
  };

  /// Parses one entry, or returns null when it is malformed — a
  /// single bad entry must not take the whole history down with it.
  static HistoryEntry? fromJson(Map<String, dynamic> json) {
    try {
      HistoryAction? action;
      for (final value in HistoryAction.values) {
        if (value.name == json['action']) action = value;
      }
      final timestamp = DateTime.tryParse(json['timestamp'] as String? ?? '');
      if (action == null || timestamp == null) return null;
      return HistoryEntry(
        assetId: json['asset_id'] as String? ?? '',
        appName: json['app_name'] as String? ?? 'Unknown',
        action: action,
        methodType: json['method_type'] as String? ?? '',
        methodLabel: json['method_label'] as String? ?? '',
        success: json['success'] as bool? ?? false,
        timestamp: timestamp,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A persisted log of install, uninstall, and upgrade actions.
///
/// Stored as JSON in the app support directory, newest first, and
/// capped so it cannot grow without bound. Recording is
/// best-effort: history is evidence for the user and for bug
/// reports, and a failure to write it must never break the action
/// it describes.
class HistoryService {
  static const String fileName = 'install_history.json';
  static const int maxEntries = 200;

  final Future<Directory> Function() _supportDir;

  HistoryService({Future<Directory> Function()? supportDir})
    : _supportDir = supportDir ?? getApplicationSupportDirectory;

  List<HistoryEntry>? _entries;

  static List<HistoryEntry> parseEntries(String text) {
    try {
      final decoded = json.decode(text);
      if (decoded is! List) return [];
      final entries = <HistoryEntry>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final entry = HistoryEntry.fromJson(item);
          if (entry != null) entries.add(entry);
        }
      }
      return entries;
    } catch (_) {
      return [];
    }
  }

  Future<File> _file() async {
    final dir = await _supportDir();
    return File('${dir.path}/$fileName');
  }

  /// All recorded entries, newest first.
  Future<List<HistoryEntry>> load() async {
    if (_entries != null) return List.unmodifiable(_entries!);
    _entries = await _readFromDisk();
    return List.unmodifiable(_entries!);
  }

  Future<List<HistoryEntry>> _readFromDisk() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      return parseEntries(await file.readAsString());
    } catch (_) {
      return [];
    }
  }

  /// Prepends [entry] and persists the log, dropping the oldest
  /// entries beyond [maxEntries].
  Future<void> record(HistoryEntry entry) async {
    final updated = [entry, ...await load()];
    if (updated.length > maxEntries) {
      updated.removeRange(maxEntries, updated.length);
    }
    _entries = updated;
    await _writeToDisk(updated);
  }

  /// Erases the whole history.
  Future<void> clear() async {
    _entries = [];
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Clearing is best-effort like everything else here.
    }
  }

  Future<void> _writeToDisk(List<HistoryEntry> entries) async {
    try {
      final dir = await _supportDir();
      final tmp = File('${dir.path}/$fileName.tmp');
      await tmp.writeAsString(
        json.encode([for (final e in entries) e.toJson()]),
        flush: true,
      );
      await tmp.rename('${dir.path}/$fileName');
    } catch (_) {
      // History is best-effort; it must never break an install.
    }
  }
}
