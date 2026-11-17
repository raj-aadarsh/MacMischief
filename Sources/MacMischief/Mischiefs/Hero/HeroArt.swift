import SpriteKit

/// Artwork for Skybolt, an original armoured jet-suit hero: gunmetal plates,
/// cyan visor band, chevron chest light, back-mounted twin-nozzle jetpack.
/// Every part is drawn facing +x, upright.
@MainActor
enum HeroArt {
    static let edge = rgb(0x0B0F15, 0.92)
    static let dark = rgb(0x171C24)
    static let base = rgb(0x343E4D)
    static let mid = rgb(0x566376)
    static let light = rgb(0x8F9DB2)
    static let spec = rgb(0xE2EBF6)
    static let plate = rgb(0x2A3444)
    static let panel = rgb(0x0E131A, 0.65)
    static let panelHi = rgb(0xC0CEDF, 0.35)
    static let glow = rgb(0xFFF3EA)
    static let glowCore = rgb(0xFFFBF2)

    /// Brushed-metal fill across a part (cylindrical shading).
    /// Crimson armour shell colours.
    static let crimsonStops = [rgb(0x2E070C), rgb(0x5E111B), rgb(0x8E1A27), rgb(0xBF2F3A), rgb(0xFFD6D2),
                               rgb(0xBF2F3A), rgb(0x8E1A27), rgb(0x5E111B), rgb(0x2E070C)]

