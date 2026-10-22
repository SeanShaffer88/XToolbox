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

  _downloadHelpersTests();
}

void _downloadHelpersTests() {
  group('DownloadService.sanitizeFilename', () {
    test('keeps ordinary file names', () {
      expect(
        DownloadService.sanitizeFilename('CleanmgrPlus.zip'),
        'CleanmgrPlus.zip',
      );
    });

    test('strips paths and query strings', () {
      expect(
        DownloadService.sanitizeFilename('../../Windows/tool.exe?download=1'),
        'tool.exe',
      );
      expect(
        DownloadService.sanitizeFilename(r'C:\Temp\setup.exe'),
        'setup.exe',
      );
    });

    test('replaces characters Windows cannot store', () {
      expect(
        DownloadService.sanitizeFilename('bad:name*.exe'),
        'bad_name_.exe',
      );
    });

    test('falls back for empty and reserved names', () {
      expect(DownloadService.sanitizeFilename(''), 'download');
      expect(DownloadService.sanitizeFilename('..'), 'download');
      expect(DownloadService.sanitizeFilename('CON'), '_CON');
      expect(DownloadService.sanitizeFilename('lpt1.txt'), '_lpt1.txt');
      expect(DownloadService.sanitizeFilename('name. '), 'name');
    });
  });

  group('DownloadService.resolveExtractedPath', () {
    test('resolves a file inside the extraction folder', () {
      expect(
        DownloadService.resolveExtractedPath(
          '/home/user/Downloads/GHelper',
          'GHelper.exe',
        ),
        '/home/user/Downloads/GHelper/GHelper.exe',
      );
    });

    test('handles Windows separators and trailing slashes', () {
      expect(
        DownloadService.resolveExtractedPath(
          r'C:\Users\me\Downloads\Tool\',
          r'bin\Tool.exe',
        ),
        'C:/Users/me/Downloads/Tool/bin/Tool.exe',
      );
    });

    test('refuses to escape the extraction folder', () {
      expect(
        () => DownloadService.resolveExtractedPath('/tmp/tool', '../evil.exe'),
        throwsArgumentError,
      );
    });
  });

  group('DownloadService.supportsAutomaticExtraction', () {
    test('accepts zip and tar archives', () {
      for (final name in [
        'tool.zip',
        'tool.ZIP',
        'tool.tar',
        'tool.tar.gz',
        'tool.tgz',
      ]) {
        expect(
          DownloadService.supportsAutomaticExtraction(name),
          isTrue,
          reason: name,
        );
      }
    });

    test('rejects archives that need an external tool', () {
      for (final name in ['image.7z', 'setup.exe', 'notes.txt']) {
        expect(
          DownloadService.supportsAutomaticExtraction(name),
          isFalse,
          reason: name,
        );
      }
    });
  });
}
