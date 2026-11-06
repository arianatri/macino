# Troubleshooting

[← Home](../README.md) · [Install](install.md)

**I can’t find the app.** Open Applications → macino. It runs from the menu bar;
it is not a normal always-visible Dock window. Search for macino in Spotlight if
needed. Keep one installed copy in Applications.

**Control + V does nothing.** Turn on both clipboard history and Keyboard shortcut.
Check the status under the shortcut button. Try recording a different combination
if another app uses it. Control (⌃) is different from Command (⌘). Fn shortcuts
also depend on Accessibility and your keyboard sending Fn to macOS.

**The popup copies but doesn’t paste.** Automatic pasting needs Accessibility and
the original destination app to regain focus. Otherwise the item is still copied;
press ⌘V yourself. Secure fields or apps with restricted automation may not accept
an injected paste. The popup uses the mouse position if caret bounds are unavailable.

**macOS shows permission as enabled, but automatic paste fails after an update.**
Local signatures can change between builds. Quit macino, check its entry in
System Settings → Privacy & Security → Accessibility, and approve the current
installed copy if needed. Do not grant unrelated permissions.

**Reader won’t read my PDF.** It must contain selectable text. Image-only or
scanned pages are not supported. Protected PDFs may not allow extraction.

**RAM doesn’t immediately drop after playback.** Voice child processes exit, but
macOS may keep file pages cached. Document text remains visible until you close it.

**My Android phone isn’t listed.** Unlock it, enable file transfer for MTP, and
approve debugging for mirroring. Check the cable and the phone’s USB mode. Wi-Fi
pairing and connection use different ports. Some other MTP apps may hold the device.

For another problem, [open a bug report](https://github.com/ArianAtri/macino/issues/new/choose)
with your macOS version, chip and steps. Remove clipboard text, documents and other
private data from screenshots and logs before attaching them.
