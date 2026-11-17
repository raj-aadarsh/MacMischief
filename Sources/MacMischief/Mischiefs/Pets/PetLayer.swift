import AppKit
import SpriteKit

/// Something a pet can stand on: the floor (Dock top) or a visible window top.
struct Platform {
    var windowID: CGWindowID?
    var y: CGFloat
    var minX: CGFloat
    var maxX: CGFloat
    var width: CGFloat { maxX - minX }
    func contains(_ x: CGFloat, margin: CGFloat = 0) -> Bool { x >= minX - margin && x <= maxX + margin }
    func isSameSurface(as o: Platform) -> Bool { windowID == o.windowID && abs(y - o.y) < 1 }
}

enum PetChoice: Hashable {
    case walk, idle, sit, groom, stretch, sleep, speak, hearts, chaseTail, backflip, zoomies, jump
    case sniff, dig, playBow, rollOver, scratch, shake, beg
}

/// What makes a cat a cat and a dog a dog.
struct PetPersonality {
    enum CursorPlay { case stalkAndPounce, chaseAndBeg }
    var words: [String]
    var pettedWords: [String]
    var weights: [PetChoice: Double]
    var cursorPlay: CursorPlay
    var walkSpeed: ClosedRange<CGFloat>
    var pettedChoice: PetChoice
    var sleepy: Bool
}

/// The shared pet brain: wanders, naps, does tricks, hops between window tops,
/// plays with the cursor, and loves being "petted" (cursor resting on it).
/// Purely visual — it can never click anything.
final class PetLayer: MischiefLayer {
    private enum Activity: Equatable {
        case entering, idle, walking, sitting, grooming, sleeping, stretching
        case stalking, windup, jumping, falling, hearts, speak, chaseTail, leaving
        case sniffing, digging, playBow, rollOver, scratching, shaking, following, begging
    }

    private struct Jump {
        var from: CGPoint
        var to: CGPoint
        var peak: CGFloat
        var duration: CGFloat
        var elapsed: CGFloat = 0
        var platform: Platform
        var flips: Bool
        var then: Activity?
        var thenDuration: CGFloat = 0
    }

    private let pet: any PetBody
    private let personality: PetPersonality
    private let shadow = SKSpriteNode(texture: PetArt.shadow, size: CGSize(width: 50, height: 10))
    private var pos: CGPoint
    private var platform: Platform?
    private var platforms: [Platform] = []

    private var activity: Activity = .entering
    private var lastChoice: PetChoice = .idle
    private var timer: CGFloat = 0
    private var walkTarget: CGFloat = 0
    private var walkSpeed: CGFloat = 55
    private var zoomLegs = 0
    private var jump: Jump?
    private var pendingJump: Jump?
    private var velocity = CGVector.zero
    private var effectTimer: CGFloat = 0
    private var flipTimer: CGFloat = 0
    private var heartBurst: CGFloat = 0
    private var heartTimer: CGFloat = 0
    private var idleLook: CGPoint?

    private var mouse = CGPoint.zero
    private var mouseSpeed: CGFloat = 0
    private var hasMouse = false
    private var cursorCooldown: CGFloat = 8
    private var hoverTime: CGFloat = 0
    private var petCooldown: CGFloat = 0
    private var bubble: SKNode?

    private var s: CGFloat { pet.petScale }
    private var size: CGSize { overlay?.size ?? CGSize(width: 1200, height: 800) }
    private var floorPlatform: Platform {
        Platform(windowID: nil, y: overlay?.geometry.floorY ?? 0, minX: 0, maxX: size.width)
    }

    init(mischiefID: String, overlay: OverlayScene, pet: any PetBody, personality: PetPersonality) {
        self.pet = pet
        self.personality = personality
        pos = CGPoint(x: -50, y: overlay.geometry.floorY)
        super.init(mischiefID: mischiefID, overlay: overlay)
        zPosition = 50
        shadow.zPosition = -1
        addChild(shadow)
        addChild(pet)
        platform = floorPlatform
        walkTarget = .random(in: 160...380)
        walkSpeed = 60
        begin(.entering)
        pet.position = pos
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) not supported") }

    override var preferredFPS: Int {
        switch activity {
        case .sleeping, .sitting, .grooming, .idle, .speak, .leaving, .begging: return 30
        default: return 60
        }
    }

    // MARK: - World

