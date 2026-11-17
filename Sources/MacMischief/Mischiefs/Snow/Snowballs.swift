import SpriteKit
import os

/// Hover over piled-up snow to roll a snowball. Move along the pile to grow it,
/// move off the snow to let go (it flies with your cursor's speed), then it
/// bounces, rolls, bursts on hard landings, and eventually melts back in.
@MainActor
final class SnowballSystem {
    @MainActor private final class Ball {
        enum State { case held, flying, rolling, melting }
        let node = SKNode()
        let body = SKSpriteNode(texture: SnowArt.snowball)
        let detail = SKSpriteNode(texture: SnowArt.snowballDetail)
        var pos: CGPoint
        var vel = CGVector.zero
        var area: CGFloat
        var radius: CGFloat = 4
        var spin: CGFloat = 0
        var state: State = .held
        weak var support: SnowPile?
        var rest: CGFloat = 0
        var melt: CGFloat = 0
        var squash: CGFloat = 0

        init(at p: CGPoint, area: CGFloat) {
            pos = p
            self.area = area
            node.addChild(body)
            detail.zPosition = 0.1
            node.addChild(detail)
            node.zPosition = 103
            updateRadius()
        }

        func updateRadius() {
            radius = clamp(sqrt(area / .pi) * 1.35, 4, 30)
        }

        func sync() {
            let side = radius * 2 * 64 / 54
            body.size = CGSize(width: side, height: side)
            detail.size = body.size
            detail.zRotation = spin
            squash *= 0.86
            node.xScale = 1 + squash * 0.5
            node.yScale = 1 - squash
            node.position = CGPoint(x: pos.x, y: pos.y - radius * squash)
        }
    }

    private let parent: SKNode
    private let spawnClump: (CGPoint, CGFloat, CGVector) -> Void
    private var balls: [Ball] = []
    private weak var held: Ball?
    private let maxBalls = 6
    /// The cursor must rest on snow briefly before a snowball starts.
    private var dwell: CGFloat = 0
    private weak var dwellPile: SnowPile?

    init(parent: SKNode, spawnClump: @escaping (CGPoint, CGFloat, CGVector) -> Void) {
        self.parent = parent
        self.spawnClump = spawnClump
    }

    private static let log = Logger(subsystem: "app.macmischief", category: "snowball")
    private var logTimer: CGFloat = 0

    func update(dt: CGFloat, mouse: CGPoint, mouseVel: CGVector, piles: [SnowPile], size: CGSize, enabled: Bool) {
        logTimer += dt
        if logTimer > 3, UserDefaults.standard.bool(forKey: "debugSnow") {
            logTimer = 0
            let desc = piles.map { p in
                "[y=\(Int(p.baseY)) x=\(Int(p.minX))-\(Int(p.maxX)) max=\(String(format: "%.1f", p.localMax(at: (p.minX + p.maxX) / 2, span: p.count))) underMouse=\(String(format: "%.1f", p.localMax(at: mouse.x, span: 3))) surf=\(p.surfaceY(at: mouse.x).map { String(format: "%.0f", $0) } ?? "nil")]"
            }.joined(separator: " ")
            Self.log.notice("mouse=(\(Int(mouse.x)),\(Int(mouse.y))) size=\(Int(size.width))x\(Int(size.height)) balls=\(self.balls.count) held=\(self.held != nil) enabled=\(enabled) piles=\(piles.count) \(desc, privacy: .public)")
        }
        if enabled { handleCursor(dt: dt, mouse: mouse, mouseVel: mouseVel, piles: piles) }
        if !enabled, let h = held { release(h, mouseVel: .zero) }

        var i = 0
        while i < balls.count {
            let b = balls[i]
            switch b.state {
            case .held: break
            case .flying: fly(b, dt: dt, piles: piles, size: size)
            case .rolling: roll(b, dt: dt, piles: piles, size: size)
            case .melting:
                b.melt += dt / 2.2
                b.node.alpha = max(0, 1 - b.melt)
                b.area *= max(0, 1 - dt * 0.6)
                b.updateRadius()
            }
            b.sync()
            if b.node.parent == nil || b.melt >= 1 || b.pos.y < -80 {
                if b.melt >= 1, let p = b.support, piles.contains(where: { $0 === p }) {
                    p.addSnow(at: b.pos.x, area: b.area * 0.9, radius: b.radius)
                }
                b.node.removeFromParent()
                balls.remove(at: i)
                continue
            }
            i += 1
        }
    }

    // MARK: - Cursor

