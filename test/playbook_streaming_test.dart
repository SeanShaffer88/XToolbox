import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xtoolbox/services/playbook_service.dart';

/// Playbook downloads stream to disk with real byte progress (they
/// used to be whole-body fetches behind fixed stage percentages).
/// These tests pin the streaming writer they now share.
void main() {
  group('PlaybookService.writeStreamToFile', () {
    test('writes every chunk in order and reports cumulative bytes', () async {
      final dir = await Directory.systemTemp.createTemp('pb_stream_');
      addTearDown(() => dir.delete(recursive: true));
      final target = File('${dir.path}/out.bin');
      final reports = <int>[];

      await PlaybookService.writeStreamToFile(
        Stream.fromIterable([
          [1, 2, 3],
          [4, 5],
          [6],
        ]),
        target,
        totalBytes: 6,
        onBytes: (received, total) {
          expect(total, 6);
          reports.add(received);
        },
      );

      expect(await target.readAsBytes(), [1, 2, 3, 4, 5, 6]);
      expect(reports, [3, 5, 6]);
    });

    test('propagates stream errors and still closes the file', () async {
      final dir = await Directory.systemTemp.createTemp('pb_stream_');
      addTearDown(() => dir.delete(recursive: true));
      final target = File('${dir.path}/out.bin');

      Stream<List<int>> failing() async* {
        yield [1];
        throw StateError('connection dropped');
      }

      await expectLater(
        PlaybookService.writeStreamToFile(
          failing(),
          target,
          totalBytes: -1,
          onBytes: (_, _) {},
        ),
        throwsStateError,
      );
      expect(await target.readAsBytes(), [1]);
    });
  });
}
