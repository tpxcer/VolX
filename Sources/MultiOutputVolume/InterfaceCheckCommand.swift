import AppKit
import SwiftUI

@MainActor
enum InterfaceCheckCommand {
    static func run() -> Bool {
        var failures = 0

        let hud = VolumeHUDController.makeContentView(
            title: "显示器 + 音箱",
            volume: 0.35,
            isMuted: false
        )
        hud.layoutSubtreeIfNeeded()
        check("HUD width", abs(hud.fittingSize.width - 300) <= 1, failures: &failures)
        check("HUD height", abs(hud.fittingSize.height - 72) <= 1, failures: &failures)
        check("HUD glass", containsNativeGlassView(in: hud), failures: &failures)
        check(
            "HUD host clips glass corners",
            hud.layer?.masksToBounds == true
                && abs((hud.layer?.cornerRadius ?? 0) - VolumeHUDController.cornerRadius) <= 0.1,
            failures: &failures
        )
        check(
            "HUD native glass clips corners",
            nativeGlassViews(in: hud).allSatisfy {
                $0.layer?.masksToBounds == true
                    && abs(($0.layer?.cornerRadius ?? 0) - VolumeHUDController.cornerRadius) <= 0.1
            },
            failures: &failures
        )

        let menu = NSHostingView(rootView: MenuPanelView(model: VolumeModel()))
        menu.layoutSubtreeIfNeeded()
        check("menu width", abs(menu.fittingSize.width - 308) <= 1, failures: &failures)
        check("menu empty height", abs(menu.fittingSize.height - 166) <= 1, failures: &failures)
        check("menu native five-row height", abs(MenuPanelView.panelHeight(outputRowCount: 5) - 294) <= 1, failures: &failures)
        check("dual-output balance fits panel", MenuPanelView.panelHeight(outputRowCount: 5, balanceCount: 2) == 366, failures: &failures)
        for master: Float in [0, 0.2, 0.4, 0.5, 1] {
            check("center balance preserves native percentage at \(master)",
                  VolumeModel.balancedVolume(master, balance: 0, isDisplay: true) == master
                    && VolumeModel.balancedVolume(master, balance: 0, isDisplay: false) == master,
                  failures: &failures)
            for balance: Float in [-1, -0.5, 0, 0.5, 1] {
                let display = VolumeModel.balancedVolume(master, balance: balance, isDisplay: true)
                let speaker = VolumeModel.balancedVolume(master, balance: balance, isDisplay: false)
                check("balance attenuates without boosting at \(master), \(balance)",
                      display >= 0 && display <= master && speaker >= 0 && speaker <= master
                        && max(display, speaker) == master, failures: &failures)
            }
        }
        check("balance toward speaker reduces display only",
              abs(VolumeModel.balancedVolume(0.2, balance: 0.5, isDisplay: true) - 0.1) < 0.001
                && VolumeModel.balancedVolume(0.2, balance: 0.5, isDisplay: false) == 0.2,
              failures: &failures)
        let suite = "VolX.InterfaceCheck.\(UUID().uuidString)"
        check("balance toward first device reduces second device only",
              VolumeModel.balancedVolume(0.2, balance: -0.5, isDisplay: true) == 0.2
                && abs(VolumeModel.balancedVolume(0.2, balance: -0.5, isDisplay: false) - 0.1) < 0.001,
              failures: &failures)
        if let defaults = UserDefaults(suiteName: suite) {
            defer { defaults.removePersistentDomain(forName: suite) }
            // No devices are loaded: exercise persistence and mute without hardware writes.
            let calibration = VolumeModel(defaults: defaults)
            calibration.setUnifiedVolume(0.2, showHUD: false)
            calibration.setOutputBalance(0.5)
            let reloaded = VolumeModel(defaults: defaults)
            check("balance survives relaunch without changing master",
                  reloaded.outputBalance == 0.5 && reloaded.volume == 0.2, failures: &failures)
            calibration.toggleMute(showHUD: false)
            calibration.setOutputBalance(0.75)
            let muted = VolumeModel(defaults: defaults)
            check("calibration while muted stays silent after relaunch",
                  muted.isMuted && muted.volume == 0 && muted.outputBalance == 0.75, failures: &failures)
            muted.toggleMute(showHUD: false)
            check("unmute restores master and calibration after relaunch",
                  !muted.isMuted && muted.volume == 0.2 && muted.outputBalance == 0.75, failures: &failures)
            muted.setOutputBalance(0)
            check("balance reset is saved", VolumeModel(defaults: defaults).outputBalance == 0, failures: &failures)
        } else {
            check("isolated calibration preferences available", false, failures: &failures)
        }
        check("menu glass", containsNativeGlassView(in: menu), failures: &failures)

        let statusIcon = StatusBarIcon.make(volume: 0.5, isMuted: false)
        check("status icon is a template image", statusIcon.isTemplate, failures: &failures)
        check("status icon width", abs(statusIcon.size.width - 26) <= 0.1, failures: &failures)
        check("status icon height", abs(statusIcon.size.height - 18) <= 0.1, failures: &failures)
        check(
            "status icon uses one pale maximum-volume layer",
            StatusBarIcon.maximumSymbolName == "speaker.wave.3"
                && StatusBarIcon.maximumLayerOpacity <= 0.1,
            failures: &failures
        )
        check(
            "status icon uses variable current-volume layer",
            StatusBarIcon.currentSymbolName == "speaker.wave.3.fill"
                && StatusBarIcon.currentLayerPasses >= 2
                && StatusBarIcon.normalizedLevel(volume: 0.15, isMuted: false)
                    < StatusBarIcon.normalizedLevel(volume: 0.85, isMuted: false),
            failures: &failures
        )
        check(
            "status icon keeps fixed content geometry",
            StatusBarIcon.contentRect(
                in: NSRect(origin: .zero, size: StatusBarIcon.size),
                sourceSize: NSSize(width: 26, height: 18)
            ).size == StatusBarIcon.size,
            failures: &failures
        )
        check(
            "status icon mute clears current volume layer",
            StatusBarIcon.normalizedLevel(volume: 0.85, isMuted: true) == 0,
            failures: &failures
        )
        check("menu title uses app name", MenuPanelView.panelTitle == "VolX", failures: &failures)

        let sliderWidth: CGFloat = 220
        let sliderInset = GlassVolumeSlider.expandedThumbWidth / 2
        check(
            "dragging slider thumb is a horizontal capsule",
            GlassVolumeSlider.expandedThumbWidth > GlassVolumeSlider.expandedThumbHeight,
            failures: &failures
        )
        check(
            "resting slider thumb is a horizontal capsule",
            GlassVolumeSlider.restingThumbWidth > GlassVolumeSlider.restingThumbHeight,
            failures: &failures
        )
        check(
            "resting slider thumb uses a light fill",
            GlassVolumeSlider.restingThumbFillOpacity >= 0.9,
            failures: &failures
        )
        check(
            "dragging slider glass stays transparent",
            GlassVolumeSlider.draggingGlassOpacity <= 0.6,
            failures: &failures
        )
        check(
            "dragging slider magnifies track through glass",
            GlassVolumeSlider.refractedTrackScale > 1,
            failures: &failures
        )
        check(
            "glass slider left edge maps to zero",
            GlassVolumeSlider.value(at: sliderInset, width: sliderWidth) == 0,
            failures: &failures
        )
        check(
            "glass slider midpoint maps to half",
            abs(GlassVolumeSlider.value(at: sliderWidth / 2, width: sliderWidth) - 0.5) < 0.001,
            failures: &failures
        )
        check(
            "glass slider right edge maps to one",
            GlassVolumeSlider.value(at: sliderWidth - sliderInset, width: sliderWidth) == 1,
            failures: &failures
        )

        let anchor = NSRect(x: 900, y: 1050, width: 24, height: 24)
        let origin = VolumeHUDController.origin(
            panelSize: NSSize(width: 300, height: 72),
            anchorRect: anchor,
            visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1050)
        )
        check(
            "HUD left edge aligns with status item",
            abs(origin.x - anchor.minX) <= 1 && origin.y < anchor.minY,
            failures: &failures
        )

