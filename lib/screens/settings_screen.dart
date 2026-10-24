import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/settings_service.dart';
import '../utils/theme_provider.dart';

class _Contributor {
  final String username;
  final String displayName;
  final String role;

  const _Contributor({
    required this.username,
    required this.displayName,
    required this.role,
  });

  String getAvatarUrl() {
    return 'https://github.com/$username.png';
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _bandwidthController = TextEditingController();
  bool _creditsExpanded = false;

  static const List<_Contributor> _contributors = [
    _Contributor(
      username: 'nyxiereal',
      displayName: 'Nyxie',
      role: 'Creator & Lead Developer',
    ),
    _Contributor(
      username: 'sudosign',
      displayName: 'sudosign',
      role: 'Contributor',
    ),
    _Contributor(
      username: 'G-rox-y',
      displayName: 'G-rox-y',
      role: 'Contributor',
    ),
    _Contributor(
      username: 'Ahmed3457',
      displayName: 'Ahmed3457',
      role: 'Contributor',
    ),
    _Contributor(
      username: 'farag2',
      displayName: 'farag2',
      role: 'Contributor',
    ),
    _Contributor(
      username: 'iakuraa',
      displayName: 'iakuraa',
      role: 'Contributor',
    ),
    _Contributor(
      username: '10maurycy10',
      displayName: '10maurycy10',
      role: 'Contributor',
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Initialize bandwidth controller with current value
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settingsService = Provider.of<SettingsService>(
        context,
        listen: false,
      );
      if (settingsService.bandwidthLimit != null) {
        _bandwidthController.text = settingsService.bandwidthLimit.toString();
      }
    });
  }

  @override
  void dispose() {
    _bandwidthController.dispose();
    super.dispose();
  }

