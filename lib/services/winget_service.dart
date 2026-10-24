import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Queries what winget has installed on this machine.
///
/// Installed state used to be invisible: the catalog could not tell a
/// tool the user already has from one they don't. `winget export`
/// dumps every installed package as JSON; this service runs it and
/// parses the result into package-id → version.
class WingetService {
  /// Parses `winget export` output. Tolerant by design: anything
  /// unexpected (malformed JSON, missing sections, entries without an
  /// id) yields an empty or partial map rather than an error, because
  /// installed state is decoration, never a blocker.
  static Map<String, String> parseExport(String jsonText) {
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return {};
      final result = <String, String>{};
      final sources = decoded['Sources'];
      if (sources is List) {
        for (final source in sources) {
          if (source is! Map) continue;
          final packages = source['Packages'];
          if (packages is! List) continue;
          for (final pkg in packages) {
            if (pkg is! Map) continue;
            final id = pkg['PackageIdentifier'];
            if (id is String && id.isNotEmpty) {
              final version = pkg['Version'];
              result[id] = version is String ? version : '';
            }
          }
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  /// The winget arguments that uninstall [packageId] silently.
  @visibleForTesting
  static List<String> uninstallArguments(String packageId) => [
    'uninstall',
    '--id',
    packageId,
    '--silent',
    '--accept-source-agreements',
    '--disable-interactivity',
  ];

  /// Uninstalls [packageId] via winget. False off Windows, when
  /// winget is missing, or when winget reports failure.
  Future<bool> uninstall(String packageId) async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run('winget', uninstallArguments(packageId));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// The installed winget packages on this machine (id → version).
  /// Empty off Windows, when winget is missing, or on any failure.
  Future<Map<String, String>> queryInstalled() async {
    if (!Platform.isWindows) return {};
    try {
      final dir = await getTemporaryDirectory();
      final outFile = File('${dir.path}\\xtoolbox_winget_export.json');
      if (await outFile.exists()) await outFile.delete();
      await Process.run('winget', [
        'export',
        '-o',
        outFile.path,
        '--accept-source-agreements',
        '--disable-interactivity',
      ]);
      if (!await outFile.exists()) return {};
      return parseExport(await outFile.readAsString());
    } catch (_) {
      return {};
    }
  }
}
