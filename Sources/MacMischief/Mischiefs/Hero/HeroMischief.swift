import SpriteKit

final class HeroMischief: Mischief {
    let id = "skybolt"
    let title = "Skybolt"
    let symbolName = "bolt.fill"
    let emoji = "🦾"
    let tagline = "An armoured jet-suit hero. Flies, loops & lands in style."
    let colors: [UInt32] = [0xE03A3E, 0x3A4252]

    func makeLayer(for scene: OverlayScene) -> MischiefLayer? {
        guard scene.isPrimary else { return nil }
        return HeroLayer(mischiefID: id, overlay: scene)
    }
}

/// Skybolt's flight brain: steering-based flight with banking, loops, barrel
/// rolls, sonic-boom fly-bys, three-point landings on window tops, and
/// friendly hovering next to the cursor. Purely visual.
final class HeroLayer: MischiefLayer {
    private enum State {
        case entering, cruise, hover, loop, flyBy, approachLand, descend, landed, standing, crouch, takeoff
        case follow, wave, leaving
    }

    private let hero: any HeroBody
    private var thrusters: [SKEmitterNode] = []
    private var pos: CGPoint
    private var vel: CGVector
    private var state: State = .entering
    private var timer: CGFloat = 0
    private var waypoint = CGPoint.zero
    private var cruiseLegs = 0
    private var platforms: [Platform] = []
    private var platform: Platform?
    private var landingPlatform: Platform?
    private var landingX: CGFloat = 0
    private var angle: CGFloat = 0
    private var facingLocked = false
    private var loopCenter = CGPoint.zero
    private var loopRadius: CGFloat = 100
    private var loopAngle: CGFloat = 0
    private var loopTurned: CGFloat = 0
    private var loopDir: CGFloat = 1
    private var loopSpeed: CGFloat = 300
    private var rollTime: CGFloat = -1
    private var boomed = false
    private var time: CGFloat = 0
    private var boost: CGFloat = 0

    private var mouse = CGPoint.zero
    private var lastMouse: CGPoint?
    private var mouseSpeed: CGFloat = 0
    private var cursorCooldown: CGFloat = 6
    private var hoverTime: CGFloat = 0
    private var dismissal: (() -> Void)?

    private var size: CGSize { overlay?.size ?? CGSize(width: 1200, height: 800) }
    private var floorY: CGFloat { overlay?.geometry.floorY ?? 0 }

    override init(mischiefID: String, overlay: OverlayScene) {
        let fromLeft = Bool.random()
        let size = overlay.size
        pos = CGPoint(x: fromLeft ? -90 : size.width + 90, y: size.height * .random(in: 0.5...0.75))
        vel = CGVector(dx: fromLeft ? 560 : -560, dy: -40)
        if let stage = overlay.acquireStage3D?() ?? nil {
            hero = Hero3DNode(stage: stage, release: { [weak overlay] in overlay?.releaseStage3D?() })
        } else {
            hero = HeroNode()
        }
        super.init(mischiefID: mischiefID, overlay: overlay)
        zPosition = 60
        hero.facing = fromLeft ? 1 : -1
        addChild(hero)
        for _ in 0..<2 {
            let e = Self.makeThruster()
            e.targetNode = self
            e.zPosition = -1
            addChild(e)
            thrusters.append(e)
        }
        waypoint = CGPoint(x: size.width * .random(in: 0.35...0.65), y: size.height * .random(in: 0.45...0.7))
        state = .entering
        boomed = false
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) not supported") }

