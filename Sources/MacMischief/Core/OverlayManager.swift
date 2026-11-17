import AppKit
import SpriteKit

/// Borderless, transparent, click-through window floating above everything,
/// on every Space, including over full-screen apps.
final class OverlayWindow: NSPanel {
    convenience init(screen: NSScreen) { self.init(frame: screen.frame) }

    init(frame: CGRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true          // every click goes straight through
        level = .screenSaver               // above normal and floating windows
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isMovable = false
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One overlay per physical screen.
@MainActor
final class Overlay {
    let displayID: CGDirectDisplayID
    let window: OverlayWindow
    let view: SKView
    let scene: OverlayScene
    var hideInFullScreen: Bool { didSet { refresh() } }
    private var shown = false
    /// The 3D layer lives in its own transparent window attached directly
    /// *below* the SpriteKit window (SpriteKit stays the content view, which
    /// is the only arrangement where it reliably presents on screen).
    private var stage: Stage3D?
    private var stageWindow: OverlayWindow?
    private var stageUsers = 0

    init(screen: NSScreen, isPrimary: Bool, hideInFullScreen: Bool) {
        displayID = screen.displayID
        self.hideInFullScreen = hideInFullScreen
        window = OverlayWindow(screen: screen)
        view = SKView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.shouldCullNonVisibleNodes = true
        view.preferredFramesPerSecond = 60
        view.autoresizingMask = [.width, .height]
        scene = OverlayScene(screenFrame: screen.frame,
                             floorY: screen.floorY,
                             displayID: displayID,
                             isPrimary: isPrimary)
        view.presentScene(scene)
        view.isPaused = true
        window.contentView = view

        scene.acquireStage3D = { [weak self] in self?.acquireStage() }
        scene.releaseStage3D = { [weak self] in self?.releaseStage() }
    }

    /// 3D view under the SpriteKit overlay, created on demand for 3D mischiefs.
    private func acquireStage() -> Stage3D {
        if stage == nil {
            let s = Stage3D(size: window.frame.size)
            let w = OverlayWindow(frame: window.frame)
            w.contentView = s.view
            w.alphaValue = window.alphaValue
            window.addChildWindow(w, ordered: .below)
            if !shown { w.orderOut(nil) }
            s.setRunning(shown)
            stage = s
            stageWindow = w
            scene.renderHook = { [weak s] in s?.render() }
            scheduleDebugCapture()
        }
        stageUsers += 1
        return stage!
    }

    /// Developer aid: `defaults write <bundle-id> debugCapture -bool true` makes the
    /// app save frames of its 3D layer into its sandbox temp folder.
    private func scheduleDebugCapture() {
        guard UserDefaults.standard.bool(forKey: "debugCapture") else { return }
        for (i, delay) in [4.0, 9.0, 15.0].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let stage = self.stage else { return }
                    stage.captureNextFrame = { image in
                        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("stage-\(i).png")
                        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
                    }
                }
            }
        }
    }

    private func releaseStage() {
        stageUsers -= 1
        guard stageUsers <= 0, let s = stage else { return }
        stageUsers = 0
        s.setRunning(false)
        if let w = stageWindow {
            window.removeChildWindow(w)
            w.orderOut(nil)
            w.close()
        }
        stageWindow = nil
        scene.renderHook = nil
        stage = nil
    }

    func apply(_ snapshot: WindowSnapshot) {
        let screen = NSScreen.screens.first { $0.displayID == displayID }
        scene.updateGeometry(snapshot: snapshot, floorY: screen?.floorY ?? scene.geometry.floorY)
        refresh()
    }

    func refresh() {
        let hiddenForFullScreen = hideInFullScreen && scene.geometry.isFullScreenCovered
        let wantShown = scene.hasLayers && !hiddenForFullScreen
        if UserDefaults.standard.bool(forKey: "debugOverlay"), wantShown != shown {
            OverlayScene.debugWrite("refresh wantShown=\(wantShown) layers=\(scene.hasLayers) full=\(hiddenForFullScreen) viewFrame=\(NSStringFromRect(view.frame))")
        }
        guard wantShown != shown else { return }
        shown = wantShown
        if wantShown {
            view.isPaused = false
            stage?.setRunning(true)
            window.alphaValue = 0
            stageWindow?.alphaValue = 0
            window.orderFrontRegardless()
            if let w = stageWindow, w.parent == nil { window.addChildWindow(w, ordered: .below) }
            stageWindow?.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                window.animator().alphaValue = 1
                stageWindow?.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                window.animator().alphaValue = 0
                stageWindow?.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.shown else { return }
                    self.view.isPaused = true
                    self.stage?.setRunning(false)
                    self.stageWindow?.orderOut(nil)
                    self.window.orderOut(nil)
                }
            })
        }
    }

    func close() {
        shown = false
        scene.removeAllLayers()
        view.isPaused = true
        stage?.setRunning(false)
        if let w = stageWindow {
            window.removeChildWindow(w)
            w.orderOut(nil)
            w.close()
        }
        window.orderOut(nil)
        window.close()
    }
}

