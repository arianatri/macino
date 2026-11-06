import SwiftUI
import Network
import SystemConfiguration

@MainActor final class AppModel: ObservableObject {
    @Published var history = ResourceHistory()
    @Published var processesPaused = false
    var historyVisible = false
    @Published var system = SystemSnapshot()
    @Published var menuMetrics = Set((UserDefaults.standard.stringArray(forKey: "menuMetrics") ?? []).compactMap(MenuMetric.init(rawValue:))) {
        didSet {
            UserDefaults.standard.set(MenuMetric.selected(menuMetrics).map(\.rawValue), forKey: "menuMetrics")
            reconcileMonitoring()
        }
    }
    @Published var processes: [ProcessRow] = []
    @Published var processSort = ProcessSort(rawValue: UserDefaults.standard.string(forKey: "processSort") ?? "") ?? .cpu {
        didSet { UserDefaults.standard.set(processSort.rawValue, forKey: "processSort") }
    }
    @Published var processTraffic: [Int32: ProcessTraffic] = [:]
    @Published var processTrafficError: String?
    @Published var traffic: [TrafficRow] = []
    @Published var trafficError: String?
    @Published var processError: String?
    @Published var localStatus = "Checking local network…"
    @Published var internetStatus = "Not checked"
    @Published var services: [String] = []
    @Published var service = ""
    @Published var config: ServiceConfig?
    @Published var dnsDraft = ""
    @Published var effectiveDNS = ""
    @Published var busy = false
    @Published var message: String?
    @Published var tab = "System"
    @Published var networkUsageExpanded = false
    @Published var caches: [CacheCategory] = []
    private let sampler = SystemSampler()
    private let pathMonitor = NWPathMonitor()
    private var loop: Task<Void, Never>?
    private var visible = false
    private var updating = false
    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let text = path.status == .satisfied ? "Local network • " + Set(path.availableInterfaces.filter { path.usesInterfaceType($0.type) }.map(\.name)).sorted().joined(separator: ", ") : "No local network path"
            Task { @MainActor in self?.localStatus = text }
        }
        pathMonitor.start(queue: DispatchQueue(label: "macino.path"))
    }
    func start() { visible = true; reconcileMonitoring() }
    func stop() { visible = false; reconcileMonitoring() }
    func reconcileMonitoring() {
        guard visible || historyVisible || !menuMetrics.isEmpty else { loop?.cancel(); loop = nil; return }
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh(systemOnly: !self.visible)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }
    func refresh(systemOnly: Bool = false) async {
        guard !updating else { return }; updating = true; defer { updating = false }
        let sampler = self.sampler
        system = await Task.detached(priority: .utility) { sampler.sample() }.value
        history.append(system)
        if !systemOnly, tab == "Processes", !processesPaused {
            do { let rows = try await Task.detached(priority: .utility) { try ProcessManager.sample() }.value; if !processesPaused { processes = rows }; processError = nil } catch { processError = error.localizedDescription }
        }
        if !systemOnly, tab == "Processes", !processesPaused, processSort == .internet {
            do {
                processTraffic = try await Task.detached(priority: .utility) { ProcessTraffic.indexed(try NetworkActivity.sample()) }.value
                processTrafficError = nil
            } catch { processTraffic = [:]; processTrafficError = error.localizedDescription }
        }
        if !systemOnly, tab == "Internet" {
            do { traffic = try await Task.detached(priority: .utility) { try NetworkActivity.sample() }.value; trafficError = nil } catch { trafficError = error.localizedDescription }
        }
    }
    func loadNetwork() { operation { model in
        let result = try await Task.detached(priority: .utility) { try NetworkSettings.services() }.value
        model.services = result
        if model.service.isEmpty { model.service = result.contains("Wi-Fi") ? "Wi-Fi" : result.first ?? "" }
        guard !model.service.isEmpty else { throw AppError.message("No configurable network services.") }
        let service = model.service
        model.config = try await Task.detached(priority: .utility) { try NetworkSettings.read(service) }.value
        model.dnsDraft = model.config?.dns.joined(separator: "\n") ?? ""
        model.effectiveDNS = try await Task.detached { try Shell.checked("/usr/sbin/scutil", ["--dns"]) }.value
    } }
    func readService() { config = nil; loadNetwork() }
    func applyNetwork(restore: Bool = false) { guard var config else { return }; config.dns = dnsDraft.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }; operation { model in
        model.config = try await Task.detached { restore ? try NetworkSettings.restore(config.service) : try NetworkSettings.apply(config) }.value
        model.dnsDraft = model.config?.dns.joined(separator: "\n") ?? ""
        model.message = "\(config.service): settings read back and verified."
    } }
    func restoreProxyDefaults(service: String, kind: String?) {
        operation { model in
            let restored = try await Task.detached(priority: .userInitiated) {
                try NetworkSettings.restoreProxyDefaults(service, kind: kind)
            }.value
            if model.service == service { model.config = restored }
            model.message = "\(service): \(kind == nil ? "all proxies" : "proxy") disabled. DNS is unchanged."
        }
    }
    func checkInternet() { operation { model in
        model.internetStatus = "Checking HTTPS reachability…"
        do {
            var request = URLRequest(url: URL(string: "https://captive.apple.com/hotspot-detect.html")!); request.timeoutInterval = 8; request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            model.internetStatus = (response as? HTTPURLResponse)?.statusCode == 200 && String(decoding: data, as: UTF8.self).contains("<TITLE>Success</TITLE>") ? "Internet reachable • Apple HTTPS probe" : "Internet not verified • captive portal or modified response"
        } catch { model.internetStatus = "Internet probe failed: \(error.localizedDescription)" }
    } }
    func operation(_ body: @escaping @MainActor (AppModel) async throws -> Void) { guard !busy else { return }; busy = true; Task { do { try await body(self) } catch { message = error.localizedDescription }; busy = false } }
    func scanCaches() { operation { model in model.caches = try await Task.detached(priority: .utility) { try Cleanup.scan() }.value } }
    func terminateGroup(_ group: ProcessGroup, force: Bool = false) {
        operation { model in
            guard !group.members.contains(where: { $0.protected }) else {
                throw AppError.message("This group includes protected processes.")
            }
            var requested = 0, exited = 0
            var failures: [String] = []
            for row in group.members {
                do {
                    // Skip members already closed by their parent, and never add
                    // newly spawned processes to the user's confirmed snapshot.
                    guard try ProcessManager.sample().contains(where: { $0.id == row.id && $0.started == row.started && $0.command == row.command }) else { exited += 1; continue }
                    try ProcessManager.terminate(row, force: force)
                    requested += 1
                } catch { failures.append("PID \(row.id): \(error.localizedDescription)") }
            }
            await model.refresh()
            model.message = "\(group.name): \(requested) termination requests, \(exited) already exited."
                + (failures.isEmpty ? "" : "\n" + failures.joined(separator: "\n"))
        }
    }
    func terminate(_ row: ProcessRow, force: Bool) { operation { model in try ProcessManager.terminate(row, force: force); model.message = force ? "Force Quit sent to \(row.name)." : "Quit requested for \(row.name). If it remains after refreshing, use Force Quit."; await model.refresh() } }
}
