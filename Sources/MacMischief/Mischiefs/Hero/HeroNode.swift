import SpriteKit

/// Joint angles (radians). Limb angles are measured from hanging straight down;
/// positive swings forward (towards +x when facing right).
struct HeroPose {
    var spine: CGFloat = 0      // + leans back, - leans forward
    var head: CGFloat = 0       // + tilts face up
    var nS: CGFloat = 0, nE: CGFloat = 0   // near shoulder / elbow
    var fS: CGFloat = 0, fE: CGFloat = 0   // far shoulder / elbow
    var nH: CGFloat = 0, nK: CGFloat = 0, nF: CGFloat = 0   // near hip / knee / foot
    var fH: CGFloat = 0, fK: CGFloat = 0, fF: CGFloat = 0   // far hip / knee / foot

    private var all: [CGFloat] {
        get { [spine, head, nS, nE, fS, fE, nH, nK, nF, fH, fK, fF] }
        set { (spine, head, nS, nE, fS, fE, nH, nK, nF, fH, fK, fF) =
                (newValue[0], newValue[1], newValue[2], newValue[3], newValue[4], newValue[5],
                 newValue[6], newValue[7], newValue[8], newValue[9], newValue[10], newValue[11]) }
    }

    static func mix(_ a: HeroPose, _ b: HeroPose, _ t: CGFloat) -> HeroPose {
        var r = a
        r.all = zip(a.all, b.all).map { $0 + ($1 - $0) * t }
        return r
    }

    mutating func approach(_ o: HeroPose, _ k: CGFloat) { self = HeroPose.mix(self, o, k) }

    static let stand = HeroPose(spine: 0, head: 0, nS: 0.1, nE: 0.18, fS: -0.06, fE: 0.14,
                                nH: 0.04, nK: -0.06, nF: 0, fH: -0.04, fK: -0.04, fF: 0)
    static let hover = HeroPose(spine: 0.04, head: 0.12, nS: 0.42, nE: 0.3, fS: 0.3, fE: 0.24,
                                nH: 0.16, nK: -0.42, nF: -0.5, fH: -0.08, fK: -0.26, fF: -0.4)
    static let flight = HeroPose(spine: 0, head: 1.0, nS: 0.12, nE: 0.08, fS: -0.04, fE: 0.06,
                                 nH: 0.02, nK: -0.1, nF: -1.1, fH: -0.1, fK: -0.18, fF: -1.0)
    static let dash = HeroPose(spine: 0, head: 1.05, nS: 2.95, nE: 0, fS: 0.05, fE: 0.05,
                               nH: 0.02, nK: -0.05, nF: -1.2, fH: -0.16, fK: -0.35, fF: -1.0)
    static let landing = HeroPose(spine: -0.7, head: -0.15, nS: 0.95, nE: 0.05, fS: -1.1, fE: 0.8,
                                  nH: -0.4, nK: -1.4, nF: 0.3, fH: 1.35, fK: -1.45, fF: 0.05)
    static let crouch = HeroPose(spine: -0.3, head: 0.15, nS: -0.55, nE: 0.35, fS: -0.6, fE: 0.3,
                                 nH: 0.75, nK: -1.15, nF: 0.4, fH: 0.65, fK: -1.05, fF: 0.35)
    static let wave = HeroPose(spine: 0.02, head: 0.1, nS: 2.7, nE: 0.6, fS: 0.3, fE: 0.24,
                               nH: 0.16, nK: -0.42, nF: -0.5, fH: -0.08, fK: -0.26, fF: -0.4)
}

/// The armoured hero, built from jointed metal parts. Origin = hip joint.
final class HeroNode: SKNode {
    var target = HeroPose.hover
    private(set) var pose = HeroPose.hover
    var poseRate: CGFloat = 8
    /// Rotation of the whole body (0 = upright, -π/2 = flying head-first along +x).
    var bodyAngle: CGFloat = 0
    /// Barrel-roll phase (0 = none).
    var roll: CGFloat = 0
    var facing: CGFloat = 1
    var bootThrust: CGFloat = 0.5
    var palmThrust: CGFloat = 0.5
    /// Extra wave motion on the near forearm.
    var waving = false
    let heroScale: CGFloat

    private let orient = SKNode()
    private let figure = SKNode()
    private let torsoJoint = SKNode()
    private let neck = SKNode()
    private var shoulders: [SKNode] = []
    private var elbows: [SKNode] = []
    private var hips: [SKNode] = []
    private var knees: [SKNode] = []
    private var ankles: [SKNode] = []
    private(set) var boots: [SKNode] = []
    private(set) var hands: [SKNode] = []
    private var bootGlows: [SKSpriteNode] = []
    private var palmGlows: [SKSpriteNode] = []
    private let visorGlow = SKSpriteNode(texture: HeroArt.glowDot, size: CGSize(width: 14, height: 7))
    private let chestGlow = SKSpriteNode(texture: HeroArt.glowDot, size: CGSize(width: 12, height: 12))
    /// Points that can touch the ground (heels, toes, knees, fists).
    private(set) var contacts: [SKNode] = []
    private var currentXScale: CGFloat
    private var t: CGFloat = 0

