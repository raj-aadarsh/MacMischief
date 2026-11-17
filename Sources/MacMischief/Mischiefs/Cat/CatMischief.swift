import SpriteKit

final class CatMischief: Mischief {
    let id = "cat"
    let title = "Munchkin Cat"
    let symbolName = "cat.fill"
    let emoji = "🐈"
    let tagline = "Short legs, big attitude. Naps, zoomies & cursor hunting."
    let colors: [UInt32] = [0xFFB347, 0xFF6F61]

    func makeLayer(for scene: OverlayScene) -> MischiefLayer? {
        guard scene.isPrimary else { return nil }
        let body: any PetBody
        if let stage = scene.acquireStage3D?() ?? nil {
            body = Pet3DNode(species: .cat3D, stage: stage, release: { [weak scene] in scene?.releaseStage3D?() })
        } else {
            body = CatNode()
        }
        return PetLayer(mischiefID: id, overlay: scene, pet: body, personality: .cat)
    }
}

extension PetPersonality {
    /// Independent, sleepy, a hunter. Grooms a lot; purrs when petted.
    static let cat = PetPersonality(
        words: ["meow!", "mrrp?", "prrr~", "nya~", "mew!"],
        pettedWords: ["prrrr ♡", "purr purr", "mrrr~ ♡"],
        weights: [.walk: 28, .idle: 9, .sit: 16, .groom: 10, .stretch: 5, .sleep: 6, .speak: 4,
                  .hearts: 2, .chaseTail: 2, .backflip: 2, .zoomies: 2.5, .jump: 18],
        cursorPlay: .stalkAndPounce,
        walkSpeed: 45...68,
        pettedChoice: .hearts,
        sleepy: true
    )
}
