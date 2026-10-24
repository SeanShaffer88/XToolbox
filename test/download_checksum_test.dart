import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xtoolbox/services/download_service.dart';

/// Downloads whose catalog entry pins a SHA-256 are verified before
/// they are extracted or launched; a mismatch deletes the file and
/// fails the install. These tests pin the digest helpers.
void main() {
  group('DownloadService.sha256OfFile', () {
    test('hashes a known file to its published digest', () async {
      final dir = await Directory.systemTemp.createTemp('sha_test_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/abc.bin');
      await file.writeAsString('abc');
      // The well-known SHA-256 of "abc".
      expect(
        await DownloadService.sha256OfFile(file),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });

  group('DownloadService.checksumMatches', () {
    test('matches identical digests regardless of case/whitespace', () {
      expect(
        DownloadService.checksumMatches(
          'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD',
          ' ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad ',
        ),
        isTrue,
      );
    });

    test('rejects different digests', () {
      expect(DownloadService.checksumMatches('a' * 64, 'b' * 64), isFalse);
    });
  });
}
