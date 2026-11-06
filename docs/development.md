# Building macino

A native SwiftUI/AppKit menu bar utility. Source lives in `Sources/macino`; `Package.swift` opens directly in Xcode. The app uses bundled third-party native tools and offline voice models; no paid developer account, privileged daemon or root app process is required for local builds.

## Requirements

- Deployment target: macOS 14 or later. Native Liquid Glass is used on macOS 26+; earlier systems use native materials.
- Build with Xcode 26+ and its macOS SDK (the guarded Liquid Glass API still requires a current SDK), Swift 5.9+ package support. Verified with Xcode 27.0 (27A266a), Apple Swift 6.4, macOS 27.0.1 (26A434), Apple M5 MacBook Air, 24 GB memory.
- This build targets the local architecture, arm64 on the verified Mac. Intel source compatibility is intended but has not been hardware-tested. macOS 14–26 fallback behavior is not runtime-tested here.

## Open, build, and run

```sh
cd ~/dev/macino
open -a Xcode Package.swift
```

Select the macino executable scheme and My Mac, then Run. The icon appears in the menu bar; there is no Dock icon. For the complete app bundle with its icon, use the script:

```sh
cd ~/dev/macino
./Scripts/build.sh debug
open build/macino.app
```

Verified Release build and checks:

```sh
cd ~/dev/macino
./Scripts/build.sh release
build/macino.app/Contents/MacOS/macino --self-test
build/macino.app/Contents/MacOS/macino --smoke-test
codesign --verify --deep --strict build/macino.app
```

The script selects `/Applications/Xcode.app/Contents/Developer` without changing the system-wide xcode-select setting. Override `DEVELOPER_DIR` if Xcode is elsewhere. The verified bundle is `~/dev/macino/build/macino.app`. Each build replaces it, so quit the running copy before rebuilding. `--show` opens the popover at launch. Choose Quit macino from the popover's upper-right menu before relaunching.

To install for personal use, quit macino, drag `build/macino.app` into Applications in Finder, and double-click it. The app is ad hoc signed locally, not notarized for distribution. No Apple Developer membership is needed to build or run this local app. Do not run it with sudo. After installing, the first launch opens **Setup & permissions**, also available from the visible Settings button in the header. Enable **Launch macino at login** there if desired.

## DMG installation and first-run setup

Open `~/dev/macino/build/macino.dmg`, drag **macino.app** onto **Applications**, then open macino from Applications. Only the DMG needs to be distributed. There is no separate installer application or installer process. Finder handles copying and any replacement confirmation. Quit a running copy before updating. Manual drag-and-drop does not automatically launch the copied app.

Rebuild the DMG with:

```sh
cd ~/dev/macino
./Scripts/package-dmg.sh
```

Packaging uses Python 3.9+ and an isolated `.build/packaging-venv` with pinned `dmgbuild==1.6.5`, `ds_store==1.3.1` and `mac_alias==2.2.2`. The first run downloads those packaging dependencies from PyPI. Runtime has no Python dependency. The script regenerates retina installer art, builds the signed Release app, creates a compressed read-only DMG and verifies its checksum. The app is checked with strict code-signature validation inside the mounted image. Finder's hide-extension flag must not be written onto the signed app bundle because that adds forbidden FinderInfo metadata. The background is static installation artwork; the running app's glass is rendered by AppKit.

The installed app asks once whether to enable launch at login, with Enable and Not now options. Existing enabled login items do not prompt again. Its bundle is registered as a normal discoverable application while its running UI stays in the menu bar.

**Launch macino at login** is also directly visible at the top of the System tab, with live macOS status and an approval link when necessary. The header has an explicit Settings button available from every tab; the three-dot menu is no longer required. Both entry points use the same control and ServiceManagement implementation.

**Setup & permissions** provides:

