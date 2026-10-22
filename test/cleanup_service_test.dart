import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xtoolbox/services/cleanup_service.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('xtoolbox_cleanup_');
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  CleanupTarget target(String id) {
    return CleanupService.targets.firstWhere((target) => target.id == id);
  }

  CleanupService service({
    Map<String, String>? environment,
    Future<Directory?> Function()? downloadsDirectory,
    Future<bool> Function()? isElevated,
    DateTime Function()? now,
  }) {
    return CleanupService(
      environment: environment ?? const {},
      isWindows: true,
      now: now,
      downloadsDirectory: downloadsDirectory,
      isElevated: isElevated ?? () async => true,
    );
  }

  test('temporary files are measured and removed', () async {
    final temp = Directory('${sandbox.path}/temp')..createSync(recursive: true);
    File('${temp.path}/a.tmp').writeAsStringSync('12345');
    Directory('${temp.path}/nested').createSync();
    File('${temp.path}/nested/b.tmp').writeAsStringSync('123');

    final cleanup = service(environment: {'TEMP': temp.path});
    final estimate = await cleanup.estimate(target('temp_files'));
    expect(estimate.bytes, 8);

    final outcome = await cleanup.clean(target('temp_files'));
    expect(outcome.success, isTrue);
    expect(outcome.bytesFreed, 8);
    expect(outcome.filesDeleted, 2);
    expect(temp.listSync(), isEmpty);
  });

  test('only downloads older than the retention window are removed', () async {
    final downloads = Directory('${sandbox.path}/Downloads')
      ..createSync(recursive: true);
    final now = DateTime(2026, 10, 22, 12);
    final oldFile = File('${downloads.path}/old.exe')..writeAsStringSync('old');
    oldFile.setLastModifiedSync(now.subtract(const Duration(days: 40)));
    final recentFile = File('${downloads.path}/recent.exe')
      ..writeAsStringSync('recent');
    recentFile.setLastModifiedSync(now.subtract(const Duration(days: 2)));

    final cleanup = service(
      downloadsDirectory: () async => downloads,
      now: () => now,
    );
    final estimate = await cleanup.estimate(target('downloads'));
    expect(estimate.bytes, 3);

    final outcome = await cleanup.clean(target('downloads'));
    expect(outcome.bytesFreed, 3);
    expect(oldFile.existsSync(), isFalse);
    expect(recentFile.existsSync(), isTrue);
    expect(outcome.message, contains('30 days'));
  });

  test('browser cache cleanup leaves profile data alone', () async {
    final localAppData = Directory('${sandbox.path}/LocalAppData');
    final profile = Directory(
      '${localAppData.path}/Google/Chrome/User Data/Default',
    )..createSync(recursive: true);
    final cache = Directory('${profile.path}/Cache')
      ..createSync(recursive: true);
    File('${cache.path}/data_0').writeAsStringSync('cache!');
    File('${profile.path}/Bookmarks').writeAsStringSync('keep me');
    final firefoxCache = Directory(
      '${localAppData.path}/Mozilla/Firefox/Profiles/abc.default/cache2',
    )..createSync(recursive: true);
    File('${firefoxCache.path}/entry').writeAsStringSync('ff');

    final cleanup = service(environment: {'LOCALAPPDATA': localAppData.path});
    final estimate = await cleanup.estimate(target('browser_cache'));
    expect(estimate.bytes, 8);

    final outcome = await cleanup.clean(target('browser_cache'));
    expect(outcome.bytesFreed, 8);
    expect(outcome.filesDeleted, 2);
    expect(File('${profile.path}/Bookmarks').existsSync(), isTrue);
  });

  test('thumbnail cleanup only removes thumbnail databases', () async {
    final localAppData = Directory('${sandbox.path}/LocalAppData');
    final explorer = Directory(
      '${localAppData.path}/Microsoft/Windows/Explorer',
    )..createSync(recursive: true);
    final thumbnail = File('${explorer.path}/thumbcache_96.db')
      ..writeAsStringSync('thumb');
    final iconCache = File('${explorer.path}/iconcache_96.db')
      ..writeAsStringSync('icon');

    final cleanup = service(environment: {'LOCALAPPDATA': localAppData.path});
    final estimate = await cleanup.estimate(target('thumbnail_cache'));
    expect(estimate.bytes, 5);

    final outcome = await cleanup.clean(target('thumbnail_cache'));
    expect(outcome.bytesFreed, 5);
    expect(outcome.filesDeleted, 1);
    expect(thumbnail.existsSync(), isFalse);
    expect(iconCache.existsSync(), isTrue);
  });

  test('prefetch cleanup removes only .pf files', () async {
    final windows = Directory('${sandbox.path}/Windows');
    final prefetch = Directory('${windows.path}/Prefetch')
      ..createSync(recursive: true);
    final pfFile = File('${prefetch.path}/APP.pf')..writeAsStringSync('pf');
    final otherFile = File('${prefetch.path}/ReadyBoot')
      ..writeAsStringSync('keep');

    final cleanup = service(environment: {'WINDIR': windows.path});
    final outcome = await cleanup.clean(target('prefetch'));
    expect(outcome.success, isTrue);
    expect(outcome.bytesFreed, 2);
    expect(outcome.filesDeleted, 1);
    expect(pfFile.existsSync(), isFalse);
    expect(otherFile.existsSync(), isTrue);
  });

  test('admin-only targets report that elevation is required', () async {
    final windows = Directory('${sandbox.path}/Windows');
    final logs = Directory('${windows.path}/Logs/CBS')
      ..createSync(recursive: true);
    final logFile = File('${logs.path}/CBS.log')..writeAsStringSync('log');

    final cleanup = service(
      environment: {'WINDIR': windows.path},
      isElevated: () async => false,
    );
    final outcome = await cleanup.clean(target('log_files'));
    expect(outcome.success, isFalse);
    expect(outcome.requiresElevation, isTrue);
    expect(outcome.filesDeleted, 0);
    expect(logFile.existsSync(), isTrue);
  });

  test('windows-only targets are unsupported on other platforms', () async {
    final cleanup = CleanupService(
      environment: const {},
      isWindows: false,
      isElevated: () async => true,
    );
    final estimate = await cleanup.estimate(target('prefetch'));
    expect(estimate.supported, isFalse);

    final outcome = await cleanup.clean(target('prefetch'));
    expect(outcome.success, isFalse);
    expect(outcome.message, contains('Windows'));
  });

  test('joinPath keeps entries inside their root', () {
    expect(
      CleanupService.joinPath('C:/Users/me/AppData', 'Microsoft/Windows'),
      'C:/Users/me/AppData/Microsoft/Windows',
    );
    expect(CleanupService.joinPath('C:/root/', '/child'), 'C:/root/child');
    expect(CleanupService.joinPath('C:/root', '../escape'), 'C:/root');
    expect(
      CleanupService.joinPath(r'C:\root', r'child\file'),
      'C:/root/child/file',
    );
  });

  test('formatBytes uses readable binary units', () {
    expect(CleanupService.formatBytes(0), '0 B');
    expect(CleanupService.formatBytes(512), '512 B');
    expect(CleanupService.formatBytes(2048), '2.0 KB');
    expect(CleanupService.formatBytes(1536 * 1024), '1.5 MB');
    expect(CleanupService.formatBytes(1024 * 1024 * 1024), '1.0 GB');
    expect(CleanupService.formatBytes(100 * 1024 * 1024), '100 MB');
  });
}
