import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

/// The machine facts a bug report needs, gathered in one place.
///
/// The bug-report template asks every reporter for the app version and
/// the Windows edition/build, and most follow-up questions are about
/// the package managers and the download settings. Collecting them by
/// hand is error-prone; this service reads them from the system and
/// formats them as one copyable block.
class SystemFacts {
  final String appVersion;
  final String osDescription;
  final String? wingetVersion;
  final String? chocoVersion;

  const SystemFacts({
    required this.appVersion,
    required this.osDescription,
    this.wingetVersion,
    this.chocoVersion,
  });
}

class DiagnosticsService {
  /// Extracts a version from `--version` output: the first non-empty
  /// line, trimmed. Null when there is no usable output (the tool is
  /// missing or said nothing recognizable).
  static String? parseVersionOutput(String? output) {
    if (output == null) return null;
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  /// Formats the full diagnostics block exactly as it is shown in
  /// Settings and copied to the clipboard, so a pasted report always
  /// matches what the user saw.
  static String buildReport({
    required SystemFacts facts,
    required String themeMode,
    required String? downloadPath,
    required int? bandwidthLimitKbps,
    required bool httpsOnly,
    required int favoritesCount,
    required int recentInstallsCount,
  }) {
    String tool(String? version) => version ?? 'not found';
    final buffer = StringBuffer()
      ..writeln('XToolBox diagnostics')
      ..writeln('App version: ${facts.appVersion}')
      ..writeln('Operating system: ${facts.osDescription}')
      ..writeln('winget: ${tool(facts.wingetVersion)}')
      ..writeln('Chocolatey: ${tool(facts.chocoVersion)}')
      ..writeln('Theme: $themeMode')
      ..writeln('HTTPS-only downloads: ${httpsOnly ? 'on' : 'off'}')
      ..writeln(
        'Downloads folder: ${downloadPath ?? 'default (system Downloads)'}',
      )
      ..writeln(
        'Bandwidth limit: '
        '${bandwidthLimitKbps == null ? 'unlimited' : '$bandwidthLimitKbps KB/s'}',
      )
      ..write(
        'Favorites: $favoritesCount · Recent installs: $recentInstallsCount',
      );
    return buffer.toString();
  }

  /// Runs `<tool> --version`, returning its parsed version or null.
  /// Package managers only exist on Windows; anywhere else, and on any
  /// failure, the answer is simply null — diagnostics must never throw
  /// into the settings screen.
  static Future<String?> _toolVersion(String executable) async {
    if (!Platform.isWindows) return null;
    try {
      final result = await Process.run(executable, [
        '--version',
      ]).timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) return null;
      return parseVersionOutput(result.stdout?.toString());
    } catch (_) {
      return null;
    }
  }

  /// Gathers the machine facts. Every field degrades gracefully: an
  /// unknown app version reads "unknown", a missing package manager
  /// reads null (rendered as "not found").
  Future<SystemFacts> collect() async {
    var appVersion = 'unknown';
    try {
      final pkg = await PackageInfo.fromPlatform();
      if (pkg.version.isNotEmpty) appVersion = pkg.version;
    } catch (_) {
      // Keep "unknown"; diagnostics must never break Settings.
    }
    final winget = await _toolVersion('winget');
    final choco = await _toolVersion('choco');
    return SystemFacts(
      appVersion: appVersion,
      osDescription: Platform.operatingSystemVersion,
      wingetVersion: winget,
      chocoVersion: choco,
    );
  }
}
