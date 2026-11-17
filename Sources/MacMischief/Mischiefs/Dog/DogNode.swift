import SpriteKit

/// A golden puppy: floppy ears on springs, a tail that never stops wagging,
/// a panting tongue, and the classic curious head tilt.
final class DogNode: QuadrupedNode {
    private let face = SKSpriteNode(texture: DogArt.head, size: CGSize(width: 50, height: 44))
    private var ears: [SKSpriteNode] = []
    private let tongue = SKSpriteNode(texture: DogArt.tongue, size: CGSize(width: 6, height: 8))
    private let mouth = SKSpriteNode(texture: DogArt.mouthOpen, size: CGSize(width: 7, height: 5))
    private let collar = SKSpriteNode(texture: DogArt.collar, size: CGSize(width: 18, height: 10))
    private var eyes: [SKSpriteNode] = []
    private var closedEyes: [SKSpriteNode] = []
    private var happyEyes: [SKSpriteNode] = []

    private var blinkTimer: CGFloat = 2
    private var blinkLeft: CGFloat = 0
    private var earAngle: CGFloat = 0.25
    private var earVelocity: CGFloat = 0
    private var curiousTilt: CGFloat = 0
    private var curiousTarget: CGFloat = 0
    private var curiousTimer: CGFloat = 2

    init(scale: CGFloat = 1.15) {
        let rig = QuadrupedRig(
            attach: [CGPoint(x: 15, y: -7), CGPoint(x: 19, y: -7), CGPoint(x: -16, y: -7), CGPoint(x: -12, y: -7)],
            headAnchor: CGPoint(x: 23, y: 10), tailAnchor: CGPoint(x: -25, y: 7), legLength: 15,
            tailSegments: 7, tailSegmentLength: 3.2, tailBaseWidth: 5.8, tailTipWidth: 3.2,
            walkAmp: 6.5, runAmp: 11)
        super.init(scale: scale, rig: rig, body: DogArt.body, bodySize: CGSize(width: 58, height: 31),
                   frontLeg: DogArt.frontLeg, hindLeg: DogArt.hindLeg, legSize: CGSize(width: 10, height: 16),
                   paw: DogArt.paw, pawSize: CGSize(width: 10, height: 7),
                   fur: DogArt.furColor, outline: DogArt.outlineColor)

        collar.position = CGPoint(x: 0, y: -18.5)
        collar.zPosition = -0.05
        head.addChild(collar)

        face.zPosition = 0
        head.addChild(face)

        for ox in [CGFloat(-6.2), 6.2] {
            let eye = SKSpriteNode(texture: DogArt.eye, size: CGSize(width: 7.5, height: 8.5))
            eye.position = CGPoint(x: ox, y: -2.6)
            eye.zPosition = 0.1
            head.addChild(eye)
            let closed = SKSpriteNode(texture: DogArt.closedEye, size: CGSize(width: 7, height: 4))
            closed.position = CGPoint(x: ox, y: -3.6)
            closed.zPosition = 0.1
            closed.isHidden = true
            head.addChild(closed)
            let happy = SKSpriteNode(texture: DogArt.happyEye, size: CGSize(width: 7, height: 4))
            happy.position = CGPoint(x: ox, y: -2.6)
            happy.zPosition = 0.1
            happy.isHidden = true
            head.addChild(happy)
            eyes.append(eye)
            closedEyes.append(closed)
            happyEyes.append(happy)
        }

        tongue.anchorPoint = CGPoint(x: 0.5, y: 1)
        tongue.position = CGPoint(x: 0, y: -12.3)
        tongue.zPosition = 0.12
        tongue.setScale(0.85)
        head.addChild(tongue)
        mouth.position = CGPoint(x: 0, y: -12.8)
        mouth.zPosition = 0.16
        mouth.isHidden = true
        head.addChild(mouth)

        // Floppy ears draping over both sides of the head.
        for side in [CGFloat(-1), 1] {
            let ear = SKSpriteNode(texture: DogArt.floppyEar, size: CGSize(width: 12, height: 19))
            ear.anchorPoint = CGPoint(x: 0.5, y: 0.94)
            ear.position = CGPoint(x: side * 13.2, y: 8.6)
            ear.xScale = side
            ear.zPosition = 0.3
            head.addChild(ear)
            ears.append(ear)
        }

        update(dt: 0)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) not supported") }

    override func extraTilt(_ tilt: CGFloat) -> CGFloat {
        mode == .shake ? tilt + 0.13 * sin(t * 34) : tilt
    }

    override func footTarget(_ i: Int, attach a: CGPoint, head h: CGPoint) -> CGPoint {
        if mode == .scratch && i == 2 {
            // Hind leg scratching behind the ear.
            return CGPoint(x: h.x - 15 + 2 * sin(t * 30), y: h.y + 1 + 2.5 * cos(t * 30))
        }
        return defaultFootTarget(i, attach: a, head: h)
    }

