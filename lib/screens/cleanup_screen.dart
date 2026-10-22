import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/cleanup_service.dart';
import '../services/security_checker_service.dart';
import '../services/toast_notification_service.dart';

class CleanupScreen extends StatefulWidget {
  const CleanupScreen({super.key});

  @override
  State<CleanupScreen> createState() => _CleanupScreenState();
}

class _CleanupScreenState extends State<CleanupScreen> {
  final CleanupService _cleanupService = CleanupService();
  final Map<String, bool> _selected = {};
  final Map<String, CleanupEstimate> _estimates = {};
  bool _calculating = false;
  bool _cleaning = false;
  String? _progress;

  @override
  void initState() {
    super.initState();
    for (final target in CleanupService.targets) {
      _selected[target.id] = false;
    }
    _calculateSizes();
  }

  List<CleanupTarget> get _selectedTargets {
    return CleanupService.targets
        .where((target) => _selected[target.id] ?? false)
        .toList();
  }

  int? get _estimatedTotal {
    var total = 0;
    var measuredAny = false;
    for (final target in _selectedTargets) {
      final bytes = _estimates[target.id]?.bytes;
      if (bytes != null) {
        total += bytes;
        measuredAny = true;
      }
    }
    return measuredAny ? total : null;
  }

  bool get _hasUnknownSelected {
    for (final target in _selectedTargets) {
      if (_estimates[target.id]?.bytes == null) return true;
    }
    return false;
  }

  Future<void> _calculateSizes() async {
    if (_calculating) return;

    setState(() {
      _calculating = true;
    });

    for (final target in CleanupService.targets) {
      final estimate = await _cleanupService.estimate(target);
      if (!mounted) return;
      setState(() {
        _estimates[target.id] = estimate;
      });
    }

    if (!mounted) return;
    setState(() {
      _calculating = false;
    });
  }

  void _toggle(String id, bool? value) {
    if (_cleaning || value == null) return;
    setState(() {
      _selected[id] = value;
    });
  }

  String _estimateText(CleanupTarget target) {
    if (!_cleanupService.supports(target)) {
      return 'Not available on this system';
    }
    final estimate = _estimates[target.id];
    if (estimate == null) {
      return _calculating ? 'Measuring...' : 'Not measured';
    }
    final bytes = estimate.bytes;
    if (bytes != null) return CleanupService.formatBytes(bytes);
    return estimate.note ?? 'Size unavailable';
  }

  IconData _iconFor(String id) {
    return switch (id) {
      'temp_files' => Icons.folder_delete,
      'downloads' => Icons.download,
      'recycle_bin' => Icons.delete,
      'browser_cache' => Icons.web,
      'log_files' => Icons.description,
      'thumbnail_cache' => Icons.image,
      'prefetch' => Icons.speed,
      _ => Icons.cleaning_services,
    };
  }

  Future<void> _performCleanup() async {
    final toastService = context.read<ToastNotificationService>();
    final selected = _selectedTargets;

    if (selected.isEmpty) {
      toastService.addNotification(
        title: 'No items selected',
        message: 'Select at least one cleanup option first.',
        status: ToastStatus.error,
      );
      return;
    }

    final needsAdmin = selected.any((target) => target.requiresAdmin);
    if (needsAdmin && !await SecurityCheckerService.isRunningAsAdmin()) {
      if (!mounted) return;
      final elevate = await showDialog<bool>(
        context: context,
        builder: (context) => const _ElevationDialog(),
      );
      if (elevate == true) {
        await SecurityCheckerService.requestAdminElevation();
      }
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _buildConfirmDialog(context, selected),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _cleaning = true;
      _progress = 'Preparing cleanup...';
    });

    final toastId = toastService.addNotification(
      title: 'Cleaning...',
      message: 'Starting',
      status: ToastStatus.inProgress,
    );
    final outcomes = <CleanupOutcome>[];

    for (var index = 0; index < selected.length; index++) {
      final target = selected[index];
      if (mounted) {
        setState(() {
          _progress = 'Cleaning ${target.title}...';
        });
      }
      toastService.updateNotification(
        id: toastId,
        message: '${index + 1} of ${selected.length}: ${target.title}',
        progress: index / selected.length,
      );
      outcomes.add(await _cleanupService.clean(target));
    }

    final freed = outcomes.fold<int>(
      0,
      (total, outcome) => total + outcome.bytesFreed,
    );
    final failures = outcomes.where((outcome) => !outcome.success).length;
    toastService.updateNotification(
      id: toastId,
      title: failures == 0
          ? 'Cleanup complete'
          : 'Cleanup finished with issues',
      message: failures == 0
          ? 'Freed ${CleanupService.formatBytes(freed)}'
          : '$failures of ${outcomes.length} options reported a problem',
      status: failures == 0 ? ToastStatus.success : ToastStatus.error,
      progress: 1.0,
    );

