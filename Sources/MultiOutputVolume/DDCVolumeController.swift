// Intentionally disabled: audio UID -> physical display mapping is not available.
// Never guess display 1 or launch blocking third-party processes on the UI thread.
struct DDCVolumeController {
    var isAvailable: Bool { false }
    func setVolume(_ volume: Float, for device: AudioDevice) -> Bool { false }
    func setMuted(_ muted: Bool, for device: AudioDevice, restoreVolume: Float) -> Bool { false }
}