- An opt-in login toggle with actual `SMAppService.mainApp` states for normally signed installed copies. The local ad-hoc build uses a per-user LaunchAgent instead: `~/Library/LaunchAgents/local.macino.login.plist`, with `RunAtLoad` and `/usr/bin/open -g` pointing to the exact app bundle. It runs once on the next graphical login, without root, KeepAlive, a paid developer membership or a privileged helper. The file is read back after saving, and the UI says **Saved for next login**, rather than claiming ServiceManagement is enabled. The switch removes only macino's managed file when turned off. Mounted disk-image copies cannot be registered; local development copies can, although Applications is the recommended stable location. If the app moves, **Use this copy for login** updates the saved path. Existing unrelated files are never overwritten. macOS can still require approval in Login Items; this path does not override a system disablement or a pending ServiceManagement approval. See [Apple's user LaunchAgent guidance](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html).
- Real read-only probes for system monitoring, process enumeration and network-counter availability. Restricted process visibility remains a macOS limitation.
- A native folder picker that checks whether the chosen folder can actually be listed. There is no public blanket TCC status check for every filesystem location, so the app does not claim that one folder grants universal access.
- A **Verify authorization…** button that invokes the native administrator dialog with a no-op command. It changes no network settings and records only a session-local successful check time. Admin authorization is not a permanent grant and later network operations may prompt again.

Basic monitoring does not require Accessibility, Screen Recording or Full Disk Access. Accessibility is optional for clipboard caret positioning/automatic paste and required for Fn event-tap shortcuts. It is not requested automatically. Setup appears automatically on the first installed launch, with login disabled until the user opts in. For development preview, run `build/macino.app/Contents/MacOS/macino --setup`.

