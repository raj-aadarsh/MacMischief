import SpriteKit

/// A ginger tabby: twitchy ears, slit pupils that go round when it hunts,
/// blinks, and a striped tail.
final class CatNode: QuadrupedNode {
    private let face = SKSpriteNode(texture: CatArt.head, size: CGSize(width: 46, height: 40))
    private var ears: [SKSpriteNode] = []
    private var eyes: [SKSpriteNode] = []
    private var pupils: [SKSpriteNode] = []
    private var closedEyes: [SKSpriteNode] = []
    private var happyEyes: [SKSpriteNode] = []
    private let mouth = SKSpriteNode(texture: CatArt.mouthOpen, size: CGSize(width: 5, height: 5))

    private var blinkTimer: CGFloat = 2
    private var blinkLeft: CGFloat = 0
    private var twitch: [CGFloat] = [0, 0]
    private var twitchTimer: CGFloat = 3
    private var dilation: CGFloat = 0.55
    private var earLay: CGFloat = 0

    init(scale: CGFloat = 1.15) {
        let rig = QuadrupedRig(
            attach: [CGPoint(x: 15, y: -7), CGPoint(x: 19, y: -7), CGPoint(x: -17, y: -7), CGPoint(x: -13, y: -7)],
            headAnchor: CGPoint(x: 24, y: 9), tailAnchor: CGPoint(x: -27, y: 3), legLength: 15,
            tailSegments: 10, tailSegmentLength: 3.3, tailBaseWidth: 6.6, tailTipWidth: 4.8,
            tailRings: [3, 5, 7, 9])
        super.init(scale: scale, rig: rig, body: CatArt.body, bodySize: CGSize(width: 60, height: 32),
                   frontLeg: CatArt.frontLeg, hindLeg: CatArt.hindLeg, legSize: CGSize(width: 10, height: 16),
                   paw: CatArt.paw, pawSize: CGSize(width: 9, height: 6),
                   fur: CatArt.furColor, outline: CatArt.outlineColor, ringColor: CatArt.stripeColor)

        for side in [CGFloat(-1), 1] {
            let ear = SKSpriteNode(texture: CatArt.ear, size: CGSize(width: 12, height: 15))
            ear.anchorPoint = CGPoint(x: 0.5, y: 0.08)
            ear.position = CGPoint(x: side * 8.2, y: 6.5)
            ear.xScale = side < 0 ? 1 : -1
            ear.zPosition = -0.1
            head.addChild(ear)
            ears.append(ear)
        }
        face.zPosition = 0
        head.addChild(face)

        for ox in [CGFloat(-5), 5] {
            let eye = SKSpriteNode(texture: CatArt.eye, size: CGSize(width: 8.5, height: 9.5))
            eye.position = CGPoint(x: ox, y: -3.2)
            eye.zPosition = 0.1
            head.addChild(eye)
            let pupil = SKSpriteNode(texture: CatArt.pupil, size: CGSize(width: 4.4, height: 7.4))
            pupil.zPosition = 0.1
            eye.addChild(pupil)
            let shine = SKSpriteNode(texture: CatArt.shine, size: CGSize(width: 5, height: 5))
            shine.position = CGPoint(x: -0.8, y: 1)
            shine.zPosition = 0.2
            eye.addChild(shine)
            let closed = SKSpriteNode(texture: CatArt.closedEye, size: CGSize(width: 8, height: 4))
            closed.position = CGPoint(x: ox, y: -4.5)
            closed.zPosition = 0.1
            closed.isHidden = true
            head.addChild(closed)
            let happy = SKSpriteNode(texture: CatArt.happyEye, size: CGSize(width: 8, height: 4))
            happy.position = CGPoint(x: ox, y: -3)
            happy.zPosition = 0.1
            happy.isHidden = true
            head.addChild(happy)
            eyes.append(eye)
            pupils.append(pupil)
            closedEyes.append(closed)
            happyEyes.append(happy)
        }
        mouth.position = CGPoint(x: 0, y: -11.6)
        mouth.zPosition = 0.2
        mouth.isHidden = true
        head.addChild(mouth)

        update(dt: 0)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) not supported") }

    override func footTarget(_ i: Int, attach a: CGPoint, head h: CGPoint) -> CGPoint {
        if mode == .groom && i == 0 {
            return CGPoint(x: h.x - 2, y: h.y - 9 + 1.5 * sin(t * 11))
        }
        return defaultFootTarget(i, attach: a, head: h)
    }