    if (!mounted) return;
    setState(() {
      _cleaning = false;
      _progress = null;
      for (final target in CleanupService.targets) {
        _selected[target.id] = false;
      }
    });

    await showDialog<void>(
      context: context,
      builder: (context) => _CleanupResultDialog(outcomes: outcomes),
    );
    if (!mounted) return;
    await _calculateSizes();
  }

  Widget _buildConfirmDialog(
    BuildContext context,
    List<CleanupTarget> selected,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final includesDownloads = selected.any(
      (target) => target.id == 'downloads',
    );
    final downloadsNote = includesDownloads
        ? ' Only downloads last modified more than '
              '${CleanupService.downloadsRetention.inDays} days ago are '
              'removed.'
        : '';

    return AlertDialog(
      title: const Text('Confirm Cleanup'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('These files will be permanently deleted:'),
              const SizedBox(height: 12),
              for (final target in selected)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(_iconFor(target.id), size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(target.title)),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This cannot be undone. Files that are in use are '
                        'skipped and reported.$downloadsNote',
                        style: TextStyle(
                          color: colorScheme.onErrorContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          child: const Text('Delete Selected'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = _selectedTargets;
    final total = _estimatedTotal;

    return Scaffold(
      appBar: AppBar(
        title: const Text('System Cleanup'),
        actions: [
          if (_calculating)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _cleaning ? null : _calculateSizes,
              tooltip: 'Recalculate sizes',
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Cleanup deletes files permanently. Options that need '
                    'administrator rights are marked Admin; files in use are '
                    'skipped and reported.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          if (selected.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.cleaning_services,
                    color: colorScheme.onPrimaryContainer,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${selected.length} '
                          '${selected.length == 1 ? 'item' : 'items'} selected',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        Text(
                          total == null
                              ? 'Estimated space: not available'
                              : 'Estimated space to free: '
                                    '${CleanupService.formatBytes(total)}'
                                    '${_hasUnknownSelected ? ' (some sizes unknown)' : ''}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (_progress != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_progress!)),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: CleanupService.targets.length,
              itemBuilder: (context, index) {
                final target = CleanupService.targets[index];
                final supported = _cleanupService.supports(target);
                final isSelected = _selected[target.id] ?? false;
                final category = target.requiresAdmin
                    ? '${target.category} · Admin'
                    : target.category;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: CheckboxListTile(
                    value: isSelected,
                    onChanged: _cleaning || !supported
                        ? null
                        : (value) => _toggle(target.id, value),
                    secondary: Icon(
                      _iconFor(target.id),
                      color: supported
                          ? colorScheme.primary
                          : colorScheme.outline,
                    ),
                    title: Text(target.title),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(target.description),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  category,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                              Text(
                                _estimateText(target),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _cleaning ? null : _performCleanup,
              icon: _cleaning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cleaning_services),
              label: Text(_cleaning ? 'Cleaning...' : 'Start Cleanup'),
            ),
    );
  }
}

class _ElevationDialog extends StatelessWidget {
  const _ElevationDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Administrator rights required'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.admin_panel_settings, size: 48, color: Colors.orange),
          SizedBox(height: 16),
          Text(
            'One or more selected options need administrator rights to '
            'delete protected system files.',
          ),
          SizedBox(height: 12),
          Text(
            'Restart XToolBox as administrator to run them, or cancel and '
            'deselect those options.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Restart as Administrator'),
        ),
      ],
    );
  }
}

class _CleanupResultDialog extends StatelessWidget {
  final List<CleanupOutcome> outcomes;

  const _CleanupResultDialog({required this.outcomes});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalFreed = outcomes.fold<int>(
      0,
      (total, outcome) => total + outcome.bytesFreed,
    );
    final totalFiles = outcomes.fold<int>(
      0,
      (total, outcome) => total + outcome.filesDeleted,
    );

    return AlertDialog(
      title: const Text('Cleanup Results'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Freed ${CleanupService.formatBytes(totalFreed)} '
                'across $totalFiles '
                '${totalFiles == 1 ? 'file' : 'files'}.',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              for (final outcome in outcomes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        outcome.success
                            ? Icons.check_circle
                            : Icons.error_outline,
                        color: outcome.success
                            ? Colors.green
                            : colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              outcome.target.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              outcome.message,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
