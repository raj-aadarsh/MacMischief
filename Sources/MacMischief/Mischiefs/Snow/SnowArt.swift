import SpriteKit

@MainActor
enum SnowArt {
    /// Soft round flake with a faint dark halo so it reads on white windows too.
    static let dot: SKTexture = TextureFactory.make(CGSize(width: 12, height: 12)) { ctx in
        ctx.setShadow(offset: .zero, blur: 1.6, color: rgb(0x22344D, 0.5))
        ctx.paint(ellipse(2.5, 2.5, 7, 7), fill: rgb(0xFFFFFF))
    }
    static let dotRatio: CGFloat = 12.0 / 7.0

    /// Snowball body: soft lit sphere (does not rotate).
    static let snowball: SKTexture = TextureFactory.make(CGSize(width: 64, height: 64), scale: 2) { ctx in
        let c = CGPoint(x: 32, y: 32), r: CGFloat = 27
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 5, color: rgb(0x1E2C40, 0.45))
        ctx.paint(ellipse(c.x - r, c.y - r, r * 2, r * 2), fill: rgb(0xF4F8FF))
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(ellipse(c.x - r, c.y - r, r * 2, r * 2))
        ctx.clip()
        let g = CGGradient(colorsSpace: nil, colors: [rgb(0xFFFFFF), rgb(0xEEF4FD), rgb(0xBCCBE0)] as CFArray,
                           locations: [0, 0.55, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.x - 9, y: c.y + 10), startRadius: 0,
                               endCenter: c, endRadius: r * 1.15, options: [.drawsAfterEndLocation])
        ctx.restoreGState()
        ctx.paint(ellipse(c.x - r, c.y - r, r * 2, r * 2), stroke: rgb(0x8EA3C2, 0.55), width: 1)
    }

    /// Lumpy surface detail that rotates as the ball rolls.
    static let snowballDetail: SKTexture = TextureFactory.make(CGSize(width: 64, height: 64), scale: 2) { ctx in
        let c = CGPoint(x: 32, y: 32)
        ctx.addPath(ellipse(c.x - 26, c.y - 26, 52, 52))
        ctx.clip()
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<26 {
            let a = CGFloat.random(in: 0...(2 * .pi), using: &rng)
            let d = CGFloat.random(in: 4...24, using: &rng)
            let s = CGFloat.random(in: 2...6, using: &rng)
            let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
            ctx.paint(ellipse(p.x - s / 2, p.y - s / 2, s, s * 0.8), fill: rgb(0x9FB2CF, CGFloat.random(in: 0.12...0.3, using: &rng)))
            ctx.paint(ellipse(p.x - s / 2 + 0.6, p.y - s / 2 + 1, s * 0.7, s * 0.5), fill: rgb(0xFFFFFF, 0.5))
        }
    }

    /// Six-armed crystal for the big, close flakes.
    static let crystal: SKTexture = TextureFactory.make(CGSize(width: 24, height: 24)) { ctx in
        let c = CGPoint(x: 12, y: 12)
        let arms = CGMutablePath()
        for i in 0..<6 {
            let a = CGFloat(i) * .pi / 3 + .pi / 2
            let dir = CGPoint(x: cos(a), y: sin(a))
            let tip = CGPoint(x: c.x + dir.x * 9.5, y: c.y + dir.y * 9.5)
            arms.move(to: c)
            arms.addLine(to: tip)
            for (along, len) in [(CGFloat(4.6), CGFloat(3.0)), (CGFloat(7.0), CGFloat(2.1))] {
                let base = CGPoint(x: c.x + dir.x * along, y: c.y + dir.y * along)
                for side in [CGFloat(-1), 1] {
                    let b = a + side * .pi / 3.2
                    arms.move(to: base)
                    arms.addLine(to: CGPoint(x: base.x + cos(b) * len, y: base.y + sin(b) * len))
                }
            }
        }
        ctx.setShadow(offset: .zero, blur: 1.4, color: rgb(0x22344D, 0.55))
        ctx.paint(arms, stroke: rgb(0xFFFFFF), width: 1.5)
        ctx.paint(ellipse(10, 10, 4, 4), fill: rgb(0xFFFFFF))
    }
}
