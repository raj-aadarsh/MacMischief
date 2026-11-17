import AppKit
import SpriteKit

/// A transparent full-screen SpriteKit scene. Scene coordinates = points from the
/// bottom-left corner of its screen.
final class OverlayScene: SKScene {
    let displayID: CGDirectDisplayID
    let isPrimary: Bool
    private(set) var screenFrame: CGRect
    private(set) var geometry: SceneGeometry
    private var layers: [MischiefLayer] = []
    private var lastUpdate: TimeInterval?
    private var fpsCheckCountdown = 0
    private var appliedFPS = 0

    /// Used by the snapshot renderer to fake the cursor position.
    var mouseOverride: CGPoint?

    /// Hooks to the overlay's shared 3D stage (for 3D characters).
    var acquireStage3D: (() -> Stage3D?)?
    var releaseStage3D: (() -> Void)?
    /// Called once per frame after all mischief updates (renders the 3D layer).
    var renderHook: (() -> Void)?

    override func didFinishUpdate() {
        renderHook?()
    }

    init(screenFrame: CGRect, floorY: CGFloat, displayID: CGDirectDisplayID, isPrimary: Bool) {
        self.screenFrame = screenFrame
        self.displayID = displayID
        self.isPrimary = isPrimary
        geometry = SceneGeometry(size: screenFrame.size, floorY: floorY)
        super.init(size: screenFrame.size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        anchorPoint = .zero
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) not supported") }

    var hasLayers: Bool { !layers.isEmpty }

    var mouseLocation: CGPoint {
        if let mouseOverride { return mouseOverride }
        let m = NSEvent.mouseLocation
        return CGPoint(x: m.x - screenFrame.minX, y: m.y - screenFrame.minY)
    }

    func addLayer(_ layer: MischiefLayer) {
        addChild(layer)
        layers.append(layer)
        layer.geometryDidChange()
    }

    func retireLayer(id: String, completion: @escaping () -> Void) {
        guard let layer = layers.first(where: { $0.mischiefID == id && !$0.isRetiring }) else {
            completion()
            return
        }
        layer.isRetiring = true
        layer.dismiss { [weak self, weak layer] in
            guard let self, let layer else { return }
            layer.willRemove()
            layer.removeFromParent()
            self.layers.removeAll { $0 === layer }
            completion()
        }
    }

    func removeAllLayers() {
        layers.forEach { $0.willRemove(); $0.removeFromParent() }
        layers.removeAll()
    }

    func updateGeometry(snapshot: WindowSnapshot, floorY: CGFloat) {
        geometry = SceneGeometry(snapshot: snapshot, screenFrame: screenFrame, floorY: floorY)
        for layer in layers { layer.geometryDidChange() }
    }

    override func update(_ currentTime: TimeInterval) {
        let dt: CGFloat
        if let last = lastUpdate {
            dt = CGFloat(min(max(currentTime - last, 0), 1.0 / 20.0))
        } else {
            dt = 1.0 / 60.0
        }
        lastUpdate = currentTime
        step(dt)
        adaptFrameRate()
    }

    /// Runs only as fast as the current animation needs (and slower in Low Power Mode).
    private func adaptFrameRate() {
        fpsCheckCountdown -= 1
        guard fpsCheckCountdown <= 0, let view else { return }
        fpsCheckCountdown = 20
        var want = layers.map(\.preferredFPS).max() ?? 30
        if ProcessInfo.processInfo.isLowPowerModeEnabled { want = max(20, want / 2) }
        if want != appliedFPS {
            appliedFPS = want
            view.preferredFramesPerSecond = want
        }
    }

    func step(_ dt: CGFloat) {
        for layer in layers { layer.update(dt: dt) }
    }
}