    override func geometryDidChange() {
        guard let g = overlay?.geometry else { return }
        var list = [floorPlatform]
        for e in g.edges where e.y < g.size.height - 80 && e.y > g.floorY + 40 {
            for span in e.spans where span.upperBound - span.lowerBound >= 70 {
                list.append(Platform(windowID: e.windowID, y: e.y, minX: span.lowerBound, maxX: span.upperBound))
            }
        }
        platforms = list
        validatePlatform()
    }

    private func validatePlatform() {
        guard let current = platform else { return }
        guard current.windowID != nil else {
            let floor = floorPlatform
            platform = floor
            if abs(pos.y - floor.y) > 0.5 && activity != .jumping && activity != .falling { pos.y = floor.y }
            return
        }
        if let match = resolve(current, near: pos.x) {
            platform = match
        } else {
            platform = nil
            guard activity != .jumping, activity != .leaving else { return }
            pendingJump = nil
            say(activity == .sleeping ? "?!" : "!", duration: 0.9)
            velocity = CGVector(dx: CGFloat.random(in: -40...40), dy: 260)
            begin(.falling)
        }
    }

    private func resolve(_ p: Platform, near x: CGFloat) -> Platform? {
        if p.windowID == nil { return floorPlatform }
        return platforms.first { $0.isSameSurface(as: p) && $0.contains(x, margin: 8) }
    }

    // MARK: - Activities

    private func begin(_ a: Activity, duration: CGFloat = 0) {
        activity = a
        timer = duration
        switch a {
        case .entering, .walking, .following:
            pet.mode = walkSpeed > 120 ? .run : .walk
            pet.gaitSpeed = walkSpeed
        case .idle:
            pet.mode = .stand
            idleLook = CGPoint(x: pos.x + pet.facing * .random(in: 60...300), y: pos.y + .random(in: -40...200))
        case .sitting: pet.mode = .sit
        case .grooming: pet.mode = .groom
        case .sleeping:
            pet.mode = .sleep
            effectTimer = 1.2
        case .stretching: pet.mode = .stretch
        case .stalking, .windup: pet.mode = .crouch
        case .jumping, .falling: pet.mode = .air
        case .hearts:
            pet.mode = .happy
            heartBurst = max(heartBurst, duration - 0.6)
        case .speak:
            pet.mode = .speak
            say(personality.words.randomElement()!)
        case .chaseTail:
            pet.mode = .run
            pet.gaitSpeed = 160
            flipTimer = 0
        case .leaving: pet.mode = .sit
        case .sniffing:
            pet.mode = .sniff
            pet.gaitSpeed = 22
        case .digging:
            pet.mode = .dig
            effectTimer = 0
        case .playBow:
            pet.mode = .playBow
            if Bool.random() { say(personality.words.randomElement()!, duration: 1.1) }
        case .rollOver: pet.mode = .rollOver
        case .scratching: pet.mode = .scratch
        case .shaking:
            pet.mode = .shake
            effectTimer = 0
        case .begging: pet.mode = .beg
        }
    }

    private func duration(of a: Activity) -> CGFloat {
        switch a {
        case .sitting: return .random(in: 3...7)
        case .hearts: return 2.4
        case .speak: return 1.5
        case .rollOver: return 2.6
        case .begging: return .random(in: 2...3)
        case .playBow: return .random(in: 1.4...2.2)
        default: return 1.2
        }
    }

    private func chooseNext() {
        guard let p = platform else {
            begin(.falling)
            return
        }
        let candidates = jumpCandidates()
        var weights = personality.weights
        if p.width < 400 { weights[.zoomies] = nil }
        if lastChoice == .sleep { weights[.sleep] = nil }
        if candidates.isEmpty { weights[.jump] = nil }

        let entries = Array(weights)
        let total = entries.reduce(0) { $0 + $1.value }
        var roll = Double.random(in: 0..<max(total, 0.001))
        var choice = PetChoice.idle
        for (c, w) in entries {
            if roll < w { choice = c; break }
            roll -= w
        }
        lastChoice = choice
        perform(choice, on: p, candidates: candidates)
    }

