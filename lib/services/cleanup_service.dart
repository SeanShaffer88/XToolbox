import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'security_checker_service.dart';

/// One selectable cleanup operation.
class CleanupTarget {
  final String id;
  final String title;
  final String description;
  final String category;
  final bool requiresAdmin;
  final bool windowsOnly;

  const CleanupTarget({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    this.requiresAdmin = false,
    this.windowsOnly = false,
  });
}

/// The size of a cleanup target before anything is deleted.
class CleanupEstimate {
  /// Bytes that would be removed, or null when the size cannot be measured.
  final int? bytes;

  /// Why the size is unavailable, or a short explanation for the number.
  final String? note;

  final bool supported;

  const CleanupEstimate({this.bytes, this.note, this.supported = true});

  const CleanupEstimate.unsupported(String reason)
    : bytes = null,
      note = reason,
      supported = false;
}

/// What happened when one cleanup target ran.
class CleanupOutcome {
  final CleanupTarget target;
  final bool success;
  final bool requiresElevation;
  final int bytesFreed;
  final int filesDeleted;
  final int filesSkipped;
  final String message;

  const CleanupOutcome({
    required this.target,
    required this.success,
    required this.bytesFreed,
    required this.filesDeleted,
    required this.filesSkipped,
    required this.message,
    this.requiresElevation = false,
  });
}

/// Runs the cleanup operations shown on the Cleanup screen.
///
/// Every operation reports what it actually did: files that are locked by
/// another process are counted as skipped rather than as freed space, and
/// targets that cannot run on this platform are marked unsupported instead
/// of pretending to succeed.
class CleanupService {
  /// Files in the Downloads folder are only eligible once they have not
  /// changed for this long. Cleanup must never wipe recent downloads.
  static const Duration downloadsRetention = Duration(days: 30);

  static const List<CleanupTarget> targets = [
    CleanupTarget(
      id: 'temp_files',
      title: 'Temporary Files',
      description:
          'Delete the contents of your user temporary folder. Files that '
          'are in use are skipped.',
      category: 'System',
      windowsOnly: true,
    ),
    CleanupTarget(
      id: 'downloads',
      title: 'Old Downloads',
      description:
          'Delete files in your Downloads folder that have not changed in '
          '30 days. Recent downloads are left alone.',
      category: 'User Files',
    ),
    CleanupTarget(
      id: 'recycle_bin',
      title: 'Recycle Bin',
      description: 'Empty the Recycle Bin. This cannot be undone.',
      category: 'System',
      windowsOnly: true,
    ),
    CleanupTarget(
      id: 'browser_cache',
      title: 'Browser Cache',
      description:
          'Clear cache folders for Chrome, Edge, Brave, Chromium and '
          'Firefox. Bookmarks, history and passwords are not touched.',
      category: 'Applications',
      windowsOnly: true,
    ),
    CleanupTarget(
      id: 'log_files',
      title: 'Setup and Update Logs',
      description:
          'Delete Windows servicing, update and setup log files. Recent '
          'diagnostic logs are lost.',
      category: 'System',
      requiresAdmin: true,
      windowsOnly: true,
    ),
    CleanupTarget(
      id: 'thumbnail_cache',
      title: 'Thumbnail Cache',
      description:
          'Delete cached thumbnails. Windows rebuilds them as you browse '
          'folders.',
      category: 'System',
      windowsOnly: true,
    ),
    CleanupTarget(
      id: 'prefetch',
      title: 'Prefetch Files',
      description:
          'Delete Windows prefetch data. Programs may start slightly '
          'slower until Windows rebuilds it.',
      category: 'System',
      requiresAdmin: true,
      windowsOnly: true,
    ),
  ];

  final Map<String, String> _environment;
  final bool _isWindows;
  final DateTime Function() _now;
  final Future<Directory?> Function() _downloadsDirectory;
  final Future<bool> Function() _isElevated;

