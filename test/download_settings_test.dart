import 'package:flutter_test/flutter_test.dart';
import 'package:xtoolbox/services/download_service.dart';

/// The Downloads settings (custom path, HTTPS-only, bandwidth limit)
/// were previously saved but never applied. These tests pin the rules
/// DownloadService now uses to honor them.
void main() {
  group('DownloadService.effectiveDownloadPath', () {
    test('uses the configured path when one is set', () {
      expect(
        DownloadService.effectiveDownloadPath(
          configuredPath: '/data/tools',
          defaultPath: '/home/user/Downloads',
        ),
        '/data/tools',
      );
    });

    test('falls back to the default when unset, empty, or blank', () {
      for (final configured in <String?>[null, '', '   ']) {
        expect(
          DownloadService.effectiveDownloadPath(
            configuredPath: configured,
            defaultPath: '/home/user/Downloads',
          ),
          '/home/user/Downloads',
          reason: '$configured',
        );
      }
    });
  });

  group('DownloadService.isUrlAllowed', () {
    test('HTTPS-only mode allows https and refuses everything else', () {
      expect(
        DownloadService.isUrlAllowed(
          'https://example.com/tool.zip',
          httpsOnly: true,
        ),
        isTrue,
      );
      expect(
        DownloadService.isUrlAllowed(
          'http://example.com/tool.zip',
          httpsOnly: true,
        ),
        isFalse,
      );
      expect(
        DownloadService.isUrlAllowed(
          'ftp://example.com/tool.zip',
          httpsOnly: true,
        ),
        isFalse,
      );
    });

    test('with HTTPS-only off, any scheme is allowed', () {
      expect(
        DownloadService.isUrlAllowed(
          'http://example.com/tool.zip',
          httpsOnly: false,
        ),
        isTrue,
      );
    });
  });

  group('DownloadService.throttleDelay', () {
    test('no limit (or a non-positive one) never waits', () {
      expect(
        DownloadService.throttleDelay(
          bytesDownloaded: 100000,
          limitBytesPerSecond: null,
          elapsed: Duration.zero,
        ),
        Duration.zero,
      );
      expect(
        DownloadService.throttleDelay(
          bytesDownloaded: 100000,
          limitBytesPerSecond: 0,
          elapsed: Duration.zero,
        ),
        Duration.zero,
      );
    });

    test('waits out the remainder of the byte budget', () {
      // 2000 bytes at 1000 B/s earns a 2000 ms budget; after 500 ms
      // elapsed, 1500 ms of waiting is due.
      expect(
        DownloadService.throttleDelay(
          bytesDownloaded: 2000,
          limitBytesPerSecond: 1000,
          elapsed: const Duration(milliseconds: 500),
        ),
        const Duration(milliseconds: 1500),
      );
    });

    test('no wait once the transfer is at or under the limit', () {
      expect(
        DownloadService.throttleDelay(
          bytesDownloaded: 500,
          limitBytesPerSecond: 1000,
          elapsed: const Duration(milliseconds: 500),
        ),
        Duration.zero,
      );
      expect(
        DownloadService.throttleDelay(
          bytesDownloaded: 500,
          limitBytesPerSecond: 1000,
          elapsed: const Duration(milliseconds: 900),
        ),
        Duration.zero,
      );
    });
  });
}