The menu surface uses a transparent borderless NSPanel with a single glass perimeter, avoiding nested popover/glass frames. Clicking outside, pressing Escape or switching apps dismisses it. The full menu and setup surface are hosted inside Apple's `NSGlassEffectView` on macOS 26+, with `NSVisualEffectView` fallback on macOS 14–15. Cards use subtle fills so opaque material layers do not mask the root glass. macOS Reduce Transparency and the background behind a window affect the appearance. See [Apple's contentView guidance](https://developer.apple.com/documentation/appkit/nsglasseffectview/contentview) and [main-app login registration](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp).

## Features and semantics

- **System:** Mach CPU tick deltas, VM memory accounting, home-volume storage, optional GPU registry counter, Mac model/chip/OS, and thermal pressure. Four labeled gauges include units and totals. A checkbox beside each gauge pins its value next to the menu bar icon; selections persist. Selected values fill two-row columns in CPU/GPU/RAM/Disk order: two selections stack vertically, four form a 2×2 grid; one selection remains vertically centered. Percent or used capacity and units are retained. Updates every three seconds while the popover is open, or while at least one menu metric is pinned; CPU needs two samples. With no pinned metrics, polling stops when closed. With pinned metrics, closed-popover updates sample only native system metrics, never the process list or network counters. Process/network subprocesses run only on their respective visible tabs.
- **Processes:** all visible processes from `ps`, with persistent CPU/RAM/network/system sorting, ascending/descending order, a Show system checkbox (off by default), a persistent Group checkbox (on by default), horizontal RAM bars, search, application icons where available, graceful Quit/SIGTERM, and separately confirmed Force Quit/SIGKILL. CPU is the `ps` lifetime average (100% = one core), not interval CPU; memory is resident size, not Activity Monitor's memory footprint. PID, start time, and executable are revalidated before signaling. Other users, macino, PID 1 and an explicit set of critical session/desktop/security/IPC executable names are blocked. Ordinary own-user Apple applications such as Home and Calculator can be terminated even when installed under `/System`; system classification does not imply termination protection. No elevated process termination is attempted. RAM bars show RSS as a percentage of installed physical RAM. Group mode combines the outermost app bundle with its nested helpers/framework processes; standalone processes are grouped only by exact executable path. Group CPU and RSS are summed and sorting uses those totals. Shared resident pages can be counted repeatedly, so group RSS is an aggregate comparison figure, not exclusive physical memory usage or Activity Monitor footprint. Search keeps matching groups intact. Expand groups to inspect and quit individual members; the group Kill button confirms termination of the listed snapshot, revalidates every process and refuses groups containing protected members. Network totals show how many group members have visible counters. System classification means root ownership or an executable under `/System`, `/usr/libexec`, `/usr/sbin` or `/sbin`; it is separate from termination protection. Internet sorting samples nettop only while that sort is selected in Processes, joins counters by PID, and orders cumulative download + upload bytes (including local traffic), with unavailable values last in both directions. This does not imply permission or measure speed.
- **Folders:** native multi-folder picker, Finder opening, persistent native bookmarks, up/down reorder, remove and Relink. Bookmarks resolve moved folders and are renewed when stale. Unavailable folders have a clear state. This personal-use build is unsandboxed, so ordinary bookmarks are appropriate; security-scoped bookmarks would be needed for a sandboxed distribution.
- **Internet:** local path/interface status from Network.framework, explicit HTTPS reachability check, editable per-service HTTP/HTTPS/SOCKS proxies, zsh proxy configuration, manual ordered DNS addresses, automatic DNS, authorized DNS cache flushing, effective system resolvers, and nettop per-process socket counters. DNS server order is edited by moving/rearranging lines in the text field. A selected service is explicitly targeted; it need not be the current default-route service. The path interface and effective resolvers help distinguish VPN behavior.

## Permissions and platform limits

| Feature | Permission / limitation |
| --- | --- |
| CPU, memory, storage, model | Read-only system APIs; no extra permission. Storage refers to the home filesystem, whose APFS capacity may be shared. VM used = active + inactive + wired + compressed pages minus purgeable and file-backed pages; it can differ from Activity Monitor. |
| GPU | Reads `IOAccelerator` → `PerformanceStatistics` → `Device Utilization %` via IOKit. Verified available on this M5. Driver-provided key is undocumented and may disappear or change across hardware/OS updates; missing/out-of-range readings show Unavailable. No guessed utilization. |
| Temperature | Read-only SMC CPU sensor average with generation-specific maps for Apple M1–M5, including Pro/Max/Ultra suffixes; invalid or missing readings remain unavailable. Uses an undocumented protocol, without root access or fan writes. Unavailable temperature is hidden in the summary and an entirely empty temperature history is omitted. Unknown chip generations safely omit temperature; public ProcessInfo thermal pressure is separate. Sensor identifiers checked against [Stats](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift). |
| Process management | Only own-user, nonprotected processes. An application may decline a normal quit or show its own save dialog. Force Quit can lose unsaved work. macOS may deny access to some process information. |
| Folder bookmarks | Native picker when Add/Relink is used. macOS may request Files & Folders access for a protected location. No Full Disk Access requirement. |
| Network counters | `/usr/bin/nettop -L 1 -P -n -x -J bytes_in,bytes_out`, no root. Cumulative visible socket bytes, not upload/download rates or firewall permission. Local traffic is included, counters may reset, helper processes are separate, inaccessible processes may be omitted. This is not a firewall; it cannot grant/revoke per-app internet permission. |
| Internet probe | User-initiated HTTPS GET to `https://captive.apple.com/hotspot-detect.html`, eight-second timeout, expected Success response. Failure can mean filtering, a portal, TLS/proxy issues or no internet. Success covers that endpoint at that time. No telemetry. |
| System proxy / DNS | `networksetup` with the standard macOS administrator authorization dialog through `osascript` when applied. Credentials are handled by macOS, never stored by macino. Authenticated proxy services are read-blocked to avoid silently replacing credentials; use System Settings for those. PAC, proxy bypass lists, VPN-specific configuration and proxy authentication are outside the editor's scope and are not changed. |
| Terminal proxy | Saves a marked block in `~/.zshrc`, separate from system proxy settings. Supports lowercase http_proxy, https_proxy, all_proxy, no_proxy; clears uppercase variants to avoid stale conflicting values. The field values are macino's saved editor configuration, not an interpretation of arbitrary shell scripts or the environment of another Terminal process. Other dotfiles/tools can override the block. New zsh sessions are required, or copy the command and paste it into the current shell. Other shells use the copyable command only if POSIX-compatible. Credentials in proxy URLs are rejected. Symlinked `.zshrc` files are not edited automatically. |
| DNS flushing | Requests administrator authorization. No daemon is installed. |

## Restore network and shell settings

Before every Apply, the complete supported proxy/DNS configuration for that service is saved in:

```
~/Library/Application Support/macino/network-backup.json
```

Select that service in Internet and click **Restore…**. The previous HTTP, HTTPS, SOCKS and manual DNS settings are reapplied with authorization, then read back and compared. The backup is per service and represents the state before the most recent Apply. Returning DNS to automatic uses `networksetup -setdnsservers SERVICE Empty`. A command failure can leave partially applied settings; macino reports it as a failure and keeps the backup available. Refresh to inspect the actual state, then Restore. Restoring does not overwrite the backup. VPNs or managed policies can override effective resolvers.

Before editing `.zshrc`, macino creates a sibling `.zshrc.macino-backup-UUID` file. Unrelated content is preserved when replacing the marked block. **Restore file…** confirms a full-file rollback to the latest backup; this also reverts later unrelated edits, so the current file is backed up as `.zshrc.before-restore-UUID` first. You can instead manually restore only the `# >>> macino proxy >>>` through `# <<< macino proxy <<<` block. Relaunch terminals or run the copyable command afterward. Restoration does not modify already-running terminal environments. macino's saved editor values live in `~/Library/Application Support/macino/terminal.json` and can differ from the restored shell file.

## Verification

Debug and Release builds and ad hoc signature validation completed on the target M5 Mac. The bundled `--self-test` exercises real system reads, GPU bounds, protected-process rejection, graceful termination of a disposable child, stale process rejection, native bookmark round-trip, cache scanning/deletion with disposable files and a symlink fixture, live service/proxy/DNS reads, nettop parsing, shell quoting, and isolated temporary-file shell saves/backups/disable. It does not edit the user's network settings, real shell files, or personal caches.

The native UI was inspected for system gauges, process controls, Internet proxy readback, folder empty state, and the native folder picker. A selected project-folder bookmark was confirmed in persistent preferences after relaunch. Administrator-authorized Apply/Restore, DNS flushing, force termination of real applications, and deleting real user caches are implemented but were not exercised against the user's live configuration. Those workflows require interactive authorization or deliberately alter the active system. Light appearance was visually inspected; dark appearance uses semantic system colors/materials but needs a separate visual pass. Compatibility on older macOS and Intel is not independently verified.

Local signature detection and login-file creation/readback/removal were tested in a temporary directory; no real login configuration was changed, and a logout/login cycle was not performed.

Packaging verifies the DMG checksum, the Applications shortcut, the absence of a separate installer, and the signed macino bundle. A disposable copy is launched through NSWorkspace with its smoke-test flag to verify that the copied application runs.

## Project layout

- `LocalLoginAgent.swift`: opt-in per-user login support for personal ad-hoc builds
- `Setup.swift`: first-run setup, actual login-item status and access checks
- `GlassHostingController.swift`: native whole-surface Liquid Glass and material fallback
- `Sources/macinoInstaller`: legacy installer source; not included in the distributed DMG
- `Scripts/build-installer.sh`: optional legacy helper build; not used by DMG packaging
- `Scripts/package-dmg.sh`, `Scripts/dmg-settings.py`: standard drag-to-Applications DMG packaging
- `Scripts/make-install-assets.swift`: original vector installer art and heart icon
- `MenuPanel.swift`: a single glass menu surface anchored below the status icon
- `macino.swift`: AppKit lifecycle, status item and SwiftUI popover
- `Views.swift`: compact native interface, materials, gauges, confirmation and error states
- `MenuMetrics.swift`: persistent gauge selection, compact menu bar labels and metric formatting
- `Monitoring.swift`: system sampling and process management
- `Folders.swift`: bookmark persistence and Finder integration
- `NetworkSettings.swift`: service settings, backup/restore, shell proxy persistence and network counters
- `Model.swift`: on-demand background work and connection state
- `Cleanup.swift`: strict cache allowlist, scan and deletion reporting
- `SelfTest.swift`: isolated integration verification
- `Resources/AppIcon.icns`, `AppIcon.iconset`: original vector-drawn macino app icon, all macOS sizes
- `Resources/MenuBarTemplate.svg`: matching monochrome icon reference, also drawn as a template NSImage in code
- `Scripts/make-icon.swift`: reproducible AppKit vector icon generator; regenerate with `swift Scripts/make-icon.swift "$PWD/Resources"` then `iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns`

API references: [Liquid Glass](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)), [IOKit](https://developer.apple.com/documentation/iokit), [thermal state](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property). CLI capabilities were checked against this Mac's `nettop -h`, `networksetup` and `powermetrics --help` output.

## About

Created by **Arian Atri**. Repository: [github.com/ArianAtri/macino](https://github.com/ArianAtri/macino). The author and clickable repository link are available in Settings → About macino and the native About macino panel.


## Resource history and process diagnostics

The chart button beside the Mac summary opens a separate live window with CPU/GPU/RAM and CPU-temperature history (last 120 samples, in memory only), memory pressure, wired/compressed memory, swap used and uptime. CSV export uses the actual timestamps; unknown measurements remain blank. Monitoring continues while this window is visible and stops when all monitoring surfaces and pinned metrics are inactive.

Processes has Pause/Resume for list updates (system monitoring continues). The `…` → Process Info window offers Copy report, JSON export, Reveal in Finder, and an on-demand Parent & Connections read. This displays PPID, state, elapsed time, nice value and visible TCP/UDP endpoints from `lsof -nP`. Inspection verifies PID/start/executable before and after querying; exited/reused identities are rejected. No DNS lookup, traffic interception, firewall installation or permission changes are performed. Reports stay local unless the user copies or exports them; process paths and connection endpoints can contain private information. Snapshot values are labeled rather than presented as live.

Design references: [Activity Monitor](https://support.apple.com/guide/activity-monitor/welcome-actmaea30277/mac), [iStat Menus](https://bjango.com/mac/istatmenus/), [Stats](https://github.com/exelban/stats), [htop](https://github.com/htop-dev/htop), [btop](https://github.com/aristocratos/btop), [MenuMeters](https://github.com/yujitach/MenuMeters), [Hot](https://github.com/macmade/Hot), [TG Pro](https://www.tunabellysoftware.com/tgpro/), [Little Snitch](https://www.obdev.at/products/littlesnitch/index.html), and [LuLu](https://objective-see.org/products/lulu.html). This comparison informed the additions; macino does not implement their fan-control or firewall functionality.


## Apple Silicon and macOS compatibility

Both app and installer target native `arm64` with macOS 14.0 minimum (Sonoma). This includes macOS 15 Sequoia and 26 Tahoe, the two releases before macOS 27. `Scripts/build.sh` passes the deployment triple explicitly; `Scripts/verify-compatibility.py` checks both packaged Mach-O binaries, minimum OS metadata and bundle declarations. macOS 26+ glass APIs have availability guards; older systems use NSVisualEffectView/materials. A forced legacy-material self-test exercises that fallback on the current host.

Temperature sensor maps are checked by generation and the parser accepts validated `flt ` and `sp78` formats. Actual readings have been verified on the local M5 only. M1–M4 hardware and macOS 14/15/26 runtime execution still require a device or VM test; a successful deployment-target build and binary audit do not substitute for those runtime tests. No M-series app functionality depends on temperature availability.


## Proxy defaults and contextual help

Internet cards keep detailed explanations behind the ⓘ button. System HTTP/HTTPS/SOCKS rows each offer a reset, plus Restore Defaults for all three on the selected service. Reset confirms first, backs up the previous service configuration, requests normal macOS authorization, disables only the chosen proxy states, and checks the read-back. It preserves DNS and saved server addresses; authenticated configurations remain managed in System Settings. Backup restore is available under `…`.

Terminal Restore Defaults confirms, backs up `.zshrc`, replaces only macino’s managed block with unsets for lowercase/uppercase proxy variables, and saves empty/disabled proxy fields with the default localhost bypass list. Unrelated shell content is preserved; symlinks are refused. Existing shells require a new terminal or the copyable current-session command. Full-file backup restore remains under `…`, with its separate warning.

Internet network counters live in an independent full-height left-hand drawer. Its vertical Network usage handle expands the native window 300 points outward to the left and collapses it again, preserving the 480-point main content width. Its list scrolls independently of proxy/DNS controls, and reduced-motion preferences disable the slide animation.

The main menu has a continuous speech-bubble outline whose tip points to the status item, including during Network usage expansion. After installation the helper opens macino with `--show`, hides its own window and exits its process immediately on successful launch. Launch errors keep the installer visible for retry.


## Android

The Android tab includes a native USB/MTP file browser using libmtp 1.1.23 and
libusb 1.0.30. Unlock the phone, select File transfer on its USB notification,
close other MTP clients, refresh, and connect. Choose internal/SD storage and
browse folders; Send uploads one local file, while a file row downloads it.
Existing filenames are preserved. Downloads are staged and size checked before
being moved to the chosen destination. Transfers require a matching phone serial;
failed uploads can leave a partial object on the phone. There is no Finder mount,
recursive folder transfer, remote deletion, or automatic overwrite.

Screen sharing uses bundled official scrcpy 5.0.1 and adb. Enable USB debugging
and approve this computer on the phone, then Refresh and Share screen. Mirroring
opens a separate view-only window, with audio and clipboard synchronization off.
Stop sharing or close that window to end the session. No TCP/IP mode or device
authorization is automatically enabled. The shared ADB server is not shut down
when mirroring ends, so other developer tools keep working. Android 5.0+ is
required for scrcpy; DRM-protected content may not be capturable.

Only the DMG is distributed. All Android runtime tools, libmtp/libusb source
archives and licenses live inside the app; Homebrew is not required on the target
Mac. `Scripts/build-android-tools.sh` pins upstream downloads and SHA-256 hashes,
builds the two shared libraries for arm64 macOS 14, fixes relative loader paths,
and signs the bundled executables. Development prerequisites for the first build:
`brew install autoconf automake libtool pkgconf`. Dependency downloads are cached
in `.build/android-tools`. `Scripts/verify-android-tools.py` audits architecture,
minimum OS, signatures, portable dylib links, versions and mirroring flags.
Physical phone file transfers and mirroring still require a hardware test; an
empty USB scan or a successful binary audit does not validate a phone session.


Wi-Fi screen sharing supports Android 11+ Wireless debugging. Choose Wi-Fi in
the Screen sharing card. With both devices on the same network, open Pair device
with pairing code on the phone; enter the phone IP, pairing port and six-digit
code, then Pair. Enter the different connection port from the main Wireless
debugging page and Connect. Select a ready phone and Share screen. Disconnect
only disconnects that phone; forgetting the computer on Android revokes pairing.
Codes are not saved to preferences or passed as process arguments. Pairing input
uses a temporary request in a directory restricted to the current user and is
removed when the command completes. This does not enable legacy `adb tcpip` or
change the phone's developer settings automatically. USB MTP remains separate.

Folder shortcuts use compact rows with a single-line path, hover feedback and a
three-dot menu for reorder, relink and removal. Removing a shortcut never deletes
the folder or its contents.

## Quick Access

Quick Access replaces the Folders tab. Its Add menu accepts files or folders,
including multiple selections. Existing folder bookmarks remain under the same
preferences key without migration. Files open with their macOS default app;
application bundles launch normally, and folders open in Finder. Shortcuts are
persistent native bookmarks, not copies of the selected files. The row menu
supports Open, Show in Finder, reorder, Relink and Remove shortcut. Removing a
shortcut never removes its original item. Duplicate resolved paths are ignored.

## Dialog interaction

Menu-bar messages and confirmations share an inline dialog surface for process
Kill/Force Kill, proxy defaults, shell-backup restoration, Quick Access and Android
errors. Background controls are disabled while a dialog is visible. OK/Cancel
clear the displayed state; Escape acknowledges messages or cancels confirmations.
Automatic menu dismissal is suspended for inline dialogs, app-modal panels and
attached sheets. Clicks inside another macino window are no longer treated as
outside clicks. Regular settings/history/process-detail windows keep native macOS
alerts and file dialogs, without the menu's old local mouse monitor intercepting
their buttons.

## Fully offline bilingual Reader

The Reader tab also supports **Type text**: type or paste mixed Persian/English,
then press **Read text** to use the same offline playback and sentence highlighting.
Drafts stay in memory only and are cleared when closing the document. Typing does
not load voices; only starting playback does.

The Reader tab accepts drag/drop or a native picker for UTF-8/UTF-16 TXT,
selectable-text PDF, DOCX and DOC. A separate, network-denied importer extracts
text using native macOS document APIs. Password-locked/image-only PDFs are
rejected; there is no OCR. Imports are capped at 100 MB and two million characters
(10,000 displayed sentences); complex PDF/Word layouts follow extracted reading
order. Document text remains available for display until Close document.

Persian and English passages within a sentence switch between bundled Piper
Amir and LJ Speech voices, using sherpa-onnx CPU inference. The main app never
links ONNX or opens model weights. Play creates one short-lived, network-denied
speech process per bounded language segment. It exits before audio playback;
only the current WAV is retained, never a whole-document audio buffer. Stop,
completion, changing tabs, closing the Reader panel, or quitting releases playback
and cancels active inference. Pausing retains only the current small audio segment;
pausing during generation cancels and re-generates that segment on Resume.

Sentence highlighting follows actual audio playback, with automatic scrolling.
Click a sentence to start there. The native speed slider (0.5–2.0x) and presets
apply to current playback and persist independently of voice/model loading.
Reader alone stays open when clicking outside the app. Escape, the status icon,
or switching to another tab still works; other tabs retain normal dismissal.

`Scripts/build-reader-tools.sh` pins native arm64 runtimes and model hashes,
bundles both voices/data/licenses and signs nested helpers/libraries. Model cache
is centralized at `~/dev/llm/macino-tts`; override
`MACINO_TTS_MODEL_CACHE` on another development machine. The distributed DMG has
no dependency on that cache, Python, Homebrew, network downloads, or online TTS.
`Scripts/verify-reader-tools.py` generates non-silent speech in both languages,
imports TXT/PDF/DOCX/DOC fixtures with network access denied, and audits signatures,
arm64/macOS-14 compatibility and the absence of inference links in the main app.

The separate `--reader-playback-test` runs muted real playback against disposable
text/preferences and verifies import without voice allocation, sentence highlight,
Pause/Resume with a changed rate, Stop cleanup, automatic end cleanup, active child
termination, and rejection of stale cancelled results. Packaging runs it on the
copied app. During a live Word playback check, vmmap showed no voice model or
ONNX runtime mappings in the main macino process. A sample voice helper peaked
at roughly 240 MB RSS on the development M5 and then exited; this is temporary
inference memory, not a fixed reservation in the menu app. macOS may retain
reclaimable filesystem cache after reading model files.

### Clipboard history

The Clipboard tab has an opt-in switch (off by default), search, one-click copy,
individual removal and Clear all. It records text copied after enabling, including
Persian and English, in memory only: at most 50 distinct items, each up to 100 KB.
Disabling or quitting clears history; only the enabled preference persists.
Polling runs every 0.6 seconds while enabled, so very rapid intermediate copies may
be missed. Images/files are excluded. Standard concealed/transient clipboard
markers are respected, but sensitive text without such markers can be recorded.
On macOS use Command-C to copy and Command-V to paste the selected history item.

The Clipboard tab has an optional keyboard shortcut. Click the shortcut button,
then press your preferred combination, or choose **Use ⌃V** (Control + V, the default). The choice is saved.
Regular shortcuts use macOS hotkey registration and can open without Accessibility.
Fn combinations use an event tap and need Accessibility; some keyboards do not
send Fn to macOS. Conflicting registered shortcuts show an error instead of
silently claiming to work. Accessibility also enables caret positioning and
automatic paste; without it the popup opens near the mouse and copies the selected
text for manual ⌘V. The panel includes search, per-item deletion and Clear all.
Escape, the shortcut again, or clicking outside closes it. Turning history off
unregisters the shortcut. Regular ⌘V is reserved for pasting and cannot be assigned.
