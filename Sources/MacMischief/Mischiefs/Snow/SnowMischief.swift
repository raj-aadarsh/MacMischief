import SpriteKit

final class SnowMischief: Mischief {
    let id = "snow"
    let title = "Snowfall"
    let symbolName = "snowflake"
    let emoji = "❄️"
    let tagline = "Snow piles up on your windows. Move one to shake it off."
    let colors: [UInt32] = [0x7FD3FF, 0x6C7BFF]

    func makeLayer(for scene: OverlayScene) -> MischiefLayer? {
        SnowLayer(mischiefID: id, overlay: scene)
    }
}

/// Falling snow that piles up on window tops and the Dock / bottom of the screen.
/// Moving or closing a window knocks its snow off. The cursor blows flakes aside.
final class SnowLayer: MischiefLayer {
    private struct Flake {
        let node: SKSpriteNode
        var x: CGFloat = 0
        var y: CGFloat = 0
        var vx: CGFloat = 0
        var fall: CGFloat = 0
        var size: CGFloat = 0
        var depth: CGFloat = 0
        var phase: CGFloat = 0
        var swayAmp: CGFloat = 0
        var swayFreq: CGFloat = 0
        var spin: CGFloat = 0
        var collides = false
        var done = false
    }

    private struct Clump {
        let node: SKSpriteNode
        var v: CGVector
        var life: CGFloat
    }

    private var flakes: [Flake] = []
    private var piles: [CGWindowID: SnowPile] = [:]
    private var floorPile: SnowPile?
    private var pileList: [SnowPile] = []
    private var clumps: [Clump] = []

    private let pileNode = SKNode()
    private let clumpNode = SKNode()
    private let dotNode = SKNode()
    private let crystalNode = SKNode()

    private var time: CGFloat = 0
    private var redrawTimer: CGFloat = 0
    private var lastMouse: CGPoint?
    private var mouseSpeed: CGFloat = 0
    private var mouseVel = CGVector.zero
    private var snowballs: SnowballSystem!
    private var stopping = false
    private var stopTimer: CGFloat = 0
    private var dismissCompletion: (() -> Void)?

