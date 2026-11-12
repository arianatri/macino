import AVFoundation
import CoreMedia
import Darwin
import ScreenCaptureKit

/// Captures system output with Apple's screen-capture permission and feeds
/// 48 kHz stereo PCM to FFmpeg through a private FIFO. No audio driver needed.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private let fifoURL: URL
    private let outputQueue = DispatchQueue(label: "macino.system-audio", qos: .userInitiated)
    private let handleLock = NSLock()
    private let stateLock = NSLock()
    private var writer: FileHandle?
    private var stream: SCStream?
    private var stopped = false
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                             sampleRate: 48_000, channels: 2,
                                             interleaved: true)!
    var onFailure: ((String) -> Void)?

    init(fifoURL: URL) { self.fifoURL = fifoURL }

    func start() {
        stateLock.lock(); stopped = false; stateLock.unlock()
        // FFmpeg closing its end of a pipe must become a recoverable
        // EPIPE error; it must never terminate the whole menu-bar app.
        _ = signal(SIGPIPE, SIG_IGN)
        guard mkfifo(fifoURL.path, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
            onFailure?("Could not prepare the system-audio stream."); return
        }
        // FFmpeg opens the FIFO reader first. Retry non-blocking opens so a
        // failed encoder or an early Stop can never strand a thread in open().
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, self.connectWriter() else { return }
            Task { await self.beginCapture() }
        }
    }

    private func beginCapture() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard !isStopped else { return }
            guard let display = content.displays.first else { throw AppError.message("No display is available for audio capture.") }
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = 16; configuration.height = 16
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 15)
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            let capture = SCStream(filter: filter, configuration: configuration, delegate: self)
            try capture.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)
            guard install(capture) else { return }
            try await capture.startCapture()
            if isStopped { try? await capture.stopCapture() }
        } catch {
            if !isStopped {
                onFailure?("System audio could not start. Allow macino in Privacy & Security → Screen Recording, then try again. Details: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        stateLock.lock(); stopped = true; let current = stream; stream = nil; stateLock.unlock()
        if let current { Task { try? await current.stopCapture() } }
        handleLock.lock(); let output = writer; writer = nil; handleLock.unlock()
        try? output?.close()
        try? FileManager.default.removeItem(at: fifoURL)
    }

    private var isStopped: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return stopped
    }

    private func install(_ capture: SCStream) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        guard !stopped else { return false }
        stream = capture
        return true
    }

    private func connectWriter() -> Bool {
        // Screen Recording permission can take a while to approve in the
        // separate FFmpeg process, so allow the same minute as stream startup.
        let deadline = Date().addingTimeInterval(90)
        while !isStopped && Date() < deadline {
            let descriptor = open(fifoURL.path, O_WRONLY | O_NONBLOCK)
            if descriptor >= 0 {
                let flags = fcntl(descriptor, F_GETFL)
                guard flags >= 0, fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK) == 0 else {
                    let errorCode = errno
                    _ = close(descriptor)
                    if !isStopped { onFailure?("Could not configure the system-audio stream: \(String(cString: strerror(errorCode)))") }
                    return false
                }
                let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                stateLock.lock()
                guard !stopped else { stateLock.unlock(); try? handle.close(); return false }
                handleLock.lock(); writer = handle; handleLock.unlock()
                stateLock.unlock()
                return true
            }
            if errno != ENXIO && errno != EINTR {
                let errorCode = errno
                if !isStopped { onFailure?("Could not connect the system-audio stream: \(String(cString: strerror(errorCode)))") }
                return false
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if !isStopped { onFailure?("Could not connect the system-audio stream to FFmpeg.") }
        return false
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard !isStopped, type == .audio, sampleBuffer.isValid,
              let description = sampleBuffer.formatDescription?.audioStreamBasicDescription else { return }
        do {
            try sampleBuffer.withAudioBufferList { buffers, _ in
                var streamDescription = description
                guard let input = AVAudioFormat(streamDescription: &streamDescription),
                      let pcm = AVAudioPCMBuffer(pcmFormat: input, bufferListNoCopy: buffers.unsafePointer) else { return }
                if converterInputFormat != input {
                    converter = AVAudioConverter(from: input, to: outputFormat)
                    converterInputFormat = input
                }
                guard let converter else { return }
                let capacity = AVAudioFrameCount(Double(pcm.frameLength) * outputFormat.sampleRate / input.sampleRate + 64)
                guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
                var conversionError: NSError?
                var suppliedInput = false
                let result = converter.convert(to: converted, error: &conversionError) { _, status in
                    guard !suppliedInput else { status.pointee = .noDataNow; return nil }
                    suppliedInput = true
                    status.pointee = .haveData
                    return pcm
                }
                guard result != .error else {
                    if let conversionError { throw conversionError }
                    throw AppError.message("The system-audio format could not be converted.")
                }
                guard converted.frameLength > 0 else { return }
                let audioBuffer = converted.audioBufferList.pointee.mBuffers
                guard let data = audioBuffer.mData else { return }
                let bytes = Data(bytes: data, count: Int(audioBuffer.mDataByteSize))
                handleLock.lock(); let destination = writer; handleLock.unlock()
                try destination?.write(contentsOf: bytes)
            }
        } catch { if !isStopped { onFailure?("System audio stream failed: \(error.localizedDescription)") } }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        if !isStopped { onFailure?("System audio capture stopped: \(error.localizedDescription)") }
    }
}
