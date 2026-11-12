//
//  Profiles.swift — encoder/container profiles for different TV generations.
//
//  Older DLNA TVs are extremely picky about what they accept from a *live*
//  source. The defaults here were reverse-engineered on a Philips 43PFS5301
//  (2016, non-Android) and cross-checked against the renderer profiles of
//  Universal Media Server and Serviio.
//
//  MirrorCast for macOS · Powered by Greenstein.Design
//

import Foundation

struct MirrorProfile: Equatable {
    let id: String
    let title: String
    let detail: String
    let mime: String
    let dlnaPN: String
    let fileExtension: String
    let videoArgs: [String]
    let audioArgs: [String]
    let muxArgs: [String]

    var dlnaFlags: String {
        dlnaPN + "DLNA.ORG_OP=01;DLNA.ORG_CI=0;" +
        "DLNA.ORG_FLAGS=01500000000000000000000000000000"
    }

    static let all: [MirrorProfile] = [
        MirrorProfile(
            id: "ps",
            title: "MPEG-2 / AC3 (empfohlen)",
            detail: "MPEG-PS 720×576 — läuft auf Philips & Co. ab ~2012",
            mime: "video/mpeg",
            dlnaPN: "DLNA.ORG_PN=MPEG_PS_PAL;",
            fileExtension: "mpg",
            videoArgs: ["-vf", "scale=720:576,setdar=16/9,format=yuv420p", "-r", "25",
                        "-c:v", "mpeg2video", "-b:v", "4500k", "-minrate", "4500k",
                        "-maxrate", "4500k", "-bufsize", "1600k", "-g", "15"],
            audioArgs: ["-c:a", "ac3", "-b:a", "192k", "-ar", "48000", "-ac", "2"],
            muxArgs: ["-max_interleave_delta", "500000", "-flush_packets", "1",
                      "-muxrate", "8000000", "-f", "vob"]),

        MirrorProfile(
            id: "ps-mp2",
            title: "MPEG-2 / MP2",
            detail: "wie oben, aber MP2-Ton (für Geräte ohne AC3-Lizenz)",
            mime: "video/mpeg",
            dlnaPN: "DLNA.ORG_PN=MPEG_PS_PAL;",
            fileExtension: "mpg",
            videoArgs: ["-vf", "scale=720:576,setdar=16/9,format=yuv420p", "-r", "25",
                        "-c:v", "mpeg2video", "-b:v", "4500k", "-minrate", "4500k",
                        "-maxrate", "4500k", "-bufsize", "1600k", "-g", "15"],
            audioArgs: ["-c:a", "mp2", "-b:a", "192k", "-ar", "48000", "-ac", "2"],
            muxArgs: ["-max_interleave_delta", "500000", "-flush_packets", "1",
                      "-muxrate", "8000000", "-f", "vob"]),

        MirrorProfile(
            id: "m2ts",
            title: "M2TS / MPEG-2",
            detail: "192-Byte-Transportstrom, MIME video/vnd.dlna.mpeg-tts",
            mime: "video/vnd.dlna.mpeg-tts",
            dlnaPN: "DLNA.ORG_PN=MPEG_TS_SD_EU_T;",
            fileExtension: "m2ts",
            videoArgs: ["-vf", "scale=720:576,setdar=16/9,format=yuv420p", "-r", "25",
                        "-c:v", "mpeg2video", "-b:v", "4500k", "-maxrate", "5M",
                        "-bufsize", "1800k", "-g", "15"],
            audioArgs: ["-c:a", "ac3", "-b:a", "192k", "-ar", "48000", "-ac", "2"],
            muxArgs: ["-max_interleave_delta", "500000", "-flush_packets", "1",
                      "-mpegts_m2ts_mode", "1", "-f", "mpegts"]),

        MirrorProfile(
            id: "mkv-h264",
            title: "H.264 / MKV (HD)",
            detail: "720p — für neuere Fernseher mit H.264-Unterstützung",
            mime: "video/x-matroska",
            dlnaPN: "",
            fileExtension: "mkv",
            videoArgs: ["-vf", "scale=-2:720,format=yuv420p", "-r", "25",
                        "-c:v", "libx264", "-profile:v", "high", "-level", "4.0",
                        "-preset", "ultrafast", "-tune", "zerolatency",
                        "-b:v", "3500k", "-maxrate", "4M", "-bufsize", "6M", "-g", "50"],
            audioArgs: ["-c:a", "ac3", "-b:a", "192k", "-ar", "48000", "-ac", "2"],
            muxArgs: ["-max_interleave_delta", "500000", "-flush_packets", "1",
                      "-f", "matroska"]),

        MirrorProfile(
            id: "m2ts-h264",
            title: "H.264 / M2TS (HD)",
            detail: "720p im Transportstrom",
            mime: "video/vnd.dlna.mpeg-tts",
            dlnaPN: "",
            fileExtension: "m2ts",
            videoArgs: ["-vf", "scale=-2:720,format=yuv420p", "-r", "25",
                        "-c:v", "libx264", "-profile:v", "high", "-level", "4.0",
                        "-preset", "ultrafast", "-tune", "zerolatency",
                        "-b:v", "3500k", "-maxrate", "4M", "-bufsize", "6M", "-g", "50"],
            audioArgs: ["-c:a", "ac3", "-b:a", "192k", "-ar", "48000", "-ac", "2"],
            muxArgs: ["-max_interleave_delta", "500000", "-flush_packets", "1",
                      "-mpegts_m2ts_mode", "1", "-f", "mpegts"]),
    ]

    static func by(id: String) -> MirrorProfile {
        all.first { $0.id == id } ?? all[0]
    }

    func ffmpegArguments(screenIndex: String, audioIndex: String?) -> [String] {
        var args = ["-hide_banner", "-loglevel", "warning",
                    "-f", "avfoundation", "-capture_cursor", "1", "-framerate", "25",
                    "-i", "\(screenIndex):\(audioIndex ?? "none")"]
        args += videoArgs
        args += (audioIndex != nil ? audioArgs : ["-an"])
        args += muxArgs
        args.append("pipe:1")
        return args
    }
}
