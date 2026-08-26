import SwiftUI

struct GlassVolumeSlider: View {
    static let controlHeight: CGFloat = 28
    static let expandedThumbWidth: CGFloat = 28
    static let expandedThumbHeight: CGFloat = 22

    @Binding var value: Double
    @Binding var isDragging: Bool

    private let trackHeight: CGFloat = 6
    private let restingThumbDiameter: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, Self.expandedThumbWidth)
            let position = Self.thumbPosition(for: value, width: width)

            ZStack(alignment: .leading) {
                track(width: width, position: position)
                thumb
                    .frame(
                        width: isDragging ? Self.expandedThumbWidth : restingThumbDiameter,
                        height: isDragging ? Self.expandedThumbHeight : restingThumbDiameter
                    )
                    .position(x: position, y: Self.controlHeight / 2)
                if isDragging {
                    track(width: width, position: position)
                        .opacity(0.88)
                        .mask {
                            Capsule()
                                .frame(
                                    width: Self.expandedThumbWidth,
                                    height: Self.expandedThumbHeight
                                )
                                .position(x: position, y: Self.controlHeight / 2)
                        }
                    Capsule()
                        .stroke(Color.primary.opacity(0.24), lineWidth: 0.65)
                        .frame(
                            width: Self.expandedThumbWidth,
                            height: Self.expandedThumbHeight
                        )
                        .position(x: position, y: Self.controlHeight / 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            withAnimation(.snappy(duration: 0.16)) {
                                isDragging = true
                            }
                        }
                        value = Self.value(at: gesture.location.x, width: width)
                    }
                    .onEnded { _ in
                        withAnimation(.snappy(duration: 0.18)) {
                            isDragging = false
                        }
                    }
            )
        }
        .frame(height: Self.controlHeight)
        .onDisappear {
            isDragging = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("音量")
        .accessibilityValue("\(Int((value * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(value + 0.0625, 1)
            case .decrement:
                value = max(value - 0.0625, 0)
            @unknown default:
                break
            }
        }
    }

    private func track(width: CGFloat, position: CGFloat) -> some View {
        let inset = Self.expandedThumbWidth / 2
        let trackWidth = max(width - Self.expandedThumbWidth, 0)
        let filledWidth = max(position - inset, 0)

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.10))
                .frame(width: trackWidth, height: trackHeight)
                .offset(x: inset)
            Capsule()
                .fill(Color.accentColor)
                .frame(width: filledWidth, height: trackHeight)
                .offset(x: inset)
        }
        .frame(width: width, height: Self.controlHeight, alignment: .leading)
    }

    @ViewBuilder
    private var thumb: some View {
        if isDragging {
            if #available(macOS 26.0, *) {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.clear.interactive(), in: Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 2.25, y: 1)
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.58), lineWidth: 0.75)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 2.5, y: 1)
            }
        } else {
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    Circle()
                        .stroke(Color(nsColor: .separatorColor).opacity(0.70), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.75)
        }
    }

    static func value(at x: CGFloat, width: CGFloat) -> Double {
        let inset = expandedThumbWidth / 2
        let travel = max(width - expandedThumbWidth, 1)
        return min(max(Double((x - inset) / travel), 0), 1)
    }

    static func thumbPosition(for value: Double, width: CGFloat) -> CGFloat {
        let inset = expandedThumbWidth / 2
        let travel = max(width - expandedThumbWidth, 1)
        return inset + CGFloat(min(max(value, 0), 1)) * travel
    }
}
