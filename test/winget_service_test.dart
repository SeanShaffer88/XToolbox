import 'package:flutter_test/flutter_test.dart';
import 'package:xtoolbox/services/winget_service.dart';

/// Installed-state badges are driven by `winget export` JSON; these
/// tests pin the parser, including its tolerance for odd shapes.
void main() {
  group('WingetService.parseExport', () {
    test('maps package ids to versions across sources', () {
      const json = '''
{
  "Sources": [
    {
      "Packages": [
        {"PackageIdentifier": "Microsoft.PowerToys", "Version": "0.95.0"},
        {"PackageIdentifier": "7zip.7zip", "Version": "25.01"}
      ]
    },
    {
      "Packages": [
        {"PackageIdentifier": "9NBLGGH4NNS1", "Version": "unknown"}
      ]
    }
  ]
}
''';
      expect(WingetService.parseExport(json), {
        'Microsoft.PowerToys': '0.95.0',
        '7zip.7zip': '25.01',
        '9NBLGGH4NNS1': 'unknown',
      });
    });

    test('entries without a version map to an empty string', () {
      const json =
          '{"Sources": [{"Packages": [{"PackageIdentifier": "A.B"}]}]}';
      expect(WingetService.parseExport(json), {'A.B': ''});
    });

    test('malformed or unexpected shapes yield an empty map', () {
      expect(WingetService.parseExport('not json'), isEmpty);
      expect(WingetService.parseExport('[]'), isEmpty);
      expect(WingetService.parseExport('{}'), isEmpty);
      expect(
        WingetService.parseExport('{"Sources": [{"Packages": [42, null]}]}'),
        isEmpty,
      );
    });
  });

  group('WingetService.uninstallArguments', () {
    test('builds a silent uninstall by exact id', () {
      expect(WingetService.uninstallArguments('Microsoft.PowerToys'), [
        'uninstall',
        '--id',
        'Microsoft.PowerToys',
        '--silent',
        '--accept-source-agreements',
        '--disable-interactivity',
      ]);
    });
  });

  group('WingetService.parseUpgradeTable', () {
    // Column layout mirrors real `winget upgrade` output: the parser
    // slices rows at the header's column positions.
    const header =
        'Name                          Id                            Version       Available     Source';
    const separator =
        '----------------------------------------------------------------------------------------------';

    String table(List<String> rows) =>
        [header, separator, ...rows, '', '2 upgrades available.'].join('\n');

    test('extracts id → available version for each row', () {
      final result = WingetService.parseUpgradeTable(
        table([
          'Git                           Git.Git                       2.45.1        2.47.0.2      winget',
          'PowerToys (x64)               Microsoft.PowerToys           0.85.1        0.86.0        winget',
        ]),
      );
      expect(result, {'Git.Git': '2.47.0.2', 'Microsoft.PowerToys': '0.86.0'});
    });

    test('works without a Source column', () {
      final result = WingetService.parseUpgradeTable(
        [
          'Name                          Id                            Version       Available',
          separator,
          'Git                           Git.Git                       2.45.1        2.47.0.2',
        ].join('\n'),
      );
      expect(result, {'Git.Git': '2.47.0.2'});
    });

    test('no-upgrade and empty outputs parse to an empty map', () {
      expect(WingetService.parseUpgradeTable(''), isEmpty);
      expect(
        WingetService.parseUpgradeTable('No available upgrade found.'),
        isEmpty,
      );
      expect(WingetService.parseUpgradeTable(table([])), isEmpty);
    });
  });

  group('WingetService.upgradeArguments', () {
    test('builds a silent upgrade by exact id', () {
      expect(WingetService.upgradeArguments('Git.Git'), [
        'upgrade',
        '--id',
        'Git.Git',
        '--silent',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--disable-interactivity',
      ]);
    });

    test('the upgrade query accepts source agreements non-interactively', () {
      expect(WingetService.upgradeQueryArguments(), [
        'upgrade',
        '--accept-source-agreements',
        '--disable-interactivity',
      ]);
    });
  });
}
