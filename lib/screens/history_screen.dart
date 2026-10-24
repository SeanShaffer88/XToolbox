import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/asset.dart';
import '../provider/asset_provider.dart';
import '../services/history_service.dart';
import '../services/install_handler_service.dart';
import '../services/settings_service.dart';

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// 'Oct 24, 2026 · 6:40 AM' — local time, no intl dependency.
String formatHistoryTime(DateTime time) {
  final local = time.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final amPm = local.hour < 12 ? 'AM' : 'PM';
  return '${_monthNames[local.month - 1]} ${local.day}, ${local.year} '
      '· $hour12:$minute $amPm';
}

/// The install history: every install, uninstall, and upgrade the
/// app has performed, newest first, with one-click retry for failed
/// installs whose tool is still in the catalog.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<HistoryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final history = Provider.of<HistoryService>(context, listen: false);
    final entries = await history.load();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  IconData _iconFor(HistoryAction action) => switch (action) {
    HistoryAction.install => Icons.download,
    HistoryAction.uninstall => Icons.delete_outline,
    HistoryAction.upgrade => Icons.upgrade,
  };

  /// The catalog method a failed entry can be retried with, resolved
  /// against the live catalog; null when the tool or that exact
  /// method is no longer in the catalog.
  InstallMethod? _retryMethod(HistoryEntry entry) {
    if (entry.assetId.isEmpty) return null;
    final provider = Provider.of<AssetProvider>(context, listen: false);
    final asset = provider.getAssetById(entry.assetId);
    if (asset == null) return null;
    for (final method in asset.installMethods) {
      if (method.type.name == entry.methodType &&
          method.label == entry.methodLabel) {
        return method;
      }
    }
    return null;
  }

  Future<void> _retry(HistoryEntry entry, InstallMethod method) async {
    final handler = Provider.of<InstallHandlerService>(context, listen: false);
    final provider = Provider.of<AssetProvider>(context, listen: false);
    final settings = Provider.of<SettingsService>(context, listen: false);
    final asset = provider.getAssetById(entry.assetId);
    final result = await handler.handleInstall(
      method: method,
      appName: entry.appName,
      assetId: entry.assetId,
    );
    if (result == InstallResult.success && asset != null) {
      await settings.recordRecentInstall(asset.id);
    }
    if (method.packageId != null) {
      await provider.refreshInstalledPackages();
    }
    await _load();
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear install history?'),
        content: const Text(
          'Every recorded install, uninstall, and upgrade will be '
          'removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await Provider.of<HistoryService>(context, listen: false).clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear history',
            onPressed: _entries.isEmpty ? null : _clearHistory,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history,
                      size: 56,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text('No history yet', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Installs, uninstalls, and upgrades you run '
                      'will be recorded here.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final entry = _entries[index];
                final retryMethod =
                    !entry.success && entry.action == HistoryAction.install
                    ? _retryMethod(entry)
                    : null;
                final methodText = entry.methodLabel.isNotEmpty
                    ? entry.methodLabel
                    : entry.methodType;
                return ListTile(
                  leading: Icon(
                    _iconFor(entry.action),
                    color: entry.success
                        ? Colors.green.shade600
                        : theme.colorScheme.error,
                  ),
                  title: Text(entry.appName),
                  subtitle: Text(
                    '${entry.action.label}'
                    '${methodText.isNotEmpty ? ' · $methodText' : ''}'
                    ' · ${formatHistoryTime(entry.timestamp)}',
                  ),
                  trailing: entry.success
                      ? Text(
                          'Done',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.green.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Failed',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (retryMethod != null) ...[
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: () => _retry(entry, retryMethod),
                                child: const Text('Retry'),
                              ),
                            ],
                          ],
                        ),
                );
              },
            ),
    );
  }
}