/// Owns the overlays and turns mischiefs on and off across all screens.
@MainActor
final class OverlayManager {
    private var overlays: [Overlay] = []
    private(set) var active: [any Mischief] = []
    private var lastSnapshot: WindowSnapshot = .empty

    var hideInFullScreen: Bool {
        didSet { overlays.forEach { $0.hideInFullScreen = hideInFullScreen } }
    }

    init() {
        hideInFullScreen = Settings.hideInFullScreen
        WindowTracker.shared.onChange = { [weak self] snapshot in self?.apply(snapshot) }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { WindowTracker.shared.nudge() }
            }
        }
    }

    func isActive(_ mischief: any Mischief) -> Bool {
        active.contains { $0 === mischief }
    }

    /// Runs exactly one mischief (or none). Anything else running is retired first.
    func activateOnly(_ mischief: (any Mischief)?) {
        for other in active where other !== mischief { setActive(other, false) }
        if let mischief { setActive(mischief, true) }
    }

    func setActive(_ mischief: any Mischief, _ on: Bool) {
        if on {
            guard !isActive(mischief) else { return }
            active.append(mischief)
            if overlays.isEmpty { buildOverlays() }
            for overlay in overlays { attach(mischief, to: overlay) }
            WindowTracker.shared.start()
        } else {
            guard isActive(mischief) else { return }
            active.removeAll { $0 === mischief }
            for overlay in overlays {
                overlay.scene.retireLayer(id: mischief.id) { [weak self, weak overlay] in
                    overlay?.refresh()
                    self?.cleanUpIfIdle()
                }
            }
        }
    }

    private func attach(_ mischief: any Mischief, to overlay: Overlay) {
        if let layer = mischief.makeLayer(for: overlay.scene) {
            overlay.scene.addLayer(layer)
        }
        overlay.refresh()
    }

    private func buildOverlays() {
        overlays = NSScreen.screens.enumerated().map { index, screen in
            Overlay(screen: screen, isPrimary: index == 0, hideInFullScreen: hideInFullScreen)
        }
        for overlay in overlays { overlay.apply(lastSnapshot) }
    }

    private func cleanUpIfIdle() {
        guard active.isEmpty, overlays.allSatisfy({ !$0.scene.hasLayers }) else { return }
        WindowTracker.shared.stop()
        overlays.forEach { $0.close() }
        overlays.removeAll()
    }

    private func screensChanged() {
        guard !overlays.isEmpty else { return }
        overlays.forEach { $0.close() }
        overlays.removeAll()
        guard !active.isEmpty else { return }
        buildOverlays()
        for mischief in active {
            for overlay in overlays { attach(mischief, to: overlay) }
        }
    }

    private func apply(_ snapshot: WindowSnapshot) {
        lastSnapshot = snapshot
        for overlay in overlays { overlay.apply(snapshot) }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Height of the "ground" in screen-local points: the top of a bottom Dock, else 0.
    var floorY: CGFloat { max(0, visibleFrame.minY - frame.minY) }
}
