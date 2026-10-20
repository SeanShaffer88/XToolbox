# Contributing to XToolBox

Thanks for helping keep XToolBox alive. This guide covers setup, the checks
your change has to pass, and how to add tools to the catalog.

By contributing, you agree that your contributions are licensed under the
project's license, GPL-2.0 (see `LICENSE`).

## Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/quick) (stable channel;
  the project requires Dart SDK `^3.10.1`, see `pubspec.yaml`)
- [Git](https://git-scm.com/downloads)
- For Windows builds: Visual Studio 2022 with the **Desktop development
  with C++** workload (a Flutter requirement). The app also builds and
  runs on Linux, which is handy for a quick check.

## Setup and running

```
git clone https://github.com/SeanShaffer88/XToolbox
cd XToolbox
flutter pub get
flutter run -d windows      # or: flutter run -d linux
```

Release build:

```
flutter build windows --release
# output: build/windows/x64/runner/Release — run xtoolbox.exe from there
```

## Checks

Run these before opening a pull request. The CI workflow
(`.github/workflows/ci.yml`) runs the same gates on every push and pull
request:

```
dart format lib/                       # the codebase is dart-format clean
flutter analyze --no-fatal-infos       # errors and warnings must be zero
flutter build windows --release        # or the linux build, if that's your OS
```

`--no-fatal-infos` exists because the codebase carries a small number of
pre-existing info-level lints (mostly deprecated Radio APIs in the playbook
setup screen). New code must not add errors, warnings, or new infos.

## Adding a tool to the catalog

Most contributions are catalog entries. The catalog is
`assets/asset_list.json`, a JSON array loaded at startup by
`lib/provider/asset_provider.dart` and parsed by `lib/models/asset.dart`.
Each entry looks like this:

```json
{
    "id": "pydebloatx",
    "name": "PyDebloatX",
    "description": "Python GUI for uninstalling some of the default Windows 10/11 apps.",
    "category": "tools",
    "icon": "delete_sweep",
    "author": "Teraskull",
    "homepage": "https://github.com/Teraskull/PyDebloatX",
    "install_methods": [
        {
            "type": "direct_download",
            "label": "Installer",
            "url": "https://github.com/Teraskull/PyDebloatX/releases/latest/download/PyDebloatX_setup.exe",
            "filename": "PyDebloatX_setup.exe"
        }
    ]
}
```

Rules:

- **`id`** — snake_case, unique across the file.
- **`description`** — one or two plain sentences about what the tool does.
  No marketing claims that can't be backed up.
- **`category`** — one of the categories already in use: `apps`,
  `antivirus`, `browsers`, `cleaners`, `customization`, `debloat`,
  `gaming`, `linux`, `runtimes`, `tools`, `windows`.
- **`icon`** — must be a key in `lib/utils/iconmap_util.dart` (currently:
  `delete_sweep`, `wallpaper`, `code`, `computer`, `download`, `build`,
  `cleaning_services`, `extension`, `sports_esports`, `terminal`, `stop`,
  `rocket`, `shield`, `browser`, `p2p`, `paint`, `malware`, `fragment`,
  `kit`, `linux`, `windows`, `power`, `music`, `game`, `box`, `keys`,
  `files`, `usb`, `toys`). Unknown names fall back to a generic icon.
- **`install_methods`** — one or more of:

  | `type` | Required fields | Notes |
  | --- | --- | --- |
  | `direct_download` | `url`, `filename` | Downloaded and launched. For `.zip` downloads set `needs_extraction: true` and `executable_path` to the `.exe` inside. Typical labels: `Installer`, `Portable`. |
  | `winget` | `package_id` | Label: `Install via Winget`. |
  | `microsoft_store` | `store_id` | The Store product ID (e.g. `9nghp3dx8hdx`). Label: `Install via Microsoft Store`. |
  | `powershell` | `command` | Run in PowerShell. Label: `Launch Application`. Only for commands the project itself publishes. |
  | `web_link` | `url` | Opens in the browser. Label: `Open in Browser`. |
  | `chocolatey` / `scoop` | `package_id` | Supported by the installer, no catalog entries use them yet. |

- **Pick a route that doesn't rot.** The biggest source of dead catalog
  entries is URLs with a version baked into the file name — they 404 the
  moment the project ships its next release. Prefer, in order:
  1. A `winget` package ID (confirm it exists in
     [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs)).
  2. A `releases/latest/download/<asset>` URL whose asset file name does
     **not** contain a version number.
  3. A `web_link` to the project's official download page.
- **Use the project's official distribution channel only** (its GitHub
  releases, its own site, winget, the Microsoft Store) — never a
  third-party mirror or re-upload site.
- **Check the link works** before submitting: the URL must return
  HTTP 200, and for downloads it must be the file the entry claims it is.
- Only add tools that are **currently maintained** (releases or commits
  within roughly the last year). If a tool you use gets abandoned, a PR
  removing or replacing its entry is just as valuable.

The JSON file is formatted with 4-space indentation; keep it that way so
diffs stay readable.

## Adding a playbook

Playbooks are listed in `lib/models/playbook.dart`
(`Playbook.availablePlaybooks`). Each needs a `name`, a one-line
`description`, and a `downloadUrl` for an AME Wizard `.apbx` file. If the
download is a `.zip` that contains an `.apbx`, set `isZipArchive: true`.
Playbooks are executed by the Trusted Uninstaller CLI, which the app
downloads on first use (see `lib/services/playbook_service.dart`). Prefer
`releases/latest/download/...` URLs so new playbook releases are picked up
automatically.

## Versioning and releases

- Bump `version` in `pubspec.yaml` (semantic versioning) and add an entry
  to `CHANGELOG.md` (Keep a Changelog format) with your change.
- Releases are built by CI: pushing a `vX.Y.Z` tag triggers the workflow
  (`.github/workflows/ci.yml`) to build the Windows release and publish
  a GitHub release with `XTBox.zip` attached.

## Code notes

- State lives in `lib/provider/`, long-running work in `lib/services/`,
  screens in `lib/screens/`, reusable UI in `lib/widgets/`.
- The UI is Material 3 with dynamic color; keep new screens consistent
  with the existing ones.
