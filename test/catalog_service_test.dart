import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xtoolbox/services/catalog_service.dart';

Map<String, dynamic> entry(String id) => {
  'id': id,
  'name': 'Tool $id',
  'description': 'A tool.',
  'category': 'tools',
  'icon': 'build',
  'author': 'Someone',
  'homepage': 'https://example.com/$id',
  'install_methods': <dynamic>[],
};

String catalogText(List<String> ids) =>
    json.encode([for (final id in ids) entry(id)]);

void main() {
  group('CatalogService.tryParseCatalog', () {
    test('parses a valid catalog in order', () {
      final assets = CatalogService.tryParseCatalog(catalogText(['a', 'b']));
      expect(assets, isNotNull);
      expect(assets!.map((a) => a.id), ['a', 'b']);
    });

    test('rejects non-catalog payloads', () {
      expect(CatalogService.tryParseCatalog(''), isNull);
      expect(CatalogService.tryParseCatalog('not json'), isNull);
      expect(CatalogService.tryParseCatalog('{}'), isNull);
      expect(CatalogService.tryParseCatalog('[]'), isNull);
      expect(CatalogService.tryParseCatalog('[1, 2]'), isNull);
    });

    test('rejects an entry with a missing field', () {
      final broken = entry('a')..remove('name');
      expect(CatalogService.tryParseCatalog(json.encode([broken])), isNull);
    });

    test('rejects duplicate ids', () {
      expect(CatalogService.tryParseCatalog(catalogText(['a', 'a'])), isNull);
    });
  });

  group('CatalogService.catalogHash', () {
    test('is a stable 64-char hex digest', () {
      final hash = CatalogService.catalogHash('abc');
      expect(hash, hasLength(64));
      expect(hash, CatalogService.catalogHash('abc'));
      expect(hash, isNot(CatalogService.catalogHash('abd')));
    });
  });

  group('CatalogService cache + refresh', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('catalog_service_test');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    CatalogService service(String? Function() fetchResult) => CatalogService(
      fetcher: (url) async => fetchResult(),
      supportDir: () async => dir,
    );

    test('refresh adopts a valid catalog and records meta', () async {
      final text = catalogText(['a', 'b']);
      final svc = service(() => text);
      expect(await svc.refresh(), isTrue);
      expect(await svc.loadCachedCatalogText(), text);
      final fetchedAt = await svc.cachedCatalogFetchedAt();
      expect(fetchedAt, isNotNull);
      expect(
        DateTime.now().toUtc().difference(fetchedAt!).inMinutes,
        lessThan(5),
      );
      expect(
        await File('${dir.path}/${CatalogService.cacheFileName}').exists(),
        isTrue,
      );
      expect(
        await File('${dir.path}/${CatalogService.cacheFileName}.tmp').exists(),
        isFalse,
      );
    });

    test('refresh rejects an invalid payload and writes nothing', () async {
      final svc = service(() => '[{"id": 1}]');
      expect(await svc.refresh(), isFalse);
      expect(await svc.loadCachedCatalogText(), isNull);
      expect(
        await File('${dir.path}/${CatalogService.cacheFileName}').exists(),
        isFalse,
      );
    });

    test('a failed refresh preserves the previous good cache', () async {
      final good = catalogText(['a']);
      expect(await service(() => good).refresh(), isTrue);
      expect(await service(() => 'garbage').refresh(), isFalse);
      expect(await service(() => null).refresh(), isFalse);
      expect(await service(() => null).loadCachedCatalogText(), good);
    });

    test('a corrupt cache file is ignored', () async {
      await File(
        '${dir.path}/${CatalogService.cacheFileName}',
      ).writeAsString('[{"id": ');
      expect(await service(() => null).loadCachedCatalogText(), isNull);
    });
  });
}
