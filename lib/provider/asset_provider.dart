import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/asset.dart';
import '../services/catalog_service.dart';
import '../services/winget_service.dart';

class AssetProvider extends ChangeNotifier {
  final WingetService _wingetService;
  final CatalogService _catalogService;

  AssetProvider({WingetService? wingetService, CatalogService? catalogService})
    : _wingetService = wingetService ?? WingetService(),
      _catalogService = catalogService ?? CatalogService();

  List<Asset> _assets = [];
  bool _isLoading = false;
  String? _error;

  List<Asset> get assets => _assets;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Whether the loaded catalog came from the remote catalog cache
  /// rather than the copy bundled with the app.
  bool _usingRemoteCatalog = false;
  bool get usingRemoteCatalog => _usingRemoteCatalog;

  /// When the remote catalog in use was fetched, if known.
  DateTime? _catalogFetchedAt;
  DateTime? get catalogFetchedAt => _catalogFetchedAt;

  /// Hash of the catalog text currently loaded, so a background
  /// refresh only swaps the catalog in when it actually changed.
  String? _catalogTextHash;

  /// Installed winget packages: package id → installed version.
  Map<String, String> _installedPackages = {};

  Map<String, String> get installedPackages => _installedPackages;

  /// The installed version of [packageId], or null when not installed.
  String? installedVersionFor(String packageId) =>
      _installedPackages[packageId];

  /// Whether any install method of [asset] maps to an installed
  /// package.
  bool isInstalled(Asset asset) => asset.installMethods.any(
    (m) => m.packageId != null && _installedPackages.containsKey(m.packageId),
  );

  /// Packages with a winget upgrade available: id → available version.
  Map<String, String> _upgradeablePackages = {};

  Map<String, String> get upgradeablePackages => _upgradeablePackages;

  /// The version [packageId] can upgrade to, or null when it is
  /// current (or not installed through winget).
  String? upgradeVersionFor(String packageId) =>
      _upgradeablePackages[packageId];

  /// Whether any install method of [asset] has an upgrade available.
  bool isUpgradeAvailable(Asset asset) => asset.installMethods.any(
    (m) => m.packageId != null && _upgradeablePackages.containsKey(m.packageId),
  );

  /// Re-queries winget for the installed-package list and for the
  /// upgrades available for them.
  Future<void> refreshInstalledPackages() async {
    _installedPackages = await _wingetService.queryInstalled();
    _upgradeablePackages = await _wingetService.queryUpgrades();
    notifyListeners();
  }

  List<Asset> getAssetsByCategory(String category) {
    return _assets.where((asset) => asset.category == category).toList();
  }

  Asset? getAssetById(String id) {
    try {
      return _assets.firstWhere((asset) => asset.id == id);
    } catch (e) {
      return null;
    }
  }

  Future<void> loadAssets() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // A previously fetched remote catalog wins over the bundled
      // copy; the bundled copy is the always-available fallback.
      final cached = await _catalogService.loadCachedCatalogText();
      if (cached != null) {
        _assets = CatalogService.tryParseCatalog(cached)!;
        _usingRemoteCatalog = true;
        _catalogFetchedAt = await _catalogService.cachedCatalogFetchedAt();
        _catalogTextHash = CatalogService.catalogHash(cached);
      } else {
        final bundled = await rootBundle.loadString('assets/asset_list.json');
        final parsed = CatalogService.tryParseCatalog(bundled);
        if (parsed == null) {
          throw StateError('The bundled catalog is not valid');
        }
        _assets = parsed;
        _usingRemoteCatalog = false;
        _catalogFetchedAt = null;
        _catalogTextHash = CatalogService.catalogHash(bundled);
      }
      _error = null;
    } catch (e) {
      _error = 'Failed to load assets: $e';
      _assets = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    // Refresh in the background; if a newer catalog was adopted, it
    // is swapped in below. Loading never waits on the network.
    unawaited(_refreshCatalog());
  }

  Future<void> _refreshCatalog() async {
    if (!await _catalogService.refresh()) return;
    final text = await _catalogService.loadCachedCatalogText();
    if (text == null) return;
    final hash = CatalogService.catalogHash(text);
    if (hash == _catalogTextHash) return;
    final parsed = CatalogService.tryParseCatalog(text);
    if (parsed == null) return;
    _assets = parsed;
    _usingRemoteCatalog = true;
    _catalogFetchedAt = await _catalogService.cachedCatalogFetchedAt();
    _catalogTextHash = hash;
    notifyListeners();
  }
}