    override func updateHead(_ dt: CGFloat) {
        enum Eyes { case open, closed, happy }
        let state: Eyes
        switch mode {
        case .sleep, .groom: state = .closed
        case .happy, .rollOver: state = .happy
        default: state = .open
        }

        blinkTimer -= dt
        if blinkTimer <= 0 {
            blinkLeft = 0.13
            blinkTimer = .random(in: 2...6)
        }
        blinkLeft -= dt

        // Pupils: thin slits when relaxed, big and round when hunting or excited.
        let wantDilation: CGFloat
        switch mode {
        case .crouch, .air, .run: wantDilation = 1.15
        case .stand, .walk: wantDilation = lookTarget == nil ? 0.5 : 0.75
        default: wantDilation = 0.55
        }
        dilation += (wantDilation - dilation) * min(1, dt * 6)

        for i in 0..<2 {
            eyes[i].isHidden = state != .open
            closedEyes[i].isHidden = state != .closed
            happyEyes[i].isHidden = state != .happy
            eyes[i].yScale = blinkLeft > 0 ? 0.15 : 1
            pupils[i].xScale = dilation

            var goal = CGPoint(x: 0.5, y: 0)
            if let target = lookTarget, let scene, abs(currentXScale) > 0.3 {
                let local = eyes[i].convert(target, from: scene)
                let len = hypot(local.x, local.y)
                if len > 0.1, len.isFinite {
                    let m = min(1.4, len / 25)
                    goal = CGPoint(x: local.x / len * m, y: local.y / len * m * 0.8)
                }
            }
            let k = min(1, dt * 12)
            pupils[i].position.x += (goal.x - pupils[i].position.x) * k
            pupils[i].position.y += (goal.y - pupils[i].position.y) * k
        }

        // Ears: random little twitches, flattened when stalking, perked when happy.
        twitchTimer -= dt
        if twitchTimer <= 0 {
            twitch[Int.random(in: 0...1)] = 1
            twitchTimer = .random(in: 2.5...7)
        }
        let wantLay: CGFloat = mode == .crouch ? 1 : (mode == .happy || mode == .speak ? -0.4 : 0)
        earLay += (wantLay - earLay) * min(1, dt * 8)
        for i in 0..<2 {
            twitch[i] *= exp(-dt * 9)
            let outward: CGFloat = i == 0 ? 1 : -1
            ears[i].zRotation = outward * (0.22 + earLay * 0.45 + twitch[i] * 0.5 * sin(t * 40))
            ears[i].yScale = 1 - earLay * 0.12
        }

        mouth.isHidden = mode != .speak
        if mode == .speak { mouth.yScale = 0.55 + 0.45 * abs(sin(t * 5)) }
    }

    override func targetPose(for m: PetMode) -> PetPose {
        var p = PetPose()
        func sitting() {
            p.bodyY = 17; p.tilt = 0.45; p.headX = -3; p.headY = 1; p.headTilt = 0.05
            p.tailAngle = 4.45; p.tailCurl = 0.2; p.tailWave = 0.05; p.tailSpeed = 1.5
        }
        switch m {
        case .stand, .shake:
            break
        case .walk, .sniff:
            p.headX = 1; p.tailAngle = 1.45; p.tailCurl = 0.11; p.tailWave = 0.1; p.tailSpeed = 3.5
        case .run:
            p.bodyY = 23; p.tilt = -0.04; p.headX = 3; p.headY = -2
            p.tailAngle = 2.75; p.tailCurl = 0.03; p.tailWave = 0.12; p.tailSpeed = 9
        case .sit, .scratch, .beg:
            sitting()
        case .happy:
            sitting()
            p.headY = 2; p.headTilt = -0.12
            p.tailAngle = 1.6; p.tailCurl = -0.1; p.tailWave = 0.18; p.tailSpeed = 6
        case .speak:
            sitting()
            p.headX = -2; p.headY = 3; p.headTilt = -0.18
        case .groom:
            sitting()
            p.headX = -2; p.headY = 0; p.headTilt = 0.25
        case .sleep:
            p.bodyY = 13; p.headX = 1; p.headY = -9; p.headTilt = -0.15
            p.tailAngle = 3.4; p.tailCurl = 0.03; p.tailWave = 0.04; p.tailSpeed = 0.8
            p.legsVisible = 0
        case .crouch:
            p.bodyY = 16; p.tilt = -0.1; p.headX = 3; p.headY = -5
            p.tailAngle = 3.05; p.tailCurl = 0; p.tailWave = 0.07; p.tailSpeed = 10
        case .stretch, .playBow, .dig:
            p.bodyY = 19; p.tilt = -0.32; p.headX = 3; p.headY = -2; p.headTilt = 0.15
            p.tailAngle = 1.35; p.tailCurl = 0.1; p.tailWave = 0.08; p.tailSpeed = 2
        case .air:
            p.headX = 2; p.tailAngle = 2.8; p.tailCurl = 0.05; p.tailWave = 0.15; p.tailSpeed = 6
        case .rollOver:
            p.bodyY = 27; p.roll = .pi; p.headY = -11; p.headX = -2; p.headTilt = 0.35; p.tailAngle = 2.6; p.tailWave = 0.2; p.tailSpeed = 4
        }
        return p
    }
}