    static func makeThruster() -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = HeroArt.spark
        e.particleBirthRate = 0
        e.particleLifetime = 0.24
        e.particleLifetimeRange = 0.1
        e.particleSpeed = 230
        e.particleSpeedRange = 70
        e.emissionAngleRange = 0.16
        e.particleAlpha = 0.95
        e.particleAlphaSpeed = -3.6
        e.particleScale = 0.55
        e.particleScaleRange = 0.18
        e.particleScaleSpeed = -2.0
        e.particlePositionRange = CGVector(dx: 2, dy: 2)
        e.particleColorBlendFactor = 1
        e.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [SKColor.white, SKColor.hex(0xFFE4C2), SKColor.hex(0xFF7A2E), SKColor.hex(0xFF4A1C, 0)],
            times: [0, 0.2, 0.6, 1])
        e.particleBlendMode = .add
        return e
    }

    override var preferredFPS: Int { state == .standing || state == .landed ? 30 : 60 }

    // MARK: - World

    override func geometryDidChange() {
        guard let g = overlay?.geometry else { return }
        var list = [Platform(windowID: nil, y: g.floorY, minX: 0, maxX: g.size.width)]
        for e in g.edges where e.y < g.size.height - 120 && e.y > g.floorY + 60 {
            for span in e.spans where span.upperBound - span.lowerBound >= 90 {
                list.append(Platform(windowID: e.windowID, y: e.y, minX: span.lowerBound, maxX: span.upperBound))
            }
        }
        platforms = list

        // If the window we're standing on moves or vanishes: lift off immediately.
        if let p = platform, p.windowID != nil,
           !platforms.contains(where: { $0.isSameSurface(as: p) && $0.contains(pos.x, margin: 6) }) {
            takeOff(quick: true)
        }
        if let p = landingPlatform, p.windowID != nil,
           !platforms.contains(where: { $0.isSameSurface(as: p) && $0.contains(landingX, margin: 6) }),
           state == .approachLand || state == .descend {
            landingPlatform = nil
            startCruise()
        }
    }

    // MARK: - Decisions

    private func randomPoint() -> CGPoint {
        CGPoint(x: .random(in: 90...(size.width - 90)),
                y: .random(in: (floorY + 130)...(size.height - 110)))
    }

    private func startCruise() {
        state = .cruise
        facingLocked = false
        cruiseLegs = Int.random(in: 1...3)
        waypoint = randomPoint()
    }

    private func chooseNext() {
        facingLocked = false
        let roll = Double.random(in: 0..<100)
        switch roll {
        case ..<30: startCruise()
        case ..<44:
            state = .hover
            timer = .random(in: 2...4)
        case ..<58: startFlyBy()
        case ..<82 where platforms.count > 0: startLanding()
        default: startCruise()
        }
    }

    private func startFlyBy() {
        state = .flyBy
        boomed = false
        let toRight = pos.x < size.width / 2
        waypoint = CGPoint(x: toRight ? size.width - 120 : 120, y: .random(in: (floorY + 160)...(size.height - 140)))
    }

    private func startLanding() {
        let candidates = platforms.filter { $0.width > 110 }
        guard let p = candidates.randomElement() else { startCruise(); return }
        landingPlatform = p
        landingX = .random(in: (p.minX + 50)...(p.maxX - 50))
        state = .approachLand
    }

    private func startLoop() -> Bool {
        let speed = max(hypot(vel.dx, vel.dy), 280)
        let r = CGFloat.random(in: 80...120)
        // Loop upwards relative to the direction of travel.
        let dir: CGFloat = vel.dx >= 0 ? 1 : -1
        let n = CGVector(dx: -vel.dy / speed * dir, dy: vel.dx / speed * dir)
        let c = CGPoint(x: pos.x + n.dx * r, y: pos.y + n.dy * r)
        guard c.y + r < size.height - 50, c.y - r > floorY + 40, c.x - r > 30, c.x + r < size.width - 30 else { return false }
        loopCenter = c
        loopRadius = r
        loopAngle = atan2(pos.y - c.y, pos.x - c.x)
        loopTurned = 0
        loopDir = dir
        loopSpeed = speed
        facingLocked = true
        state = .loop
        return true
    }

    private func takeOff(quick: Bool) {
        platform = nil
        if quick {
            state = .takeoff
            vel = CGVector(dx: hero.facing * 60, dy: 520)
            timer = 0.5
            boost = 1
        } else {
            state = .crouch
            timer = 0.35
        }
    }

    // MARK: - Frame

    override func update(dt: CGFloat) {
        time += dt
        cursorCooldown -= dt
        timer -= dt
        boost = max(0, boost - dt * 1.5)
        trackMouse(dt)

        var grounded = false
        var poseOverride: HeroPose?

        switch state {
        case .entering:
            steer(to: waypoint, maxSpeed: 560, accel: 500, dt: dt, arrive: 260)
            if hypot(waypoint.x - pos.x, waypoint.y - pos.y) < 60 { state = .hover; timer = 2 }
        case .cruise:
            steer(to: waypoint, maxSpeed: 320, accel: 520, dt: dt, arrive: 120)
            if hypot(waypoint.x - pos.x, waypoint.y - pos.y) < 70 {
                cruiseLegs -= 1
                if cruiseLegs <= 0 { chooseNext() } else { waypoint = randomPoint() }
            } else if rollTime < 0 && Double.random(in: 0..<1) < Double(dt) * 0.12 && hypot(vel.dx, vel.dy) > 220 {
                if Bool.random() || !startLoop() { rollTime = 0 }
            }
        case .flyBy:
            steer(to: waypoint, maxSpeed: 680, accel: 900, dt: dt, arrive: 200)
            if !boomed && hypot(vel.dx, vel.dy) > 560 {
                boomed = true
                sonicBoom()
            }
            if hypot(waypoint.x - pos.x, waypoint.y - pos.y) < 80 { state = .hover; timer = .random(in: 1.5...2.5) }
        case .loop:
            let w = loopSpeed / loopRadius
            loopAngle += w * dt * loopDir
            loopTurned += w * dt
            let prev = pos
            pos = CGPoint(x: loopCenter.x + cos(loopAngle) * loopRadius, y: loopCenter.y + sin(loopAngle) * loopRadius)
            vel = CGVector(dx: (pos.x - prev.x) / max(dt, 0.001), dy: (pos.y - prev.y) / max(dt, 0.001))
            if loopTurned >= 2 * .pi {
                facingLocked = false
                startCruise()
            }
        case .hover:
            steer(to: pos, maxSpeed: 60, accel: 300, dt: dt, arrive: 100)
            if timer <= 0 { chooseNext() }
        case .follow:
            let side: CGFloat = pos.x < mouse.x ? -1 : 1
            let target = CGPoint(x: clamp(mouse.x + side * 95, 60, size.width - 60),
                                 y: clamp(mouse.y - 10, floorY + 80, size.height - 80))
            steer(to: target, maxSpeed: 460, accel: 800, dt: dt, arrive: 160)
            if hypot(target.x - pos.x, target.y - pos.y) < 20 && hypot(vel.dx, vel.dy) < 60 {
                state = .wave
                timer = 2.2
            } else if timer <= 0 {
                state = .hover
                timer = 1
            }
        case .wave:
            steer(to: pos, maxSpeed: 40, accel: 300, dt: dt, arrive: 80)
            facingLocked = true
            hero.facing = mouse.x >= pos.x ? 1 : -1
            poseOverride = .wave
            if timer <= 0 {
                facingLocked = false
                state = .hover
                timer = 1.2
            }
        case .approachLand:
            guard let p = landingPlatform else { startCruise(); break }
            let target = CGPoint(x: landingX, y: p.y + 150)
            steer(to: target, maxSpeed: 360, accel: 600, dt: dt, arrive: 180)
            if hypot(target.x - pos.x, target.y - pos.y) < 24 && hypot(vel.dx, vel.dy) < 90 {
                state = .descend
                vel = CGVector(dx: 0, dy: -150)
            }
        case .descend:
            guard let p = landingPlatform else { startCruise(); break }
            vel.dx *= max(0, 1 - dt * 6)
            vel.dy = max(vel.dy - 2400 * dt, -950)
            pos.x += (landingX - pos.x) * min(1, dt * 6)
            poseOverride = .hover
            if hero.lowestPoint() + vel.dy * dt <= p.y {
                impact(on: p)
            }
        case .landed:
            grounded = true
            poseOverride = .landing
            if timer <= 0 {
                state = .standing
                timer = .random(in: 2.2...4)
            }
        case .standing:
            grounded = true
            poseOverride = .stand
            if hypot(mouse.x - pos.x, mouse.y - pos.y) < 220 {
                hero.facing = mouse.x >= pos.x ? 1 : -1
            }
            if timer <= 0 { takeOff(quick: false) }
        case .crouch:
            grounded = true
            poseOverride = .crouch
            if timer <= 0 {
                state = .takeoff
                vel = CGVector(dx: hero.facing * 90, dy: 640)
                boost = 1
                timer = 0.55
            }
        case .takeoff:
            vel.dy -= 500 * dt
            if timer <= 0 { startCruise() }
        case .leaving:
            vel.dy = min(vel.dy + 1600 * dt, 1100)
            vel.dx *= max(0, 1 - dt * 2)
            boost = 1
            if pos.y > size.height + 140 {
                let done = dismissal
                dismissal = nil
                done?()
            }
        }

        if !grounded && state != .loop {
            pos.x += vel.dx * dt
            pos.y += vel.dy * dt
        }
        if grounded {
            vel = .zero
            if let p = platform {
                hero.position = pos
                let low = hero.lowestPoint()
                pos.y += p.y - low
            }
        }

        updateOrientation(dt, grounded: grounded, override: poseOverride)

        let bob: CGFloat = grounded ? 0 : 2.5 * sin(time * 2.3) * (1 - smoothstep(60, 200, hypot(vel.dx, vel.dy)))
        hero.position = CGPoint(x: pos.x, y: pos.y + bob)
        hero.update(dt: dt)
        updateThrusters(grounded: grounded)
    }

    private func steer(to target: CGPoint, maxSpeed: CGFloat, accel: CGFloat, dt: CGFloat, arrive: CGFloat) {
        let dx = target.x - pos.x, dy = target.y - pos.y
        let dist = hypot(dx, dy)
        let speed = dist < arrive ? maxSpeed * dist / arrive : maxSpeed
        let desired = dist > 0.01 ? CGVector(dx: dx / dist * speed, dy: dy / dist * speed) : .zero
        var ax = desired.dx - vel.dx, ay = desired.dy - vel.dy
        let a = hypot(ax, ay), maxA = accel * dt
        if a > maxA { ax *= maxA / a; ay *= maxA / a }
        vel.dx += ax
        vel.dy += ay
    }

    private func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = clamp((x - a) / (b - a), 0, 1)
        return t * t * (3 - 2 * t)
    }

    private func updateOrientation(_ dt: CGFloat, grounded: Bool, override: HeroPose?) {
        let speed = hypot(vel.dx, vel.dy)
        if !facingLocked && !grounded && abs(vel.dx) > 50 {
            hero.facing = vel.dx > 0 ? 1 : -1
        }
        let f = (grounded || state == .descend || state == .takeoff || state == .wave) ? 0 : smoothstep(110, 280, speed)
        let lvx = vel.dx * hero.facing, lvy = vel.dy
        let hoverAngle = clamp(-lvx / 650, -0.35, 0.35)
        let flightAngle = atan2(lvy, lvx) - .pi / 2
        var desired = hoverAngle + (flightAngle - hoverAngle) * f
        if grounded { desired = 0 }
        while desired - angle > .pi { desired -= 2 * .pi }
        while desired - angle < -.pi { desired += 2 * .pi }
        angle += (desired - angle) * min(1, dt * (state == .loop ? 14 : 7))
        hero.bodyAngle = angle

        // Barrel roll
        if rollTime >= 0 {
            rollTime += dt
            hero.roll = 2 * .pi * min(1, rollTime / 0.75)
            if rollTime >= 0.75 { rollTime = -1; hero.roll = 0 }
        }

        if let override {
            hero.target = override
            hero.poseRate = state == .landed ? 18 : 8
        } else {
            let dashW = smoothstep(420, 560, speed)
            hero.target = HeroPose.mix(HeroPose.mix(.hover, .flight, f), .dash, dashW)
            hero.poseRate = 8
        }
        hero.waving = state == .wave

        if grounded {
            hero.bootThrust = 0
            hero.palmThrust = 0
        } else {
            hero.bootThrust = 0.45 + 0.55 * f + boost * 0.6
            hero.palmThrust = (1 - f) * 0.7
        }
    }

    private func updateThrusters(grounded: Bool) {
        let jets = hero.thrusters(in: self)
        for (i, e) in thrusters.enumerated() where i < jets.count {
            e.position = jets[i].0
            e.emissionAngle = jets[i].1
            e.particleBirthRate = grounded ? 0 : 140 + 260 * hero.bootThrust
            e.particleSpeed = 160 + 160 * hero.bootThrust
        }
    }

    // MARK: - Moments

    private func impact(on p: Platform) {
        platform = p
        landingPlatform = nil
        state = .landed
        timer = 1.5
        vel = .zero
        hero.target = .landing
        // Dust burst + shockwave along the surface
        for i in 0..<14 {
            let d = SKSpriteNode(texture: HeroArt.dust, size: CGSize(width: 16, height: 16))
            let dir: CGFloat = i % 2 == 0 ? 1 : -1
            d.position = CGPoint(x: pos.x + dir * .random(in: 0...10), y: p.y + 3)
            d.zPosition = 5
            d.setScale(.random(in: 0.6...1.2))
            addChild(d)
            let move = SKAction.moveBy(x: dir * .random(in: 30...90), y: .random(in: 4...22), duration: 0.6)
            move.timingMode = .easeOut
            d.run(.sequence([.group([move, .scale(by: 1.8, duration: 0.6), .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
        }
        let ring = SKShapeNode(ellipseOf: CGSize(width: 30, height: 7))
        ring.position = CGPoint(x: pos.x, y: p.y + 1)
        ring.strokeColor = .hex(0xFFE4C2, 0.9)
        ring.lineWidth = 1.5
        ring.glowWidth = 2
        ring.zPosition = 4
        addChild(ring)
        ring.run(.sequence([.group([.scaleX(to: 7, y: 4, duration: 0.45), .fadeOut(withDuration: 0.45)]), .removeFromParent()]))
    }

    private func sonicBoom() {
        for (i, delay) in [0.0, 0.08].enumerated() {
            let ring = SKShapeNode(circleOfRadius: 18)
            ring.position = pos
            ring.strokeColor = .hex(0xFFFFFF, i == 0 ? 0.85 : 0.5)
            ring.lineWidth = i == 0 ? 2 : 1.2
            ring.zPosition = 2
            ring.setScale(0.3)
            ring.alpha = 0
            addChild(ring)
            ring.run(.sequence([.wait(forDuration: delay), .fadeIn(withDuration: 0.02),
                                .group([.scale(to: 3.4, duration: 0.5), .fadeOut(withDuration: 0.5)]),
                                .removeFromParent()]))
        }
    }

    // MARK: - Cursor

    private func trackMouse(_ dt: CGFloat) {
        guard let scene = overlay else { return }
        mouse = scene.mouseLocation
        if let last = lastMouse {
            let v = hypot(mouse.x - last.x, mouse.y - last.y) / max(dt, 0.001)
            mouseSpeed += (v - mouseSpeed) * min(1, dt * 10)
        }
        lastMouse = mouse

        let d = hypot(mouse.x - pos.x, mouse.y - (pos.y + 12))
        // Cursor resting on the hero → a friendly wave.
        if d < 40 && mouseSpeed < 80 { hoverTime += dt } else { hoverTime = 0 }
        if hoverTime > 0.5, [.hover, .cruise].contains(state) {
            hoverTime = 0
            state = .wave
            timer = 2.2
            cursorCooldown = 10
            return
        }
        guard cursorCooldown <= 0, mouseSpeed > 160, d < 340,
              [.hover, .cruise].contains(state),
              mouse.y > floorY + 70, mouse.y < size.height - 70 else { return }
        cursorCooldown = .random(in: 14...24)
        if Bool.random() {
            state = .follow
            timer = 4
        }
    }

    override func willRemove() { hero.detach() }

    override func dismiss(completion: @escaping () -> Void) {
        dismissal = completion
        platform = nil
        landingPlatform = nil
        facingLocked = false
        state = .leaving
        if vel.dy < 200 { vel.dy = 200 }
        sonicBoom()
        run(.sequence([.wait(forDuration: 3), .run { [weak self] in
            let done = self?.dismissal
            self?.dismissal = nil
            done?()
        }]))
    }
}
