import AppKit
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let config = NSWorkspace.OpenConfiguration()
config.createsNewApplicationInstance = true
config.activates = false
config.arguments = ["--smoke-test"]
var complete = false
var launched: NSRunningApplication?
var failure: Error?
NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
    launched = app; failure = error; complete = true
}
let deadline = Date().addingTimeInterval(15)
while !complete && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
if let failure { fatalError("Installed copy launch failed: \(failure.localizedDescription)") }
guard complete, let launched, launched.bundleURL?.resolvingSymlinksInPath().path == url.resolvingSymlinksInPath().path else { fatalError("macOS did not launch the expected copied application") }
while !launched.isTerminated && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
guard launched.isTerminated else { launched.terminate(); fatalError("Installed application smoke test did not exit") }
print("PASS NSWorkspace opens the copied application, and its smoke test exits")
