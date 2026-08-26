import Foundation

@MainActor
final class AirPlayDeviceBrowser: NSObject, @preconcurrency NetServiceBrowserDelegate {
    var onChange: (([AirPlayDevice]) -> Void)?

    private let browser = NetServiceBrowser()
    private var services: [String: NetService] = [:]

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        browser.searchForServices(ofType: "_airplay._tcp.", inDomain: "local.")
    }

    func stop() {
        browser.stop()
        services.removeAll()
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        services[serviceID(for: service)] = service
        if !moreComing {
            publishDevices()
        }
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        services.removeValue(forKey: serviceID(for: service))
        if !moreComing {
            publishDevices()
        }
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didNotSearch errorDict: [String: NSNumber]
    ) {
        services.removeAll()
        onChange?([])
    }

    private func publishDevices() {
        let localNames = Self.localServiceNames
        var names: [String: String] = [:]

        for service in services.values {
            let name = service.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !localNames.contains(Self.normalized(name)) else { continue }
            names[Self.normalized(name)] = name
        }

        let devices = names.values
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { AirPlayDevice(id: "airplay:\($0)", name: $0) }
        onChange?(devices)
    }

    private func serviceID(for service: NetService) -> String {
        "\(service.name)|\(service.type)|\(service.domain)"
    }

    private static var localServiceNames: Set<String> {
        let names = [
            Host.current().localizedName,
            Host.current().name,
            ProcessInfo.processInfo.hostName
        ]
        return Set(names.compactMap { value in
            guard let value else { return nil }
            return normalized(value.replacingOccurrences(of: ".local", with: ""))
        })
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