    override func updateHead(_ dt: CGFloat) {
        // Curious head tilt now and then while watching something.
        curiousTimer -= dt
        if curiousTimer <= 0 {
            curiousTimer = .random(in: 1.5...4)
            let canTilt = [.stand, .sit, .beg].contains(mode) && lookTarget != nil
            curiousTarget = canTilt && Bool.random() ? (Bool.random() ? 0.28 : -0.2) : 0
        }
        curiousTilt += (curiousTarget - curiousTilt) * min(1, dt * 7)
        head.zRotation += curiousTilt

        // Eyes
        blinkTimer -= dt
        if blinkTimer <= 0 {
            blinkLeft = 0.12
            blinkTimer = .random(in: 2...5)
        }
        blinkLeft -= dt
        let closed = mode == .sleep
        let happy = mode == .happy || mode == .rollOver || mode == .shake || mode == .beg
        for i in 0..<2 {
            eyes[i].isHidden = closed || happy
            closedEyes[i].isHidden = !closed
            happyEyes[i].isHidden = !happy || closed
            eyes[i].yScale = blinkLeft > 0 ? 0.15 : 1
        }

        // Ears swing on a spring (positive = flared outward).
        var target: CGFloat = 0.25
        switch mode {
        case .walk, .sniff: target = 0.25 + 0.16 * sin(2 * gait)
        case .run: target = 0.7 + 0.3 * sin(2 * gait)
        case .air: target = 1.5
        case .shake: target = 0.3 + 0.9 * sin(t * 34)
        case .rollOver: target = 0.9
        case .happy, .beg, .playBow: target = 0.35 + 0.12 * sin(t * 7)
        case .sleep: target = 0.1
        case .scratch: target = 0.5 + 0.3 * sin(t * 30)
        default: break
        }
        earVelocity += (target - earAngle) * 140 * dt
        earVelocity *= exp(-dt * 9)
        earAngle += earVelocity * dt
        // Left ear flares to -x (clockwise), right ear mirrored; a little
        // asymmetry from the head tilt keeps them lively.
        ears[0].zRotation = -earAngle - curiousTilt * 0.4
        ears[1].zRotation = earAngle - curiousTilt * 0.4

        // Tongue: panting when active or happy; mouth open when barking.
        let panting: Bool
        switch mode {
        case .run, .walk, .happy, .beg, .playBow, .rollOver, .dig: panting = true
        case .stand, .sit: panting = gaitSpeed > 0 && t.truncatingRemainder(dividingBy: 9) < 5
        default: panting = false
        }
        tongue.isHidden = !panting || mode == .speak
        if panting { tongue.yScale = 0.72 + 0.15 * sin(t * (mode == .run ? 16 : 9)) }
        mouth.isHidden = mode != .speak
        if mode == .speak { mouth.yScale = 0.5 + 0.5 * abs(sin(t * 9)) }
    }

    override func targetPose(for m: PetMode) -> PetPose {
        var p = PetPose()
        p.headY = 2
        p.tailAngle = 2.0; p.tailCurl = -0.06; p.tailWave = 0.18; p.tailSpeed = 7
        func sitting() {
            p.bodyY = 17; p.tilt = 0.45; p.headX = -2; p.headY = 3; p.headTilt = 0.02
            p.tailAngle = 3.6; p.tailCurl = 0; p.tailWave = 0.32; p.tailSpeed = 12
        }
        switch m {
        case .stand:
            break
        case .walk:
            p.headY = 1; p.tailAngle = 1.9; p.tailWave = 0.3; p.tailSpeed = 11
        case .run:
            p.bodyY = 23; p.tilt = -0.05; p.headX = 3; p.headY = -1
            p.tailAngle = 2.6; p.tailCurl = 0; p.tailWave = 0.22; p.tailSpeed = 14
        case .sit, .scratch:
            sitting()
            if m == .scratch { p.headTilt = 0.35; p.headX = -4 }
        case .happy:
            sitting()
            p.headTilt = 0.12; p.tailWave = 0.45; p.tailSpeed = 18
        case .beg:
            sitting()
            p.tilt = 0.6; p.headY = 6; p.headTilt = -0.15; p.tailWave = 0.42; p.tailSpeed = 18
        case .speak:
            sitting()
            p.headY = 5; p.headTilt = -0.22; p.tailWave = 0.35; p.tailSpeed = 16
        case .groom:
            sitting()
        case .sleep:
            p.bodyY = 13; p.headX = 2; p.headY = -9; p.headTilt = -0.12
            p.tailAngle = 3.3; p.tailCurl = 0.05; p.tailWave = 0.03; p.tailSpeed = 0.8
            p.legsVisible = 0
        case .crouch:
            p.bodyY = 17; p.tilt = -0.15; p.headX = 3; p.headY = -3
            p.tailAngle = 1.9; p.tailWave = 0.35; p.tailSpeed = 16
        case .stretch:
            p.bodyY = 19; p.tilt = -0.32; p.headX = 3; p.headY = -1; p.headTilt = 0.15
            p.tailAngle = 1.6; p.tailWave = 0.2; p.tailSpeed = 6
        case .playBow:
            p.bodyY = 20; p.tilt = -0.38; p.headX = 4; p.headY = 0; p.headTilt = 0.25
            p.tailAngle = 1.6; p.tailCurl = -0.05; p.tailWave = 0.48; p.tailSpeed = 19
        case .sniff:
            p.bodyY = 23; p.tilt = -0.12; p.headX = 5; p.headY = -10; p.headTilt = -0.35
            p.tailAngle = 1.9; p.tailWave = 0.3; p.tailSpeed = 12
        case .dig:
            p.bodyY = 21; p.tilt = -0.25; p.headX = 4; p.headY = -6; p.headTilt = -0.2
            p.tailAngle = 1.8; p.tailWave = 0.3; p.tailSpeed = 14
        case .rollOver:
            p.bodyY = 27; p.roll = .pi; p.headY = -11; p.headX = -2; p.headTilt = 0.35
            p.tailAngle = 2.6; p.tailWave = 0.45; p.tailSpeed = 18
        case .shake:
            p.headY = 1; p.tailWave = 0.4; p.tailSpeed = 30
        case .air:
            p.headX = 2; p.tailAngle = 2.5; p.tailWave = 0.2; p.tailSpeed = 10
        }
        return p
    }
}
