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
}
