import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static const _autoUpdateKey = 'auto_update_enabled';
  static const _lastUpdateCheckKey = 'update_last_check_ms';
  static const _downloadPathKey = 'download_path';
  static const _httpsOnlyKey = 'https_only_mode';
  static const _bandwidthLimitKey = 'bandwidth_limit_kbps';
  static const _installPreferenceKey = 'install_preference_order';
  static const _favoritesKey = 'favorite_asset_ids';
  static const _recentInstallsKey = 'recent_install_ids';

  /// How many recently installed entries are kept.
  static const maxRecentInstalls = 10;

  SharedPreferences? _prefs;
  bool _autoUpdate = true;
  String? _downloadPath;
  bool _httpsOnly = false;
  int? _bandwidthLimit; // in KB/s, null = unlimited
  List<String> _installPreference = [
    'direct_download',
    'powershell',
    'winget',
    'chocolatey',
    'scoop',
  ];
  List<String> _favorites = [];
  List<String> _recentInstalls = [];

  SettingsService() {
    _ready = _init();
  }

  late final Future<void> _ready;

  /// Completes when the initial preference load has finished.
  /// Operations that replace many values at once (settings import)
  /// await this first, so the initial load cannot land afterwards
  /// and overwrite them with the previously stored values.
  Future<void> get ready => _ready;

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    _autoUpdate = _prefs?.getBool(_autoUpdateKey) ?? true;
    _downloadPath = _prefs?.getString(_downloadPathKey);
    _httpsOnly = _prefs?.getBool(_httpsOnlyKey) ?? false;
    _bandwidthLimit = _prefs?.getInt(_bandwidthLimitKey);

    final prefOrder = _prefs?.getStringList(_installPreferenceKey);
    if (prefOrder != null && prefOrder.isNotEmpty) {
      _installPreference = prefOrder;
    }

    _favorites = _prefs?.getStringList(_favoritesKey) ?? [];
    _recentInstalls = _prefs?.getStringList(_recentInstallsKey) ?? [];

    notifyListeners();
  }

  bool get autoUpdate => _autoUpdate;
  String? get downloadPath => _downloadPath;
  bool get httpsOnly => _httpsOnly;
  int? get bandwidthLimit => _bandwidthLimit;
  List<String> get installPreference => List.unmodifiable(_installPreference);
  List<String> get favorites => List.unmodifiable(_favorites);
  List<String> get recentInstalls => List.unmodifiable(_recentInstalls);

  bool isFavorite(String assetId) => _favorites.contains(assetId);

  /// The favorites list with [assetId] toggled.
  static List<String> updatedFavorites(List<String> current, String assetId) {
    final next = List<String>.of(current);
    if (!next.remove(assetId)) next.add(assetId);
    return next;
  }

  /// The recents list with [assetId] moved to the front, de-duplicated
  /// and capped at [maxRecentInstalls].
  static List<String> updatedRecents(List<String> current, String assetId) {
    return [
      assetId,
      ...current.where((id) => id != assetId),
    ].take(maxRecentInstalls).toList();
  }

  Future<void> toggleFavorite(String assetId) async {
    _favorites = updatedFavorites(_favorites, assetId);
    await _prefs?.setStringList(_favoritesKey, _favorites);
    notifyListeners();
  }

  Future<void> recordRecentInstall(String assetId) async {
    _recentInstalls = updatedRecents(_recentInstalls, assetId);
    await _prefs?.setStringList(_recentInstallsKey, _recentInstalls);
    notifyListeners();
  }

  /// The format version stamped into exported settings files.
  static const settingsFormatVersion = 1;

  /// Every portable setting as a JSON-ready map: the preferences on
  /// this screen plus favorites and recent installs. Machine-local
  /// state (like the last update check) is deliberately excluded.
  Map<String, dynamic> exportSettings() {
    return {
      'xtoolbox_settings_version': settingsFormatVersion,
      'auto_update_enabled': _autoUpdate,
      'download_path': _downloadPath,
      'https_only_mode': _httpsOnly,
      'bandwidth_limit_kbps': _bandwidthLimit,
      'install_preference_order': List<String>.of(_installPreference),
      'favorite_asset_ids': List<String>.of(_favorites),
      'recent_install_ids': List<String>.of(_recentInstalls),
    };
  }

  /// [exportSettings] as pretty-printed JSON text.
  String exportSettingsJson() =>
      const JsonEncoder.withIndent('  ').convert(exportSettings());

  /// Validates an exported settings map and returns the recognized
  /// entries, normalized. Unknown keys are ignored; a key that is
  /// present with the wrong type throws a [FormatException] naming
  /// it, as does a file from a newer format version.
  @visibleForTesting
  static Map<String, dynamic> parseSettingsExport(Map<String, dynamic> data) {
    final version = data['xtoolbox_settings_version'];
    if (version != null) {
      if (version is! int) {
        throw const FormatException(
          '"xtoolbox_settings_version" must be a number.',
        );
      }
      if (version > settingsFormatVersion) {
        throw const FormatException(
          'This settings file was made by a newer version of XToolbox.',
        );
      }
    }

    final result = <String, dynamic>{};

    void boolKey(String key) {
      final value = data[key];
      if (value == null) return;
      if (value is! bool) {
        throw FormatException('"$key" must be true or false.');
      }
      result[key] = value;
    }

    void stringListKey(String key) {
      final value = data[key];
      if (value == null) return;
      if (value is! List || value.any((e) => e is! String)) {
        throw FormatException('"$key" must be a list of strings.');
      }
      result[key] = List<String>.from(value);
    }

    boolKey('auto_update_enabled');
    boolKey('https_only_mode');
    stringListKey('install_preference_order');
    stringListKey('favorite_asset_ids');
    stringListKey('recent_install_ids');

    if (data.containsKey('download_path')) {
      final value = data['download_path'];
      if (value != null && value is! String) {
        throw const FormatException(
          '"download_path" must be a string or null.',
        );
      }
      result['download_path'] = value;
    }

    if (data.containsKey('bandwidth_limit_kbps')) {
      final value = data['bandwidth_limit_kbps'];
      if (value != null && (value is! int || value <= 0)) {
        throw const FormatException(
          '"bandwidth_limit_kbps" must be a positive number or null.',
        );
      }
      result['bandwidth_limit_kbps'] = value;
    }

    return result;
  }

  /// Applies an exported settings map (see [exportSettings]). Only
  /// the keys present are changed; everything else keeps its current
  /// value.
  Future<void> importSettings(Map<String, dynamic> data) async {
    await ready;
    final parsed = parseSettingsExport(data);
    if (parsed.containsKey('auto_update_enabled')) {
      await setAutoUpdate(parsed['auto_update_enabled'] as bool);
    }
    if (parsed.containsKey('https_only_mode')) {
      await setHttpsOnly(parsed['https_only_mode'] as bool);
    }
    if (parsed.containsKey('download_path')) {
      await setDownloadPath(parsed['download_path'] as String?);
    }
    if (parsed.containsKey('bandwidth_limit_kbps')) {
      await setBandwidthLimit(parsed['bandwidth_limit_kbps'] as int?);
    }
    if (parsed.containsKey('install_preference_order')) {
      await setInstallPreference(
        parsed['install_preference_order'] as List<String>,
      );
    }
    if (parsed.containsKey('favorite_asset_ids')) {
      _favorites = parsed['favorite_asset_ids'] as List<String>;
      await _prefs?.setStringList(_favoritesKey, _favorites);
    }
    if (parsed.containsKey('recent_install_ids')) {
      _recentInstalls = parsed['recent_install_ids'] as List<String>;
      await _prefs?.setStringList(_recentInstallsKey, _recentInstalls);
    }
    notifyListeners();
  }

  /// Imports settings from JSON text (see [exportSettingsJson]).
  /// Throws a [FormatException] with a user-facing message when the
  /// text is not a settings file.
  Future<void> importSettingsJson(String text) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FormatException('The file is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'The file does not contain a settings object.',
      );
    }
    await importSettings(decoded);
  }

  Future<void> setAutoUpdate(bool value) async {
    _autoUpdate = value;
    await _prefs?.setBool(_autoUpdateKey, value);
    notifyListeners();
  }

  Future<void> setDownloadPath(String? path) async {
    _downloadPath = path;
    if (path == null) {
      await _prefs?.remove(_downloadPathKey);
    } else {
      await _prefs?.setString(_downloadPathKey, path);
    }
    notifyListeners();
  }

  Future<void> setHttpsOnly(bool value) async {
    _httpsOnly = value;
    await _prefs?.setBool(_httpsOnlyKey, value);
    notifyListeners();
  }

  Future<void> setBandwidthLimit(int? kbps) async {
    _bandwidthLimit = kbps;
    if (kbps == null) {
      await _prefs?.remove(_bandwidthLimitKey);
    } else {
      await _prefs?.setInt(_bandwidthLimitKey, kbps);
    }
    notifyListeners();
  }

  Future<void> setInstallPreference(List<String> order) async {
    _installPreference = order;
    await _prefs?.setStringList(_installPreferenceKey, order);
    notifyListeners();
  }

  DateTime? get lastUpdateCheck {
    final ms = _prefs?.getInt(_lastUpdateCheckKey);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastUpdateCheck(DateTime dt) async {
    await _prefs?.setInt(_lastUpdateCheckKey, dt.millisecondsSinceEpoch);
    notifyListeners();
  }
}
