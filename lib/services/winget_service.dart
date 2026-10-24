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

  /// Parses the table printed by `winget upgrade` into
  /// package id → available version.
  ///
  /// The table is fixed-width; column positions are taken from the
  /// header line (`Name  Id  Version  Available  Source`), and each
  /// row below the dashed separator is sliced at those positions —
  /// the only reliable way to read it, since names contain spaces.
  /// Tolerant by design, like [parseExport]: no recognizable header
  /// (including winget's "no upgrades" message) yields an empty map.
  static Map<String, String> parseUpgradeTable(String output) {
    final lines = output.split('\n');
    var headerIndex = -1;
    int idStart = -1, versionStart = -1, availableStart = -1, sourceStart = -1;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final v = line.indexOf('Version');
      final a = v < 0 ? -1 : line.indexOf('Available', v);
      final id = line.indexOf('Id');
      if (id >= 0 && v > id && a > v && line.contains('Name')) {
        headerIndex = i;
        idStart = id;
        versionStart = v;
        availableStart = a;
        sourceStart = line.indexOf('Source', a);
        break;
      }
    }
    if (headerIndex < 0) return {};

    // Data starts after the dashed separator line under the header.
    var rowStart = headerIndex + 1;
    while (rowStart < lines.length &&
        !lines[rowStart].trimLeft().startsWith('---')) {
      rowStart++;
    }
    rowStart++;

    final result = <String, String>{};
    final footer = RegExp(r'^\d+ upgrades? available');
    for (var i = rowStart; i < lines.length; i++) {
      final line = lines[i];
      if (footer.hasMatch(line.trim())) break;
      if (line.length <= availableStart) continue;
      final id = line.substring(idStart, versionStart).trim();
      final end = (sourceStart > availableStart && sourceStart < line.length)
          ? sourceStart
          : line.length;
      final available = line.substring(availableStart, end).trim();
      // Package ids never contain spaces; the guard drops any
      // non-row noise that survived the slicing.
      if (id.isNotEmpty && !id.contains(' ') && available.isNotEmpty) {
        result[id] = available;
      }
    }
    return result;
  }

  /// The winget arguments that list available upgrades.
  @visibleForTesting
  static List<String> upgradeQueryArguments() => [
    'upgrade',
    '--accept-source-agreements',
    '--disable-interactivity',
  ];

  /// The packages with an upgrade available (id → available
  /// version). Empty off Windows, when winget is missing, when
  /// nothing is upgradeable, or on any failure.
  Future<Map<String, String>> queryUpgrades() async {
    if (!Platform.isWindows) return {};
    try {
      final result = await Process.run('winget', upgradeQueryArguments());
      return parseUpgradeTable(result.stdout.toString());
    } catch (_) {
      return {};
    }
  }

  /// The winget arguments that upgrade [packageId] silently.
  @visibleForTesting
  static List<String> upgradeArguments(String packageId) => [
    'upgrade',
    '--id',
    packageId,
    '--silent',
    '--accept-package-agreements',
    '--accept-source-agreements',
    '--disable-interactivity',
  ];

  /// Upgrades [packageId] via winget. False off Windows, when
  /// winget is missing, or when winget reports failure.
  Future<bool> upgrade(String packageId) async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run('winget', upgradeArguments(packageId));
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