        let panelOrigin = StatusBarController.panelOrigin(
            panelSize: NSSize(width: 308, height: 294),
            anchorRect: anchor,
            visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1050)
        )
        check(
            "menu panel left edge aligns with status item",
            abs(panelOrigin.x - anchor.minX) <= 1 && panelOrigin.y < anchor.minY,
            failures: &failures
        )

        check(
            "global monitor suppresses custom HUD",
            !VolumeModel.shouldShowCustomHUD(for: .globalMonitor),
            failures: &failures
        )
        check(
            "output selection suppresses custom HUD",
            !VolumeModel.outputSelectionShowsHUD,
            failures: &failures
        )
        check(
            "exclusive hot-key paths show custom HUD",
            VolumeModel.shouldShowCustomHUD(for: .eventTap)
                && VolumeModel.shouldShowCustomHUD(for: .carbon),
            failures: &failures
        )
        check(
            "global monitor suppresses duplicate volume feedback",
            !VolumeModel.shouldPlayVolumeFeedback(for: .globalMonitor),
            failures: &failures
        )
        check(
            "exclusive hot-key paths play volume feedback",
            VolumeModel.shouldPlayVolumeFeedback(for: .eventTap)
                && VolumeModel.shouldPlayVolumeFeedback(for: .carbon),
            failures: &failures
        )

        let builtIn = AudioDevice(
            id: 1,
            uid: "built-in",
            name: "Mac mini扬声器",
            manufacturer: "Apple Inc.",
            kind: .builtIn,
            outputChannels: 2,
            canSetVolume: true,
            canSetMute: true
        )
        let display = AudioDevice(
            id: 2,
            uid: "display",
            name: "BenQ MA270UP",
            manufacturer: "BNQ",
            kind: .display,
            outputChannels: 2,
            canSetVolume: false,
            canSetMute: false
        )
        let usb = AudioDevice(
            id: 3,
            uid: "usb",
            name: "CX31993 384Khz HIFI AUDIO",
            manufacturer: "TTGK",
            kind: .usb,
            outputChannels: 2,
            canSetVolume: true,
            canSetMute: true
        )
        let aggregate = AudioDevice(
            id: 4,
            uid: "aggregate",
            name: "显示器+音箱",
            manufacturer: "Apple Inc.",
            kind: .aggregate,
            outputChannels: 2,
            canSetVolume: false,
            canSetMute: false,
            aggregateSubDeviceUIDs: [display.uid, usb.uid]
        )
        let testDevices = [builtIn, display, usb, aggregate]
        check(
            "system single output maps to one VolX device",
            VolumeModel.selectionForSystemOutput(uid: builtIn.uid, devices: testDevices) == [builtIn.uid],
            failures: &failures
        )
        check(
            "system aggregate maps to preferred VolX group",
            VolumeModel.selectionForSystemOutput(uid: aggregate.uid, devices: testDevices) == [display.uid, usb.uid],
            failures: &failures
        )
        var otherPair = aggregate
        otherPair.aggregateSubDeviceUIDs = [usb.uid, builtIn.uid]
        check("USB and Mac pair excludes display", VolumeModel.selectionForSystemOutput(
            uid: otherPair.uid, devices: [builtIn, display, usb, otherPair]
        ) == [usb.uid, builtIn.uid], failures: &failures)

        print(failures == 0 ? "INTERFACE_RESULT=PASS" : "INTERFACE_RESULT=FAIL failures=\(failures)")
        return failures == 0
    }

    private static func check(_ name: String, _ passed: Bool, failures: inout Int) {
        if passed {
            print("PASS \(name)")
        } else {
            failures += 1
            print("FAIL \(name)")
        }
    }

    private static func containsNativeGlassView(in view: NSView) -> Bool {
        if #available(macOS 26.0, *), view is NSGlassEffectView {
            return true
        }
        if view is NSVisualEffectView {
            return true
        }
        return view.subviews.contains { containsNativeGlassView(in: $0) }
    }

    private static func nativeGlassViews(in view: NSView) -> [NSView] {
        var matches: [NSView] = []
        if #available(macOS 26.0, *), view is NSGlassEffectView {
            matches.append(view)
        } else if view is NSVisualEffectView {
            matches.append(view)
        }
        return matches + view.subviews.flatMap { nativeGlassViews(in: $0) }
    }
}
