# XToolBox
A toolbox full of Windows 10/11 utilities: run AME Wizard playbooks (AtlasOS, ReviOS, AME), install curated software, clean up your system, and check system info — all from one app.  
Originally made by [Nyx](https://nyx.meowery.eu).

> [!NOTE]
> **XToolBox lives on.** The original project reached end-of-life in May 2026 when its author moved to Linux full-time. This fork, maintained by [SeanShaffer88](https://github.com/SeanShaffer88), continues development: updates, fixes, and new tools are published here. The in-app update checker points at this repository, so releases from here reach you automatically. Huge thanks to Nyx and all past contributors for four years of work.

## 🚀 Quickstart
>[!TIP]
> [You can click here to download the latest XTBox zip.](https://github.com/SeanShaffer88/XToolbox/releases/latest/download/XTBox.zip)  
1. Go to the releases tab.
2. Click on the `XTBox.zip` file attached to the latest release.
3. Unpack the folder and run the `xtoolbox.exe` file.
4. You now have XToolBox running on your computer, pretty cool!

## 📑 Important
1. This program runs on Windows 10 (tested on 22H2 and LTSC) and Windows 11 (tested on 25H2 and LTSC). Older versions, like Windows 7 or Windows 8.1, aren't supported. The source also builds on Linux, but everything in the toolbox targets Windows, so that's where it's useful.
2. If this program gets flagged as malware, it's a false positive, here's why:
    1. It downloads and executes files — that's how the installers and playbooks work.
    2. It's a compiled Dart (Flutter) binary, which some scanners distrust.

## 📸 Screenshots
<details>
    <summary>Click to reveal!</summary>
    <img width="1379" height="757" alt="image" src="https://github.com/user-attachments/assets/6cc574db-2d3a-4145-be57-fb6a09c0adb3" />
    <img width="1379" height="757" alt="image" src="https://github.com/user-attachments/assets/3913ce8b-0dc6-481c-9dc3-e4514fb9668e" />
    <img width="1379" height="757" alt="image" src="https://github.com/user-attachments/assets/807706c2-03d4-424f-a5c2-e932bfc4ec87" />
</details>

## 🖊️ Reviews
*nice toolbox*

- `jonathah#1221`

------

*Thanks bro, very useful softwhere*

- `@sennv`

------

*After using XTB my computer started having an erection*

- `@genc1337`

------

*now I get more fps in minecraft lessgooo*

- `@arxify`

------

*xtooblox made me pregnant*

- `@jamieroot`

## ⚒️ Building
- The building process requires [Flutter](https://docs.flutter.dev/get-started/quick) and [Git](https://git-scm.com/downloads)
- Building for Windows also requires Visual Studio 2022 with the **Desktop development with C++** workload (a Flutter requirement)
```
git clone https://github.com/SeanShaffer88/XToolbox
cd XToolbox
flutter pub get
flutter build windows --release
cd build/windows/x64/runner/Release
```
Run `xtoolbox.exe` from that folder to test your build.
>[!NOTE]
> You have to zip up the entire Release folder, not only the `xtoolbox.exe` file!

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, checks, and how to add tools to the catalog.

## 🔗 Links
<a href="https://star-history.com/#SeanShaffer88/xtoolbox&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=SeanShaffer88/xtoolbox&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=SeanShaffer88/xtoolbox&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=SeanShaffer88/xtoolbox&type=Date" />
 </picture>
</a>

## ✍️ Keywords, pls ignore
input lag latency optimization performance gaming overclock oc windows ping debloat milliseconds fps boost increase decrease guide mouse tweak tweaks bios uefi pc overclocking 7 8.1 10 11 w7 w8 . w10 w11 linux game gamer optimizations frametime frametimes 0. 1080p 720p reaction time delay delayed bloat bloated debloated steam battle origin epic games quake counter strike royale br intel nvidia pascal turing ampere reflex amd ati ryzen r9 r7 r5 r3 radeon rdna core i9 i7 i5 i3 memory ram gpu ssd nvme psu power supply laptop how to screenshot on window download release date andersen blinds for pella media creation tool fast chris titus tech optimize debloater github reddit iso beebom jayztwocents script best does not work defender dell dism deutsch what mean 
