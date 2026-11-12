# Third-party components

macino bundles native tools and models. Their license files, model cards and
notices are included with the built application and described in
`Resources/Android-NOTICES.txt` and `Resources/Reader-NOTICES.txt` when present.

The major components include libmtp, libusb, adb, scrcpy, sherpa-onnx, ONNX Runtime,
espeak-ng and Piper voice models. These do not all use the same license. Read the
bundled notices and source-material provisions before redistributing a build.
The app’s original source currently has no general open-source license; making
the repository public by itself does not grant one.

The TV mirroring integration is derived from MirrorCast for macOS by Rene
Grebenstein / Greenstein.Design. Its PolyForm Noncommercial License 1.0.0 is
included in `Resources/MirrorCast-NONCOMMERCIAL-LICENSE.txt`, with attribution
in `Resources/MirrorCast-NOTICE.txt`. This component may only be used and
redistributed for permitted noncommercial purposes under that license.

TV mirroring invokes a separately installed FFmpeg executable. System audio
capture requires a separately installed loopback audio driver such as
BlackHole; that driver is not part of macino.
