import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xtoolbox/services/settings_service.dart';

/// Settings export/import: the exported map is validated before
/// anything is applied, because the file comes from disk and could
/// be hand-edited, truncated, or from a newer app version.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsService.parseSettingsExport', () {
    test('keeps recognized keys and ignores unknown ones', () {
      final parsed = SettingsService.parseSettingsExport({
        'xtoolbox_settings_version': 1,
        'https_only_mode': true,
        'favorite_asset_ids': ['a', 'b'],
        'something_unknown': 42,
      });
      expect(parsed, {
        'https_only_mode': true,
        'favorite_asset_ids': ['a', 'b'],
      });
    });

    test('rejects wrong types, naming the key', () {
      expect(
        () => SettingsService.parseSettingsExport({'https_only_mode': 'yes'}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('https_only_mode'),
          ),
        ),
      );
      expect(
        () => SettingsService.parseSettingsExport({
          'favorite_asset_ids': ['ok', 7],
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SettingsService.parseSettingsExport({'bandwidth_limit_kbps': -5}),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects files from a newer format version', () {
      expect(
        () => SettingsService.parseSettingsExport({
          'xtoolbox_settings_version': 99,
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('newer version'),
          ),
        ),
      );
    });

    test('nullables survive: download path and bandwidth may be null', () {
      final parsed = SettingsService.parseSettingsExport({
        'download_path': null,
        'bandwidth_limit_kbps': null,
      });
      expect(parsed.containsKey('download_path'), isTrue);
      expect(parsed['download_path'], isNull);
      expect(parsed['bandwidth_limit_kbps'], isNull);
    });
  });

  group('round trip', () {
    test('export → JSON → import restores the values', () async {
      SharedPreferences.setMockInitialValues({
        'https_only_mode': true,
        'bandwidth_limit_kbps': 512,
        'favorite_asset_ids': ['7zip'],
      });
      final source = SettingsService();
      await source.ready;
      expect(source.httpsOnly, isTrue);

      final json = source.exportSettingsJson();
      expect(json, contains('"xtoolbox_settings_version": 1'));

      SharedPreferences.setMockInitialValues({});
      final target = SettingsService();
      await target.importSettingsJson(json);
      expect(target.httpsOnly, isTrue);
      expect(target.bandwidthLimit, 512);
      expect(target.favorites, ['7zip']);
    });

    test('importing garbage is a clean FormatException', () async {
      SharedPreferences.setMockInitialValues({});
      final service = SettingsService();
      await expectLater(
        service.importSettingsJson('not json at all'),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        service.importSettingsJson('[1, 2, 3]'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