  CleanupService({
    Map<String, String>? environment,
    bool? isWindows,
    DateTime Function()? now,
    Future<Directory?> Function()? downloadsDirectory,
    Future<bool> Function()? isElevated,
  }) : _environment = environment ?? Platform.environment,
       _isWindows = isWindows ?? Platform.isWindows,
       _now = now ?? DateTime.now,
       _downloadsDirectory = downloadsDirectory ?? getDownloadsDirectory,
       _isElevated = isElevated ?? SecurityCheckerService.isRunningAsAdmin;

  bool get isWindows => _isWindows;

  CleanupTarget? targetById(String id) {
    for (final target in targets) {
      if (target.id == id) return target;
    }
    return null;
  }

  bool supports(CleanupTarget target) => !target.windowsOnly || _isWindows;

  /// Measures how much [target] would remove without deleting anything.
  Future<CleanupEstimate> estimate(CleanupTarget target) async {
    if (!supports(target)) {
      return const CleanupEstimate.unsupported('Windows only');
    }

    try {
      switch (target.id) {
        case 'temp_files':
          final directory = _tempDirectory;
          if (directory == null) {
            return const CleanupEstimate(note: 'Temporary folder not found');
          }
          final sizes = await _measureDirectory(directory);
          return CleanupEstimate(bytes: sizes.bytes);
        case 'downloads':
          final directory = await _downloads();
          if (directory == null) {
            return const CleanupEstimate(note: 'Downloads folder not found');
          }
          final sizes = await _measureOldDownloads(directory);
          return CleanupEstimate(bytes: sizes.bytes);
        case 'recycle_bin':
          final bytes = await _recycleBinBytes();
          return CleanupEstimate(
            bytes: bytes,
            note: bytes == null ? 'Size unavailable' : null,
          );
        case 'browser_cache':
          final sizes = await _measureDirectories(_browserCacheDirectories());
          return CleanupEstimate(bytes: sizes.bytes);
        case 'log_files':
          final sizes = await _measureDirectories(_logDirectories());
          return CleanupEstimate(bytes: sizes.bytes);
        case 'thumbnail_cache':
          final sizes = await _measureFiles(
            _thumbnailDirectory,
            pattern: _thumbnailPattern,
          );
          return CleanupEstimate(bytes: sizes.bytes);
        case 'prefetch':
          final sizes = await _measureFiles(
            _prefetchDirectory,
            pattern: _prefetchPattern,
          );
          return CleanupEstimate(bytes: sizes.bytes);
        default:
          return const CleanupEstimate(note: 'Unknown cleanup option');
      }
    } on FileSystemException {
      return const CleanupEstimate(note: 'Size unavailable');
    }
  }

  /// Runs [target] and reports the real result.
  Future<CleanupOutcome> clean(CleanupTarget target) async {
    if (!supports(target)) {
      return _failure(target, 'This option is only available on Windows.');
    }

    if (target.requiresAdmin && !await _isElevated()) {
      return CleanupOutcome(
        target: target,
        success: false,
        requiresElevation: true,
        bytesFreed: 0,
        filesDeleted: 0,
        filesSkipped: 0,
        message: 'Administrator rights are required for this option.',
      );
    }

    try {
      switch (target.id) {
        case 'temp_files':
          final directory = _tempDirectory;
          if (directory == null) {
            return _failure(target, 'Temporary folder not found.');
          }
          final sizes = await _deleteContents(directory);
          return _resultFor(target, sizes);
        case 'downloads':
          final directory = await _downloads();
          if (directory == null) {
            return _failure(target, 'Downloads folder not found.');
          }
          final sizes = await _deleteOldDownloads(directory);
          return _resultFor(
            target,
            sizes,
            extraNote:
                'Only files older than ${downloadsRetention.inDays} days '
                'were removed.',
          );
        case 'recycle_bin':
          return await _emptyRecycleBin(target);
        case 'browser_cache':
          final directories = _browserCacheDirectories();
          if (directories.isEmpty) {
            return _failure(target, 'No browser caches were found.');
          }
          final sizes = await _deleteFilesInDirectories(directories);
          return _resultFor(
            target,
            sizes,
            extraNote:
                'Close browsers before cleaning for the best result; '
                'locked files are skipped.',
          );
        case 'log_files':
          final directories = _logDirectories();
          if (directories.isEmpty) {
            return _failure(target, 'Windows log folders were not found.');
          }
          final sizes = await _deleteFilesInDirectories(directories);
          return _resultFor(
            target,
            sizes,
            extraNote: 'Log files that Windows is using are skipped.',
          );
        case 'thumbnail_cache':
          final directory = _thumbnailDirectory;
          if (directory == null) {
            return _failure(target, 'Thumbnail cache folder not found.');
          }
          final sizes = await _deleteFilesInDirectories(
            [directory],
            pattern: _thumbnailPattern,
          );
          return _resultFor(
            target,
            sizes,
            extraNote:
                'Sign out or restart Explorer to finish clearing '
                'thumbnails that are still in use.',
          );
        case 'prefetch':
          final directory = _prefetchDirectory;
          if (directory == null) {
            return _failure(target, 'Prefetch folder not found.');
          }
          final sizes = await _deleteFilesInDirectories(
            [directory],
            pattern: _prefetchPattern,
          );
          return _resultFor(target, sizes);
        default:
          return _failure(target, 'Unknown cleanup option.');
      }
    } on FileSystemException catch (error) {
      return _failure(
        target,
        'Cleanup failed: ${error.message}'
        '${error.path == null ? '' : ' (${error.path})'}',
      );
    } on ProcessException {
      return _failure(target, 'Cleanup failed: a required system tool '
          'could not be started.');
    }
  }

