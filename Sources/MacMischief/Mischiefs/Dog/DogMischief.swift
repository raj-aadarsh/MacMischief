import SpriteKit

final class DogMischief: Mischief {
    let id = "dog"
    let title = "Pomsky"
    let symbolName = "dog.fill"
    let emoji = "🐺"
    let tagline = "Fluffy husky-pom! Sniffs, digs, wags & chases your cursor."
    let colors: [UInt32] = [0x8FB8FF, 0x5A6478]

    func makeLayer(for scene: OverlayScene) -> MischiefLayer? {
        guard scene.isPrimary else { return nil }
        let body: any PetBody
        if let stage = scene.acquireStage3D?() ?? nil {
            body = Pet3DNode(species: .dog3D, stage: stage, release: { [weak scene] in scene?.releaseStage3D?() })
        } else {
            body = DogNode()
        }
        return PetLayer(mischiefID: id, overlay: scene, pet: body, personality: .dog)
    }
}

extension PetPersonality {
    /// Energetic, friendly, nosy. Follows the cursor everywhere; rolls over for belly rubs.
    static let dog = PetPersonality(
        words: ["woof!", "arf!", "bork!", "yip yip!", "woof woof!", "awoo~"],
        pettedWords: ["belly rub!! ♡", "*happy wiggle*", "arf ♡"],
        weights: [.walk: 20, .sniff: 14, .idle: 6, .sit: 9, .dig: 7, .playBow: 6, .speak: 6, .scratch: 5,
                  .shake: 3, .rollOver: 3, .beg: 3, .stretch: 3, .sleep: 3, .chaseTail: 4, .zoomies: 4,
                  .jump: 16, .hearts: 2],
        cursorPlay: .chaseAndBeg,
        walkSpeed: 55...80,
        pettedChoice: .rollOver,
        sleepy: false
    )
}