    private func perform(_ choice: PetChoice, on p: Platform, candidates: [(CGPoint, Platform)] = []) {
        let lo = p.minX + 18, hi = p.maxX - 18
        switch choice {
        case .walk, .sniff:
            guard hi - lo > 40 else { begin(.sitting, duration: .random(in: 3...6)); return }
            var target = CGFloat.random(in: lo...hi)
            if abs(target - pos.x) < 40 { target = pos.x < (lo + hi) / 2 ? hi : lo }
            walkTarget = target
            if choice == .sniff {
                walkTarget = clamp(pos.x + pet.facing * .random(in: 50...120), lo, hi)
                walkSpeed = 22
                begin(.sniffing, duration: .random(in: 3...6))
            } else {
                walkSpeed = .random(in: personality.walkSpeed)
                begin(.walking)
            }
        case .zoomies:
            zoomLegs = 3
            walkTarget = pos.x < (lo + hi) / 2 ? hi : lo
            walkSpeed = 280
            begin(.walking)
        case .idle: begin(.idle, duration: .random(in: 1.5...3.5))
        case .sit: begin(.sitting, duration: .random(in: 4...9))
        case .groom: begin(.grooming, duration: .random(in: 2.5...4.5))
        case .stretch: begin(.stretching, duration: 1.8)
        case .sleep: begin(.sleeping, duration: personality.sleepy ? .random(in: 18...45) : .random(in: 10...25))
        case .speak: begin(.speak, duration: 1.5)
        case .hearts: begin(.hearts, duration: 2.4)
        case .chaseTail: begin(.chaseTail, duration: 2.0)
        case .dig: begin(.digging, duration: .random(in: 2...3.5))
        case .playBow: begin(.playBow, duration: duration(of: .playBow))
        case .rollOver: begin(.rollOver, duration: 2.6)
        case .scratch: begin(.scratching, duration: .random(in: 1.8...2.8))
        case .shake: begin(.shaking, duration: 1.1)
        case .beg: begin(.begging, duration: duration(of: .begging))
        case .backflip:
            prepare(Jump(from: pos, to: pos, peak: pos.y + 78, duration: 0.75, platform: p,
                         flips: true, then: .hearts, thenDuration: 2.0))
        case .jump:
            guard let (target, platform) = candidates.randomElement() else { begin(.idle, duration: 1); return }
            prepare(makeJump(to: target, platform: platform))
        }
    }

    private func jumpCandidates() -> [(CGPoint, Platform)] {
        guard let current = platform else { return [] }
        var out: [(CGPoint, Platform)] = []
        for p in platforms where !(p.isSameSurface(as: current) && p.contains(pos.x)) && p.width >= 50 {
            let tx = clamp(pos.x + .random(in: -260...260), p.minX + 20, p.maxX - 20)
            let dx = abs(tx - pos.x), dy = p.y - pos.y
            guard dx < 460, dy < 320, dy > -800, abs(dy) > 25 || dx > 60 else { continue }
            out.append((CGPoint(x: tx, y: p.y), p))
        }
        return out
    }

    private func makeJump(to target: CGPoint, platform: Platform, extraPeak: CGFloat? = nil,
                          then: Activity? = nil, thenDuration: CGFloat = 0) -> Jump {
        let dx = abs(target.x - pos.x), dy = target.y - pos.y
        let peak = max(pos.y, target.y) + (extraPeak ?? (36 + dx * 0.12))
        let duration = 0.38 + dx / 1500 + abs(dy) / 1500
        return Jump(from: pos, to: target, peak: peak, duration: duration, platform: platform,
                    flips: false, then: then, thenDuration: thenDuration)
    }

    private func prepare(_ j: Jump) {
        if abs(j.to.x - pos.x) > 1 { pet.facing = j.to.x > pos.x ? 1 : -1 }
        pendingJump = j
        begin(.windup, duration: 0.3)
    }

    // MARK: - Frame update

