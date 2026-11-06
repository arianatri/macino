# Privacy and permissions

[← Home](../README.md)

macino does not include an analytics or telemetry service. It has no account or
cloud sync for clipboard history or Reader documents.

| Feature | What it uses |
| --- | --- |
| Clipboard | Reads plain text from the system clipboard only while history is enabled. Keeps 50 unique items in memory; quitting or turning it off clears them. |
| Private clipboard items | Skips standard concealed/transient markers. It cannot recognize every password or secret if the source app does not mark it. |
| Reader | Extracts text and generates speech locally. Voice/import helpers deny network access. The current document/draft remains in memory until closed; temporary audio is deleted when playback resources are released. |
| Ordinary clipboard shortcut | Registers a macOS hotkey. It can open without Accessibility. |
| Accessibility | Optional for locating the insertion point and sending a paste shortcut. Required for Fn event-tap shortcuts. No automatic permission prompts. |
| Network tools | Reads counters and applies the DNS/proxy operations you choose. Changes may need macOS administrator approval. |
| Android | USB MTP plus local adb/scrcpy connections, including wireless debugging when chosen. Approvals happen on the phone. |
| Files/folders | Opens files or folders you choose; Quick Access saves bookmarks/shortcuts. |
| Launch at login | Opt-in. Turn it off from Settings. |

Build and packaging scripts download their third-party dependencies. This is
separate from Reader’s fully offline runtime. Saved app preferences stay on the
Mac between launches. Clipboard text and Reader documents are not saved as a
history database. macOS can retain reclaimable file caches after a process exits;
released model memory does not mean all cached pages disappear immediately.
