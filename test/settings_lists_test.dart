import 'package:flutter_test/flutter_test.dart';
import 'package:xtoolbox/services/settings_service.dart';

/// Favorites and Recently Installed are plain id lists in
/// SettingsService; these tests pin their update rules.
void main() {
  group('SettingsService.updatedFavorites', () {
    test('adds when absent, removes when present', () {
      expect(SettingsService.updatedFavorites([], 'a'), ['a']);
      expect(SettingsService.updatedFavorites(['a', 'b'], 'a'), ['b']);
      expect(SettingsService.updatedFavorites(['a'], 'b'), ['a', 'b']);
    });
  });

  group('SettingsService.updatedRecents', () {
    test('moves the id to the front without duplicating it', () {
      expect(SettingsService.updatedRecents(['a', 'b', 'c'], 'c'), [
        'c',
        'a',
        'b',
      ]);
      expect(SettingsService.updatedRecents(['a'], 'b'), ['b', 'a']);
    });

    test('caps the list at maxRecentInstalls', () {
      final current = List.generate(10, (i) => 'id$i');
      final next = SettingsService.updatedRecents(current, 'new');
      expect(next.length, SettingsService.maxRecentInstalls);
      expect(next.first, 'new');
      expect(next.contains('id9'), isFalse);
    });
  });
}