    override func update(dt: CGFloat) {
        trackMouse(dt)
        cursorCooldown -= dt
        petCooldown -= dt
        timer -= dt

        switch activity {
        case .entering:
            if moveToward(walkTarget, dt) {
                say(personality.words.randomElement()!)
                begin(.sitting, duration: 3)
            }
        case .walking:
            if let p = platform { walkTarget = clamp(walkTarget, p.minX + 12, p.maxX - 12) }
            if moveToward(walkTarget, dt) {
                if zoomLegs > 1, let p = platform {
                    zoomLegs -= 1
                    walkTarget = walkTarget > (p.minX + p.maxX) / 2 ? p.minX + 18 : p.maxX - 18
                } else if zoomLegs == 1 {
                    zoomLegs = 0
                    say("hff hff", duration: 1.2)
                    begin(.sitting, duration: 3)
                } else {
                    chooseNext()
                }
            }
        case .sniffing:
            if let p = platform { walkTarget = clamp(walkTarget, p.minX + 12, p.maxX - 12) }
            if moveToward(walkTarget, dt) { pet.mode = .sniff; pet.gaitSpeed = 0.01 } else { pet.gaitSpeed = walkSpeed }
            if timer <= 0 { chooseNext() }
        case .following:
            let p = platform ?? floorPlatform
            let target = clamp(mouse.x - pet.facing * 6, p.minX + 14, p.maxX - 14)
            let far = abs(target - pos.x) > 90
            walkSpeed = far ? 210 : 90
            pet.mode = far ? .run : .walk
            if moveToward(target, dt) {
                pet.facing = mouse.x >= pos.x ? 1 : -1
                let r = Int.random(in: 0..<3)
                if r == 0 {
                    jump = makeJump(to: pos, platform: p, extraPeak: clamp(mouse.y - p.y, 30, 90),
                                    then: .begging, thenDuration: 2)
                    begin(.jumping)
                } else if r == 1 {
                    begin(.playBow, duration: 1.8)
                } else {
                    begin(.begging, duration: 2.5)
                }
            } else if timer <= 0 {
                begin(.idle, duration: 1)
            }
        case .idle, .sitting, .grooming, .stretching, .speak, .playBow, .scratching, .begging:
            if activity == .begging || activity == .playBow { pet.facing = mouse.x >= pos.x ? 1 : -1 }
            if timer <= 0 { chooseNext() }
        case .rollOver:
            if timer <= 0 { begin(.shaking, duration: 1.0) }
        case .shaking:
            effectTimer -= dt
            if effectTimer <= 0 { puffDust(); effectTimer = 0.12 }
            if timer <= 0 { chooseNext() }
        case .digging:
            effectTimer -= dt
            if effectTimer <= 0 { flingDirt(); effectTimer = 0.07 }
            if timer <= 0 { chooseNext() }
        case .sleeping:
            effectTimer -= dt
            if effectTimer <= 0 {
                puffZ()
                effectTimer = 1.5
            }
            if timer <= 0 { begin(.stretching, duration: 1.8) }
        case .hearts:
            if timer <= 0 { chooseNext() }
        case .chaseTail:
            flipTimer -= dt
            if flipTimer <= 0 {
                pet.facing *= -1
                flipTimer = 0.2
            }
            if timer <= 0 {
                say("💫", duration: 1.4)
                begin(.sitting, duration: 2.5)
            }
        case .stalking:
            if timer <= 0 { pounce() }
        case .windup:
            if timer <= 0 {
                if let j = pendingJump {
                    pendingJump = nil
                    jump = j
                    begin(.jumping)
                } else {
                    chooseNext()
                }
            }
        case .jumping:
            advanceJump(dt)
        case .falling:
            advanceFall(dt)
        case .leaving:
            break
        }

        if heartBurst > 0 {
            heartBurst -= dt
            heartTimer -= dt
            if heartTimer <= 0 {
                puffHeart()
                heartTimer = 0.38
            }
        }

        pet.position = pos
        updateShadow()
        if let bubble {
            let h = pet.headPositionInParent
            bubble.position = CGPoint(x: h.x, y: h.y + 30 * s)
        }
        pet.update(dt: dt)
    }

    private func moveToward(_ target: CGFloat, _ dt: CGFloat) -> Bool {
        let dx = target - pos.x
        if abs(dx) < 1.5 { return true }
        pet.facing = dx > 0 ? 1 : -1
        pos.x += min(abs(dx), walkSpeed * dt) * pet.facing
        pet.gaitSpeed = walkSpeed
        return abs(target - pos.x) < 1.5
    }

