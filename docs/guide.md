# Using macino

[← Home](../README.md)

## System and menu bar stats

Open macino’s menu bar icon. System shows live CPU, GPU, memory and storage values.
Tick a gauge to show it in the menu bar. Multiple values stack in pairs to save
space. Memory is macOS VM usage, not just the sum of app memory. CPU temperature
appears only when a supported sensor returns a valid reading. Click **History**
for recorded resource activity.

## Processes

Use search and sorting to find a process. **Group** combines an app and its
helpers; **Show system processes** is off by default. **Kill** asks a process to
exit, while the **…** menu includes Force Kill and process details. Force Kill can
lose unsaved work. macino protects critical processes and cannot kill processes
your account does not control.

## Quick Access

Add a file or folder. Files open in their default app and folders open in Finder.
Removing a shortcut does not delete the original file or folder.

## Internet

Inspect traffic and open the Network usage drawer on the left. Network counters
can be unavailable for protected processes. Choose the right network service
before editing proxies. Restore Defaults can reset proxy settings; macOS may ask
for administrator approval when applying changes or flushing DNS.

## Android

MTP browsing uses a USB connection. Unlock the phone, choose its file-transfer
mode and approve any phone prompts. Screen mirroring uses the bundled scrcpy/adb
tools. USB mirroring needs USB debugging approval. Wireless mirroring needs an
Android device that supports wireless debugging, a pairing code and the correct
pairing/connection ports. The Mac and phone must be able to reach each other.
Physical-device compatibility is not guaranteed for every phone.

## TV screen sharing

Open **TV**, refresh the list, choose a DLNA television on the same network and
start sharing. Stop sharing to end the stream. Choose a video profile if the TV
does not accept the default format. Screen Recording permission is requested by
macOS when capture starts. The stream stays on your local network. A few seconds
of delay is normal; protected video may be blank.

FFmpeg must be installed separately (`brew install ffmpeg`). macino does not
install it. **Send Mac audio to TV** is on by default and captures system audio
with Apple's ScreenCaptureKit. macino does not capture your microphone, install
an audio driver or change your Mac's sound output. macOS asks for Screen
Recording access the first time; allow macino and FFmpeg in **System Settings →
Privacy & Security → Screen Recording** if either prompt appears. If you don't
want sound in the TV stream, turn the option off. This feature uses DLNA/UPnP,
not Miracast or Android TV.

## Offline Reader

Choose **Type text** to write or paste, then **Read text**. Alternatively drop a
TXT, text PDF, DOCX or DOC file into Reader. Mixed Persian and English passages
switch voices automatically. Play, pause, stop and adjust the speed; the current
sentence is highlighted. Reader stays open when you click outside it. Escape or
the menu bar icon closes it. Leaving Reader stops playback.

Scanned PDFs need OCR, which macino does not provide. Voice models are bundled
and run in network-denied child processes. Typing alone does not load a voice.
Stop/end clears playback resources; document text stays until you close it.

## Clipboard

Enable history to keep up to 50 unique copied text items, each at most 100 KB.
Images and files are not recorded. Standard private clipboard markers are
respected, but unmarked sensitive text can still enter history.

Enable **Keyboard shortcut** to open the small popup. **⌃V** is the default. Click
the shortcut button to record a different combination. A conflict message means
the combination could not be registered. Fn may be handled by the keyboard or
macOS; choose a regular shortcut if it does not work.

Search the popup, click an item to copy/paste it, use the trash icon to delete one,
or **Clear all** at the bottom to empty history. Drag any outer edge to move the
popup. The square **×**, Escape, clicking outside or the shortcut again closes it.
Accessibility enables automatic paste; without it, use ⌘V after choosing an item.
Clear all clears macino’s history, not the current system clipboard.