    private func handleCursor(dt: CGFloat, mouse: CGPoint, mouseVel: CGVector, piles: [SnowPile]) {
        if let b = held {
            guard let p = b.support, piles.contains(where: { $0 === p }),
                  let s = p.surfaceY(at: mouse.x),
                  mouse.y >= p.baseY - 10, mouse.y <= s + b.radius * 2 + 18 else {
                release(b, mouseVel: mouseVel)
                return
            }
            // Roll along under the cursor, scooping up snow as it goes.
            let target = CGPoint(x: mouse.x, y: s + b.radius - min(b.radius * 0.25, 3))
            let dx = target.x - b.pos.x
            b.pos.x += dx * min(1, dt * 18)
            b.pos.y += (target.y - b.pos.y) * min(1, dt * 18)
            b.spin -= dx * min(1, dt * 18) / b.radius
            let want = (70 + min(abs(mouseVel.dx), 800) * 0.35) * dt
            if b.radius < 30 {
                b.area += p.scoop(at: b.pos.x, radius: max(6, b.radius), amount: want)
                b.updateRadius()
            }
            return
        }

        // Start a new snowball when hovering over a decent pile.
        var best: (SnowPile, CGFloat)?
        for p in piles {
            guard p.localMax(at: mouse.x, span: 3) >= 2.5, let s = p.surfaceY(at: mouse.x),
                  mouse.y >= p.baseY - 6, mouse.y <= s + 14 else { continue }
            if best == nil || s > best!.1 { best = (p, s) }
        }
        guard let (pile, surface) = best else {
            dwell = 0
            dwellPile = nil
            return
        }
        if dwellPile !== pile { dwellPile = pile; dwell = 0 }
        dwell += dt
        guard dwell >= 0.25 else { return }
        dwell = 0
        if balls.count >= maxBalls, let oldest = balls.first(where: { $0.state != .held && $0.state != .melting }) {
            oldest.state = .melting
        }
        let got = pile.scoop(at: mouse.x, radius: 6, amount: 30)
        guard got > 4 else { return }
        let b = Ball(at: CGPoint(x: mouse.x, y: surface + 4), area: got)
        b.support = pile
        b.node.setScale(0.2)
        b.node.run(.scale(to: 1, duration: 0.15))
        parent.addChild(b.node)
        balls.append(b)
        held = b
    }

    private func release(_ b: Ball, mouseVel: CGVector) {
        held = nil
        var v = CGVector(dx: mouseVel.dx * 0.75, dy: mouseVel.dy * 0.75)
        let speed = hypot(v.dx, v.dy)
        if speed > 1100 { v.dx *= 1100 / speed; v.dy *= 1100 / speed }
        b.vel = v
        b.state = .flying
    }

    // MARK: - Physics

    private func fly(_ b: Ball, dt: CGFloat, piles: [SnowPile], size: CGSize) {
        b.vel.dy -= 1500 * dt
        var next = CGPoint(x: b.pos.x + b.vel.dx * dt, y: b.pos.y + b.vel.dy * dt)
        if next.x < b.radius { next.x = b.radius; b.vel.dx = abs(b.vel.dx) * 0.6 }
        if next.x > size.width - b.radius { next.x = size.width - b.radius; b.vel.dx = -abs(b.vel.dx) * 0.6 }
        b.spin -= b.vel.dx * dt / b.radius

        if b.vel.dy <= 0 {
            var hit: (SnowPile, CGFloat)?
            for p in piles {
                guard let s = p.surfaceY(at: next.x) else { continue }
                if b.pos.y - b.radius >= s - 1, next.y - b.radius <= s {
                    if hit == nil || s > hit!.1 { hit = (p, s) }
                }
            }
            if let (pile, s) = hit {
                if b.vel.dy < -720 {
                    splat(b, on: pile, at: CGPoint(x: next.x, y: s))
                    return
                }
                next.y = s + b.radius
                b.vel.dy = -b.vel.dy * 0.3
                b.vel.dx *= 0.85
                b.squash = min(0.3, abs(b.vel.dy) / 900 + 0.08)
                if abs(b.vel.dy) < 90 {
                    b.vel.dy = 0
                    b.state = .rolling
                    b.support = pile
                    b.rest = 0
                }
            }
        }
        b.pos = next
    }

    private func roll(_ b: Ball, dt: CGFloat, piles: [SnowPile], size: CGSize) {
        guard let p = b.support, piles.contains(where: { $0 === p }), let s = p.surfaceY(at: b.pos.x) else {
            b.state = .flying
            return
        }
        b.vel.dx *= max(0, 1 - dt * 1.6)
        b.pos.x += b.vel.dx * dt
        if b.pos.x < b.radius || b.pos.x > size.width - b.radius {
            b.vel.dx = -b.vel.dx * 0.5
            b.pos.x = clamp(b.pos.x, b.radius, size.width - b.radius)
        }
        b.pos.y += (s + b.radius - min(b.radius * 0.2, 2.5) - b.pos.y) * min(1, dt * 20)
        b.spin -= b.vel.dx * dt / b.radius
        // Rolling picks up a little more snow.
        if abs(b.vel.dx) > 40, b.radius < 30 {
            b.area += p.scoop(at: b.pos.x, radius: b.radius, amount: abs(b.vel.dx) * dt * 0.15)
            b.updateRadius()
        }
        if abs(b.vel.dx) < 4 {
            b.rest += dt
            if b.rest > 9 { b.state = .melting }
        } else {
            b.rest = 0
        }
    }

    private func splat(_ b: Ball, on pile: SnowPile, at p: CGPoint) {
        pile.addSnow(at: p.x, area: b.area * 0.6, radius: b.radius * 1.4)
        let n = Int(clamp(b.radius * 0.8, 6, 18))
        for k in 0..<n {
            let a = CGFloat.pi * (0.1 + 0.8 * CGFloat(k) / CGFloat(max(1, n - 1)))
            let speed = CGFloat.random(in: 120...320)
            spawnClump(CGPoint(x: p.x + cos(a) * b.radius * 0.5, y: p.y + 2),
                       CGFloat.random(in: 2.5...max(3, b.radius * 0.35)),
                       CGVector(dx: cos(a) * speed + b.vel.dx * 0.2, dy: sin(a) * speed))
        }
        b.node.removeFromParent()
        b.melt = 1
        b.support = nil
    }

    func removeAll() {
        held = nil
        balls.forEach { $0.node.removeFromParent() }
        balls.removeAll()
    }
}
