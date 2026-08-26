import SwiftUI

struct MenuPanelView: View {
    static let panelWidth: CGFloat = 308
    private static let baseHeight: CGFloat = 134
    private static let rowHeight: CGFloat = 32
    private static let maximumVisibleRows = 6

    @ObservedObject var model: VolumeModel

    static func panelHeight(outputRowCount: Int) -> CGFloat {
        let rows = min(max(outputRowCount, 1), maximumVisibleRows)
        return baseHeight + CGFloat(rows) * rowHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            volumeSlider
            Divider()
                .opacity(0.42)
                .padding(.vertical, 8)
                .padding(.horizontal, -7)
            deviceList
            Divider()
                .opacity(0.42)
                .padding(.top, 5)
                .padding(.horizontal, -7)
            footer
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(
            width: Self.panelWidth,
            height: Self.panelHeight(outputRowCount: model.visibleOutputRowCount),
            alignment: .top
        )
        .background {
            GlassBackground(material: .popover, cornerRadius: 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.5)
        }
    }

    private var header: some View {
        Text("声音")
            .font(.system(size: 15, weight: .semibold))
            .frame(height: 22, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private var volumeSlider: some View {
        HStack(spacing: 8) {
            Button {
                model.toggleMute(showHUD: false)
            } label: {
                Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.isMuted ? "取消静音" : "静音")
            .accessibilityLabel(model.isMuted ? "取消静音" : "静音")

            GlassVolumeSlider(
                value: Binding(
                    get: { Double(model.volume) },
                    set: { model.setUnifiedVolume(Float($0), showHUD: false) }
                ),
                isDragging: Binding(
                    get: { model.isVolumeSliderDragging },
                    set: { isDragging in
                        let finishedDragging = model.isVolumeSliderDragging && !isDragging
                        model.isVolumeSliderDragging = isDragging
                        if finishedDragging {
                            model.playVolumeFeedback()
                        }
                    }
                )
            )
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 20)
        }
        .frame(height: GlassVolumeSlider.controlHeight)
        .padding(.top, 4)
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("输出")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(height: 18, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(primaryOutputDevices) { device in
                        deviceRow(device)
                    }

                    groupRow

                    ForEach(secondaryOutputDevices) { device in
                        deviceRow(device)
                    }

                    ForEach(model.visibleAirPlayDevices) { device in
                        airPlayRow(device)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .frame(
            height: 18 + CGFloat(visibleRowCount) * Self.rowHeight,
            alignment: .top
        )
    }

    private var groupRow: some View {
        Button {
            model.selectPreferredGroup()
        } label: {
            rowContent(
                title: model.preferredGroupName,
                symbolName: "speaker.wave.2.fill",
                selected: model.isPreferredGroupSelected
            )
        }
        .buttonStyle(.plain)
    }

    private func deviceRow(_ device: AudioDevice) -> some View {
        Button {
            model.selectOnly(device.uid)
        } label: {
            rowContent(
                title: device.name,
                symbolName: device.symbolName,
                selected: !model.isPreferredGroupSelected && model.selectedDeviceUIDs.contains(device.uid)
            )
        }
        .buttonStyle(.plain)
    }

    private func airPlayRow(_ device: AirPlayDevice) -> some View {
        Button {
            model.openAirPlayOutput(device)
        } label: {
            rowContent(
                title: device.name,
                symbolName: "airplayaudio",
                selected: false
            )
        }
        .buttonStyle(.plain)
        .help("在系统声音设置中选择 \(device.name)")
    }

    private func rowContent(
        title: String,
        symbolName: String,
        selected: Bool
    ) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(selected ? Color.accentColor : Color.primary.opacity(0.075))
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? Color.white : Color.secondary)
            }
            .frame(width: 28, height: 28)

            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .frame(height: Self.rowHeight)
        .contentShape(Rectangle())
        .accessibilityValue(selected ? "已选择" : "")
    }

    private var footer: some View {
        Button("声音设置...") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
        .help("打开系统声音设置")
        .frame(height: 28)
    }

    private var primaryOutputDevices: [AudioDevice] {
        model.visibleOutputDevices
            .filter { ![.bluetooth, .virtual, .unknown].contains($0.kind) }
            .sorted { deviceRank($0) < deviceRank($1) }
    }

    private var secondaryOutputDevices: [AudioDevice] {
        model.visibleOutputDevices
            .filter { [.bluetooth, .virtual, .unknown].contains($0.kind) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func deviceRank(_ device: AudioDevice) -> Int {
        switch device.kind {
        case .builtIn: 0
        case .display: 1
        case .usb: 2
        case .aggregate: 3
        case .bluetooth: 4
        case .virtual: 5
        case .unknown: 6
        }
    }

    private var visibleRowCount: Int {
        min(max(model.visibleOutputRowCount, 1), Self.maximumVisibleRows)
    }
}