    static func metal(_ ctx: CGContext, _ path: CGPath, from: CGPoint, to: CGPoint, bright: CGFloat = 1, crimson: Bool = false) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let colors = crimson ? crimsonStops : [dark, base, mid, light, spec, light, mid, base, dark]
        let locs: [CGFloat] = [0, 0.14, 0.32, 0.46, 0.53, 0.6, 0.76, 0.9, 1]
        let g = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: locs)!
        ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        if bright < 1 { ctx.paint(path, fill: rgb(0x000000, 1 - bright)) }
        ctx.restoreGState()
    }

    static func line(_ ctx: CGContext, _ pts: [CGPoint], _ color: CGColor, _ w: CGFloat) {
        let p = CGMutablePath()
        p.addLines(between: pts)
        ctx.paint(p, stroke: color, width: w)
    }

    static func glowStroke(_ ctx: CGContext, _ path: CGPath, width: CGFloat) {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 2.2, color: glow)
        ctx.paint(path, stroke: glow, width: width)
        ctx.restoreGState()
        ctx.paint(path, stroke: glowCore, width: width * 0.4)
    }

    // MARK: Helmet (16x18, neck at bottom centre-ish)

    static let helmet: SKTexture = TextureFactory.make(CGSize(width: 17.6, height: 19.4), scale: 4) { ctx in
        ctx.scaleBy(x: 1.1, y: 1.08)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 3.5, y: 1))
        p.addQuadCurve(to: CGPoint(x: 1.6, y: 10), control: CGPoint(x: 1.2, y: 4))
        p.addQuadCurve(to: CGPoint(x: 8.5, y: 17.4), control: CGPoint(x: 2.2, y: 17.2))
        p.addQuadCurve(to: CGPoint(x: 14.6, y: 12), control: CGPoint(x: 13.6, y: 17))
        p.addLine(to: CGPoint(x: 15.2, y: 7))
        p.addQuadCurve(to: CGPoint(x: 11.5, y: 1.2), control: CGPoint(x: 15, y: 2.2))
        p.closeSubpath()
        metal(ctx, p, from: CGPoint(x: 2, y: 2), to: CGPoint(x: 14, y: 17), crimson: true)
        ctx.saveGState()
        ctx.addPath(p)
        ctx.clip()
        // Faceplate (slightly darker plate) and crest ridge
        let face = CGMutablePath()
        face.move(to: CGPoint(x: 9.5, y: 1))
        face.addLine(to: CGPoint(x: 9, y: 12.5))
        face.addQuadCurve(to: CGPoint(x: 16, y: 13), control: CGPoint(x: 12.5, y: 14.5))
        face.addLine(to: CGPoint(x: 16, y: 0))
        face.closeSubpath()
        metal(ctx, face, from: CGPoint(x: 9, y: 2), to: CGPoint(x: 16, y: 13))
        line(ctx, [CGPoint(x: 9.5, y: 1.5), CGPoint(x: 9, y: 12.4)], panel, 0.45)
        let crest = CGMutablePath()
        crest.move(to: CGPoint(x: 3, y: 14))
        crest.addQuadCurve(to: CGPoint(x: 12.5, y: 15.5), control: CGPoint(x: 7, y: 19))
        ctx.paint(crest, stroke: panelHi, width: 0.9)
        ctx.paint(crest, stroke: panel, width: 0.35)
        ctx.restoreGState()
        // Ear disc
        ctx.paint(ellipse(4, 6, 4, 4), fill: plate)
        ctx.paint(ellipse(4, 6, 4, 4), stroke: rgb(0x8F9DB2, 0.7), width: 0.4)
        ctx.paint(ellipse(5.4, 7.4, 1.2, 1.2), fill: rgb(0xFFF3EA, 0.8))
        // Visor band
        let visor = CGMutablePath()
        visor.move(to: CGPoint(x: 8.6, y: 9.6))
        visor.addQuadCurve(to: CGPoint(x: 15.1, y: 9.9), control: CGPoint(x: 12, y: 10.6))
        ctx.paint(visor, stroke: rgb(0x000000, 0.9), width: 2.4)
        glowStroke(ctx, visor, width: 1.3)
        // Mouth grille
        for y in [CGFloat(4.2), 5.4] { line(ctx, [CGPoint(x: 12.4, y: y), CGPoint(x: 14.8, y: y + 0.2)], panel, 0.4) }
        ctx.paint(ellipse(10.5, 13.8, 3, 1.4), fill: rgb(0xFFFFFF, 0.5))
        ctx.paint(p, stroke: edge, width: 0.7)
    }

    // MARK: Torso (20x26, waist at (10,1))

    static let torso: SKTexture = TextureFactory.make(CGSize(width: 24, height: 26), scale: 4) { ctx in
        ctx.scaleBy(x: 24 / 20.0, y: 1)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 5.5, y: 1))
        p.addLine(to: CGPoint(x: 14.5, y: 1))
        p.addQuadCurve(to: CGPoint(x: 18.6, y: 15.5), control: CGPoint(x: 16, y: 8))
        p.addQuadCurve(to: CGPoint(x: 15.5, y: 23.2), control: CGPoint(x: 19.4, y: 21.5))
        p.addLine(to: CGPoint(x: 12.5, y: 25.4))
        p.addLine(to: CGPoint(x: 6, y: 25.4))
        p.addQuadCurve(to: CGPoint(x: 2.6, y: 20), control: CGPoint(x: 2.6, y: 24))
        p.addQuadCurve(to: CGPoint(x: 5.5, y: 1), control: CGPoint(x: 2.8, y: 8))
        p.closeSubpath()
        metal(ctx, p, from: CGPoint(x: 2.6, y: 10), to: CGPoint(x: 18.6, y: 14), crimson: true)
        ctx.saveGState()
        ctx.addPath(p)
        ctx.clip()
        // Chest plate
        let chest = CGMutablePath()
        chest.move(to: CGPoint(x: 8.5, y: 12))
        chest.addQuadCurve(to: CGPoint(x: 18.8, y: 13), control: CGPoint(x: 14, y: 10.4))
        chest.addLine(to: CGPoint(x: 18.8, y: 24))
        chest.addLine(to: CGPoint(x: 9.5, y: 24))
        chest.closeSubpath()
        ctx.paint(chest, fill: rgb(0xFFFFFF, 0.07))
        ctx.paint(chest, stroke: panel, width: 0.45)
        // Abdominal plates
        for y in [CGFloat(4.4), 7.6, 10.6] {
            let a = CGMutablePath()
            a.move(to: CGPoint(x: 3, y: y))
            a.addQuadCurve(to: CGPoint(x: 18, y: y + 0.6), control: CGPoint(x: 11, y: y - 1.2))
            ctx.paint(a, stroke: panel, width: 0.5)
        }
        // Side vent
        for i in 0..<3 { line(ctx, [CGPoint(x: 4.2, y: 15 + CGFloat(i) * 1.6), CGPoint(x: 7, y: 15.4 + CGFloat(i) * 1.6)], panel, 0.5) }
        // Collar ring
        ctx.paint(CGPath(roundedRect: CGRect(x: 5.5, y: 23.6, width: 7.5, height: 2.4), cornerWidth: 1, cornerHeight: 1, transform: nil),
                  fill: plate)
        ctx.restoreGState()
        // Chevron chest light
        let chev = CGMutablePath()
        chev.move(to: CGPoint(x: 12.4, y: 20))
        chev.addLine(to: CGPoint(x: 15.2, y: 16.6))
        chev.addLine(to: CGPoint(x: 18, y: 20))
        ctx.paint(chev, stroke: rgb(0x000000, 0.85), width: 2.2)
        glowStroke(ctx, chev, width: 1.2)
        ctx.paint(p, stroke: edge, width: 0.7)
    }

    // MARK: Pelvis / belt (14x9, hip joint at (7,5))

    static let pelvis: SKTexture = TextureFactory.make(CGSize(width: 16, height: 9), scale: 4) { ctx in
        ctx.scaleBy(x: 16 / 14.0, y: 1)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 1.5, y: 8.4))
        p.addLine(to: CGPoint(x: 12.6, y: 8.4))
        p.addQuadCurve(to: CGPoint(x: 10.5, y: 1), control: CGPoint(x: 13.4, y: 3))
        p.addLine(to: CGPoint(x: 3.5, y: 1))
        p.addQuadCurve(to: CGPoint(x: 1.5, y: 8.4), control: CGPoint(x: 0.6, y: 3))
        p.closeSubpath()
        metal(ctx, p, from: CGPoint(x: 1, y: 4), to: CGPoint(x: 13, y: 6), bright: 0.85)
        line(ctx, [CGPoint(x: 1.8, y: 6.2), CGPoint(x: 12.4, y: 6.2)], panel, 0.5)
        ctx.paint(CGPath(roundedRect: CGRect(x: 8.6, y: 5.6, width: 3.4, height: 2.4), cornerWidth: 0.6, cornerHeight: 0.6, transform: nil),
                  fill: plate)
        ctx.paint(ellipse(9.8, 6.3, 1, 1), fill: glow)
        ctx.paint(p, stroke: edge, width: 0.7)
    }

    // MARK: Jetpack (10x20, mounts at its right edge)

    static let jetpack: SKTexture = TextureFactory.make(CGSize(width: 10, height: 20), scale: 4) { ctx in
        let body = CGPath(roundedRect: CGRect(x: 1, y: 4.5, width: 8, height: 15), cornerWidth: 3, cornerHeight: 3, transform: nil)
        metal(ctx, body, from: CGPoint(x: 1, y: 10), to: CGPoint(x: 9, y: 12), bright: 0.9)
        for x in [CGFloat(1.2), 5.2] {
            let n = polygon([CGPoint(x: x + 0.4, y: 4.8), CGPoint(x: x + 3.4, y: 4.8), CGPoint(x: x + 3.8, y: 0.6), CGPoint(x: x, y: 0.6)])
            metal(ctx, n, from: CGPoint(x: x, y: 2), to: CGPoint(x: x + 3.8, y: 2), bright: 0.7)
            ctx.paint(n, stroke: edge, width: 0.5)
            ctx.paint(ellipse(x + 0.6, 0.2, 2.6, 1), fill: rgb(0xFFF3EA, 0.9))
        }
        for i in 0..<3 {
            line(ctx, [CGPoint(x: 3, y: 9 + CGFloat(i) * 2.2), CGPoint(x: 7, y: 9 + CGFloat(i) * 2.2)], rgb(0xFFF3EA, 0.75), 0.6)
        }
        ctx.paint(body, stroke: edge, width: 0.7)
    }

    // MARK: Limbs (drawn hanging down; joint at the top centre)

    static let pauldron: SKTexture = TextureFactory.make(CGSize(width: 13.5, height: 8), scale: 4) { ctx in
        ctx.scaleBy(x: 13.5 / 10.0, y: 1)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0.6, y: 1.5))
        p.addQuadCurve(to: CGPoint(x: 5, y: 7.6), control: CGPoint(x: 0.4, y: 7.6))
        p.addQuadCurve(to: CGPoint(x: 9.4, y: 1.5), control: CGPoint(x: 9.6, y: 7.6))
        p.addQuadCurve(to: CGPoint(x: 0.6, y: 1.5), control: CGPoint(x: 5, y: 0))
        metal(ctx, p, from: CGPoint(x: 0.5, y: 3), to: CGPoint(x: 9.5, y: 6), crimson: true)
        line(ctx, [CGPoint(x: 1.5, y: 3.4), CGPoint(x: 8.5, y: 3.4)], panel, 0.45)
        ctx.paint(p, stroke: edge, width: 0.6)
    }

    static let upperArm: SKTexture = TextureFactory.make(CGSize(width: 9, height: 14), scale: 4) { ctx in
        ctx.scaleBy(x: 9 / 7.0, y: 1)
        let p = CGPath(roundedRect: CGRect(x: 1, y: 0.5, width: 5, height: 13), cornerWidth: 2.4, cornerHeight: 2.4, transform: nil)
        metal(ctx, p, from: CGPoint(x: 1, y: 7), to: CGPoint(x: 6, y: 7), crimson: true)
        line(ctx, [CGPoint(x: 1.2, y: 8), CGPoint(x: 5.8, y: 8.4)], panel, 0.45)
        ctx.paint(p, stroke: edge, width: 0.6)
    }

    static let forearm: SKTexture = TextureFactory.make(CGSize(width: 10, height: 14), scale: 4) { ctx in
        ctx.scaleBy(x: 10 / 8.0, y: 1)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 1.8, y: 13.5))
        p.addLine(to: CGPoint(x: 6.2, y: 13.5))
        p.addLine(to: CGPoint(x: 7.4, y: 2))
        p.addQuadCurve(to: CGPoint(x: 0.6, y: 2), control: CGPoint(x: 4, y: 0.2))
        p.closeSubpath()
        metal(ctx, p, from: CGPoint(x: 0.6, y: 7), to: CGPoint(x: 7.4, y: 7), crimson: true)
        ctx.saveGState()
        ctx.addPath(p)
        ctx.clip()
        ctx.paint(CGPath(rect: CGRect(x: 0, y: 3.4, width: 8, height: 1.6), transform: nil), fill: plate)
        ctx.restoreGState()
        ctx.paint(ellipse(5.4, 3.6, 1.2, 1.2), fill: glow)
        line(ctx, [CGPoint(x: 2, y: 12.2), CGPoint(x: 6.2, y: 12.2)], panel, 0.45)
        ctx.paint(p, stroke: edge, width: 0.6)
    }

    static let hand: SKTexture = TextureFactory.make(CGSize(width: 7.4, height: 6.5), scale: 4) { ctx in
        ctx.scaleBy(x: 7.4 / 6.0, y: 1)
        let p = CGPath(roundedRect: CGRect(x: 0.6, y: 0.5, width: 4.8, height: 5.6), cornerWidth: 1.8, cornerHeight: 1.8, transform: nil)
        metal(ctx, p, from: CGPoint(x: 0.6, y: 3), to: CGPoint(x: 5.4, y: 3), bright: 0.9)
        for y in [CGFloat(2), 3.3] { line(ctx, [CGPoint(x: 3, y: y), CGPoint(x: 5.3, y: y)], panel, 0.4) }
        ctx.paint(p, stroke: edge, width: 0.6)
    }

    static let thigh: SKTexture = TextureFactory.make(CGSize(width: 11.5, height: 18), scale: 4) { ctx in
        ctx.scaleBy(x: 11.5 / 9.0, y: 1)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0.6, y: 15))
        p.addQuadCurve(to: CGPoint(x: 4.5, y: 17.6), control: CGPoint(x: 0.6, y: 17.6))
        p.addQuadCurve(to: CGPoint(x: 8.4, y: 15), control: CGPoint(x: 8.4, y: 17.6))
        p.addLine(to: CGPoint(x: 7.6, y: 2.6))
        p.addQuadCurve(to: CGPoint(x: 1.4, y: 2.6), control: CGPoint(x: 4.5, y: 0))
        p.closeSubpath()
        metal(ctx, p, from: CGPoint(x: 0.6, y: 9), to: CGPoint(x: 8.4, y: 9), crimson: true)
        line(ctx, [CGPoint(x: 4.8, y: 16), CGPoint(x: 5.6, y: 5)], panel, 0.45)
        // Knee pad
        let knee = ellipse(4.2, 0.4, 4.4, 4.6)
        metal(ctx, knee, from: CGPoint(x: 4, y: 2), to: CGPoint(x: 8.6, y: 3), bright: 1)
        ctx.paint(knee, stroke: edge, width: 0.5)
        ctx.paint(p, stroke: edge, width: 0.6)
    }

    static let shin: SKTexture = TextureFactory.make(CGSize(width: 10, height: 17), scale: 4) { ctx in
        ctx.scaleBy(x: 10 / 8.0, y: 1)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 1, y: 16.5))
        p.addLine(to: CGPoint(x: 7, y: 16.5))
        p.addLine(to: CGPoint(x: 6.6, y: 1))
        p.addLine(to: CGPoint(x: 1.6, y: 1))
        p.closeSubpath()
        metal(ctx, p, from: CGPoint(x: 1, y: 8), to: CGPoint(x: 7, y: 8), crimson: true)
        let guardPlate = polygon([CGPoint(x: 4.6, y: 15.8), CGPoint(x: 7, y: 15.8), CGPoint(x: 6.6, y: 3), CGPoint(x: 4.8, y: 3)])
        ctx.paint(guardPlate, fill: rgb(0xFFFFFF, 0.1))
        ctx.paint(guardPlate, stroke: panel, width: 0.4)
        line(ctx, [CGPoint(x: 1.4, y: 6), CGPoint(x: 4.4, y: 6)], rgb(0xFFF3EA, 0.6), 0.5)
        ctx.paint(p, stroke: edge, width: 0.6)
    }

    /// Ankle joint at (3.5, 5.5); sole at y = 0.5.
    static let boot: SKTexture = TextureFactory.make(CGSize(width: 13, height: 7), scale: 4) { ctx in
        ctx.scaleBy(x: 13 / 12.0, y: 1)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0.8, y: 0.6))
        p.addLine(to: CGPoint(x: 10.6, y: 0.6))
        p.addQuadCurve(to: CGPoint(x: 11.2, y: 3), control: CGPoint(x: 11.8, y: 1.4))
        p.addQuadCurve(to: CGPoint(x: 5.8, y: 6.4), control: CGPoint(x: 8, y: 5.4))
        p.addLine(to: CGPoint(x: 1.2, y: 6.6))
        p.closeSubpath()
        metal(ctx, p, from: CGPoint(x: 1, y: 6.5), to: CGPoint(x: 9, y: 0.5), crimson: true)
        ctx.paint(CGPath(rect: CGRect(x: 0.8, y: 0.6, width: 10, height: 1.2), transform: nil), fill: dark)
        ctx.paint(ellipse(2.4, 0.2, 3, 0.9), fill: glow)
        ctx.paint(p, stroke: edge, width: 0.6)
    }

    static let joint: SKTexture = TextureFactory.make(CGSize(width: 7, height: 7), scale: 4) { ctx in
        let c = ellipse(0.5, 0.5, 6, 6)
        ctx.saveGState()
        ctx.addPath(c)
        ctx.clip()
        let g = CGGradient(colorsSpace: nil, colors: [rgb(0x6A778A), rgb(0x1A2029), rgb(0x0B0F15)] as CFArray, locations: [0, 0.6, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 2.6, y: 4.4), startRadius: 0, endCenter: CGPoint(x: 3.5, y: 3.5), endRadius: 3.6, options: [])
        ctx.restoreGState()
        ctx.paint(c, stroke: edge, width: 0.5)
    }

    // MARK: Glows & effects

    static let glowDot: SKTexture = TextureFactory.make(CGSize(width: 24, height: 24), scale: 2) { ctx in
        let g = CGGradient(colorsSpace: nil, colors: [rgb(0xFFFFFF, 1), rgb(0xFFFFFF, 0.8), rgb(0xFFF3EA, 0.25), rgb(0xFFF3EA, 0)] as CFArray,
                           locations: [0, 0.18, 0.5, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 12, y: 12), startRadius: 0, endCenter: CGPoint(x: 12, y: 12), endRadius: 12, options: [])
    }

    static let spark: SKTexture = TextureFactory.make(CGSize(width: 16, height: 16), scale: 2) { ctx in
        let g = CGGradient(colorsSpace: nil, colors: [rgb(0xFFFFFF, 1), rgb(0xFFFFFF, 0.5), rgb(0xFFFFFF, 0)] as CFArray,
                           locations: [0, 0.35, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 8, y: 8), startRadius: 0, endCenter: CGPoint(x: 8, y: 8), endRadius: 8, options: [])
    }

    static let dust: SKTexture = TextureFactory.make(CGSize(width: 16, height: 16), scale: 2) { ctx in
        let g = CGGradient(colorsSpace: nil, colors: [rgb(0xC9CFD8, 0.75), rgb(0xC9CFD8, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 8, y: 8), startRadius: 0, endCenter: CGPoint(x: 8, y: 8), endRadius: 8, options: [])
    }
}
