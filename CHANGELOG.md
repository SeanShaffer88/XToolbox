# Changelog

All notable changes to XToolBox are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [5.2.2] - 2026-10-20

### Fixed

- The Downloads settings now actually apply. Previously the custom
  download path, HTTPS-only mode, and bandwidth limit were saved but
  never used — downloads always went to the system Downloads folder, at
  full speed, over any scheme. The download service now reads all three
  settings: files land in the configured folder, HTTPS-only mode
  refuses non-HTTPS downloads with a clear error, and the bandwidth
  limit (KB/s) throttles transfers.

## [5.2.1] - 2026-10-20

Security fix for archive extraction.

### Security

- Archive extraction now validates every entry before writing anything:
  entries that would escape the destination folder (`../`, absolute or
  Windows drive paths) and symbolic-link entries are rejected. This applies
  to catalog downloads and to the TrustedUninstaller CLI and playbook ZIP
  extraction in the playbook flow, which now share one safe extractor.

## [5.2.0] - 2026-10-20

Catalog expansion: 77 → 133 tools, broken downloads repaired, two new playbooks.

### Added

- 56 new tools in the catalog, each verified for current maintenance and a
  working install route before inclusion — including Win11Debloat, UniGetUI,
  Bulk Crap Uninstaller, Windhawk, Sophia Script, Ventoy, ShareX,
  Sandboxie-Plus, Display Driver Uninstaller, Playnite, official 7-Zip,
  BleachBit, LocalSend, RustDesk and ExplorerPatcher.
- RapidOS and AtmosphereOS AME playbooks.
- Proper support for `web_link` install methods: they now open in the browser
  (previously they were silently treated as file downloads).

### Fixed

- Internal code health: every analyzer lint resolved — the deprecated
  Radio APIs migrated to `RadioGroup`, the install-preference list to
  `onReorderItem`, and the playbook run flow now checks the right context
  after async gaps. `flutter analyze` reports no issues at all, and a
  permanent catalog parse test (`test/catalog_parse_test.dart`) means a
  malformed catalog entry fails CI instead of silently disappearing.
- 11 catalog entries with broken downloads:
  - Rufus, PowerToys, KeePassXC, PowerShell 7, Alacritty and ATLauncher now
    install via Winget instead of version-pinned URLs that had gone stale.
  - PyDebloatX (portable) and qBittorrent Enhanced Edition point at their
    current release assets again.
  - Rectify11, GDLauncher and Feather Launcher link to their current homes
    (rectify11.net, gdlauncher.com, feather.gg).

## [5.1.0] - 2026-10-20

First release of the maintained fork. XToolBox was created by Nyx and
contributors; the original project reached end-of-life in May 2026, and this
fork continues development.

### Added

- Continued-maintenance note in the README, crediting the original author.

### Removed

- The end-of-life startup screen — the app opens directly again.

### Changed

- The in-app update checker and the repository links point at this fork
  (SeanShaffer88/XToolbox), so releases published here reach existing installs.
- Removed the funding configuration that pointed at the original author's
  Sponsors page.

### Fixed

- AtlasOS playbook download: the old mirror URL was dead (404); the playbook
  is now fetched as the official `.apbx` from Atlas-OS releases.

## [5.0.1] and earlier

See the upstream repository (nyxiereal/XToolbox) and its releases for the
history up to the original project's end-of-life.
