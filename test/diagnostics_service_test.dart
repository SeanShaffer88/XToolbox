import 'package:flutter_test/flutter_test.dart';
import 'package:xtoolbox/services/diagnostics_service.dart';

void main() {
  group('DiagnosticsService.parseVersionOutput', () {
    test('returns the first non-empty line, trimmed', () {
      expect(
        DiagnosticsService.parseVersionOutput('\n  v1.9.25200  \nextra'),
        'v1.9.25200',
      );
    });

    test('returns null for null, empty, and whitespace-only output', () {
      expect(DiagnosticsService.parseVersionOutput(null), isNull);
      expect(DiagnosticsService.parseVersionOutput(''), isNull);
      expect(DiagnosticsService.parseVersionOutput('  \n \n'), isNull);
    });
  });

  group('DiagnosticsService.buildReport', () {
    const facts = SystemFacts(
      appVersion: '5.3.11',
      osDescription: '"Windows 11 Pro" 10.0 (Build 26200)',
      wingetVersion: 'v1.9.25200',
      chocoVersion: '2.4.3',
    );

    test('includes every fact and setting, verbatim', () {
      final report = DiagnosticsService.buildReport(
        facts: facts,
        themeMode: 'Dark',
        downloadPath: r'D:\Installers',
        bandwidthLimitKbps: 2048,
        httpsOnly: true,
        favoritesCount: 3,
        recentInstallsCount: 5,
      );
      expect(
        report,
        'XToolBox diagnostics\n'
        'App version: 5.3.11\n'
        'Operating system: "Windows 11 Pro" 10.0 (Build 26200)\n'
        'winget: v1.9.25200\n'
        'Chocolatey: 2.4.3\n'
        'Theme: Dark\n'
        'HTTPS-only downloads: on\n'
        r'Downloads folder: D:\Installers'
        '\n'
        'Bandwidth limit: 2048 KB/s\n'
        'Favorites: 3 · Recent installs: 5',
      );
    });

    test('missing tools and defaults read plainly, never blank', () {
      final report = DiagnosticsService.buildReport(
        facts: const SystemFacts(
          appVersion: 'unknown',
          osDescription: 'Windows 10',
        ),
        themeMode: 'System',
        downloadPath: null,
        bandwidthLimitKbps: null,
        httpsOnly: false,
        favoritesCount: 0,
        recentInstallsCount: 0,
      );
      expect(report, contains('winget: not found'));
      expect(report, contains('Chocolatey: not found'));
      expect(report, contains('Downloads folder: default (system Downloads)'));
      expect(report, contains('Bandwidth limit: unlimited'));
      expect(report, contains('HTTPS-only downloads: off'));
    });
  });
}
