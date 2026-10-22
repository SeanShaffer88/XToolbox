import 'package:flutter_test/flutter_test.dart';
import 'package:xtoolbox/services/playbook_service.dart';

/// HTTPS-only mode must hold for playbook downloads (TrustedUninstaller
/// CLI, playbook files, 7zr.exe), not just catalog installs.
void main() {
  group('PlaybookService.ensureDownloadAllowed', () {
    test('refuses non-HTTPS downloads when HTTPS-only is on', () {
      expect(
        () => PlaybookService.ensureDownloadAllowed(
          'http://example.com/playbook.zip',
          httpsOnly: true,
        ),
        throwsException,
      );
    });

    test('allows HTTPS downloads when HTTPS-only is on', () {
      expect(
        () => PlaybookService.ensureDownloadAllowed(
          'https://example.com/playbook.zip',
          httpsOnly: true,
        ),
        returnsNormally,
      );
    });

    test('allows any scheme when HTTPS-only is off', () {
      expect(
        () => PlaybookService.ensureDownloadAllowed(
          'http://example.com/playbook.zip',
          httpsOnly: false,
        ),
        returnsNormally,
      );
    });

    test('the built-in download URLs satisfy HTTPS-only mode', () {
      for (final url in [
        PlaybookService.cliDownloadUrl,
        PlaybookService.sevenZipDownloadUrl,
      ]) {
        expect(
          () => PlaybookService.ensureDownloadAllowed(url, httpsOnly: true),
          returnsNormally,
          reason: url,
        );
      }
    });
  });
}
