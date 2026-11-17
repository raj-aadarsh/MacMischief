import SpriteKit

/// A toggleable desktop effect. Each mischief only *draws* — it never receives
/// input and never interacts with other apps.
@MainActor
protocol Mischief: AnyObject {
    var id: String { get }
    var title: String { get }
    /// SF Symbol shown in the menu bar while this mischief is running.
    var symbolName: String { get }
    var emoji: String { get }
    var tagline: String { get }
    /// Two hex colours for the menu card gradient.
    var colors: [UInt32] { get }
    /// Build the visual layer for one screen. Return nil to skip that screen.
    func makeLayer(for scene: OverlayScene) -> MischiefLayer?
}

/// The per-screen visual node of a mischief.
class MischiefLayer: SKNode {
    let mischiefID: String
    weak var overlay: OverlayScene?
    var isRetiring = false

    init(mischiefID: String, overlay: OverlayScene) {
        self.mischiefID = mischiefID
        self.overlay = overlay
        super.init()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) not supported") }

    /// Frames per second this layer needs right now. Calm moments can ask for
    /// fewer frames to save battery.
    var preferredFPS: Int { 60 }

    /// Called every frame with the elapsed time in seconds.
    func update(dt: CGFloat) {}

    /// Called whenever the window layout on this screen changes.
    func geometryDidChange() {}

    /// Animate out, then call completion. Default: disappear immediately.
    func dismiss(completion: @escaping () -> Void) { completion() }

    /// Last chance to clean up resources outside SpriteKit (e.g. 3D nodes).
    func willRemove() {}
}

@MainActor
enum MischiefRegistry {
    static let all: [any Mischief] = [CatMischief(), DogMischief(), HeroMischief(), SnowMischief(), LeavesMischief()]
}
