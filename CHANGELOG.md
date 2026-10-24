# Changelog

All notable changes to XToolBox are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [5.3.3] - 2026-10-23

### Added

- **Checksum verification for pinned downloads.** Install methods can
  now carry a `sha256`; when one is present, the downloaded file is
  hashed and compared before it is extracted or launched. A mismatch
  deletes the file and fails the install with the expected and actual
  hashes shown. All 15 version-pinned GitHub-release downloads in the
  catalog are pinned (hashes taken from the publishers' release
  records or computed from the release files themselves). Downloads
  without a pinned hash — including every `latest` URL, whose content
  changes between releases — behave as before.

## [5.3.2] - 2026-10-23

### Fixed

- **Distro ISO downloads work again.** 18 catalog entries (Linux Mint,
  Ubuntu and flavors, Pop!_OS, Artix, Solus, Debian, EndeavourOS,
  CachyOS) shipped with `%TOKEN%` placeholder URLs that nothing ever
  resolved, so those downloads always failed. A new resolver turns
  each template into the current image URL using the distro's own
  mirror listing or build API, verifies the file exists (stepping
  down to the previous release if the newest is missing), and only
  then downloads. Data fixes riding along: the Ubuntu image is the
  standard desktop ISO (the legacy variant is discontinued), the
  Lubuntu entry points at Lubuntu images (it linked Xubuntu), the
  CachyOS Handheld entry points at the handheld image (it linked the
  desktop one), and Pop!_OS for Raspberry Pi is now a web link (it is
  no longer published as a direct image).

## [5.3.1] - 2026-10-22

### Fixed

- HTTPS-only mode now covers playbook downloads too. The setting
  previously applied only to catalog installs; the TrustedUninstaller
  CLI, playbook files, and the 7-Zip helper were fetched without the
  check. Every download the app makes now honors the setting. (The
  download-path and bandwidth-limit settings still apply to catalog
  downloads only: playbook files are internal staging data rather
  than user downloads, and those transfers are not streamed.)

## [5.3.0] - 2026-10-22

Revival completion: the cleanup screen is finished, portable installs work,
and downloads are safer.

### Added

- **Cleanup now does real work for every option it lists.** Temporary
  files, old downloads, the Recycle Bin, browser caches, setup/update
  logs, thumbnail cache and prefetch files are measured and removed with
  per-item results. Files that are in use are counted as skipped instead
  of being reported as freed. Options that need administrator rights ask
  for elevation before anything runs.
- **Old Downloads instead of the whole folder.** The cleanup option now
  only removes files that have not changed in 30 days. A cleanup tool
  should not silently wipe recent downloads.
- A Theme selector with System, Light and Dark. Previously the dark-mode
  switch could not return to following the system theme.
- Cleanup, download-path and catalog extraction tests, and a Linux
  release build in CI. The README's Linux-build claim is now checked on
  every pull request.

### Fixed

- **Portable ZIP installs.** `executable_path` was passed to the download
  service as the extraction destination, so entries such as G-Helper,
  TranslucentTB, LibreHardwareMonitor, Cleanmgr+ and Winaero Tweaker
  extracted into a folder named after the executable and then failed to
  launch. Archives now extract into the download folder and the app
  resolves and verifies the executable inside it. Missing files and
  unsupported archive types produce a clear error with the extraction
  path.
- **Download integrity and cleanup.** Failed downloads no longer leave a
  truncated installer behind. Remote file names are sanitized before
  they become local paths. The explicit `Accept-Encoding: br` header was
  removed: the HTTP client already negotiates and decodes compression,
  and asking for Brotli could write compressed bytes to disk.
- Playbook extraction now uses a platform-appropriate 7-Zip binary, and
  playbooks without a `playbook.conf` can be run after initialization.
- Toast notification ids are unique, so two notifications created in the
  same millisecond no longer overwrite each other.
- The package details dialog uses the full icon map and hides the
  homepage button when an entry has no homepage.

### Changed

- Window metadata and titles use **XToolBox** instead of the lowercase
  `xtoolbox`.
- `linux/` and `windows/` are no longer gitignored; generated plugin and
  build output is ignored inside those folders instead.
- Catalog text cleanup: professional descriptions for the Windows
  entries, fixed homepages and names, and the Windows 7/8.1 `.7z` images
  are browser downloads because the app only extracts ZIP and TAR
  archives.
- The codebase is formatted with the current Dart formatter.

### Verification

- Verified by CI: `dart format`, `flutter analyze`, `flutter test`, and a
  Linux release build.
- The Windows release is built by CI from the tagged commit. Interactive
  Windows runtime behavior is not re-validated by CI, so treat the
  binary as **partially verified** until you have exercised the affected
  screens on Windows.

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
