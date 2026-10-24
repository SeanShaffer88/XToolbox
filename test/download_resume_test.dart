import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xtoolbox/services/download_service.dart';
import 'package:xtoolbox/services/settings_service.dart';
import 'package:xtoolbox/services/toast_notification_service.dart';

/// Downloads resume after transient failures: a dropped connection
/// keeps the bytes already fetched and the next attempt continues
/// with a Range request. The transfer is exercised for real against
/// a raw socket server (HttpServer refuses to truncate a body on
/// purpose); only the settings store is mocked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The widgets binding replaces dart:io's HttpClient with a mock
  // that fails every request; restore the real client.
  HttpOverrides.global = null;

  group('resume helpers', () {
    test('rangeHeaders only asks to resume with bytes on disk', () {
      expect(DownloadService.rangeHeaders(0), isEmpty);
      expect(DownloadService.rangeHeaders(4000), {'Range': 'bytes=4000-'});
    });

    test('shouldAppend only for 206 with a partial file', () {
      expect(
        DownloadService.shouldAppend(statusCode: 206, existingBytes: 10),
        isTrue,
      );
      expect(
        DownloadService.shouldAppend(statusCode: 200, existingBytes: 10),
        isFalse,
      );
      expect(
        DownloadService.shouldAppend(statusCode: 206, existingBytes: 0),
        isFalse,
      );
    });

    test('totalFromContentRange parses the total size', () {
      expect(
        DownloadService.totalFromContentRange('bytes 4000-9999/10000'),
        10000,
      );
      expect(DownloadService.totalFromContentRange('bytes */10000'), 10000);
      expect(DownloadService.totalFromContentRange(null), isNull);
      expect(DownloadService.totalFromContentRange('garbage'), isNull);
      expect(DownloadService.totalFromContentRange('bytes 0-9/*'), isNull);
    });
  });

  group('downloadFile', () {
    late Directory tempDir;
    late SettingsService settings;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dl_resume_');
      SharedPreferences.setMockInitialValues({'download_path': tempDir.path});
      settings = SettingsService();
      for (var i = 0; i < 100 && settings.downloadPath == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(settings.downloadPath, tempDir.path);
    });

    tearDown(() => tempDir.delete(recursive: true));

    test('resumes after the first connection drops mid-body', () async {
      final content = List<int>.generate(10000, (i) => i % 251);
      final rangesSeen = <String?>[];
      var requestCount = 0;

      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close());
      server.listen((socket) {
        final buffer = StringBuffer();
        socket.listen((data) async {
          buffer.write(latin1.decode(data));
          final request = buffer.toString();
          if (!request.contains('\r\n\r\n')) return;
          requestCount++;
          final rangeLine = request
              .split('\r\n')
              .where((l) => l.toLowerCase().startsWith('range:'))
              .firstOrNull;
          rangesSeen.add(rangeLine?.split(':').last.trim());
          if (requestCount == 1) {
            // Promise the whole body, deliver part of it, then drop.
            socket.write(
              'HTTP/1.1 200 OK\r\nContent-Length: ${content.length}\r\n'
              'Connection: close\r\n\r\n',
            );
            socket.add(content.sublist(0, 4000));
            await socket.flush();
            socket.destroy();
          } else if (rangeLine != null &&
              rangeLine.toLowerCase().contains('bytes=4000-')) {
            socket.write(
              'HTTP/1.1 206 Partial Content\r\n'
              'Content-Range: bytes 4000-9999/10000\r\n'
              'Content-Length: 6000\r\nConnection: close\r\n\r\n',
            );
            socket.add(content.sublist(4000));
            await socket.flush();
            await socket.close();
          } else {
            socket.write(
              'HTTP/1.1 200 OK\r\nContent-Length: ${content.length}\r\n'
              'Connection: close\r\n\r\n',
            );
            socket.add(content);
            await socket.flush();
            await socket.close();
          }
        });
      });

      final service = DownloadService(ToastNotificationService(), settings);
      final result = await service.downloadFile(
        url: 'http://127.0.0.1:${server.port}/file.bin',
        displayName: 'Test',
        filename: 'file.bin',
      );

      expect(result, '${tempDir.path}/file.bin');
      expect(await File(result!).readAsBytes(), content);
      expect(requestCount, 2);
      expect(rangesSeen, [null, 'bytes=4000-']);
    });

    test('an HTTP error status fails fast without retrying', () async {
      var requestCount = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requestCount++;
        request.response.statusCode = 404;
        await request.response.close();
      });

      final service = DownloadService(ToastNotificationService(), settings);
      final result = await service.downloadFile(
        url: 'http://127.0.0.1:${server.port}/missing.bin',
        displayName: 'Missing',
        filename: 'missing.bin',
      );

      expect(result, isNull);
      expect(requestCount, 1);
      // The partial-file cleanup removed anything that was written.
      expect(await File('${tempDir.path}/missing.bin').exists(), isFalse);
    });
  });
}
