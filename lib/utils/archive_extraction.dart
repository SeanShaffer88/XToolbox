import 'dart:io';

import 'package:archive/archive.dart';

/// Extracts decoded archives without allowing entries to escape the
/// destination directory.
///
/// Archive entry names are remote-controlled data. A name such as
/// `../../payload.exe`, an absolute path, or a symbolic link must never be
/// trusted as a filesystem path. All entries are validated before any file
/// is written, so a hostile archive cannot leave a partially extracted tree
/// behind merely because its unsafe entry appeared late in the archive.
class ArchiveExtraction {
  ArchiveExtraction._();

  /// Resolves [entryName] beneath [destinationPath].
  ///
  /// Both forward slashes and backslashes are treated as path separators.
  /// Throws a [FormatException] for absolute paths, Windows drive paths,
  /// empty names, and any name containing a parent-directory segment.
  static String resolveEntryPath(String destinationPath, String entryName) {
    final normalizedName = entryName.replaceAll('\\', '/');
    if (normalizedName.isEmpty ||
        normalizedName.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalizedName)) {
      throw FormatException('Unsafe archive entry path: $entryName');
    }

    final segments = <String>[];
    for (final segment in normalizedName.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        throw FormatException('Unsafe archive entry path: $entryName');
      }
      segments.add(segment);
    }

    var root = destinationPath.replaceAll('\\', '/');
    if (root.length > 1) {
      root = root.replaceAll(RegExp(r'/+$'), '');
    }
    if (segments.isEmpty) {
      return root;
    }
    final childPath = segments.join('/');
    return root == '/' ? '/$childPath' : '$root/$childPath';
  }

  /// Extracts [archive] into [destinationPath] and returns the paths of
  /// the regular files written.
  ///
  /// Throws a [FormatException] before writing anything if any entry is a
  /// symbolic link or has an unsafe path.
  static Future<List<String>> extract(
    Archive archive,
    String destinationPath,
  ) async {
    final planned = <({ArchiveFile entry, String outputPath})>[];

    for (final entry in archive.files) {
      if (entry.isSymbolicLink) {
        throw FormatException(
          'Archive contains a symbolic link: ${entry.name}',
        );
      }
      planned.add((
        entry: entry,
        outputPath: resolveEntryPath(destinationPath, entry.name),
      ));
    }

    final destination = Directory(destinationPath);
    await destination.create(recursive: true);

    final extractedFiles = <String>[];
    for (final item in planned) {
      if (item.entry.isFile) {
        final outputFile = File(item.outputPath);
        await outputFile.create(recursive: true);
        await outputFile.writeAsBytes(item.entry.content as List<int>);
        extractedFiles.add(item.outputPath);
      } else {
        await Directory(item.outputPath).create(recursive: true);
      }
    }

    return extractedFiles;
  }
}