    init(scale: CGFloat = 1.12) {
        heroScale = scale
        currentXScale = scale
        super.init()
        setScale(scale)
        addChild(orient)
        orient.addChild(figure)

        // Legs (far first, darker)
        for (i, x) in [CGFloat(-1), 1].enumerated() {
            let near = i == 1
            let z: CGFloat = near ? 7 : 2
            let hip = SKNode()
            hip.position = CGPoint(x: x, y: 0)
            hip.zPosition = z
            figure.addChild(hip)
            let thigh = part(HeroArt.thigh, CGSize(width: 11.5, height: 18), anchor: CGPoint(x: 0.5, y: 0.97), far: !near)
            hip.addChild(thigh)
            hip.addChild(jointBall(far: !near, size: 8))
            let knee = SKNode()
            knee.position = CGPoint(x: 0, y: -16.5)
            knee.zPosition = -0.01
            hip.addChild(knee)
            let shin = part(HeroArt.shin, CGSize(width: 10, height: 17), anchor: CGPoint(x: 0.5, y: 0.97), far: !near)
            knee.addChild(shin)
            knee.addChild(jointBall(far: !near, size: 7))
            let ankle = SKNode()
            ankle.position = CGPoint(x: 0, y: -15.5)
            ankle.zPosition = 0.02
            knee.addChild(ankle)
            let boot = part(HeroArt.boot, CGSize(width: 13, height: 7), anchor: CGPoint(x: 3.8 / 13, y: 5.5 / 7), far: !near)
            ankle.addChild(boot)
            let bootGlow = SKSpriteNode(texture: HeroArt.glowDot, size: CGSize(width: 12, height: 12))
            bootGlow.blendMode = .add
            bootGlow.position = CGPoint(x: 0.5, y: -6)
            bootGlow.zPosition = 0.05
            ankle.addChild(bootGlow)
            let sole = SKNode()
            sole.position = CGPoint(x: 0.5, y: -5.5)
            ankle.addChild(sole)
            for p in [CGPoint(x: -2.9, y: -5.3), CGPoint(x: 8.4, y: -5.1)] {
                let c = SKNode(); c.position = p; ankle.addChild(c); contacts.append(c)
            }
            let kneeMark = SKNode(); kneeMark.position = CGPoint(x: 2.5, y: -1); knee.addChild(kneeMark); contacts.append(kneeMark)
            hips.append(hip); knees.append(knee); ankles.append(ankle); boots.append(sole); bootGlows.append(bootGlow)
        }

        let pelvis = part(HeroArt.pelvis, CGSize(width: 16, height: 9), anchor: CGPoint(x: 0.5, y: 5 / 9.0), far: false)
        pelvis.position = CGPoint(x: 0.5, y: 1.5)
        pelvis.zPosition = 4
        figure.addChild(pelvis)

        torsoJoint.position = CGPoint(x: 0, y: 4)
        figure.addChild(torsoJoint)
        let torso = part(HeroArt.torso, CGSize(width: 24, height: 26), anchor: CGPoint(x: 0.5, y: 0.04), far: false)
        torso.zPosition = 5
        torsoJoint.addChild(torso)
        chestGlow.blendMode = .add
        chestGlow.position = CGPoint(x: 6.3, y: 17)
        chestGlow.zPosition = 5.2
        torsoJoint.addChild(chestGlow)
        let jetpack = part(HeroArt.jetpack, CGSize(width: 10, height: 20), anchor: CGPoint(x: 0.9, y: 0.2), far: false)
        jetpack.position = CGPoint(x: -7.6, y: 8)
        jetpack.zPosition = 3
        torsoJoint.addChild(jetpack)

        neck.position = CGPoint(x: -0.5, y: 24)
        neck.zPosition = 6
        torsoJoint.addChild(neck)
        let helmet = part(HeroArt.helmet, CGSize(width: 17.6, height: 19.4), anchor: CGPoint(x: 7 / 16.0, y: 1 / 18.0), far: false)
        neck.addChild(helmet)
        visorGlow.blendMode = .add
        visorGlow.position = CGPoint(x: 5.6, y: 9.5)
        visorGlow.zPosition = 0.1
        neck.addChild(visorGlow)

        // Arms (far first)
        for i in 0..<2 {
            let near = i == 1
            let shoulder = SKNode()
            shoulder.position = CGPoint(x: near ? 1.2 : -0.8, y: 20.5)
            shoulder.zPosition = near ? 8 : 1
            torsoJoint.addChild(shoulder)
            let upper = part(HeroArt.upperArm, CGSize(width: 9, height: 14), anchor: CGPoint(x: 0.5, y: 0.95), far: !near)
            shoulder.addChild(upper)
            shoulder.addChild(jointBall(far: !near, size: 8))
            if near {
                let pad = part(HeroArt.pauldron, CGSize(width: 13.5, height: 9), anchor: CGPoint(x: 0.5, y: 0.58), far: false)
                pad.zPosition = 0.3
                shoulder.addChild(pad)
            }
            let elbow = SKNode()
            elbow.position = CGPoint(x: 0, y: -12.2)
            elbow.zPosition = 0.02
            shoulder.addChild(elbow)
            let fore = part(HeroArt.forearm, CGSize(width: 10, height: 14), anchor: CGPoint(x: 0.5, y: 0.96), far: !near)
            elbow.addChild(fore)
            elbow.addChild(jointBall(far: !near, size: 6.5))
            let hand = part(HeroArt.hand, CGSize(width: 7.4, height: 6.5), anchor: CGPoint(x: 0.5, y: 0.9), far: !near)
            hand.position = CGPoint(x: 0, y: -12.6)
            hand.zPosition = 0.02
            elbow.addChild(hand)
            let palm = SKSpriteNode(texture: HeroArt.glowDot, size: CGSize(width: 11, height: 11))
            palm.blendMode = .add
            palm.position = CGPoint(x: 0, y: -17.5)
            palm.zPosition = 0.05
            elbow.addChild(palm)
            let fist = SKNode(); fist.position = CGPoint(x: 0, y: -18.4); elbow.addChild(fist); contacts.append(fist)
            shoulders.append(shoulder); elbows.append(elbow); hands.append(fist); palmGlows.append(palm)
        }
        update(dt: 0)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) not supported") }