  Future<void> _exportSettings(BuildContext context) async {
    final settingsService = Provider.of<SettingsService>(
      context,
      listen: false,
    );
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Settings',
      fileName: 'xtoolbox-settings.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null || !context.mounted) return;
    try {
      await File(path).writeAsString(settingsService.exportSettingsJson());
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Settings exported to $path')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export settings: $e')),
        );
      }
    }
  }

  Future<void> _importSettings(BuildContext context) async {
    final settingsService = Provider.of<SettingsService>(
      context,
      listen: false,
    );
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import Settings',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;
    try {
      final text = await File(path).readAsString();
      await settingsService.importSettingsJson(text);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Settings imported')));
      }
    } on FormatException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: ${e.message}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  Future<void> _pickDownloadPath(BuildContext context) async {
    final settingsService = Provider.of<SettingsService>(
      context,
      listen: false,
    );

    String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Download Directory',
      initialDirectory: settingsService.downloadPath,
    );

    if (selectedDirectory != null && context.mounted) {
      await settingsService.setDownloadPath(selectedDirectory);
    }
  }

  void _updateBandwidthLimit(BuildContext context, String value) async {
    final settingsService = Provider.of<SettingsService>(
      context,
      listen: false,
    );

    if (value.isEmpty) {
      await settingsService.setBandwidthLimit(null);
      return;
    }

    final parsed = int.tryParse(value);
    if (parsed != null && parsed > 0) {
      await settingsService.setBandwidthLimit(parsed);
    }
  }

  Future<void> _launchGitHub() async {
    final uri = Uri.parse('https://github.com/SeanShaffer88/XToolbox');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  IconData _getInstallMethodIcon(String method) {
    return switch (method) {
      'chocolatey' => Icons.coffee,
      'winget' => Icons.window,
      'scoop' => Icons.sync_alt,
      'powershell' => Icons.terminal,
      'direct_download' => Icons.download,
      'web_link' => Icons.open_in_browser,
      _ => Icons.help_outline,
    };
  }

  String _getInstallMethodLabel(String method) {
    return switch (method) {
      'chocolatey' => 'Chocolatey',
      'winget' => 'WinGet',
      'scoop' => 'Scoop',
      'powershell' => 'PowerShell',
      'direct_download' => 'Direct Download',
      'web_link' => 'Web Link',
      _ => method,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Appearance Section
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.palette_outlined, color: colorScheme.primary),
                      const SizedBox(width: 12),
                      Text(
                        'Appearance',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Consumer<ThemeProvider>(
                    builder: (context, themeProvider, _) {
                      final mode = themeProvider.themeMode;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          mode == ThemeMode.system
                              ? Icons.brightness_auto
                              : mode == ThemeMode.dark
                              ? Icons.dark_mode
                              : Icons.light_mode,
                        ),
                        title: const Text('Theme'),
                        subtitle: Text(
                          mode == ThemeMode.system
                              ? 'Following the system theme'
                              : mode == ThemeMode.dark
                              ? 'Always dark'
                              : 'Always light',
                        ),
                        trailing: DropdownButton<ThemeMode>(
                          value: mode,
                          onChanged: (value) {
                            if (value != null) {
                              themeProvider.setThemeMode(value);
                            }
                          },
                          items: const [
                            DropdownMenuItem(
                              value: ThemeMode.system,
                              child: Text('System'),
                            ),
                            DropdownMenuItem(
                              value: ThemeMode.light,
                              child: Text('Light'),
                            ),
                            DropdownMenuItem(
                              value: ThemeMode.dark,
                              child: Text('Dark'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // General Section
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.settings_outlined, color: colorScheme.primary),
                      const SizedBox(width: 12),
                      Text(
                        'General',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Consumer<SettingsService>(
                    builder: (context, settings, _) {
                      return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Auto Update'),
                        subtitle: const Text(
                          'Automatically check for app updates',
                        ),
                        secondary: const Icon(Icons.update),
                        value: settings.autoUpdate,
                        onChanged: (value) => settings.setAutoUpdate(value),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Downloads Section
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.download_outlined, color: colorScheme.primary),
                      const SizedBox(width: 12),
                      Text(
                        'Downloads',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Download Path Selector
                  Consumer<SettingsService>(
                    builder: (context, settings, _) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.folder_outlined),
                        title: const Text('Download Path'),
                        subtitle: Text(
                          settings.downloadPath ?? 'Default Downloads folder',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.folder_open),
                          tooltip: 'Browse',
                          onPressed: () => _pickDownloadPath(context),
                        ),
                      );
                    },
                  ),
                  const Divider(),

                  // Bandwidth Limit
                  Consumer<SettingsService>(
                    builder: (context, settings, _) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.speed),
                        title: const Text('Bandwidth Limit'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            TextField(
                              controller: _bandwidthController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                hintText: 'Unlimited',
                                suffixText: 'KB/s',
                                border: const OutlineInputBorder(),
                                isDense: true,
                                helperText: 'Leave empty for unlimited',
                              ),
                              onChanged: (value) {
                                _updateBandwidthLimit(context, value);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  const Divider(),

                  // HTTPS Only Mode
                  Consumer<SettingsService>(
                    builder: (context, settings, _) {
                      return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('HTTPS Only Mode'),
                        subtitle: const Text(
                          'Only download from secure HTTPS sources',
                        ),
                        secondary: const Icon(Icons.lock_outlined),
                        value: settings.httpsOnly,
                        onChanged: (value) => settings.setHttpsOnly(value),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Install Methods Section
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.construction_outlined,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Install Methods',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Drag to reorder installation preferences',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Consumer<SettingsService>(
                    builder: (context, settings, _) {
                      final preferences = settings.installPreference;

                      return ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: preferences.length,
                        onReorderItem: (oldIndex, newIndex) {
                          final items = List<String>.from(preferences);
                          final item = items.removeAt(oldIndex);
                          items.insert(newIndex, item);
                          settings.setInstallPreference(items);
                        },
                        itemBuilder: (context, index) {
                          final method = preferences[index];
                          return Card(
                            key: ValueKey(method),
                            margin: const EdgeInsets.only(bottom: 8.0),
                            elevation: 1,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: colorScheme.primaryContainer,
                                child: Icon(
                                  _getInstallMethodIcon(method),
                                  color: colorScheme.onPrimaryContainer,
                                  size: 20,
                                ),
                              ),
                              title: Text(_getInstallMethodLabel(method)),
                              subtitle: Text('Priority ${index + 1}'),
                              trailing: ReorderableDragStartListener(
                                index: index,
                                child: Icon(
                                  Icons.drag_handle,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Backup Section
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.save_outlined,
                    color: colorScheme.primary,
                  ),
                  title: Text(
                    'Backup',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.upload_file_outlined),
                  title: const Text('Export Settings'),
                  subtitle: const Text(
                    'Save settings, favorites and recent installs to a '
                    'JSON file',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _exportSettings(context),
                ),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Import Settings'),
                  subtitle: const Text(
                    'Apply settings from a previously exported file; '
                    'only the entries in the file are changed',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _importSettings(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Credits Section
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.info_outlined,
                    color: colorScheme.primary,
                  ),
                  title: Text(
                    'Credits',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  trailing: Icon(
                    _creditsExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  onTap: () {
                    setState(() {
                      _creditsExpanded = !_creditsExpanded;
                    });
                  },
                ),
                if (_creditsExpanded) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._contributors.map((contributor) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildCreditItem(
                              context,
                              username: contributor.username,
                              displayName: contributor.displayName,
                              role: contributor.role,
                              avatarUrl: contributor.getAvatarUrl(),
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                        Center(
                          child: FilledButton.tonalIcon(
                            onPressed: _launchGitHub,
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('View on GitHub'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCreditItem(
    BuildContext context, {
    required String username,
    required String displayName,
    required String role,
    required String avatarUrl,
  }) {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse('https://github.com/$username');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            backgroundImage: NetworkImage(avatarUrl),
            child: const SizedBox.shrink(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  role,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.open_in_new,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