    private func advanceJump(_ dt: CGFloat) {
        guard var j = jump else {
            begin(.falling)
            return
        }
        j.elapsed += dt
        let u = min(1, j.elapsed / j.duration)
        let c = 2 * j.peak - 0.5 * (j.from.y + j.to.y)
        let y = (1 - u) * (1 - u) * j.from.y + 2 * (1 - u) * u * c + u * u * j.to.y
        let x = j.from.x + (j.to.x - j.from.x) * u
        if j.flips {
            pet.spin = 2 * .pi * (u * u * (3 - 2 * u))
            pet.airTilt = 0
        } else {
            let dyds = 2 * (1 - u) * (c - j.from.y) + 2 * u * (j.to.y - c)
            pet.airTilt = clamp(atan2(dyds, max(abs(j.to.x - j.from.x), 1)) * 0.45, -0.6, 0.6)
        }
        pos = CGPoint(x: x, y: y)
        jump = j
        guard u >= 1 else { return }

        pet.spin = 0
        jump = nil
        if let p = resolve(j.platform, near: pos.x) {
            platform = p
            pos.y = p.y
            pos.x = clamp(pos.x, p.minX + 8, p.maxX - 8)
            pet.land()
            if let then = j.then {
                begin(then, duration: j.thenDuration > 0 ? j.thenDuration : duration(of: then))
            } else {
                begin(.idle, duration: .random(in: 0.6...1.4))
            }
        } else {
            platform = nil
            velocity = .zero
            begin(.falling)
        }
    }

    private func advanceFall(_ dt: CGFloat) {
        let old = pos
        velocity.dy -= 1900 * dt
        pos.x = clamp(pos.x + velocity.dx * dt, 10, size.width - 10)
        pos.y += velocity.dy * dt
        pet.airTilt = clamp(velocity.dy / 1500, -0.4, 0.3)
        guard velocity.dy <= 0 else { return }

        var best: Platform?
        for p in platforms where p.contains(pos.x) && p.y <= old.y + 0.5 && p.y >= pos.y {
            if best == nil || p.y > best!.y { best = p }
        }
        let floor = floorPlatform
        if best == nil && pos.y <= floor.y { best = floor }
        guard let landing = best else { return }

        pos.y = landing.y
        pos.x = clamp(pos.x, landing.minX + 8, landing.maxX - 8)
        platform = landing
        velocity = .zero
        pet.land(0.3)
        begin(.idle, duration: .random(in: 0.8...1.6))
    }

    // MARK: - Cursor play

    private func trackMouse(_ dt: CGFloat) {
        guard let scene = overlay else { return }
        let m = scene.mouseLocation
        if hasMouse {
            let v = hypot(m.x - mouse.x, m.y - mouse.y) / max(dt, 0.001)
            mouseSpeed += (v - mouseSpeed) * min(1, dt * 10)
        }
        mouse = m
        hasMouse = true

        let head = pet.headPositionInParent
        let dist = hypot(m.x - head.x, m.y - head.y)
        pet.lookTarget = dist < 420 ? m : (activity == .idle ? idleLook : nil)

        // Petting: the cursor resting on the pet.
        let onPet = abs(m.x - pos.x) < 34 * s && m.y > pos.y - 4 && m.y < pos.y + 50 * s
        if onPet && mouseSpeed < 80 { hoverTime += dt } else { hoverTime = 0 }
        if hoverTime > 0.5, petCooldown <= 0, platform != nil,
           [.idle, .walking, .sitting, .grooming, .sleeping, .sniffing, .begging, .speak].contains(activity) {
            petted()
            return
        }

        switch activity {
        case .sleeping:
            if dist < 110 && mouseSpeed > 900 {
                say("?!", duration: 0.9)
                velocity = CGVector(dx: 0, dy: 320)
                platform = nil
                cursorCooldown = 8
                begin(.falling)
            }
        case .idle, .walking, .sitting, .grooming, .sniffing:
            guard cursorCooldown <= 0, zoomLegs == 0, let p = platform, mouseSpeed > 140,
                  abs(m.x - pos.x) < (personality.cursorPlay == .chaseAndBeg ? 450 : 320),
                  m.y > p.y - 10, m.y < p.y + 220,
                  p.contains(m.x, margin: -14) else { return }
            guard Bool.random() else {
                cursorCooldown = .random(in: 3...6)
                return
            }
            pet.facing = m.x > pos.x ? 1 : -1
            switch personality.cursorPlay {
            case .stalkAndPounce:
                begin(.stalking, duration: .random(in: 0.7...1.3))
                cursorCooldown = .random(in: 14...26)
            case .chaseAndBeg:
                if Bool.random() { say(personality.words.randomElement()!, duration: 1) }
                walkSpeed = 210
                begin(.following, duration: 5)
                cursorCooldown = .random(in: 10...20)
            }
        case .stalking:
            pet.facing = m.x >= pos.x ? 1 : -1
        default:
            break
        }
    }