  CleanupOutcome _resultFor(
    CleanupTarget target,
    _Sizes sizes, {
    String? extraNote,
  }) {
    final parts = <String>[];
    if (sizes.files > 0) {
      parts.add(
        'Removed ${sizes.files} '
        '${sizes.files == 1 ? 'file' : 'files'} '
        '(${formatBytes(sizes.bytes)}).',
      );
    } else {
      parts.add('Nothing to remove.');
    }
    if (sizes.skipped > 0) {
      parts.add(
        '${sizes.skipped} '
        '${sizes.skipped == 1 ? 'item was' : 'items were'} in use or '
        'could not be deleted.',
      );
    }
    if (extraNote != null) parts.add(extraNote);

    return CleanupOutcome(
      target: target,
      success: sizes.files > 0 || sizes.skipped == 0,
      bytesFreed: sizes.bytes,
      filesDeleted: sizes.files,
      filesSkipped: sizes.skipped,
      message: parts.join(' '),
    );
  }

  CleanupOutcome _failure(CleanupTarget target, String message) {
    return CleanupOutcome(
      target: target,
      success: false,
      bytesFreed: 0,
      filesDeleted: 0,
      filesSkipped: 0,
      message: message,
    );
  }

  Future<CleanupOutcome> _emptyRecycleBin(CleanupTarget target) async {
    final before = await _recycleBinBytes();
    final result = await _runPowerShell(
      r'Clear-RecycleBin -Force -ErrorAction SilentlyContinue',
    );
    if (result == null) {
      return _failure(target, 'PowerShell is unavailable.');
    }
    if (result.exitCode != 0) {
      final details = result.stderr.toString().trim();
      return _failure(
        target,
        details.isEmpty
            ? 'The Recycle Bin could not be emptied.'
            : 'The Recycle Bin could not be emptied: $details',
      );
    }
    final after = await _recycleBinBytes();
    final freed = before != null && after != null && before > after
        ? before - after
        : 0;
    return CleanupOutcome(
      target: target,
      success: true,
      bytesFreed: freed,
      filesDeleted: 0,
      filesSkipped: 0,
      message: freed > 0
          ? 'Emptied the Recycle Bin (${formatBytes(freed)}).'
          : 'Emptied the Recycle Bin.',
    );
  }

  Future<Directory?> _downloads() async {
    try {
      return await _downloadsDirectory();
    } on Exception {
      return null;
    }
  }

  Directory? get _tempDirectory {
    final configured = _environment['TEMP'] ?? _environment['TMP'];
    if (configured != null && configured.trim().isNotEmpty) {
      return Directory(configured);
    }
    return _isWindows ? Directory.systemTemp : null;
  }

  String? get _localAppData {
    final value = _environment['LOCALAPPDATA'];
    return value == null || value.trim().isEmpty ? null : value;
  }

