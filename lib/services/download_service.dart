import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../utils/archive_extraction.dart';
import 'settings_service.dart';
import 'toast_notification_service.dart';

class DownloadService {
  final ToastNotificationService _toastService;
  final SettingsService? _settingsService;

  DownloadService(this._toastService, [this._settingsService]);

  /// The directory downloads are written to: the user's configured
  /// download path when one is set, otherwise [defaultPath] (the system
  /// Downloads folder).
  @visibleForTesting
  static String effectiveDownloadPath({
    required String? configuredPath,
    required String defaultPath,
  }) {
    final trimmed = configuredPath?.trim();
    return (trimmed == null || trimmed.isEmpty) ? defaultPath : trimmed;
  }

  /// Whether [url] may be downloaded under the HTTPS-only setting.
  /// Shared by DownloadService and PlaybookService so every download
  /// the app makes follows the same rule.
  static bool isUrlAllowed(String url, {required bool httpsOnly}) {
    if (!httpsOnly) return true;
    return Uri.tryParse(url)?.scheme.toLowerCase() == 'https';
  }

  /// How many times one [downloadFile] call attempts the transfer
  /// before giving up.
  static const int maxDownloadAttempts = 3;

  /// The Range header that resumes a partial download of
  /// [existingBytes] bytes (empty when starting fresh).
  @visibleForTesting
  static Map<String, String> rangeHeaders(int existingBytes) =>
      existingBytes > 0 ? {'Range': 'bytes=$existingBytes-'} : {};

  /// Whether a response continues an existing partial file (HTTP 206)
  /// rather than starting over.
  @visibleForTesting
  static bool shouldAppend({
    required int statusCode,
    required int existingBytes,
  }) => statusCode == 206 && existingBytes > 0;

  /// The total resource size from a `Content-Range` header
  /// (`bytes 4000-9999/10000` → 10000), or null when unavailable.
  @visibleForTesting
  static int? totalFromContentRange(String? header) {
    if (header == null) return null;
    final slash = header.lastIndexOf('/');
    if (slash < 0) return null;
    final total = int.tryParse(header.substring(slash + 1).trim());
    return (total != null && total > 0) ? total : null;
  }

  /// Downloads [url] to [outputFile] with resume-and-retry: a dropped
  /// connection no longer discards the bytes already fetched. Each
  /// attempt resumes from the partial file when the server honors
  /// Range requests. HTTP error statuses are thrown immediately —
  /// they are answers, not glitches. Throws the last error when every
  /// attempt fails; the caller still removes the partial file, so a
  /// failed download never leaves a truncated installer behind.
  Future<void> _downloadWithResume({
    required String url,
    required File outputFile,
    required String toastId,
    required int? limitBytesPerSecond,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxDownloadAttempts; attempt++) {
      try {
        await _downloadAttempt(
          url: url,
          outputFile: outputFile,
          toastId: toastId,
          limitBytesPerSecond: limitBytesPerSecond,
        );
        return;
      } on _HttpStatusError {
        rethrow;
      } catch (e) {
        lastError = e;
        if (attempt < maxDownloadAttempts) {
          _toastService.updateNotification(
            id: toastId,
            message:
                'Connection interrupted — retrying (attempt '
                '${attempt + 1} of $maxDownloadAttempts)...',
            progress: null,
          );
          await Future.delayed(Duration(seconds: attempt));
        }
      }
    }
    throw lastError ?? Exception('Download failed');
  }

  /// One transfer attempt: streams the response to [outputFile],
  /// appending when resuming a partial file.
  Future<void> _downloadAttempt({
    required String url,
    required File outputFile,
    required String toastId,
    required int? limitBytesPerSecond,
  }) async {
    var existingBytes = await outputFile.exists()
        ? await outputFile.length()
        : 0;

    final request = http.Request('GET', Uri.parse(url));

    // No manual Accept-Encoding: the HTTP client already negotiates and
    // decodes compression. Asking for Brotli here would save compressed
    // bytes to disk, corrupting installers and archives.
    request.headers.addAll({
      'User-Agent':
          'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, '
          'like Gecko) Chrome/131.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Upgrade-Insecure-Requests': '1',
      ...rangeHeaders(existingBytes),
    });

    final response = await request.send();

    if (response.statusCode == 416 && existingBytes > 0) {
      // The resume offset is past the end of the resource: the
      // partial file is unusable. Drop it and let the retry start
      // fresh.
      await outputFile.delete();
      throw const _RetryableDownloadError(
        'Server rejected the resume offset; restarting the download',
      );
    }
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw _HttpStatusError(response.statusCode);
    }

    final append = shouldAppend(
      statusCode: response.statusCode,
      existingBytes: existingBytes,
    );
    if (!append) existingBytes = 0;

    final totalBytes = response.statusCode == 206
        ? totalFromContentRange(response.headers['content-range']) ??
              existingBytes + (response.contentLength ?? 0)
        : (response.contentLength ?? 0);

    var bytesDownloaded = existingBytes;
    final stopwatch = Stopwatch()..start();
    final sink = outputFile.openWrite(
      mode: append ? FileMode.append : FileMode.write,
    );

