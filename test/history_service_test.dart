import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xtoolbox/services/history_service.dart';

HistoryEntry entry(String name, {bool success = true, int minute = 0}) =>
    HistoryEntry(
      assetId: 'tool-$name',
      appName: name,
      action: HistoryAction.install,
      methodType: 'winget',
      methodLabel: 'WinGet',
      success: success,
      timestamp: DateTime.utc(2026, 10, 24, 12, minute),
    );

void main() {
  group('HistoryEntry serialization', () {
    test('round-trips through JSON', () {
      final original = entry('Git', success: false, minute: 30);
      final parsed = HistoryEntry.fromJson(original.toJson());
      expect(parsed, isNotNull);
      expect(parsed!.assetId, original.assetId);
      expect(parsed.appName, original.appName);
      expect(parsed.action, original.action);
      expect(parsed.methodType, original.methodType);
      expect(parsed.methodLabel, original.methodLabel);
      expect(parsed.success, isFalse);
      expect(parsed.timestamp, original.timestamp);
    });

    test('malformed entries parse to null', () {
      expect(HistoryEntry.fromJson({'action': 'explode'}), isNull);
      expect(HistoryEntry.fromJson({'action': 'install'}), isNull);
      expect(
        HistoryEntry.fromJson({'timestamp': '2026-10-24T12:00:00Z'}),
        isNull,
      );
    });

    test('parseEntries skips bad entries and tolerates garbage', () {
      final text = json.encode([
        entry('A').toJson(),
        {'nonsense': true},
        entry('B').toJson(),
      ]);
      final parsed = HistoryService.parseEntries(text);
      expect(parsed.map((e) => e.appName), ['A', 'B']);
      expect(HistoryService.parseEntries('not json'), isEmpty);
      expect(HistoryService.parseEntries('{}'), isEmpty);
    });
  });

  group('HistoryService persistence', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('history_service_test');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    HistoryService service() => HistoryService(supportDir: () async => dir);

    test('records newest-first and persists across instances', () async {
      final svc = service();
      await svc.record(entry('First', minute: 1));
      await svc.record(entry('Second', minute: 2));
      final inMemory = await svc.load();
      expect(inMemory.map((e) => e.appName), ['Second', 'First']);

      final reopened = await service().load();
      expect(reopened.map((e) => e.appName), ['Second', 'First']);
    });

    test('caps the log at maxEntries, dropping the oldest', () async {
      final svc = service();
      for (var i = 0; i < HistoryService.maxEntries + 5; i++) {
        await svc.record(entry('Tool$i', minute: i % 60));
      }
      final entries = await svc.load();
      expect(entries, hasLength(HistoryService.maxEntries));
      expect(entries.first.appName, 'Tool${HistoryService.maxEntries + 4}');
    });

    test('clear erases the log and the file', () async {
      final svc = service();
      await svc.record(entry('A'));
      await svc.clear();
      expect(await svc.load(), isEmpty);
      expect(
        await File('${dir.path}/${HistoryService.fileName}').exists(),
        isFalse,
      );
    });

    test('a corrupt history file loads as empty', () async {
      await File(
        '${dir.path}/${HistoryService.fileName}',
      ).writeAsString('[{"asset_id": ');
      expect(await service().load(), isEmpty);
    });
  });
}
