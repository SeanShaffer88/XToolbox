import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/asset.dart';

/// Fetches a URL's body, or null when it cannot be retrieved.
typedef CatalogFetcher = Future<String?> Function(String url);

/// Keeps the tool catalog fresh between app releases.
///
/// The catalog ships inside the app, but tools come and go faster
/// than releases do. This service caches the catalog published in the
/// project repository: a previously fetched copy that still validates
/// is used at startup, a background refresh adopts a newer one only
/// after it parses as a complete, well-formed catalog, and the
/// bundled copy remains the fallback whenever there is no usable
/// cache or no network — the app works fully offline, always.
class CatalogService {
  static const String defaultCatalogUrl =
      'https://raw.githubusercontent.com/SeanShaffer88/XToolbox/main/'
      'assets/asset_list.json';
  static const String cacheFileName = 'catalog_cache.json';
  static const String metaFileName = 'catalog_cache_meta.json';

  final CatalogFetcher _fetcher;
  final Future<Directory> Function() _supportDir;
  final String catalogUrl;

  CatalogService({
    CatalogFetcher? fetcher,
    Future<Directory> Function()? supportDir,
    this.catalogUrl = defaultCatalogUrl,
  }) : _fetcher = fetcher ?? _defaultFetch,
       _supportDir = supportDir ?? getApplicationSupportDirectory;

  static Future<String?> _defaultFetch(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'XToolBox'})
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      return response.body;
    } catch (_) {
      return null;
    }
  }

  /// Parses catalog JSON into assets, or returns null when the text
  /// is not a complete, well-formed catalog: it must decode to a
  /// non-empty list whose every entry parses and whose ids are
  /// unique. A downloaded catalog is adopted only when this passes,
  /// so a truncated or corrupted response can never replace a good
  /// catalog.
  static List<Asset>? tryParseCatalog(String text) {
    try {
      final decoded = json.decode(text);
      if (decoded is! List || decoded.isEmpty) return null;
      final assets = <Asset>[];
      final ids = <String>{};
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) return null;
        final asset = Asset.fromJson(entry);
        if (asset.id.isEmpty || !ids.add(asset.id)) return null;
        assets.add(asset);
      }
      return assets;
    } catch (_) {
      return null;
    }
  }

  /// SHA-256 of a catalog text, recorded with each adopted copy so
  /// changes are detectable and auditable.
  static String catalogHash(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  Future<File> _file(String name) async {
    final dir = await _supportDir();
    return File('${dir.path}/$name');
  }

  /// The cached remote catalog text, when one was stored and still
  /// validates; otherwise null (the caller falls back to the bundled
  /// catalog).
  Future<String?> loadCachedCatalogText() async {
    try {
      final file = await _file(cacheFileName);
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      return tryParseCatalog(text) != null ? text : null;
    } catch (_) {
      return null;
    }
  }

  /// When the cached catalog was fetched, per its meta file.
  Future<DateTime?> cachedCatalogFetchedAt() async {
    try {
      final file = await _file(metaFileName);
      if (!await file.exists()) return null;
      final meta = json.decode(await file.readAsString());
      if (meta is Map<String, dynamic>) {
        final raw = meta['fetched_at'];
        if (raw is String) return DateTime.tryParse(raw);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches the remote catalog and adopts it as the cache when (and
  /// only when) it validates. The cache and its meta file are written
  /// via temp files renamed into place, so an interrupted write
  /// leaves the previous good copy untouched. Returns true when the
  /// cache now holds the fetched catalog.
  Future<bool> refresh() async {
    final text = await _fetcher(catalogUrl);
    if (text == null || tryParseCatalog(text) == null) return false;
    try {
      final dir = await _supportDir();
      final tmp = File('${dir.path}/$cacheFileName.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename('${dir.path}/$cacheFileName');
      final meta = json.encode({
        'fetched_at': DateTime.now().toUtc().toIso8601String(),
        'sha256': catalogHash(text),
        'source': catalogUrl,
      });
      final metaTmp = File('${dir.path}/$metaFileName.tmp');
      await metaTmp.writeAsString(meta, flush: true);
      await metaTmp.rename('${dir.path}/$metaFileName');
      return true;
    } catch (_) {
      return false;
    }
  }
}
