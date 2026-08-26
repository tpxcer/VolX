import Foundation

struct DDCVolumeController {
    enum Backend: Equatable {
        case m1ddc(URL)
        case ddcctl(URL)
        case unavailable
    }

    let backend: Backend

    init() {
        self.backend = Self.detectBackend()
    }

    var isAvailable: Bool {
        backend != .unavailable
    }

    func setVolume(_ volume: Float, for device: AudioDevice) -> Bool {
        guard device.isBenQDisplay else { return false }
        let percent = Int((min(max(volume, 0), 1) * 100).rounded())
        switch backend {
        case let .m1ddc(url):
            return run(url, arguments: ["display", "1", "set", "volume", "\(percent)"])
        case let .ddcctl(url):
            return run(url, arguments: ["-d", "1", "-v", "\(percent)"])
        case .unavailable:
            return false
        }
    }

    func setMuted(_ muted: Bool, for device: AudioDevice, restoreVolume: Float) -> Bool {
        guard device.isBenQDisplay else { return false }
        return setVolume(muted ? 0 : restoreVolume, for: device)
    }

    private static func detectBackend() -> Backend {
        let candidates = [
            "/opt/homebrew/bin/m1ddc",
            "/usr/local/bin/m1ddc"
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return .m1ddc(URL(fileURLWithPath: path))
        }

        let ddcctlCandidates = [
            "/opt/homebrew/bin/ddcctl",
            "/usr/local/bin/ddcctl"
        ]
        if let path = ddcctlCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return .ddcctl(URL(fileURLWithPath: path))
        }
        return .unavailable
    }

    private func run(_ executable: URL, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
