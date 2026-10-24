import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Fetches a page body; returns null unless the response is HTTP 200.
typedef PageFetcher = Future<String?> Function(String url);

/// Checks that a URL actually serves a file (2xx/3xx response).
typedef UrlChecker = Future<bool> Function(String url);

/// Resolves catalog URLs that contain a `%TOKEN%` placeholder to a real,
/// current download URL.
///
/// Several distro entries were added with template URLs such as
/// `.../stable/%MINTVERSION%/linuxmint-%MINTVERSION%-cinnamon-64bit.iso`,
/// or a bare token like `%POP%,nvidia`, and nothing ever substituted the
/// token — those downloads requested the literal template and failed.
/// Each known token resolves against the distro's own official source
/// (a mirror directory listing, the vendor's build API, or the vendor's
/// download page), and the resulting URL is verified to exist before it
/// is used. Candidates are tried newest-first, so filename drift in the
/// newest release falls back to the previous one instead of failing.
///
/// Resolution failures return null; the caller reports the failure
/// rather than attempting the template URL.
class DistroResolver {
  DistroResolver({PageFetcher? fetchPage, UrlChecker? urlExists})
    : _fetchPage = fetchPage ?? _defaultFetchPage,
      _urlExists = urlExists ?? _defaultUrlExists;

  final PageFetcher _fetchPage;
  final UrlChecker _urlExists;
  final Map<String, String> _cache = {};

  static final RegExp _tokenPattern = RegExp(r'%([A-Z0-9_]+)%');

  /// Whether [url] contains a `%TOKEN%` placeholder. Percent-escapes in
  /// ordinary URLs (e.g. `%20`) do not match: a token is an all-caps
  /// name wrapped in percent signs.
  static bool needsResolution(String url) => _tokenPattern.hasMatch(url);

  /// The resolved URL for [template], or null when it cannot be
  /// resolved right now. Non-template URLs are returned unchanged.
  Future<String?> resolve(String template) async {
    final match = _tokenPattern.firstMatch(template);
    if (match == null) return template;
    final cached = _cache[template];
    if (cached != null) return cached;

    final token = match.group(1)!;
    final String? resolved = switch (token) {
      'MINTVERSION' ||
      'UBUNTUVERSION' => await _latestVersionFill(template, token),
      'CACHYVERSION' => await _cachy(template),
      'ENDEAVOUR' => await _endeavour(template),
      'DEBIAN' => await _debian(),
      'POP' => await _pop(template, match),
      'ARTIX' => await _artix(template, match),
      'SOLUS' => await _solus(template, match),
      _ => null,
    };
    if (resolved != null) _cache[template] = resolved;
    return resolved;
  }

  /// The variant suffix of a whole-token reference like `%POP%,nvidia`.
  String? _variantOf(String template, RegExpMatch match) {
    final rest = template.substring(match.end);
    return rest.startsWith(',') ? rest.substring(1) : null;
  }