  String? get _windowsDirectory {
    final value = _environment['WINDIR'] ?? _environment['SystemRoot'];
    return value == null || value.trim().isEmpty ? null : value;
  }

  Directory? get _thumbnailDirectory {
    final localAppData = _localAppData;
    if (localAppData == null) return null;
    return Directory(
      joinPath(localAppData, 'Microsoft/Windows/Explorer'),
    );
  }

  Directory? get _prefetchDirectory {
    final windowsDirectory = _windowsDirectory;
    if (windowsDirectory == null) return null;
    return Directory(joinPath(windowsDirectory, 'Prefetch'));
  }

  List<Directory> _logDirectories() {
    final windowsDirectory = _windowsDirectory;
    if (windowsDirectory == null) return const [];
    return [
      'Logs/CBS',
      'Logs/DISM',
      'Logs/MoSetup',
      'Logs/WindowsUpdate',
      'Panther',
    ].map((path) => Directory(joinPath(windowsDirectory, path))).toList();
  }

  /// Cache folders used by the major Chromium browsers and Firefox.
  ///
  /// Only cache directories are listed. Profile data (bookmarks, history,
  /// cookies, passwords) is never added here.
  List<Directory> _browserCacheDirectories() {
    final localAppData = _localAppData;
    if (localAppData == null) return const [];

    const chromiumRoots = [
      'Google/Chrome/User Data',
      'Microsoft/Edge/User Data',
      'BraveSoftware/Brave-Browser/User Data',
      'Chromium/User Data',
    ];
    const cacheNames = ['Cache', 'Code Cache', 'GPUCache'];
    const firefoxProfiles = 'Mozilla/Firefox/Profiles';

    final directories = <Directory>[];
    for (final root in chromiumRoots) {
      final userData = Directory(joinPath(localAppData, root));
      if (!userData.existsSync()) continue;
      for (final profile in _subdirectories(userData)) {
        for (final cacheName in cacheNames) {
          final cache = Directory(joinPath(profile.path, cacheName));
          if (cache.existsSync()) directories.add(cache);
        }
      }
    }

    final profiles = Directory(joinPath(localAppData, firefoxProfiles));
    if (profiles.existsSync()) {
      for (final profile in _subdirectories(profiles)) {
        final cache = Directory(joinPath(profile.path, 'cache2'));
        if (cache.existsSync()) directories.add(cache);
      }
    }
    return directories;
  }

  List<Directory> _subdirectories(Directory directory) {
    try {
      return directory
          .listSync(followLinks: false)
          .whereType<Directory>()
          .toList();
    } on FileSystemException {
      return const [];
    }
  }

  static final RegExp _thumbnailPattern = RegExp(
    r'^thumbcache_.*\.db$',
    caseSensitive: false,
  );
  static final RegExp _prefetchPattern = RegExp(
    r'\.pf$',
    caseSensitive: false,
  );

  Future<int?> _recycleBinBytes() async {
    if (!_isWindows) return null;
    final result = await _runPowerShell(
      r"$total = 0; "
      r"Get-ChildItem -LiteralPath 'C:\$Recycle.Bin' -Force -Recurse "
      r'-File -ErrorAction SilentlyContinue | '
      r'ForEach-Object { $total += $_.Length }; '
      r'[Console]::WriteLine($total)',
    );
    if (result == null || result.exitCode != 0) return null;
    return int.tryParse(result.stdout.toString().trim());
  }

