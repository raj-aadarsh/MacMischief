import AppKit
import SpriteKit
import SwiftUI

/// Developer tool: renders preview images of the art without touching the real
/// desktop. Run: `.build/release/MacMischief --snapshot <dir>`
@MainActor
enum SnapshotRenderer {
    static func run(outDir: String) {
        let dir = URL(fileURLWithPath: outDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        renderPoses(to: dir.appendingPathComponent("cat-poses.png"))
        renderDesktop(to: dir.appendingPathComponent("desktop.png"))
        renderMenu(to: dir.appendingPathComponent("menu.png"))
        renderHero(to: dir.appendingPathComponent("hero.png"))
        renderSnowballs(dir)
    }

    /// Simulates a cursor rolling a snowball along a window pile, then flicking it.
    private static func renderSnowballs(_ dir: URL) {
        let size = CGSize(width: 1400, height: 820)
        let scene = OverlayScene(screenFrame: CGRect(origin: .zero, size: size), floorY: 64, displayID: 0, isPrimary: true)
        scene.mouseOverride = CGPoint(x: -5000, y: -5000)
        background(scene, size, top: 0x3B5A86, bottom: 0x8FA9C9)
        let windows: [(CGWindowID, CGRect)] = [
            (2, CGRect(x: 460, y: 140, width: 560, height: 300)),
            (1, CGRect(x: 90, y: 230, width: 520, height: 380)),
        ]
        for (z, (_, frame)) in windows.reversed().enumerated() { drawWindow(frame, in: scene, z: CGFloat(-40 + z * 3)) }
        scene.updateGeometry(snapshot: WindowSnapshot(windows: windows.map { TrackedWindow(id: $0.0, frame: $0.1) }), floorY: 64)
        let snow = SnowMischief().makeLayer(for: scene)!
        scene.addLayer(snow)
        for _ in 0..<(150 * 30) { scene.step(1.0 / 30.0) }

        let top: CGFloat = 610
        var x: CGFloat = 130
        scene.mouseOverride = CGPoint(x: x, y: top + 8)
        for _ in 0..<(60 * 3) {          // roll right along the pile for 3 s
            x += 260.0 / 60
            scene.mouseOverride = CGPoint(x: x, y: top + 10)
            scene.step(1.0 / 60.0)
        }
        write(scene, size: size, to: dir.appendingPathComponent("snowball-held.png"))
        for _ in 0..<6 {                 // flick up and to the right
            x += 14
            scene.mouseOverride = CGPoint(x: x, y: scene.mouseOverride!.y + 18)
            scene.step(1.0 / 60.0)
        }
        scene.mouseOverride = CGPoint(x: -5000, y: -5000)
        for _ in 0..<20 { scene.step(1.0 / 60.0) }
        write(scene, size: size, to: dir.appendingPathComponent("snowball-thrown.png"))
        for _ in 0..<(60 * 2) { scene.step(1.0 / 60.0) }
        write(scene, size: size, to: dir.appendingPathComponent("snowball-landed.png"))
    }

    private static func renderHero(to url: URL) {
        let poses: [(HeroPose, CGFloat, CGFloat, CGFloat)] = [   // pose, bodyAngle, boot, palm
            (.stand, 0, 0, 0), (.hover, 0, 0.5, 0.7), (.hover, -0.3, 0.6, 0.5), (.flight, -.pi / 2, 1, 0.1),
            (.dash, -.pi / 2 + 0.25, 1.2, 0), (.landing, 0, 0, 0), (.crouch, 0, 0, 0), (.wave, 0, 0.5, 0.6),
        ]
        let size = CGSize(width: CGFloat(poses.count) * 150 + 40, height: 420)
        let scene = SKScene(size: size)
        scene.anchorPoint = .zero
        background(scene, size, top: 0xDCE3EC, bottom: 0xC7D2DF)
        let dark = SKSpriteNode(color: .hex(0x1E2128), size: CGSize(width: size.width, height: size.height / 2))
        dark.anchorPoint = .zero
        dark.zPosition = -50
        scene.addChild(dark)
        for row in 0..<2 {
            for (i, item) in poses.enumerated() {
                let h = HeroNode(scale: 2)
                h.target = item.0
                h.bodyAngle = item.1
                h.bootThrust = item.2
                h.palmThrust = item.3
                h.waving = item.0.nS > 2.5 && item.0.spine > 0
                scene.addChild(h)
                h.position = CGPoint(x: 90 + CGFloat(i) * 150, y: CGFloat(1 - row) * 210 + 100)
                for _ in 0..<90 { h.update(dt: 1.0 / 60.0) }
                if item.1 == 0 && item.2 == 0 {
                    h.position.y += CGFloat(1 - row) * 210 + 22 - h.lowestPoint()
                }
            }
        }
        write(scene, size: size, to: url)
    }

    private static func renderMenu(to url: URL) {
        let items = MischiefRegistry.all.map {
            MischiefCardInfo(id: $0.id, title: $0.title, emoji: $0.emoji, tagline: $0.tagline,
                             colors: $0.colors.map { Color(hex: $0) })
        }
        let model = MenuModel(items: items, activeID: "cat", hideInFullScreen: true)
        let view = MenuView(model: model).background(Color(nsColor: .windowBackgroundColor))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return }
        try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)")
    }

    /// Writes a macOS .iconset folder (convert with `iconutil -c icns`).
    static func renderIconSet(to dir: String) {
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
            let px = points * scale
            let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
            drawIcon(ctx)
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
            try? rep.representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent(name))
        }
        print("wrote \(url.path)")
    }

    private static func drawIcon(_ ctx: CGContext) {
        let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                          cornerWidth: 185, cornerHeight: 185, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.3))
        ctx.paint(tile, fill: rgb(0xFF7A70))
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(tile)
        ctx.clip()
        let g = CGGradient(colorsSpace: nil, colors: [rgb(0xFFA05A), rgb(0xFF5E8A), rgb(0x8F6BFF)] as CFArray,
                           locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
        // Snow sprinkles
        for (x, y, r) in [(220, 800, 16), (330, 860, 10), (800, 830, 18), (870, 720, 11), (180, 640, 9),
                          (760, 900, 8), (900, 560, 13), (260, 300, 10), (840, 260, 12), (470, 880, 9)] as [(CGFloat, CGFloat, CGFloat)] {
            ctx.paint(ellipse(x - r, y - r, r * 2, r * 2), fill: rgb(0xFFFFFF, 0.55))
        }
        // Snowy ground
        let ground = CGMutablePath()
        ground.move(to: CGPoint(x: 100, y: 100))
        ground.addLine(to: CGPoint(x: 100, y: 250))
        ground.addCurve(to: CGPoint(x: 924, y: 240), control1: CGPoint(x: 380, y: 310), control2: CGPoint(x: 640, y: 190))
        ground.addLine(to: CGPoint(x: 924, y: 100))
        ground.closeSubpath()
        ctx.paint(ground, fill: rgb(0xFFFFFF, 0.92))
        ctx.restoreGState()

        // Cat head
        ctx.saveGState()
        ctx.translateBy(x: 512 - 23 * 15.5, y: 470 - 20 * 15.5)
        ctx.scaleBy(x: 15.5, y: 15.5)
        ctx.setShadow(offset: CGSize(width: 0, height: -0.6), blur: 1.5, color: rgb(0x000000, 0.25))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        for side in [CGFloat(-1), 1] {
            ctx.saveGState()
            ctx.translateBy(x: 23 + side * 8.2, y: 26.5)
            ctx.rotate(by: -side * 0.22)
            ctx.scaleBy(x: side < 0 ? 1 : -1, y: 1)
            ctx.translateBy(x: -6, y: -1.2)
            CatArt.drawEar(ctx)
            ctx.restoreGState()
        }
        CatArt.drawHead(ctx)
        ctx.endTransparencyLayer()
        for cx in [CGFloat(18.3), 27.7] {
            let eye = ellipse(cx - 3.3, 12.4, 6.6, 7.8)
            ctx.paint(eye, fill: CatArt.iris)
            ctx.paint(eye, stroke: CatArt.outline, width: 0.8)
            ctx.paint(ellipse(cx - 1.8 + 0.6, 13.2, 3.6, 5.8), fill: CatArt.pupilColor)
            ctx.paint(ellipse(cx - 1.2 + 0.6, 16.6, 1.6, 1.6), fill: rgb(0xFFFFFF))
        }
        ctx.restoreGState()
    }

    private static func renderPoses(to url: URL) {
        let modes: [PetMode] = [.stand, .walk, .run, .sit, .sleep, .crouch, .playBow, .air, .groom, .happy, .speak,
                                .sniff, .dig, .rollOver, .scratch, .beg]
        let size = CGSize(width: 16 * 104 + 40, height: 340)
        let scene = SKScene(size: size)
        scene.anchorPoint = .zero
        background(scene, size, top: 0xDCE3EC, bottom: 0xC7D2DF)
        let dark = SKSpriteNode(color: .hex(0x1E2128), size: CGSize(width: size.width, height: size.height / 2))
        dark.anchorPoint = .zero
        dark.zPosition = -50
        scene.addChild(dark)

        for row in 0..<2 {
            for (i, mode) in modes.enumerated() {
                let pet: QuadrupedNode = row == 0 ? CatNode(scale: 1.4) : DogNode(scale: 1.4)
                pet.mode = mode
                pet.gaitSpeed = mode == .run ? 220 : 55
                pet.position = CGPoint(x: 60 + CGFloat(i) * 104, y: CGFloat(1 - row) * 170 + 40)
                pet.lookTarget = CGPoint(x: pet.position.x + 120, y: pet.position.y + 80)
                scene.addChild(pet)
                for _ in 0..<70 { pet.update(dt: 1.0 / 60.0) }
            }
        }
        write(scene, size: size, to: url)
    }

    private static func renderDesktop(to url: URL) {
        let size = CGSize(width: 1400, height: 820)
        let scene = OverlayScene(screenFrame: CGRect(origin: .zero, size: size), floorY: 64, displayID: 0, isPrimary: true)
        scene.mouseOverride = CGPoint(x: -5000, y: -5000)
        background(scene, size, top: 0x3B5A86, bottom: 0x8FA9C9)

        // Fake desktop: menu bar, dock, and three windows (front to back: B, C, A).
        let windows: [(CGWindowID, CGRect)] = [
            (2, CGRect(x: 460, y: 140, width: 560, height: 300)),
            (3, CGRect(x: 920, y: 330, width: 420, height: 330)),
            (1, CGRect(x: 90, y: 230, width: 520, height: 380)),
        ]
        for (z, (_, frame)) in windows.reversed().enumerated() {
            drawWindow(frame, in: scene, z: CGFloat(-40 + z * 3))
        }
        let dock = SKShapeNode(rect: CGRect(x: 380, y: 6, width: 640, height: 58), cornerRadius: 16)
        dock.fillColor = .hex(0xFFFFFF, 0.35)
        dock.strokeColor = .hex(0xFFFFFF, 0.5)
        dock.zPosition = -30
        scene.addChild(dock)

        let snapshot = WindowSnapshot(windows: windows.map { TrackedWindow(id: $0.0, frame: $0.1) })
        scene.updateGeometry(snapshot: snapshot, floorY: 64)

        let snow = SnowMischief().makeLayer(for: scene)!
        scene.addLayer(snow)
        let cat = DogMischief().makeLayer(for: scene)!
        scene.addLayer(cat)
        for _ in 0..<(120 * 30) { scene.step(1.0 / 30.0) }
        write(scene, size: size, to: url)
    }

    private static func drawWindow(_ frame: CGRect, in scene: SKScene, z: CGFloat) {
        let shadow = SKShapeNode(rect: frame.offsetBy(dx: 0, dy: -6).insetBy(dx: -4, dy: -4), cornerRadius: 14)
        shadow.fillColor = .hex(0x000000, 0.18)
        shadow.strokeColor = .clear
        shadow.zPosition = z
        let win = SKShapeNode(rect: frame, cornerRadius: 10)
        win.fillColor = .hex(0xF6F6F6)
        win.strokeColor = .hex(0x000000, 0.2)
        win.zPosition = z + 1
        let bar = SKShapeNode(rect: CGRect(x: frame.minX, y: frame.maxY - 28, width: frame.width, height: 28), cornerRadius: 10)
        bar.fillColor = .hex(0xE6E6E6)
        bar.strokeColor = .clear
        bar.zPosition = z + 2
        scene.addChild(shadow)
        scene.addChild(win)
        scene.addChild(bar)
        for (i, color) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            let dot = SKShapeNode(circleOfRadius: 6)
            dot.fillColor = .hex(UInt32(color))
            dot.strokeColor = .clear
            dot.position = CGPoint(x: frame.minX + 18 + CGFloat(i) * 20, y: frame.maxY - 14)
            dot.zPosition = z + 2.5
            scene.addChild(dot)
        }
    }

    private static func background(_ scene: SKScene, _ size: CGSize, top: UInt32, bottom: UInt32) {
        let tex = TextureFactory.make(size, scale: 1) { ctx in
            let g = CGGradient(colorsSpace: nil, colors: [rgb(top), rgb(bottom)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
        }
        let bg = SKSpriteNode(texture: tex, size: size)
        bg.anchorPoint = .zero
        bg.zPosition = -100
        scene.addChild(bg)
    }

    private static func write(_ scene: SKScene, size: CGSize, to url: URL) {
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        view.ignoresSiblingOrder = true
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.presentScene(scene)
        guard let texture = view.texture(from: scene) else {
            print("render failed: \(url.lastPathComponent)")
            return
        }
        let rep = NSBitmapImageRep(cgImage: texture.cgImage())
        do {
            try rep.representation(using: .png, properties: [:])?.write(to: url)
            print("wrote \(url.path)")
        } catch {
            print("write failed: \(error)")
        }
    }
}
