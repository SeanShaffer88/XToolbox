import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/asset.dart';
import '../provider/asset_provider.dart';
import '../services/install_handler_service.dart';
import '../services/settings_service.dart';
import '../utils/iconmap_util.dart';

class ViewItemWidget extends StatelessWidget {
  final Asset asset;

  const ViewItemWidget({super.key, required this.asset});

  static Future<void> show(BuildContext context, Asset asset) async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => ViewItemWidget(asset: asset),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  Future<void> _handleInstall(
    BuildContext context,
    InstallMethod method,
  ) async {
    final installHandler = Provider.of<InstallHandlerService>(
      context,
      listen: false,
    );
    final assetProvider = Provider.of<AssetProvider>(context, listen: false);
    final settings = Provider.of<SettingsService>(context, listen: false);

    // Close the dialog first
    Navigator.of(context).pop();

    // Use the install handler service which has auto-retry logic
    final result = await installHandler.handleInstall(
      method: method,
      appName: asset.name,
      assetId: asset.id,
    );

    if (result == InstallResult.success) {
      await settings.recordRecentInstall(asset.id);
    }

    // Keep the Installed badges truthful after a package-manager install.
    if (method.packageId != null) {
      await assetProvider.refreshInstalledPackages();
    }
  }

  Future<void> _handleUninstall(
    BuildContext context,
    InstallMethod method,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Uninstall ${asset.name}?'),
        content: Text(
          'Winget will remove ${asset.name} from this PC. '
          'Its own settings and data may remain. '
          'You can reinstall it from here at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Uninstall'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final installHandler = Provider.of<InstallHandlerService>(
      context,
      listen: false,
    );
    final assetProvider = Provider.of<AssetProvider>(context, listen: false);

    Navigator.of(context).pop();
    await installHandler.handleUninstall(
      method: method,
      appName: asset.name,
      assetId: asset.id,
    );
    await assetProvider.refreshInstalledPackages();
  }

  Future<void> _handleUpgrade(
    BuildContext context,
    InstallMethod method,
  ) async {
    final installHandler = Provider.of<InstallHandlerService>(
      context,
      listen: false,
    );
    final assetProvider = Provider.of<AssetProvider>(context, listen: false);

    Navigator.of(context).pop();
    await installHandler.handleUpgrade(
      method: method,
      appName: asset.name,
      assetId: asset.id,
    );
    await assetProvider.refreshInstalledPackages();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final assetProvider = context.watch<AssetProvider>();

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.cardColor.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        asset.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Consumer<SettingsService>(
                      builder: (context, settings, _) {
                        final isFavorite = settings.isFavorite(asset.id);
                        return IconButton(
                          icon: Icon(
                            isFavorite ? Icons.star : Icons.star_border,
                          ),
                          color: isFavorite ? Colors.amber : null,
                          tooltip: isFavorite
                              ? 'Remove from favorites'
                              : 'Add to favorites',
                          onPressed: () => settings.toggleFavorite(asset.id),
                        );
                      },
                    ),
                    if (asset.homepage.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.open_in_new),
                        tooltip: 'Open Homepage',
                        onPressed: () => _launchUrl(asset.homepage),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // Body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with icon and basic info
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              getIconFromString(asset.icon),
                              size: 48,
                              color: primaryColor,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  asset.name,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'by ${asset.author}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.textTheme.bodySmall?.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // Description
                      Text(
                        'About',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(asset.description, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 32),

                      // Installation methods
                      Text(
                        'Installation Options',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...asset.installMethods.map(
                        (method) => _InstallMethodCard(
                          method: method,
                          installedVersion: method.packageId == null
                              ? null
                              : assetProvider.installedVersionFor(
                                  method.packageId!,
                                ),
                          upgradeVersion: method.packageId == null
                              ? null
                              : assetProvider.upgradeVersionFor(
                                  method.packageId!,
                                ),
                          onInstall: () => _handleInstall(context, method),
                          onUninstall:
                              method.type == InstallType.winget &&
                                  method.packageId != null
                              ? () => _handleUninstall(context, method)
                              : null,
                          onUpgrade:
                              method.type == InstallType.winget &&
                                  method.packageId != null
                              ? () => _handleUpgrade(context, method)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstallMethodCard extends StatefulWidget {
  final InstallMethod method;
  final VoidCallback onInstall;
  final VoidCallback? onUninstall;
  final VoidCallback? onUpgrade;
  final String? installedVersion;
  final String? upgradeVersion;

  const _InstallMethodCard({
    required this.method,
    required this.onInstall,
    this.onUninstall,
    this.onUpgrade,
    this.installedVersion,
    this.upgradeVersion,
  });

  @override
  State<_InstallMethodCard> createState() => _InstallMethodCardState();
}

class _InstallMethodCardState extends State<_InstallMethodCard> {
  bool _isHovered = false;

  IconData _getIconForType(InstallType type) {
    switch (type) {
      case InstallType.directDownload:
        return Icons.download;
      case InstallType.winget:
        return Icons.terminal;
      case InstallType.chocolatey:
        return Icons.terminal;
      case InstallType.scoop:
        return Icons.terminal;
      case InstallType.microsoftStore:
        return Icons.store;
      case InstallType.powershell:
        return Icons.terminal;
      case InstallType.webLink:
        return Icons.open_in_browser;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isHovered
                ? primaryColor.withValues(alpha: 0.08)
                : theme.cardColor.withValues(alpha: 0.95),
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: Row(
            children: [
              Icon(
                _getIconForType(widget.method.type),
                size: 28,
                color: primaryColor,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.method.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.method.type.displayName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                    if (widget.installedVersion != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 16,
                            color: Colors.green.shade600,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Installed · v${widget.installedVersion}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.green.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (widget.upgradeVersion != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.upgrade,
                            size: 16,
                            color: Colors.amber.shade800,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Update available · v${widget.upgradeVersion}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.amber.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: widget.onInstall,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Install'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
              if (widget.installedVersion != null &&
                  widget.upgradeVersion != null &&
                  widget.onUpgrade != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: widget.onUpgrade,
                  icon: const Icon(Icons.upgrade, size: 18),
                  label: const Text('Upgrade'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
              if (widget.installedVersion != null &&
                  widget.onUninstall != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: widget.onUninstall,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Uninstall'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