    private func petted() {
        hoverTime = 0
        petCooldown = .random(in: 6...10)
        say(personality.pettedWords.randomElement()!, duration: 1.4)
        switch personality.pettedChoice {
        case .rollOver:
            heartBurst = 2.0
            begin(.rollOver, duration: 2.6)
        default:
            begin(.hearts, duration: 2.6)
        }
    }

    private func pounce() {
        guard let p = platform else {
            begin(.falling)
            return
        }
        let tx = clamp(mouse.x - pet.facing * 8, p.minX + 14, p.maxX - 14)
        let extra = clamp(mouse.y - p.y + 10, 30, 190)
        let then: Activity = Bool.random() ? .hearts : .sitting
        jump = makeJump(to: CGPoint(x: tx, y: p.y), platform: p, extraPeak: extra,
                        then: then, thenDuration: duration(of: then))
        begin(.jumping)
    }

    // MARK: - Effects

    private func say(_ text: String, duration: CGFloat = 1.6) {
        bubble?.removeFromParent()
        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = text
        label.fontSize = 13
        label.fontColor = .hex(0x3A2A1E)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 1
        let w = max(30, label.frame.width + 16), h: CGFloat = 22
        let bg = SKShapeNode(rect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: h / 2)
        bg.fillColor = .hex(0xFFFFFF, 0.96)
        bg.strokeColor = .hex(0x3A2A1E, 0.8)
        bg.lineWidth = 1.2
        let node = SKNode()
        node.addChild(bg)
        node.addChild(label)
        node.zPosition = 30
        node.setScale(0.4)
        node.alpha = 0
        let h0 = pet.headPositionInParent
        node.position = CGPoint(x: h0.x, y: h0.y + 30 * s)
        addChild(node)
        bubble = node
        node.run(.sequence([
            .group([.scale(to: 1, duration: 0.15), .fadeIn(withDuration: 0.12)]),
            .wait(forDuration: duration),
            .fadeOut(withDuration: 0.25),
            .removeFromParent(),
        ]))
    }

    private func puffZ() {
        let font = NSFont(name: "AvenirNext-HeavyItalic", size: .random(in: 11...16)) ?? .boldSystemFont(ofSize: 14)
        let text = NSAttributedString(string: "z", attributes: [
            .font: font,
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.hex(0x2E3A55),
            .strokeWidth: -4,
        ])
        let label = SKLabelNode(attributedText: text)
        let h = pet.headPositionInParent
        label.position = CGPoint(x: h.x + pet.facing * 8 * s, y: h.y + 12 * s)
        label.zPosition = 25
        label.alpha = 0
        addChild(label)
        let drift = SKAction.moveBy(x: pet.facing * .random(in: 6...18), y: 36, duration: 2.2)
        drift.timingMode = .easeOut
        label.run(.sequence([
            .group([drift,
                    .sequence([.fadeIn(withDuration: 0.3), .wait(forDuration: 1.2), .fadeOut(withDuration: 0.7)]),
                    .scale(to: 1.4, duration: 2.2)]),
            .removeFromParent(),
        ]))
    }

    private func puffHeart() {
        let heart = SKSpriteNode(texture: PetArt.heart, size: CGSize(width: 14, height: 13))
        let h = pet.headPositionInParent
        heart.position = CGPoint(x: h.x + .random(in: -10...10), y: h.y + 14 * s)
        heart.zPosition = 25
        heart.setScale(0.3)
        addChild(heart)
        let rise = SKAction.moveBy(x: .random(in: -16...16), y: 44, duration: 1.6)
        rise.timingMode = .easeOut
        heart.run(.sequence([
            .group([.scale(to: 1, duration: 0.25), rise,
                    .sequence([.wait(forDuration: 0.9), .fadeOut(withDuration: 0.7)])]),
            .removeFromParent(),
        ]))
    }

    private func flingDirt() {
        let dot = SKSpriteNode(texture: PetArt.dirt, size: CGSize(width: 5, height: 5))
        dot.setScale(.random(in: 0.6...1.2))
        dot.position = CGPoint(x: pos.x + pet.facing * 12 * s, y: pos.y + 3)
        dot.zPosition = 20
        addChild(dot)
        let dx = -pet.facing * .random(in: 18...45)
        let up = SKAction.moveBy(x: dx * 0.5, y: .random(in: 10...24), duration: 0.22)
        up.timingMode = .easeOut
        let down = SKAction.moveBy(x: dx * 0.5, y: -18, duration: 0.25)
        down.timingMode = .easeIn
        dot.run(.sequence([up, .group([down, .fadeOut(withDuration: 0.25)]), .removeFromParent()]))
    }

