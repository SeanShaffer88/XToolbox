import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xtoolbox/models/asset.dart';
import 'package:xtoolbox/services/download_service.dart';

/// Guards the catalog (assets/asset_list.json) against silent data loss.
///
/// The app parses every entry through [Asset.fromJson] at startup; a
/// malformed entry used to fail the whole load (or an entry could be
/// dropped) without anyone noticing until a user reported a missing tool.
/// If this test fails, the catalog change that broke it must be fixed —
/// do not weaken the test to make it pass.
void main() {
  test('every catalog entry parses through the Asset model', () {
    final raw = File('assets/asset_list.json').readAsStringSync();
    final decoded = jsonDecode(raw) as List<dynamic>;

    final assets = decoded
        .map((entry) => Asset.fromJson(entry as Map<String, dynamic>))
        .toList();

    // Nothing was dropped or merged during parsing.
    expect(assets.length, decoded.length);

    // Ids are the catalog's primary key — they must be unique.
    final ids = assets.map((asset) => asset.id).toList();
    expect(
      ids.toSet().length,
      ids.length,
      reason: 'catalog ids must be unique',
    );

    for (final asset in assets) {
      expect(asset.id, isNotEmpty);
      expect(asset.name, isNotEmpty, reason: '${asset.id} has no name');
      expect(
        asset.installMethods,
        isNotEmpty,
        reason: '${asset.id} has no install methods',
      );
      for (final method in asset.installMethods) {
        switch (method.type) {
          case InstallType.directDownload:
            expect(
              method.url,
              isNotNull,
              reason: '${asset.id}: direct_download needs a url',
            );
            expect(
              method.filename,
              isNotNull,
              reason: '${asset.id}: direct_download needs a filename',
            );
            if (method.needsExtraction) {
              expect(
                DownloadService.supportsAutomaticExtraction(
                  Uri.parse(method.url!).path,
                ),
                isTrue,
                reason:
                    '${asset.id}: needs_extraction requires a ZIP or TAR '
                    'archive',
              );
            }
            if (method.sha256 != null) {
              expect(
                method.sha256,
                matches(RegExp(r'^[0-9a-f]{64}$')),
                reason:
                    '${asset.id}: sha256 must be 64 lowercase hex '
                    'characters',
              );
            }
          case InstallType.winget:
          case InstallType.chocolatey:
          case InstallType.scoop:
            expect(
              method.packageId,
              isNotNull,
              reason: '${asset.id}: ${method.type} needs a package_id',
            );
          case InstallType.microsoftStore:
            expect(
              method.storeId,
              isNotNull,
              reason: '${asset.id}: microsoft_store needs a store_id',
            );
          case InstallType.powershell:
            expect(
              method.command,
              isNotNull,
              reason: '${asset.id}: powershell needs a command',
            );
          case InstallType.webLink:
            expect(
              method.url,
              isNotNull,
              reason: '${asset.id}: web_link needs a url',
            );
        }
      }
    }
  });
}