    override init(mischiefID: String, overlay: OverlayScene) {
        super.init(mischiefID: mischiefID, overlay: overlay)
        pileNode.zPosition = 10
        clumpNode.zPosition = 11
        dotNode.zPosition = 100
        crystalNode.zPosition = 101
        [pileNode, clumpNode, dotNode, crystalNode].forEach(addChild)
        snowballs = SnowballSystem(parent: self) { [weak self] p, size, v in
            self?.addClump(at: p, size: size, velocity: v)
        }

        let size = overlay.size
        let count = Int(clamp(size.width * size.height / 5200, 120, 520))
        for _ in 0..<count {
            var flake = Flake(node: SKSpriteNode(texture: SnowArt.dot))
            configure(&flake, size: size)
            // Stagger the start so the snow drifts in gently from the top.
            flake.y = size.height + CGFloat.random(in: 0...size.height)
            flakes.append(flake)
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) not supported") }

    private func configure(_ f: inout Flake, size: CGSize) {
        let depth = pow(CGFloat.random(in: 0...1), 1.3)
        let crystal = depth > 0.72 && Bool.random()
        f.depth = depth
        f.size = 1.6 + depth * 5.0
        f.x = CGFloat.random(in: 0...size.width)
        f.y = size.height + CGFloat.random(in: 4...40)
        f.vx = 0
        f.fall = 17 + 40 * depth + CGFloat.random(in: -4...4)
        f.phase = CGFloat.random(in: 0...(2 * .pi))
        f.swayAmp = 5 + 13 * CGFloat.random(in: 0...1)
        f.swayFreq = 0.5 + CGFloat.random(in: 0...1.1)
        f.spin = CGFloat.random(in: -1.4...1.4)
        f.collides = depth > 0.28
        f.node.texture = crystal ? SnowArt.crystal : SnowArt.dot
        let side = crystal ? f.size * 2.1 : f.size * SnowArt.dotRatio
        f.node.size = CGSize(width: side, height: side)
        f.node.alpha = 0.5 + 0.5 * depth
        let parent = crystal ? crystalNode : dotNode
        if f.node.parent !== parent {
            f.node.removeFromParent()
            parent.addChild(f.node)
        }
    }

    // MARK: - Geometry

    override func geometryDidChange() {
        guard let g = overlay?.geometry else { return }
        var seen = Set<CGWindowID>()

        for edge in g.edges {
            seen.insert(edge.windowID)
            if let pile = piles[edge.windowID] {
                if Self.same(pile.frame, edge.frame) {
                    pile.setVisibleSpans(edge.spans)
                    continue
                }
                // Window moved or resized: shake the snow off.
                knockOff(pile, push: CGVector(dx: edge.frame.midX - pile.frame.midX, dy: edge.frame.maxY - pile.frame.maxY))
                piles[edge.windowID] = nil
            }
            guard !stopping else { continue }
            let lo = max(edge.frame.minX, 0), hi = min(edge.frame.maxX, g.size.width)
            guard hi - lo > 12 else { continue }
            let maxH = min(18, 8 + edge.frame.width * 0.012)
            let pile = SnowPile(frame: edge.frame, minX: lo, maxX: hi, baseY: edge.y, maxHeight: maxH, taper: true)
            pile.setVisibleSpans(edge.spans)
            pileNode.addChild(pile.node)
            piles[edge.windowID] = pile
        }

        for (id, pile) in piles where !seen.contains(id) {
            knockOff(pile, push: .zero)
            piles[id] = nil
        }

        if let floor = floorPile, abs(floor.baseY - g.floorY) > 0.5 {
            knockOff(floor, push: .zero)
            floorPile = nil
        }
        if floorPile == nil && !stopping {
            let floor = SnowPile(frame: CGRect(x: 0, y: g.floorY, width: g.size.width, height: 0),
                                 minX: 0, maxX: g.size.width, baseY: g.floorY, maxHeight: 26, taper: false)
            pileNode.addChild(floor.node)
            floorPile = floor
        }
        floorPile?.setVisibleSpans(g.floorSpans)

        pileList = Array(piles.values) + (floorPile.map { [$0] } ?? [])
    }

    private static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.maxY - b.maxY) < 0.5 && abs(a.width - b.width) < 0.5
    }

    private func knockOff(_ pile: SnowPile, push: CGVector) {
        let room = 700 - clumps.count
        if room > 0 {
            let seeds = pile.clumpSeeds()
            let stride = max(1, seeds.count / room + 1)
            for (n, seed) in seeds.enumerated() where n % stride == 0 {
                let side = clamp(3 + seed.1 * 0.8, 3, 14)
                let node = SKSpriteNode(texture: SnowArt.dot, size: CGSize(width: side * SnowArt.dotRatio, height: side * SnowArt.dotRatio))
                node.position = seed.0
                clumpNode.addChild(node)
                let v = CGVector(dx: clamp(push.dx, -300, 300) * 0.6 + CGFloat.random(in: -30...30),
                                 dy: clamp(push.dy, -200, 300) * 0.4 + CGFloat.random(in: 10...90))
                clumps.append(Clump(node: node, v: v, life: CGFloat.random(in: 1.2...1.9)))
            }
        }
        pile.node.removeFromParent()
    }

    // MARK: - Frame update

    override func update(dt: CGFloat) {
        guard let scene = overlay else { return }
        let size = scene.size
        time += dt

        let wind = 11 * sin(time * 0.11) + 6 * sin(time * 0.37 + 2)
        let mouse = scene.mouseLocation
        if let last = lastMouse {
            let v = hypot(mouse.x - last.x, mouse.y - last.y) / max(dt, 0.001)
            mouseSpeed += (v - mouseSpeed) * min(1, dt * 8)
            let raw = CGVector(dx: (mouse.x - last.x) / max(dt, 0.001), dy: (mouse.y - last.y) / max(dt, 0.001))
            let k = min(1, dt * 14)
            mouseVel = CGVector(dx: mouseVel.dx + (raw.dx - mouseVel.dx) * k, dy: mouseVel.dy + (raw.dy - mouseVel.dy) * k)
        }
        lastMouse = mouse
        let gust = 1 + min(mouseSpeed / 700, 2.5)
        let damping = max(0, 1 - dt * 2.5)

        var active = 0
        for i in flakes.indices {
            var f = flakes[i]
            if f.done { continue }
            active += 1

            // The cursor acts like a little umbrella that pushes flakes aside.
            let dx = f.x - mouse.x, dy = f.y - mouse.y
            let d2 = dx * dx + dy * dy
            if d2 < 75 * 75 {
                let d = sqrt(d2) + 0.01
                f.vx += dx / d * (75 - d) * 9 * gust * dt
            }
            f.vx *= damping

            let prevY = f.y
            f.x += (wind * (0.35 + f.depth) + f.swayAmp * sin(time * f.swayFreq + f.phase) + f.vx) * dt
            f.y -= f.fall * dt
            if f.x < -12 { f.x += size.width + 24 } else if f.x > size.width + 12 { f.x -= size.width + 24 }

            if f.collides && land(x: f.x, from: prevY, to: f.y, size: f.size) {
                if stopping { f.done = true; f.node.isHidden = true } else { configure(&f, size: size) }
            } else if f.y < -12 {
                if stopping { f.done = true; f.node.isHidden = true } else { configure(&f, size: size) }
            }

            f.node.position = CGPoint(x: f.x, y: f.y)
            f.node.zRotation += f.spin * dt
            flakes[i] = f
        }

        updateClumps(dt)
        snowballs.update(dt: dt, mouse: mouse, mouseVel: mouseVel, piles: pileList, size: size, enabled: !stopping)

        redrawTimer += dt
        if redrawTimer >= 1.0 / 12.0 {
            redrawTimer = 0
            for pile in pileList { pile.step() }
        }

        if stopping {
            stopTimer += dt
            if (active == 0 && clumps.isEmpty) || stopTimer > 5 {
                let done = dismissCompletion
                dismissCompletion = nil
                done?()
            }
        }
    }

    private func land(x: CGFloat, from prevY: CGFloat, to y: CGFloat, size: CGFloat) -> Bool {
        for pile in pileList {
            guard let c = pile.column(at: x), pile.visible[c] else { continue }
            let surface = pile.surface(c)
            if prevY >= surface && y <= surface {
                if !stopping { pile.deposit(at: c, amount: 1.0 + size * 0.6) }
                return true
            }
        }
        return false
    }

    private func addClump(at p: CGPoint, size side: CGFloat, velocity: CGVector) {
        guard clumps.count < 700 else { return }
        let node = SKSpriteNode(texture: SnowArt.dot, size: CGSize(width: side * SnowArt.dotRatio, height: side * SnowArt.dotRatio))
        node.position = p
        clumpNode.addChild(node)
        clumps.append(Clump(node: node, v: velocity, life: CGFloat.random(in: 0.9...1.5)))
    }

    private func updateClumps(_ dt: CGFloat) {
        guard !clumps.isEmpty else { return }
        var i = 0
        while i < clumps.count {
            var c = clumps[i]
            c.v.dy -= 900 * dt
            c.life -= dt
            c.node.position.x += c.v.dx * dt
            c.node.position.y += c.v.dy * dt
            c.node.alpha = min(1, c.life / 0.6)
            if c.life <= 0 || c.node.position.y < -30 {
                c.node.removeFromParent()
                clumps.swapAt(i, clumps.count - 1)
                clumps.removeLast()
                continue
            }
            clumps[i] = c
            i += 1
        }
    }

    override func dismiss(completion: @escaping () -> Void) {
        stopping = true
        dismissCompletion = completion
        snowballs.removeAll()
        for pile in pileList { knockOff(pile, push: .zero) }
        piles.removeAll()
        floorPile = nil
        pileList.removeAll()
    }
}