    private func puffDust() {
        let puff = SKSpriteNode(texture: SnowArt.dot, size: CGSize(width: 7, height: 7))
        let a = CGFloat.random(in: 0...(2 * .pi))
        puff.position = CGPoint(x: pos.x + cos(a) * 14 * s, y: pos.y + 20 * s + sin(a) * 10 * s)
        puff.zPosition = 20
        puff.alpha = 0.8
        addChild(puff)
        puff.run(.sequence([
            .group([.moveBy(x: cos(a) * 18, y: sin(a) * 14, duration: 0.4), .fadeOut(withDuration: 0.4)]),
            .removeFromParent(),
        ]))
    }

    private func updateShadow() {
        let ground: CGFloat
        if let p = platform {
            ground = p.y
        } else {
            ground = platforms.filter { $0.contains(pos.x) && $0.y <= pos.y + 1 }.map(\.y).max() ?? floorPlatform.y
        }
        let height = max(0, pos.y - ground)
        let k = max(0, 1 - height / 240)
        shadow.position = CGPoint(x: pos.x - pet.facing * 2 * s, y: ground + 1)
        shadow.alpha = k
        let wide: CGFloat = pet.mode == .sleep || pet.mode == .rollOver ? 1.1 : 1
        shadow.xScale = s * (0.6 + 0.4 * k) * wide
        shadow.yScale = s * (0.6 + 0.4 * k)
        if pet.placeShadow(at: CGPoint(x: shadow.position.x, y: ground), strength: k, width: s * (0.6 + 0.4 * k) * wide) {
            shadow.isHidden = true
        }
    }

    override func willRemove() { pet.detach() }

    override func dismiss(completion: @escaping () -> Void) {
        jump = nil
        pendingJump = nil
        pet.spin = 0
        if activity == .jumping || activity == .falling, platform == nil {
            pos.y = floorPlatform.y
        }
        begin(.leaving)
        say("bye!", duration: 0.9)
        run(.sequence([
            .wait(forDuration: 1.0),
            .fadeOut(withDuration: 0.45),
            .run { completion() },
        ]))
    }
}

/// Art shared by all pets.
@MainActor
enum PetArt {
    static let heart: SKTexture = TextureFactory.make(CGSize(width: 16, height: 15)) { ctx in
        let h = CGMutablePath()
        h.move(to: CGPoint(x: 8, y: 1.5))
        h.addCurve(to: CGPoint(x: 1.2, y: 9.5), control1: CGPoint(x: 5, y: 4), control2: CGPoint(x: 1.2, y: 6))
        h.addCurve(to: CGPoint(x: 8, y: 11.5), control1: CGPoint(x: 1.2, y: 14.5), control2: CGPoint(x: 6.5, y: 15))
        h.addCurve(to: CGPoint(x: 14.8, y: 9.5), control1: CGPoint(x: 9.5, y: 15), control2: CGPoint(x: 14.8, y: 14.5))
        h.addCurve(to: CGPoint(x: 8, y: 1.5), control1: CGPoint(x: 14.8, y: 6), control2: CGPoint(x: 11, y: 4))
        ctx.paint(h, fill: rgb(0xFF5C8A))
        ctx.paint(ellipse(3.5, 8.5, 3, 2.4), fill: rgb(0xFFFFFF, 0.6))
        ctx.paint(h, stroke: rgb(0x7A1F3D), width: 1.1)
    }

    static let shadow: SKTexture = TextureFactory.make(CGSize(width: 50, height: 10)) { ctx in
        ctx.translateBy(x: 25, y: 5)
        ctx.scaleBy(x: 1, y: 0.2)
        let grad = CGGradient(colorsSpace: nil, colors: [rgb(0x000000, 0.32), rgb(0x000000, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(grad, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 25, options: [])
    }

    static let dirt: SKTexture = TextureFactory.make(CGSize(width: 5, height: 5)) { ctx in
        ctx.paint(ellipse(0.5, 0.5, 4, 4), fill: rgb(0x8A5A34))
        ctx.paint(ellipse(1.2, 2.4, 1.4, 1.2), fill: rgb(0xB98552))
    }
}
