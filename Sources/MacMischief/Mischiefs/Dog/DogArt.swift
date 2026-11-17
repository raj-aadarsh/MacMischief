import SpriteKit

/// All puppy artwork, drawn as vector shapes (golden pup, cream socks, red collar).
@MainActor
enum DogArt {
    static let furTop = rgb(0xD9954C)
    static let fur = rgb(0xEBB46E)
    static let furLight = rgb(0xF6D29E)
    static let patch = rgb(0xC07A3A)
    static let ear = rgb(0x9A5A2A)
    static let earLight = rgb(0xB8743C)
    static let cream = rgb(0xFFF3E1)
    static let outline = rgb(0x5E3A1E, 0.85)
    static let noseColor = rgb(0x2A201C)
    static let tongueColor = rgb(0xFF7F95)

    static let furColor = SKColor.hex(0xE6AC66)
    static let outlineColor = SKColor.hex(0x5E3A1E, 0.85)

    static let body: SKTexture = TextureFactory.make(CGSize(width: 58, height: 31)) { ctx in
        let shape = ellipse(2, 3, 54, 25)
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let grad = CGGradient(colorsSpace: nil, colors: [furTop, fur, furLight] as CFArray, locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 28), end: CGPoint(x: 0, y: 6), options: [.drawsAfterEndLocation])
        // A darker saddle patch for character
        ctx.paint(ellipse(14, 17, 24, 15), fill: rgb(0xC07A3A, 0.55))
        ctx.paint(ellipse(4, 8, 20, 17), fill: rgb(0xFFFFFF, 0.07))
        ctx.paint(ellipse(10, -5, 40, 15), fill: cream)
        ctx.restoreGState()
        ctx.paint(shape, stroke: outline, width: 1.1)
        let tuft = polygon([CGPoint(x: 44, y: 4.5), CGPoint(x: 56, y: 7), CGPoint(x: 53.5, y: 9.5),
                            CGPoint(x: 57, y: 12), CGPoint(x: 53, y: 14), CGPoint(x: 54.5, y: 17.5), CGPoint(x: 48, y: 16.5)])
        ctx.paint(tuft, fill: cream)
        ctx.paint(tuft, stroke: rgb(0x5E3A1E, 0.4), width: 0.7)
    }

    /// Front-facing chibi puppy head in a 50x44 canvas (centre 25,22).
    static let head: SKTexture = TextureFactory.make(CGSize(width: 50, height: 44)) { drawHead($0) }

    static func drawHead(_ ctx: CGContext) {
        // Little hair tuft on top
        let tuft = CGMutablePath()
        tuft.move(to: CGPoint(x: 22.5, y: 33))
        tuft.addQuadCurve(to: CGPoint(x: 26.8, y: 38.6), control: CGPoint(x: 21.8, y: 38.2))
        tuft.addQuadCurve(to: CGPoint(x: 25.4, y: 36), control: CGPoint(x: 27.4, y: 36.6))
        tuft.addQuadCurve(to: CGPoint(x: 28, y: 33), control: CGPoint(x: 26.8, y: 34.6))
        tuft.closeSubpath()
        ctx.paint(tuft, fill: furTop)
        ctx.paint(tuft, stroke: outline, width: 1)

        let skull = ellipse(9, 6, 32, 28.5)
        let cheeks = ellipse(7.5, 4.5, 15, 13).union(ellipse(27.5, 4.5, 15, 13))
        let shape = skull.union(cheeks)

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let grad = CGGradient(colorsSpace: nil, colors: [furTop, fur, furLight] as CFArray, locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 34), end: CGPoint(x: 0, y: 6), options: [.drawsAfterEndLocation])
        // Cream blaze down the forehead into a round button muzzle
        let blaze = CGMutablePath()
        blaze.move(to: CGPoint(x: 22.4, y: 35))
        blaze.addQuadCurve(to: CGPoint(x: 21, y: 15), control: CGPoint(x: 21.5, y: 22))
        blaze.addLine(to: CGPoint(x: 29, y: 15))
        blaze.addQuadCurve(to: CGPoint(x: 27.6, y: 35), control: CGPoint(x: 28.5, y: 22))
        blaze.closeSubpath()
        ctx.paint(blaze, fill: cream)
        ctx.paint(ellipse(15.5, 3.5, 19, 14), fill: cream)
        ctx.restoreGState()
        ctx.paint(shape, stroke: outline, width: 1.1)

        // Eyebrow dots (they make the face so expressive)
        ctx.paint(ellipse(16.2, 25.4, 4, 2.4), fill: rgb(0x9A5A2A, 0.85))
        ctx.paint(ellipse(29.8, 25.4, 4, 2.4), fill: rgb(0x9A5A2A, 0.85))

        // Blush
        ctx.paint(ellipse(10.5, 10.5, 6, 3), fill: rgb(0xFF8FA0, 0.5))
        ctx.paint(ellipse(33.5, 10.5, 6, 3), fill: rgb(0xFF8FA0, 0.5))

        // Heart-ish button nose with a shine
        let nose = CGMutablePath()
        nose.move(to: CGPoint(x: 25, y: 11.4))
        nose.addCurve(to: CGPoint(x: 21.2, y: 15), control1: CGPoint(x: 23.4, y: 12.2), control2: CGPoint(x: 21.2, y: 13.2))
        nose.addCurve(to: CGPoint(x: 25, y: 16.6), control1: CGPoint(x: 21.2, y: 16.4), control2: CGPoint(x: 23.4, y: 16.6))
        nose.addCurve(to: CGPoint(x: 28.8, y: 15), control1: CGPoint(x: 26.6, y: 16.6), control2: CGPoint(x: 28.8, y: 16.4))
        nose.addCurve(to: CGPoint(x: 25, y: 11.4), control1: CGPoint(x: 28.8, y: 13.2), control2: CGPoint(x: 26.6, y: 12.2))
        ctx.paint(nose, fill: noseColor)
        ctx.paint(ellipse(22.6, 14.4, 2.6, 1.4), fill: rgb(0xFFFFFF, 0.7))

        // "w" smile
        let mouth = CGMutablePath()
        mouth.move(to: CGPoint(x: 25, y: 11.4))
        mouth.addLine(to: CGPoint(x: 25, y: 9.8))
        mouth.move(to: CGPoint(x: 21.2, y: 9.6))
        mouth.addQuadCurve(to: CGPoint(x: 25, y: 9.8), control: CGPoint(x: 23, y: 7.6))
        mouth.addQuadCurve(to: CGPoint(x: 28.8, y: 9.6), control: CGPoint(x: 27, y: 7.6))
        ctx.paint(mouth, stroke: outline, width: 0.95)

        // Muzzle freckles
        for (x, y) in [(19.6, 12.2), (18.6, 10.6), (30.4, 12.2), (31.4, 10.6)] as [(CGFloat, CGFloat)] {
            ctx.paint(ellipse(x - 0.4, y - 0.4, 0.8, 0.8), fill: rgb(0x5E3A1E, 0.45))
        }
    }

    /// Floppy ear, hanging down from its anchor at the top.
    static let floppyEar: SKTexture = TextureFactory.make(CGSize(width: 12, height: 19)) { ctx in
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 3, y: 18.4))
        p.addQuadCurve(to: CGPoint(x: 0.8, y: 6.5), control: CGPoint(x: -0.4, y: 13.5))
        p.addQuadCurve(to: CGPoint(x: 6.2, y: 0.8), control: CGPoint(x: 1.4, y: 0.8))
        p.addQuadCurve(to: CGPoint(x: 11.3, y: 6.5), control: CGPoint(x: 11.2, y: 0.8))
        p.addQuadCurve(to: CGPoint(x: 9, y: 18.4), control: CGPoint(x: 12.4, y: 13.5))
        p.closeSubpath()
        ctx.saveGState()
        ctx.addPath(p)
        ctx.clip()
        let grad = CGGradient(colorsSpace: nil, colors: [ear, earLight] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 18), end: CGPoint(x: 0, y: 1), options: [])
        ctx.paint(ellipse(3.5, 3, 4, 9), fill: rgb(0xFFFFFF, 0.08))
        ctx.restoreGState()
        ctx.paint(p, stroke: outline, width: 1.1)
    }

    static let eye: SKTexture = TextureFactory.make(CGSize(width: 7.5, height: 8.5)) { ctx in
        let shape = ellipse(0.5, 0.5, 6.5, 7.5)
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let grad = CGGradient(colorsSpace: nil, colors: [rgb(0x140E0B), rgb(0x4A2E1C)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 8), end: CGPoint(x: 0, y: 0.5), options: [])
        ctx.restoreGState()
        ctx.paint(ellipse(1.3, 4.2, 2.8, 2.8), fill: rgb(0xFFFFFF, 0.95))
        ctx.paint(ellipse(4.4, 1.6, 1.3, 1.3), fill: rgb(0xFFFFFF, 0.75))
    }

    static let closedEye: SKTexture = TextureFactory.make(CGSize(width: 7, height: 4)) { ctx in
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0.8, y: 3))
        p.addQuadCurve(to: CGPoint(x: 6.2, y: 3), control: CGPoint(x: 3.5, y: 0.2))
        ctx.paint(p, stroke: outline, width: 1.2)
    }

    static let happyEye: SKTexture = TextureFactory.make(CGSize(width: 7, height: 4)) { ctx in
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0.8, y: 0.8))
        p.addQuadCurve(to: CGPoint(x: 6.2, y: 0.8), control: CGPoint(x: 3.5, y: 4.2))
        ctx.paint(p, stroke: outline, width: 1.2)
    }

    static let tongue: SKTexture = TextureFactory.make(CGSize(width: 6, height: 8)) { ctx in
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0.6, y: 7.6))
        p.addLine(to: CGPoint(x: 0.6, y: 3))
        p.addQuadCurve(to: CGPoint(x: 5.4, y: 3), control: CGPoint(x: 3, y: -1.4))
        p.addLine(to: CGPoint(x: 5.4, y: 7.6))
        p.closeSubpath()
        ctx.paint(p, fill: tongueColor)
        let line = CGMutablePath()
        line.move(to: CGPoint(x: 3, y: 7))
        line.addLine(to: CGPoint(x: 3, y: 3.2))
        ctx.paint(line, stroke: rgb(0xD9506A), width: 0.6)
        ctx.paint(p, stroke: rgb(0x9C3048, 0.8), width: 0.7)
    }

    static let mouthOpen: SKTexture = TextureFactory.make(CGSize(width: 7, height: 5)) { ctx in
        ctx.paint(ellipse(0.5, 0.5, 6, 4), fill: rgb(0x6E1F2C))
        ctx.paint(ellipse(1.5, 0.6, 3.5, 1.8), fill: tongueColor)
        ctx.paint(ellipse(0.5, 0.5, 6, 4), stroke: outline, width: 0.7)
    }

    static let collar: SKTexture = TextureFactory.make(CGSize(width: 16, height: 9)) { ctx in
        let band = CGPath(roundedRect: CGRect(x: 0.6, y: 4, width: 14.8, height: 4.2), cornerWidth: 2, cornerHeight: 2, transform: nil)
        ctx.paint(band, fill: rgb(0xE5484D))
        ctx.paint(ellipse(2, 6.6, 11, 1), fill: rgb(0xFFFFFF, 0.3))
        ctx.paint(band, stroke: rgb(0x7A1E22, 0.9), width: 0.8)
        let tag = ellipse(6, 0.4, 4.4, 4.4)
        ctx.paint(tag, fill: rgb(0xFFC83D))
        ctx.paint(ellipse(6.9, 2.6, 1.4, 1), fill: rgb(0xFFFFFF, 0.7))
        ctx.paint(tag, stroke: rgb(0x9A6A10, 0.9), width: 0.7)
    }

    static let frontLeg: SKTexture = TextureFactory.make(CGSize(width: 10, height: 16)) { ctx in
        let shape = CGPath(roundedRect: CGRect(x: 1.6, y: 0.6, width: 6.8, height: 14.8), cornerWidth: 3.4, cornerHeight: 3.4, transform: nil)
        ctx.paint(shape, fill: fur)
        ctx.paint(shape, stroke: outline, width: 1.1)
    }

    static let hindLeg: SKTexture = TextureFactory.make(CGSize(width: 10, height: 16)) { ctx in
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0.6, y: 12.5))
        p.addQuadCurve(to: CGPoint(x: 5, y: 15.6), control: CGPoint(x: 0.6, y: 15.6))
        p.addQuadCurve(to: CGPoint(x: 9.4, y: 12.5), control: CGPoint(x: 9.4, y: 15.6))
        p.addLine(to: CGPoint(x: 8, y: 2.6))
        p.addQuadCurve(to: CGPoint(x: 5, y: 0.5), control: CGPoint(x: 8, y: 0.5))
        p.addQuadCurve(to: CGPoint(x: 2, y: 2.6), control: CGPoint(x: 2, y: 0.5))
        p.closeSubpath()
        ctx.paint(p, fill: fur)
        ctx.paint(p, stroke: outline, width: 1.1)
    }

    /// Cream "sock" paw.
    static let paw: SKTexture = TextureFactory.make(CGSize(width: 10, height: 7)) { ctx in
        let shape = ellipse(0.6, 0.6, 8.8, 5.4)
        ctx.paint(shape, fill: cream)
        let toes = CGMutablePath()
        for x in [CGFloat(3.6), 6.4] {
            toes.move(to: CGPoint(x: x, y: 5.8))
            toes.addLine(to: CGPoint(x: x, y: 4.2))
        }
        ctx.paint(toes, stroke: rgb(0x5E3A1E, 0.45), width: 0.5)
        ctx.paint(shape, stroke: outline, width: 1)
    }
}
