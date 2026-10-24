import 'package:flutter_test/flutter_test.dart';
import 'package:xtoolbox/services/distro_resolver.dart';

/// The distro ISO entries ship as %TOKEN% templates; DistroResolver
/// turns them into current, verified URLs against each distro's own
/// listing/API. These tests drive it with fake pages — no network.
void main() {
  DistroResolver resolverWith(Map<String, String> pages, Set<String> live) {
    return DistroResolver(
      fetchPage: (url) async => pages[url],
      urlExists: (url) async => live.contains(url),
    );
  }

  group('needsResolution', () {
    test('flags templates and bare tokens, not ordinary URLs', () {
      expect(
        DistroResolver.needsResolution(
          'https://mirror.example/iso/%MINTVERSION%/x.iso',
        ),
        isTrue,
      );
      expect(DistroResolver.needsResolution('%POP%,nvidia'), isTrue);
      expect(
        DistroResolver.needsResolution('https://example.com/tool.zip'),
        isFalse,
      );
      // A percent-escaped space is not a token.
      expect(
        DistroResolver.needsResolution(
          'https://example.com/Hone%20-%20Installer.exe',
        ),
        isFalse,
      );
    });
  });

  group('version helpers', () {
    test('compareVersions orders numerically, missing parts are zero', () {
      expect(DistroResolver.compareVersions('22.3', '22'), greaterThan(0));
      expect(DistroResolver.compareVersions('21.3', '22'), lessThan(0));
      expect(DistroResolver.compareVersions('22.1', '22.1'), 0);
    });

    test('extractVersions finds version dirs, newest first', () {
      const html =
          '<a href="21/">21</a><a href="22.1/">x</a>'
          '<a href="22.3/">x</a><a href="22/">x</a><a href="../">up</a>';
      expect(DistroResolver.extractVersions(html), [
        '22.3',
        '22.1',
        '22',
        '21',
      ]);
    });

    test('extractEndeavourFiles sorts by the embedded date', () {
      const html =
          '<a href="EndeavourOS_Mercury-2025.03.19.iso">a</a>'
          '<a href="EndeavourOS_Titan-Nova-2026.08.15.iso">b</a>';
      expect(DistroResolver.extractEndeavourFiles(html), [
        'EndeavourOS_Titan-Nova-2026.08.15.iso',
        'EndeavourOS_Mercury-2025.03.19.iso',
      ]);
    });
  });

  group('resolve', () {
    test('passes non-template URLs through unchanged', () async {
      final r = resolverWith({}, {});
      expect(
        await r.resolve('https://example.com/a.iso'),
        'https://example.com/a.iso',
      );
    });

    test('Mint: fills the newest version whose file exists', () async {
      const listing = 'https://mirror.example/linuxmint/iso/stable/';
      final r = resolverWith(
        {listing: '<a href="22.2/">a</a><a href="22.3/">b</a>'},
        {
          'https://mirror.example/linuxmint/iso/stable/22.2/linuxmint-22.2-cinnamon-64bit.iso',
        },
      );
      // 22.3's file does not exist, so it steps down to 22.2.
      expect(
        await r.resolve(
          'https://mirror.example/linuxmint/iso/stable/%MINTVERSION%/linuxmint-%MINTVERSION%-cinnamon-64bit.iso',
        ),
        'https://mirror.example/linuxmint/iso/stable/22.2/linuxmint-22.2-cinnamon-64bit.iso',
      );
    });

    test('Pop: returns the API URL for the channel; raspi unresolved', () async {
      final r = resolverWith(
        {
          'https://api.pop-os.org/builds/24.04/nvidia':
              '{"url": "https://iso.pop-os.org/24.04/amd64/nvidia/20/pop.iso"}',
        },
        {'https://iso.pop-os.org/24.04/amd64/nvidia/20/pop.iso'},
      );
      expect(
        await r.resolve('%POP%,nvidia'),
        'https://iso.pop-os.org/24.04/amd64/nvidia/20/pop.iso',
      );
      expect(await r.resolve('%POP%,raspi'), isNull);
    });

    test('Solus: builds the dated directory URL for the edition', () async {
      final r = resolverWith(
        {
          'https://downloads.getsol.us/isos/':
              '<a href="./2025-01-26/">a</a><a href="./2025-11-29/">b</a>',
        },
        {
          'https://downloads.getsol.us/isos/2025-11-29/Solus-Plasma-Release-2025-11-29.iso',
        },
      );
      expect(
        await r.resolve('%SOLUS%,Plasma'),
        'https://downloads.getsol.us/isos/2025-11-29/Solus-Plasma-Release-2025-11-29.iso',
      );
    });

    test(
      'Debian: picks the newest netinst from the current directory',
      () async {
        const dir =
            'https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/';
        final r = resolverWith(
          {
            dir:
                '<a href="debian-13.5.0-amd64-netinst.iso">a</a>'
                '<a href="debian-13.7.0-amd64-netinst.iso">b</a>',
          },
          {'${dir}debian-13.7.0-amd64-netinst.iso'},
        );
        expect(
          await r.resolve('%DEBIAN%'),
          '${dir}debian-13.7.0-amd64-netinst.iso',
        );
      },
    );

    test('unknown tokens and dead sources resolve to null', () async {
      final r = resolverWith({}, {});
      expect(await r.resolve('%NOSUCHTOKEN%'), isNull);
      expect(
        await r.resolve(
          'https://mirror.example/iso/%MINTVERSION%/linuxmint-%MINTVERSION%-cinnamon-64bit.iso',
        ),
        isNull,
      );
    });
  });
}