    private func jointBall(far: Bool, size: CGFloat) -> SKSpriteNode {
        let j = part(HeroArt.joint, CGSize(width: size, height: size), anchor: CGPoint(x: 0.5, y: 0.5), far: far)
        j.zPosition = -0.05
        return j
    }

    private func part(_ tex: SKTexture, _ size: CGSize, anchor: CGPoint, far: Bool) -> SKSpriteNode {
        let s = SKSpriteNode(texture: tex, size: size)
        s.anchorPoint = anchor
        if far {
            s.color = .black
            s.colorBlendFactor = 0.32
        }
        return s
    }

    /// Lowest point of the body (ground contact) in the parent's coordinates.
    func lowestPoint() -> CGFloat {
        guard let parent else { return position.y }
        return contacts.map { $0.convert(CGPoint.zero, to: parent).y }.min() ?? position.y
    }

    /// World-space (parent) position and direction of each boot thruster.
    func thrusters(in node: SKNode) -> [(CGPoint, CGFloat)] {
        boots.map { sole in
            let a = sole.convert(CGPoint.zero, to: node)
            let b = sole.convert(CGPoint(x: 0, y: -10), to: node)
            return (a, atan2(b.y - a.y, b.x - a.x))
        }
    }

    func update(dt: CGFloat) {
        t += dt
        pose.approach(target, 1 - exp(-dt * poseRate))
        var p = pose
        if waving { p.nE += 0.45 * sin(t * 11) }

        torsoJoint.zRotation = p.spine
        neck.zRotation = p.head
        shoulders[1].zRotation = p.nS; elbows[1].zRotation = p.nE
        shoulders[0].zRotation = p.fS; elbows[0].zRotation = p.fE
        hips[1].zRotation = p.nH; knees[1].zRotation = p.nK; ankles[1].zRotation = p.nF
        hips[0].zRotation = p.fH; knees[0].zRotation = p.fK; ankles[0].zRotation = p.fF

        orient.zRotation = bodyAngle
        figure.xScale = cos(roll)

        currentXScale += (facing * heroScale - currentXScale) * (1 - exp(-dt * 12))
        xScale = currentXScale

        let flicker = 0.9 + 0.1 * sin(t * 53) * sin(t * 31)
        for g in bootGlows {
            g.alpha = min(1, bootThrust) * flicker
            g.setScale(0.6 + 0.7 * bootThrust)
        }
        for g in palmGlows {
            g.alpha = min(1, palmThrust) * flicker
            g.setScale(0.5 + 0.6 * palmThrust)
        }
        visorGlow.alpha = 0.55 + 0.15 * sin(t * 2.4)
        chestGlow.alpha = 0.6 + 0.2 * sin(t * 2.4 + 1)
    }
}
