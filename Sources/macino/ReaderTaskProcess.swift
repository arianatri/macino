import Foundation
import Darwin

/// Only short-lived child processes load document parsers and voice libraries.
final class ReaderTaskProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timedOut = false
    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return process?.isRunning == true }
    var processIdentifier: Int32? { lock.lock(); defer { lock.unlock() }; return process?.isRunning == true ? process?.processIdentifier : nil }
    func cancel(timeout: Bool = false) {
        lock.lock(); cancelled = true; timedOut = timeout; let current = process; lock.unlock()
        guard let current, current.isRunning else { return }
        current.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if current.isRunning { kill(current.processIdentifier, SIGKILL) }
        }
    }
    func run(helper: URL, arguments: [String], input: Data, directory: URL, timeout: TimeInterval = 60) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let request = directory.appendingPathComponent("request"), output = directory.appendingPathComponent("response"), error = directory.appendingPathComponent("errors")
        try input.write(to: request)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: request.path)
        FileManager.default.createFile(atPath: output.path, contents: nil)
        FileManager.default.createFile(atPath: error.path, contents: nil)
        let stdin = try FileHandle(forReadingFrom: request), stdout = try FileHandle(forWritingTo: output), stderr = try FileHandle(forWritingTo: error)
        let job = Process()
        job.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        job.arguments = ["-p", "(version 1)(allow default)(deny network*)", helper.path] + arguments
        job.standardInput = stdin; job.standardOutput = stdout; job.standardError = stderr
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            job.terminationHandler = { [self] finished in
                try? stdin.close(); try? stdout.close(); try? stderr.close()
                lock.lock(); process = nil; let wasCancelled = cancelled, expired = timedOut; lock.unlock()
                if expired { continuation.resume(throwing: AppError.message("The offline reader timed out. Try a smaller document or sentence.")) }
                else if wasCancelled { continuation.resume(throwing: CancellationError()) }
                else if finished.terminationStatus != 0 {
                    let data = (try? Data(contentsOf: output)) ?? Data()
                    let response = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
                    let detail = response?["error"] ?? "The offline reader could not process this document or generate speech."
                    continuation.resume(throwing: AppError.message(detail))
                } else { continuation.resume() }
            }
            lock.lock()
            if cancelled {
                lock.unlock(); try? stdin.close(); try? stdout.close(); try? stderr.close()
                continuation.resume(throwing: CancellationError()); return
            }
            process = job
            do { try job.run(); lock.unlock() }
            catch {
                process = nil; lock.unlock(); try? stdin.close(); try? stdout.close(); try? stderr.close()
                continuation.resume(throwing: error)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self, self.isRunning else { return }; self.cancel(timeout: true)
            }
        }
    }
}
