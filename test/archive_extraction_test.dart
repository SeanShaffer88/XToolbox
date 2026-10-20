import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xtoolbox/utils/archive_extraction.dart';

void main() {
  group('ArchiveExtraction.resolveEntryPath', () {
    test('keeps ordinary nested entries inside the destination', () {
      expect(
        ArchiveExtraction.resolveEntryPath('/tmp/out', 'folder/tool.exe'),
        '/tmp/out/folder/tool.exe',
      );
      expect(
        ArchiveExtraction.resolveEntryPath('/tmp/out', './folder/./tool.exe'),
        '/tmp/out/folder/tool.exe',
      );
    });

    test('rejects traversal, absolute, drive, and empty entry paths', () {
      for (final entryName in <String>[
        '../evil.exe',
        'safe/../../evil.exe',
        r'..\evil.exe',
        '/tmp/evil.exe',
        r'C:\evil.exe',
        r'C:evil.exe',
        '',
      ]) {
        expect(
          () => ArchiveExtraction.resolveEntryPath('/tmp/out', entryName),
          throwsFormatException,
          reason: entryName,
        );
      }
    });
  });

  group('ArchiveExtraction.extract', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'archive_extraction_test_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('extracts files and directories', () async {
      final archive = Archive()
        ..addFile(ArchiveFile('folder/', 0, const <int>[])..isFile = false)
        ..addFile(
          ArchiveFile(
            'folder/readme.txt',
            utf8.encode('hello').length,
            utf8.encode('hello'),
          ),
        )
        ..addFile(ArchiveFile('plain.txt', 5, utf8.encode('plain')));

      final destination = '${tempDir.path}/out';
      final files = await ArchiveExtraction.extract(archive, destination);

      expect(files, [
        '$destination/folder/readme.txt',
        '$destination/plain.txt',
      ]);
      expect(
        await File('$destination/folder/readme.txt').readAsString(),
        'hello',
      );
      expect(await File('$destination/plain.txt').readAsString(), 'plain');
    });

    test('validates every entry before writing anything', () async {
      final archive = Archive()
        ..addFile(ArchiveFile('safe.txt', 4, utf8.encode('safe')))
        ..addFile(ArchiveFile('../evil.txt', 4, utf8.encode('evil')));

      final destination = '${tempDir.path}/out';

      await expectLater(
        ArchiveExtraction.extract(archive, destination),
        throwsFormatException,
      );
      expect(await Directory(destination).exists(), isFalse);
      expect(await File('${tempDir.path}/evil.txt').exists(), isFalse);
    });

    test('rejects symbolic links before writing anything', () async {
      final archive = Archive()
        ..addFile(ArchiveFile('safe.txt', 4, utf8.encode('safe')))
        ..addFile(
          ArchiveFile('link.txt', 4, utf8.encode('safe'))
            ..isSymbolicLink = true,
        );

      final destination = '${tempDir.path}/out';

      await expectLater(
        ArchiveExtraction.extract(archive, destination),
        throwsFormatException,
      );
      expect(await Directory(destination).exists(), isFalse);
    });
  });
}