    try {
      await for (final chunk in response.stream) {
        bytesDownloaded += chunk.length;
        sink.add(chunk);

        final delay = throttleDelay(
          bytesDownloaded: bytesDownloaded,
          limitBytesPerSecond: limitBytesPerSecond,
          elapsed: stopwatch.elapsed,
        );
        if (delay > Duration.zero) {
          await Future.delayed(delay);
        }

        if (totalBytes > 0) {
          _toastService.updateNotification(
            id: toastId,
            progress: bytesDownloaded / totalBytes,
            message:
                'Downloaded ${_formatBytes(bytesDownloaded)} / '
                '${_formatBytes(totalBytes)}',
          );
        }
      }
    } finally {
      await sink.close();
    }

    // A stream can also end early without an error; with a known
    // total, that is a truncated file — fail so the retry resumes it
    // instead of the caller treating it as complete.
    if (totalBytes > 0 && bytesDownloaded < totalBytes) {
      throw _RetryableDownloadError(
        'Connection closed early at ${_formatBytes(bytesDownloaded)} '
        'of ${_formatBytes(totalBytes)}',
      );
    }
  }

  /// The SHA-256 digest of [file], streamed so large images do not
  /// have to fit in memory.
  static Future<String> sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Whether two SHA-256 hex digests are equal, ignoring case and
  /// surrounding whitespace.
  @visibleForTesting
  static bool checksumMatches(String expected, String actual) {
    return expected.trim().toLowerCase() == actual.trim().toLowerCase();
  }

  /// How long to pause after [bytesDownloaded] bytes so the average
  /// transfer rate stays at or below [limitBytesPerSecond]. Zero when
  /// no wait is due, when there is no limit, or when the transfer is
  /// already at or under the limit.
  @visibleForTesting
  static Duration throttleDelay({
    required int bytesDownloaded,
    required int? limitBytesPerSecond,
    required Duration elapsed,
  }) {
    if (limitBytesPerSecond == null || limitBytesPerSecond <= 0) {
      return Duration.zero;
    }
    final budgetMs = bytesDownloaded * 1000 ~/ limitBytesPerSecond;
    final waitMs = budgetMs - elapsed.inMilliseconds;
    return waitMs > 0 ? Duration(milliseconds: waitMs) : Duration.zero;
  }

  /// Joins [relativePath] onto [extractedDirectory].
  ///
  /// Catalog entries point at a file inside an archive. The archive itself
  /// must always be extracted into the download folder; [relativePath] only
  /// selects a file inside it. Throws [ArgumentError] if the path tries to
  /// leave the extraction directory.
  static String resolveExtractedPath(
    String extractedDirectory,
    String relativePath,
  ) {
    final base = extractedDirectory
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    final relative = relativePath
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'^/+'), '');
    if (relative.isEmpty) return base;
    if (relative.split('/').contains('..')) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'must stay inside the extracted folder',
      );
    }
    return '$base/$relative';
  }

  /// Turns a remote file name into a safe local file name.
  @visibleForTesting
  static String sanitizeFilename(String name) {
    final withoutQuery = name.split('?').first.split('#').first;
    final baseName = withoutQuery.replaceAll('\\', '/').split('/').last.trim();
    var cleaned = baseName.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    cleaned = cleaned.replaceAll(RegExp(r'[. ]+$'), '');
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
      return 'download';
    }
    final reserved = RegExp(
      r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$',
      caseSensitive: false,
    );
    return reserved.hasMatch(cleaned) ? '_$cleaned' : cleaned;
  }

  /// Whether the archive at [path] can be extracted by this app.
  @visibleForTesting
  static bool supportsAutomaticExtraction(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.zip') ||
        lower.endsWith('.tar.gz') ||
        lower.endsWith('.tgz') ||
        lower.endsWith('.tar');
  }

  Future<String?> downloadFile({
    required String url,
    required String displayName,
    String? filename,
    bool needsExtraction = false,
    bool autoComplete = true,
    String? expectedSha256,
  }) async {
    String? toastId;
    File? outputFile;
    var downloadCompleted = false;

    try {
      toastId = _toastService.addNotification(
        title: 'Downloading $displayName',
        message: 'Preparing download...',
        status: ToastStatus.pending,
      );

      // HTTPS-only mode (Settings): refuse non-HTTPS sources outright.
      if (!isUrlAllowed(url, httpsOnly: _settingsService?.httpsOnly ?? false)) {
        throw Exception(
          'HTTPS-only mode is on, but this download is not HTTPS',
        );
      }

      // Downloads directory: the configured download path (Settings)
      // when one is set, otherwise the system Downloads folder. The
      // system folder is only queried when needed: resolving it needs
      // a platform plugin, a configured path does not.
      final configuredPath = _settingsService?.downloadPath;
      final hasConfiguredPath =
          configuredPath != null && configuredPath.trim().isNotEmpty;
      final systemDownloadsDir = hasConfiguredPath
          ? null
          : await getDownloadsDirectory();
      if (!hasConfiguredPath && systemDownloadsDir == null) {
        throw Exception('Could not access downloads directory');
      }
      final downloadsDir = Directory(
        effectiveDownloadPath(
          configuredPath: configuredPath,
          defaultPath: systemDownloadsDir?.path ?? configuredPath!.trim(),
        ),
      );
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      // Determine filename
      final fileName = sanitizeFilename(filename ?? url.split('/').last);
      final filePath = '${downloadsDir.path}/$fileName';

      _toastService.updateNotification(
        id: toastId,
        status: ToastStatus.inProgress,
        message: 'Downloading...',
        progress: 0.0,
      );

      outputFile = File(filePath);

      // Bandwidth limit (Settings), stored as KB/s; 1 KB = 1024 bytes.
      final limitKbps = _settingsService?.bandwidthLimit;
      final limitBytesPerSecond = (limitKbps != null && limitKbps > 0)
          ? limitKbps * 1024
          : null;

      await _downloadWithResume(
        url: url,
        outputFile: outputFile,
        toastId: toastId,
        limitBytesPerSecond: limitBytesPerSecond,
      );
      downloadCompleted = true;

      // Integrity check: when the catalog pins a SHA-256 for this
      // download, the file must match it before anything extracts or
      // launches it. A mismatch means the file is not what the catalog
      // entry promises — delete it and fail loudly.
      if (expectedSha256 != null) {
        _toastService.updateNotification(
          id: toastId,
          message: 'Verifying checksum...',
          progress: null,
        );
        final actualSha256 = await sha256OfFile(outputFile);
        if (!checksumMatches(expectedSha256, actualSha256)) {
          await outputFile.delete();
          throw Exception(
            'Checksum mismatch for $fileName — the download does not '
            'match the catalog\'s SHA-256 and was deleted. Expected '
            '$expectedSha256, got $actualSha256.',
          );
        }
      }

      if (needsExtraction) {
        if (!supportsAutomaticExtraction(filePath)) {
          throw Exception(
            '$fileName cannot be extracted automatically. '
            'ZIP and TAR archives are supported; extract this file '
            'manually with 7-Zip.',
          );
        }

        _toastService.updateNotification(
          id: toastId,
          message: 'Extracting...',
          progress: null,
        );

        final extractDir =
            '${downloadsDir.path}/'
            '${fileName.replaceAll(RegExp(r'\.(zip|tar\.gz|tgz|tar)$'), '')}';
        await _extractArchive(filePath, extractDir);

        if (autoComplete) {
          _toastService.updateNotification(
            id: toastId,
            status: ToastStatus.success,
            message: 'Extracted to $extractDir',
          );
        } else {
          _toastService.removeNotification(toastId);
        }

        return extractDir;
      } else {
        if (autoComplete) {
          _toastService.updateNotification(
            id: toastId,
            status: ToastStatus.success,
            message: 'Saved to $filePath',
          );
        } else {
          _toastService.removeNotification(toastId);
        }

        return filePath;
      }
    } catch (e) {
      // A failed download must not leave a truncated installer behind.
      if (outputFile != null && !downloadCompleted) {
        try {
          if (await outputFile.exists()) {
            await outputFile.delete();
          }
        } on FileSystemException catch (error) {
          debugPrint('Could not remove partial download: $error');
        }
      }

      final details = e.toString().replaceFirst('Exception: ', '');
      if (toastId != null) {
        _toastService.updateNotification(
          id: toastId,
          status: ToastStatus.error,
          message: 'Failed: $details',
        );
      }

      if (kDebugMode) {
        print('Download error: $e');
      }

      return null;
    }
  }

  Future<void> _extractArchive(String archivePath, String extractPath) async {
    final file = File(archivePath);
    final bytes = await file.readAsBytes();

    final extractDir = Directory(extractPath);
    if (!await extractDir.exists()) {
      await extractDir.create(recursive: true);
    }

    final lower = archivePath.toLowerCase();
    if (lower.endsWith('.zip')) {
      await ArchiveExtraction.extract(
        ZipDecoder().decodeBytes(bytes),
        extractPath,
      );
    } else if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
      final gzipBytes = GZipDecoder().decodeBytes(bytes);
      final archive = TarDecoder().decodeBytes(gzipBytes);
      await ArchiveExtraction.extract(archive, extractPath);
    } else if (lower.endsWith('.tar')) {
      final archive = TarDecoder().decodeBytes(bytes);
      await ArchiveExtraction.extract(archive, extractPath);
    } else {
      throw Exception(
        'Unsupported archive type. ZIP and TAR archives are supported.',
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// An HTTP error status from the download server. Not retried: the
/// server answered, and the answer will not change by asking again.
class _HttpStatusError implements Exception {
  final int statusCode;
  const _HttpStatusError(this.statusCode);

  @override
  String toString() => 'Failed to download: HTTP $statusCode';
}

/// A transfer failure that a resumed attempt may be able to finish.
class _RetryableDownloadError implements Exception {
  final String message;
  const _RetryableDownloadError(this.message);

  @override
  String toString() => message;
}