  Future<ProcessResult?> _runPowerShell(String script) async {
    if (!_isWindows) return null;
    try {
      return await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        script,
      ]);
    } on ProcessException {
      return null;
    }
  }

  Future<_Sizes> _measureOldDownloads(Directory directory) async {
    final sizes = _Sizes();
    if (!await directory.exists()) return sizes;
    final cutoff = _now().subtract(downloadsRetention);

    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      try {
        final modified = await entity.lastModified();
        if (!modified.isBefore(cutoff)) continue;
        sizes.bytes += await entity.length();
        sizes.files++;
      } on FileSystemException {
        continue;
      }
    }
    return sizes;
  }

  Future<_Sizes> _deleteOldDownloads(Directory directory) async {
    final sizes = _Sizes();
    if (!await directory.exists()) return sizes;
    final cutoff = _now().subtract(downloadsRetention);

    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      try {
        final modified = await entity.lastModified();
        if (!modified.isBefore(cutoff)) continue;
        final length = await entity.length();
        await entity.delete();
        sizes.bytes += length;
        sizes.files++;
      } on FileSystemException {
        sizes.skipped++;
      }
    }
    return sizes;
  }

  Future<_Sizes> _measureDirectories(List<Directory> directories) async {
    final sizes = _Sizes();
    for (final directory in directories) {
      sizes.add(await _measureDirectory(directory));
    }
    return sizes;
  }

  Future<_Sizes> _measureFiles(
    Directory? directory, {
    RegExp? pattern,
  }) async {
    final sizes = _Sizes();
    if (directory == null || !await directory.exists()) return sizes;
    for (final entity in await directory.list(followLinks: false).toList()) {
      if (entity is! File) continue;
      if (pattern != null && !pattern.hasMatch(_baseName(entity.path))) {
        continue;
      }
      try {
        sizes.bytes += await entity.length();
        sizes.files++;
      } on FileSystemException {
        continue;
      }
    }
    return sizes;
  }

  Future<_Sizes> _measureDirectory(Directory directory) async {
    final sizes = _Sizes();
    if (!await directory.exists()) return sizes;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      try {
        sizes.bytes += await entity.length();
        sizes.files++;
      } on FileSystemException {
        continue;
      }
    }
    return sizes;
  }

  Future<_Sizes> _measureEntity(FileSystemEntity entity) async {
    if (entity is File) {
      final sizes = _Sizes();
      try {
        sizes.bytes = await entity.length();
        sizes.files = 1;
      } on FileSystemException {
        return sizes;
      }
      return sizes;
    }
    if (entity is Directory) return _measureDirectory(entity);
    return _Sizes();
  }

  Future<_Sizes> _deleteContents(Directory directory) async {
    final sizes = _Sizes();
    if (!await directory.exists()) return sizes;

    List<FileSystemEntity> entries;
    try {
      entries = await directory.list(followLinks: false).toList();
    } on FileSystemException {
      return sizes;
    }

    for (final entry in entries) {
      final measured = await _measureEntity(entry);
      try {
        await entry.delete(recursive: true);
        sizes.bytes += measured.bytes;
        sizes.files += measured.files;
      } on FileSystemException {
        sizes.skipped += measured.files == 0 ? 1 : measured.files;
      }
    }
    return sizes;
  }

  Future<_Sizes> _deleteFilesInDirectories(
    List<Directory> directories, {
    RegExp? pattern,
  }) async {
    final sizes = _Sizes();
    for (final directory in directories) {
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        if (pattern != null && !pattern.hasMatch(_baseName(entity.path))) {
          continue;
        }
        try {
          final length = await entity.length();
          await entity.delete();
          sizes.bytes += length;
          sizes.files++;
        } on FileSystemException {
          sizes.skipped++;
        }
      }
    }
    return sizes;
  }

  /// Joins [relative] onto [root] with a single separator and without
  /// allowing a parent-directory segment to escape [root].
  static String joinPath(String root, String relative) {
    final cleanRoot = root
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    final cleanRelative = relative
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'^/+'), '');
    if (cleanRelative.isEmpty) return cleanRoot;
    if (cleanRelative.split('/').contains('..')) return cleanRoot;
    return '$cleanRoot/$cleanRelative';
  }

  static String _baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final separator = normalized.lastIndexOf('/');
    return separator == -1 ? normalized : normalized.substring(separator + 1);
  }

  /// Formats a byte count for display, using binary units.
  static String formatBytes(int bytes) {
    if (bytes < 0) return 'Unknown';
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = value >= 100 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }
}

class _Sizes {
  int bytes = 0;
  int files = 0;
  int skipped = 0;

  void add(_Sizes other) {
    bytes += other.bytes;
    files += other.files;
    skipped += other.skipped;
  }
}
