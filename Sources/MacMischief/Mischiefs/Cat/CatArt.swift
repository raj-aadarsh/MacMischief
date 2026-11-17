import SpriteKit

/// All cat artwork, drawn as vector shapes (ginger tabby).
@MainActor
enum CatArt {
    static let furTop = rgb(0xE38B3C)
    static let fur = rgb(0xF2A85F)
    static let furLight = rgb(0xF9C88E)
    static let stripe = rgb(0xC0652A)
    static let cream = rgb(0xFFF4E6)
    static let outline = rgb(0x6B3A1A, 0.85)
    static let pink = rgb(0xF6A3AE)
    static let nose = rgb(0xEE8796)
    static let irisTop = rgb(0x6EA846)
    static let irisBottom = rgb(0xD8E67E)
    static let iris = rgb(0x9CC860)
    static let pupilColor = rgb(0x1A1411)

    static let furColor = SKColor.hex(0xF0A35A)
    static let stripeColor = SKColor.hex(0xC0652A, 0.9)
    static let outlineColor = SKColor.hex(0x6B3A1A, 0.85)

    static let body: SKTexture = TextureFactory.make(CGSize(width: 60, height: 32)) { ctx in
        let shape = ellipse(2, 3, 56, 26)
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let grad = CGGradient(colorsSpace: nil, colors: [furTop, fur, furLight] as CFArray, locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 29), end: CGPoint(x: 0, y: 6), options: [.drawsAfterEndLocation])
        // Soft form shading on hip and shoulder
        ctx.paint(ellipse(4, 8, 22, 18), fill: rgb(0xFFFFFF, 0.08))
        ctx.paint(ellipse(36, 9, 16, 15), fill: rgb(0xFFFFFF, 0.06))
        ctx.paint(ellipse(10, -5, 42, 16), fill: cream)
        // Tapered tabby stripes
        for i in 0..<5 {
            let x = CGFloat(13 + i * 8)
            let s = CGMutablePath()
            s.move(to: CGPoint(x: x - 1.8, y: 31))
            s.addQuadCurve(to: CGPoint(x: x - 3.2, y: 17), control: CGPoint(x: x + 0.2, y: 24))
            s.addQuadCurve(to: CGPoint(x: x + 1.9, y: 31), control: CGPoint(x: x + 3.4, y: 24.5))
            s.closeSubpath()
            ctx.paint(s, fill: rgb(0xC0652A, 0.85))
        }
        ctx.restoreGState()
        ctx.paint(shape, stroke: outline, width: 1.1)
        // Fluffy chest tuft poking out at the front
        let tuft = polygon([CGPoint(x: 45, y: 5), CGPoint(x: 57.5, y: 7.5), CGPoint(x: 55, y: 10),
                            CGPoint(x: 58.5, y: 12.5), CGPoint(x: 54.5, y: 14.5), CGPoint(x: 56.5, y: 18),
                            CGPoint(x: 49, y: 17)])
        ctx.paint(tuft, fill: cream)
        ctx.paint(tuft, stroke: rgb(0x6B3A1A, 0.45), width: 0.7)
    }

    static let head: SKTexture = TextureFactory.make(CGSize(width: 46, height: 40)) { drawHead($0) }

    /// The face (no ears), in a 46x40 point canvas.
    static func drawHead(_ ctx: CGContext) {
        // Cheek fluff behind the face
        for side in [CGFloat(1), -1] {
            let x = { (v: CGFloat) -> CGFloat in side > 0 ? v : 46 - v }
            let tuft = polygon([CGPoint(x: x(12), y: 7), CGPoint(x: x(5.5), y: 7.5), CGPoint(x: x(8.5), y: 10.5),
                                CGPoint(x: x(4.5), y: 12.5), CGPoint(x: x(9), y: 14), CGPoint(x: x(6.5), y: 17),
                                CGPoint(x: x(12), y: 17)])
            ctx.paint(tuft, fill: fur)
            ctx.paint(tuft, stroke: outline, width: 1)
        }

        let face = ellipse(8.5, 3, 29, 25)
        ctx.saveGState()
        ctx.addPath(face)
        ctx.clip()
        let grad = CGGradient(colorsSpace: nil, colors: [furTop, fur, furLight] as CFArray, locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 28), end: CGPoint(x: 0, y: 6), options: [.drawsAfterEndLocation])
        // Puffy muzzle + chin
        ctx.paint(ellipse(15, 3.5, 9, 8.5), fill: cream)
        ctx.paint(ellipse(22, 3.5, 9, 8.5), fill: cream)
        ctx.paint(ellipse(18.5, 1.5, 9, 6), fill: cream)
        // Tabby "M" on the forehead
        for (top, bottom, w) in [(CGPoint(x: 23, y: 28.5), CGPoint(x: 23, y: 23.4), CGFloat(1.7)),
                                 (CGPoint(x: 19.6, y: 27.8), CGPoint(x: 20.7, y: 23.8), CGFloat(1.5)),
                                 (CGPoint(x: 26.4, y: 27.8), CGPoint(x: 25.3, y: 23.8), CGFloat(1.5)),
                                 (CGPoint(x: 13, y: 22), CGPoint(x: 16.5, y: 20.5), CGFloat(1.3)),
                                 (CGPoint(x: 33, y: 22), CGPoint(x: 29.5, y: 20.5), CGFloat(1.3))] {
            let s = CGMutablePath()
            s.move(to: top)
            s.addLine(to: bottom)
            ctx.paint(s, stroke: stripe, width: w)
        }
        ctx.restoreGState()
        ctx.paint(face, stroke: outline, width: 1.1)

        // Blush
        ctx.paint(ellipse(11.5, 8.8, 5, 2.6), fill: rgb(0xFF8FA0, 0.4))
        ctx.paint(ellipse(29.5, 8.8, 5, 2.6), fill: rgb(0xFF8FA0, 0.4))

        // Nose with highlight
        let nosePath = CGMutablePath()
        nosePath.move(to: CGPoint(x: 21.2, y: 12.7))
        nosePath.addQuadCurve(to: CGPoint(x: 24.8, y: 12.7), control: CGPoint(x: 23, y: 13.5))
        nosePath.addQuadCurve(to: CGPoint(x: 23, y: 10.6), control: CGPoint(x: 24.6, y: 11.3))
        nosePath.addQuadCurve(to: CGPoint(x: 21.2, y: 12.7), control: CGPoint(x: 21.4, y: 11.3))
        ctx.paint(nosePath, fill: nose)
        ctx.paint(nosePath, stroke: outline, width: 0.7)
        ctx.paint(ellipse(22, 12, 1.3, 0.7), fill: rgb(0xFFFFFF, 0.7))

        let mouth = CGMutablePath()
        mouth.move(to: CGPoint(x: 23, y: 10.6))
        mouth.addLine(to: CGPoint(x: 23, y: 9.5))
        mouth.move(to: CGPoint(x: 20.6, y: 8.9))
        mouth.addQuadCurve(to: CGPoint(x: 23, y: 9.5), control: CGPoint(x: 21.8, y: 8.1))
        mouth.addQuadCurve(to: CGPoint(x: 25.4, y: 8.9), control: CGPoint(x: 24.2, y: 8.1))
        ctx.paint(mouth, stroke: outline, width: 0.8)

        // Whisker dots + whiskers
        for (x, y) in [(18.6, 9.6), (17.8, 8.4), (27.4, 9.6), (28.2, 8.4)] as [(CGFloat, CGFloat)] {
            ctx.paint(ellipse(x - 0.35, y - 0.35, 0.7, 0.7), fill: rgb(0x6B3A1A, 0.5))
        }
        let whiskers = CGMutablePath()
        for (a, c, b) in [(CGPoint(x: 15.5, y: 10.4), CGPoint(x: 9, y: 12.4), CGPoint(x: 2.5, y: 13.4)),
                          (CGPoint(x: 15.5, y: 9.4), CGPoint(x: 9, y: 9.8), CGPoint(x: 2, y: 9.2)),
                          (CGPoint(x: 15.8, y: 8.5), CGPoint(x: 9.5, y: 7.4), CGPoint(x: 3.5, y: 5.2))] {
            whiskers.move(to: a)
            whiskers.addQuadCurve(to: b, control: c)
            whiskers.move(to: CGPoint(x: 46 - a.x, y: a.y))
            whiskers.addQuadCurve(to: CGPoint(x: 46 - b.x, y: b.y), control: CGPoint(x: 46 - c.x, y: c.y))
        }
        ctx.paint(whiskers, stroke: rgb(0x5A3418, 0.5), width: 0.55)
    }

    /// Ear outline path in a 12x15 canvas.
    static func earPath() -> CGPath {
        let outer = CGMutablePath()
        outer.move(to: CGPoint(x: 1, y: 1))
        outer.addQuadCurve(to: CGPoint(x: 5.2, y: 14.4), control: CGPoint(x: 1.2, y: 9.5))
        outer.addQuadCurve(to: CGPoint(x: 11, y: 1), control: CGPoint(x: 10.2, y: 8))
        outer.closeSubpath()
        return outer
    }

    /// One ear (left); mirrored for the right. Anchor near the bottom centre.
    static let ear: SKTexture = TextureFactory.make(CGSize(width: 12, height: 15)) { drawEar($0) }

    static func drawEar(_ ctx: CGContext) {
        let outer = earPath()
        ctx.paint(outer, fill: fur)
        let inner = CGMutablePath()
        inner.move(to: CGPoint(x: 3, y: 2))
        inner.addQuadCurve(to: CGPoint(x: 5.3, y: 11.3), control: CGPoint(x: 3, y: 8))
        inner.addQuadCurve(to: CGPoint(x: 9, y: 2), control: CGPoint(x: 8.6, y: 6.5))
        inner.closeSubpath()
        ctx.paint(inner, fill: pink)
        let tufts = CGMutablePath()
        for (a, b) in [(CGPoint(x: 4.5, y: 2), CGPoint(x: 3.6, y: 6)), (CGPoint(x: 6, y: 2), CGPoint(x: 5.6, y: 6.8)),
                       (CGPoint(x: 7.5, y: 2), CGPoint(x: 7.6, y: 5.6))] {
            tufts.move(to: a)
            tufts.addLine(to: b)
        }
        ctx.paint(tufts, stroke: rgb(0xFFFFFF, 0.85), width: 0.5)
        ctx.paint(outer, stroke: outline, width: 1.1)
    }

    static let eye: SKTexture = TextureFactory.make(CGSize(width: 8.5, height: 9.5)) { ctx in
        let shape = ellipse(0.5, 0.5, 7.5, 8.5)
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let grad = CGGradient(colorsSpace: nil, colors: [irisTop, irisBottom] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 9), end: CGPoint(x: 0, y: 1), options: [])
        ctx.paint(ellipse(-1, 6.5, 10.5, 5), fill: rgb(0x000000, 0.12))
        ctx.restoreGState()
        ctx.paint(shape, stroke: outline, width: 0.9)
    }

    static let pupil: SKTexture = TextureFactory.make(CGSize(width: 4.4, height: 7.4)) { ctx in
        ctx.paint(ellipse(0.2, 0.2, 4, 7), fill: pupilColor)
    }

    static let shine: SKTexture = TextureFactory.make(CGSize(width: 5, height: 5)) { ctx in
        ctx.paint(ellipse(0.4, 2, 2.6, 2.6), fill: rgb(0xFFFFFF, 0.95))
        ctx.paint(ellipse(3.2, 0.4, 1.2, 1.2), fill: rgb(0xFFFFFF, 0.8))
    }

    static let closedEye: SKTexture = TextureFactory.make(CGSize(width: 8, height: 4)) { ctx in
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0.8, y: 3))
        p.addQuadCurve(to: CGPoint(x: 7.2, y: 3), control: CGPoint(x: 4, y: 0))
        ctx.paint(p, stroke: outline, width: 1.2)
    }

    static let happyEye: SKTexture = TextureFactory.make(CGSize(width: 8, height: 4)) { ctx in
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0.8, y: 0.8))
        p.addQuadCurve(to: CGPoint(x: 7.2, y: 0.8), control: CGPoint(x: 4, y: 4.4))
        ctx.paint(p, stroke: outline, width: 1.2)
    }

    static let mouthOpen: SKTexture = TextureFactory.make(CGSize(width: 5, height: 5)) { ctx in
        ctx.paint(ellipse(0.5, 0.5, 4, 4), fill: rgb(0x8E2C3A))
        ctx.paint(ellipse(1.3, 0.6, 2.4, 1.6), fill: rgb(0xF07C8C))
        ctx.paint(ellipse(0.5, 0.5, 4, 4), stroke: outline, width: 0.7)
    }

    static let frontLeg: SKTexture = TextureFactory.make(CGSize(width: 10, height: 16)) { ctx in
        let shape = CGPath(roundedRect: CGRect(x: 2, y: 0.6, width: 6, height: 14.8), cornerWidth: 3, cornerHeight: 3, transform: nil)
        ctx.paint(shape, fill: fur)
        ctx.paint(shape, stroke: outline, width: 1.1)
    }

    /// Hind leg with a thicker thigh at the top.
    static let hindLeg: SKTexture = TextureFactory.make(CGSize(width: 10, height: 16)) { ctx in
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0.6, y: 12.5))
        p.addQuadCurve(to: CGPoint(x: 5, y: 15.6), control: CGPoint(x: 0.6, y: 15.6))
        p.addQuadCurve(to: CGPoint(x: 9.4, y: 12.5), control: CGPoint(x: 9.4, y: 15.6))
        p.addLine(to: CGPoint(x: 7.6, y: 2.6))
        p.addQuadCurve(to: CGPoint(x: 5, y: 0.5), control: CGPoint(x: 7.6, y: 0.5))
        p.addQuadCurve(to: CGPoint(x: 2.4, y: 2.6), control: CGPoint(x: 2.4, y: 0.5))
        p.closeSubpath()
        ctx.paint(p, fill: fur)
        ctx.paint(p, stroke: outline, width: 1.1)
    }

    static let paw: SKTexture = TextureFactory.make(CGSize(width: 9, height: 6)) { ctx in
        let shape = ellipse(0.7, 0.7, 7.6, 4.6)
        ctx.paint(shape, fill: cream)
        let toes = CGMutablePath()
        for x in [CGFloat(3.4), 5.6] {
            toes.move(to: CGPoint(x: x, y: 5.1))
            toes.addLine(to: CGPoint(x: x, y: 3.6))
        }
        ctx.paint(toes, stroke: rgb(0x6B3A1A, 0.45), width: 0.5)
        ctx.paint(shape, stroke: outline, width: 1)
    }
}
