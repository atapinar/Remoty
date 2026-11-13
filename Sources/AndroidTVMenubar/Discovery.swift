import Foundation
import Network

struct FoundDevice: Identifiable, Equatable {
    var id: String { identity.isEmpty ? host : identity }
    let host: String
    let name: String
    let hostName: String
    let deviceID: String
    var identity: String { deviceID.isEmpty ? hostName : deviceID }
    var address: String { hostName.isEmpty ? host : hostName }
}

enum DiscoveryError: LocalizedError {
    case denied
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .denied: return "Local Network access denied - allow Remoty in System Settings > Privacy & Security > Local Network."
        case .failed(let detail): return "Network discovery failed: \(detail)"
        }
    }
}

enum Discovery {
    static let serviceTypes = ["_androidtvremote2._tcp.", "_airplay._tcp."]

    @MainActor static func search(seconds: Double = 4) async -> (devices: [FoundDevice], failure: DiscoveryError?) {
        let session = Session()
        session.start()
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        return session.finish()
    }

    static func txt(_ data: Data) -> [String: String] {
        var result: [String: String] = [:]
        var index = data.startIndex
        while index < data.endIndex {
            let length = Int(data[index])
            let start = data.index(after: index)
            let end = start + length
            guard end <= data.endIndex else { break }
            let entry = String(decoding: data[start..<end], as: UTF8.self)
            if let equals = entry.firstIndex(of: "=") {
                result[entry[..<equals].lowercased()] = String(entry[entry.index(after: equals)...])
            } else if !entry.isEmpty {
                result[entry.lowercased()] = ""
            }
            index = end
        }
        return result
    }

    static func hostName(_ value: String?) -> String {
        guard var name = value?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return "" }
        if name.hasSuffix(".") { name.removeLast() }
        return Adb.mdnsName(name) ? name : ""
    }

    static func ipv4(_ addresses: [Data]) -> String? {
        for data in addresses where data.count >= MemoryLayout<sockaddr_in>.size {
            let address = data.withUnsafeBytes { $0.load(as: sockaddr_in.self) }
            guard address.sin_family == sa_family_t(AF_INET) else { continue }
            let bytes = withUnsafeBytes(of: address.sin_addr.s_addr) { Array($0) }
            let text = bytes.map(String.init).joined(separator: ".")
            if Adb.localHost(text) { return text }
        }
        return nil
    }

    final class Session: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
        private var browsers: [NetServiceBrowser] = []
        private var services: [NetService] = []
        private var connections: [NWConnection] = []
        private var devices: [String: FoundDevice] = [:]
        private var failure: DiscoveryError?

        func start() {
            for type in Discovery.serviceTypes {
                let browser = NetServiceBrowser()
                browser.delegate = self
                browser.searchForServices(ofType: type, inDomain: "local.")
                browsers.append(browser)
            }
        }

        func finish() -> (devices: [FoundDevice], failure: DiscoveryError?) {
            browsers.forEach { $0.stop() }
            services.forEach { $0.stop() }
            connections.forEach { $0.cancel() }
            return (devices.values.sorted { $0.name < $1.name }, failure)
        }

        func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
            services.append(service)
            service.delegate = self
            service.resolve(withTimeout: 3)
        }

        func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
            failure = Discovery.failure(errorDict)
        }

        func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
            failure = failure ?? Discovery.failure(errorDict)
        }

        func netServiceDidResolveAddress(_ sender: NetService) {
            guard let ip = Discovery.ipv4(sender.addresses ?? []) else { return }
            let values = sender.txtRecordData().map(Discovery.txt) ?? [:]
            let found = FoundDevice(host: ip, name: sender.name, hostName: Discovery.hostName(sender.hostName), deviceID: values["deviceid"] ?? "")
            if let existing = devices[ip] {
                devices[ip] = FoundDevice(host: ip, name: found.name.count < existing.name.count ? found.name : existing.name,
                                          hostName: existing.hostName.isEmpty ? found.hostName : existing.hostName,
                                          deviceID: existing.deviceID.isEmpty ? found.deviceID : existing.deviceID)
            } else {
                devices[ip] = found
                checkAccess(ip, port: sender.port)
            }
        }

        private func checkAccess(_ ip: String, port: Int) {
            guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: port)), port.rawValue > 0 else { return }
            let connection = NWConnection(host: NWEndpoint.Host(ip), port: port, using: .tcp)
            connections.append(connection)
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard case .waiting = state, connection?.currentPath?.unsatisfiedReason == .localNetworkDenied else {
                    if case .ready = state { connection?.cancel() }
                    return
                }
                DispatchQueue.main.async { self?.failure = .denied }
                connection?.cancel()
            }
            connection.start(queue: .main)
        }
    }

    static func failure(_ errorDict: [String: NSNumber]) -> DiscoveryError {
        let code = errorDict[NetService.errorCode]?.intValue ?? 0
        if code == -65570 { return .denied }
        if code == -72008 { return .failed("the app bundle does not declare its Bonjour services") }
        return .failed("error \(code)")
    }
}