  /// Compares dotted version strings numerically (`22.3` > `22` >
  /// `21.3`). Non-numeric segments count as 0.
  @visibleForTesting
  static int compareVersions(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < pa.length || i < pb.length; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  /// Version directory names found in a mirror listing, newest first.
  @visibleForTesting
  static List<String> extractVersions(String html) {
    final found = RegExp(
      r'href="(\d+(?:\.\d+)*)/"',
    ).allMatches(html).map((m) => m.group(1)!).toSet().toList();
    found.sort((a, b) => compareVersions(b, a));
    return found;
  }

  /// EndeavourOS ISO filenames found in a mirror listing, newest first
  /// by the release date embedded in the name.
  @visibleForTesting
  static List<String> extractEndeavourFiles(String html) {
    final files = RegExp(
      r'href="(EndeavourOS_[^"]+\.iso)"',
    ).allMatches(html).map((m) => m.group(1)!).toSet().toList();
    int dateKey(String f) {
      final m = RegExp(r'(\d{4})\.(\d{2})\.(\d{2})').firstMatch(f);
      if (m == null) return 0;
      return int.parse(m.group(1)!) * 10000 +
          int.parse(m.group(2)!) * 100 +
          int.parse(m.group(3)!);
    }

    files.sort((a, b) => dateKey(b).compareTo(dateKey(a)));
    return files;
  }

  /// %MINTVERSION% / %UBUNTUVERSION%: the token appears in a version
  /// directory and again in the filename. The parent directory listing
  /// enumerates the versions; try each, newest first, until one yields
  /// a file that exists.
  Future<String?> _latestVersionFill(String template, String token) async {
    final tokenIndex = template.indexOf('%$token%');
    final slash = template.lastIndexOf('/', tokenIndex);
    if (slash < 0) return null;
    final listingUrl = template.substring(0, slash + 1);
    final page = await _fetchPage(listingUrl);
    if (page == null) return null;
    for (final version in extractVersions(page).take(4)) {
      final candidate = template.replaceAll('%$token%', version);
      if (await _urlExists(candidate)) return candidate;
    }
    return null;
  }

  /// %CACHYVERSION%: the CDN bucket is not listable, but the project's
  /// download page embeds the current version per edition.
  Future<String?> _cachy(String template) async {
    final kind = template.contains('/handheld/') ? 'handheld' : 'desktop';
    final page = await _fetchPage('https://cachyos.org/download/');
    if (page == null) return null;
    final versions =
        RegExp(
            'ISO/$kind/(\\d{6})/',
          ).allMatches(page).map((m) => m.group(1)!).toSet().toList()
          ..sort((a, b) => b.compareTo(a));
    for (final version in versions.take(3)) {
      final candidate = template.replaceAll('%CACHYVERSION%', version);
      if (await _urlExists(candidate)) return candidate;
    }
    return null;
  }

  /// %ENDEAVOUR%: the token is the ISO filename itself.
  Future<String?> _endeavour(String template) async {
    final dir = template.substring(0, template.lastIndexOf('/') + 1);
    final page = await _fetchPage(dir);
    if (page == null) return null;
    for (final file in extractEndeavourFiles(page).take(3)) {
      final candidate = '$dir$file';
      if (await _urlExists(candidate)) return candidate;
    }
    return null;
  }

  /// %DEBIAN%: the whole URL is the token. The current netinst image
  /// lives in a stable directory; only its version changes.
  Future<String?> _debian() async {
    const dir = 'https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/';
    final page = await _fetchPage(dir);
    if (page == null) return null;
    final versions = RegExp(
      r'debian-(\d+\.\d+\.\d+)-amd64-netinst\.iso',
    ).allMatches(page).map((m) => m.group(1)!).toSet().toList();
    versions.sort((a, b) => compareVersions(b, a));
    for (final version in versions.take(3)) {
      final candidate = '${dir}debian-$version-amd64-netinst.iso';
      if (await _urlExists(candidate)) return candidate;
    }
    return null;
  }

  /// %POP%,`<channel>`: System76's build API returns the current image
  /// URL per release and channel. The Raspberry Pi image is not in the
  /// API, so `raspi` does not resolve here (its catalog entry is a web
  /// link instead).
  Future<String?> _pop(String template, RegExpMatch match) async {
    final channel = _variantOf(template, match);
    if (channel == null || channel == 'raspi') return null;
    for (final release in ['24.04', '22.04']) {
      final page = await _fetchPage(
        'https://api.pop-os.org/builds/$release/$channel',
      );
      if (page == null) continue;
      try {
        final url =
            (jsonDecode(page) as Map<String, dynamic>)['url'] as String?;
        if (url != null && await _urlExists(url)) return url;
      } catch (_) {
        // Not JSON — try the next release.
      }
    }
    return null;
  }

  /// %ARTIX%,`<edition>`: weekly images named
  /// `artix-<edition>-openrc-<yyyymmdd>-x86_64.iso` on the project's
  /// mirrors; openrc is the default init.
  Future<String?> _artix(String template, RegExpMatch match) async {
    final edition = _variantOf(template, match);
    if (edition == null) return null;
    const dir = 'https://eu-mirror.artixlinux.org/iso/';
    final page = await _fetchPage(dir);
    if (page == null) return null;
    final dates =
        RegExp(
            'artix-${RegExp.escape(edition)}-openrc-(\\d{8})-x86_64\\.iso',
          ).allMatches(page).map((m) => m.group(1)!).toSet().toList()
          ..sort((a, b) => b.compareTo(a));
    for (final date in dates.take(3)) {
      final candidate = '${dir}artix-$edition-openrc-$date-x86_64.iso';
      if (await _urlExists(candidate)) return candidate;
    }
    return null;
  }

  /// %SOLUS%,`<edition>`: images live in date-stamped directories as
  /// `Solus-<edition>-Release-<date>.iso`.
  Future<String?> _solus(String template, RegExpMatch match) async {
    final edition = _variantOf(template, match);
    if (edition == null) return null;
    const root = 'https://downloads.getsol.us/isos/';
    final page = await _fetchPage(root);
    if (page == null) return null;
    final dirs =
        RegExp(
            r'href="(?:\./)?(\d{4}-\d{2}-\d{2})/"',
          ).allMatches(page).map((m) => m.group(1)!).toSet().toList()
          ..sort((a, b) => b.compareTo(a));
    for (final dir in dirs.take(3)) {
      final candidate = '$root$dir/Solus-$edition-Release-$dir.iso';
      if (await _urlExists(candidate)) return candidate;
    }
    return null;
  }

  static Future<String?> _defaultFetchPage(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      return response.statusCode == 200 ? response.body : null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _defaultUrlExists(String url) async {
    try {
      final response = await http
          .head(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      return false;
    }
  }
}
