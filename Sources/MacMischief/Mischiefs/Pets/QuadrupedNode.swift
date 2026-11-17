import SpriteKit

/// Everything a pet's body can be asked to do. Each species decides what each
/// mode looks like.
enum PetMode {
    case stand, walk, run, sit, sleep, crouch, stretch, air, groom, happy, speak
    case sniff, dig, playBow, rollOver, scratch, shake, beg
}

struct PetPose {
    var bodyY: CGFloat = 25
    var tilt: CGFloat = 0
    var headX: CGFloat = 0
    var headY: CGFloat = 0
    var headTilt: CGFloat = 0
    var tailAngle: CGFloat = 1.75
    var tailCurl: CGFloat = 0.07
    var tailWave: CGFloat = 0.1
    var tailSpeed: CGFloat = 2.2
    var legsVisible: CGFloat = 1
    var roll: CGFloat = 0

    mutating func approach(_ o: PetPose, _ k: CGFloat) {
        bodyY += (o.bodyY - bodyY) * k
        tilt += (o.tilt - tilt) * k
        headX += (o.headX - headX) * k
        headY += (o.headY - headY) * k
        headTilt += (o.headTilt - headTilt) * k
        tailAngle += (o.tailAngle - tailAngle) * k
        tailCurl += (o.tailCurl - tailCurl) * k
        tailWave += (o.tailWave - tailWave) * k
        tailSpeed += (o.tailSpeed - tailSpeed) * k
        legsVisible += (o.legsVisible - legsVisible) * k
        roll += (o.roll - roll) * k
    }
}

/// Shape of a species' skeleton, in body-local points (facing +x).
struct QuadrupedRig {
    /// near-front, far-front, near-hind, far-hind
    var attach: [CGPoint]
    var headAnchor: CGPoint
    var tailAnchor: CGPoint
    var legLength: CGFloat
    var tailSegments: Int
    var tailSegmentLength: CGFloat
    var tailBaseWidth: CGFloat
    var tailTipWidth: CGFloat
    var tailRings: [Int] = []
    var walkAmp: CGFloat = 6.5
    var runAmp: CGFloat = 10
}

/// A procedurally animated four-legged animal. Origin = ground between its paws.
/// Subclasses supply the art, the head details and the poses.
class QuadrupedNode: SKNode {
    var mode: PetMode = .stand
    var gaitSpeed: CGFloat = 50
    var facing: CGFloat = 1
    var lookTarget: CGPoint?
    var spin: CGFloat = 0
    var airTilt: CGFloat = 0
    let petScale: CGFloat
    let rigSpec: QuadrupedRig

    let pivot = SKNode()
    let rig = SKNode()
    let body: SKSpriteNode
    let head = SKNode()
    private(set) var legs: [SKSpriteNode] = []
    private(set) var paws: [SKSpriteNode] = []
    private let tail = SKShapeNode()
    private let tailRings = SKShapeNode()

    private(set) var pose = PetPose()
    private(set) var t: CGFloat = 0
    private(set) var gait: CGFloat = 0
    private var feet: [CGPoint]
    private var squash: CGFloat = 0
    private(set) var currentXScale: CGFloat

    private static let walkPhase: [CGFloat] = [.pi / 2, 1.5 * .pi, 0, .pi]
    private static let runPhase: [CGFloat] = [0, 0.35, .pi, .pi + 0.35]

    init(scale: CGFloat, rig spec: QuadrupedRig, body bodyTexture: SKTexture, bodySize: CGSize,
         frontLeg: SKTexture, hindLeg: SKTexture, legSize: CGSize, paw: SKTexture, pawSize: CGSize,
         fur: SKColor, outline: SKColor, ringColor: SKColor? = nil) {
        petScale = scale
        rigSpec = spec
        currentXScale = scale
        feet = spec.attach.map { CGPoint(x: $0.x, y: 0) }
        body = SKSpriteNode(texture: bodyTexture, size: bodySize)
        super.init()
        xScale = scale
        yScale = scale

        addChild(pivot)
        pivot.position = CGPoint(x: 0, y: 20)
        pivot.addChild(rig)
        rig.position = CGPoint(x: 0, y: -20)

        for i in 0..<4 {
            let far = i == 1 || i == 3
            let leg = SKSpriteNode(texture: i < 2 ? frontLeg : hindLeg, size: legSize)
            leg.anchorPoint = CGPoint(x: 0.5, y: 1)
            leg.zPosition = far ? 1 : 4
            let p = SKSpriteNode(texture: paw, size: pawSize)
            p.zPosition = far ? 1.1 : 4.1
            if far {
                for s in [leg, p] {
                    s.color = .black
                    s.colorBlendFactor = 0.2
                }
            }
            rig.addChild(leg)
            rig.addChild(p)
            legs.append(leg)
            paws.append(p)
        }

        tail.fillColor = fur
        tail.strokeColor = outline
        tail.lineWidth = 1.1
        tail.lineJoin = .round
        tail.isAntialiased = true
        tail.zPosition = 2
        rig.addChild(tail)
        if let ringColor {
            tailRings.strokeColor = ringColor
            tailRings.lineWidth = 1.7
            tailRings.lineCap = .round
            tailRings.zPosition = 2.1
            rig.addChild(tailRings)
        }

        body.zPosition = 3
        rig.addChild(body)
        head.zPosition = 6
        rig.addChild(head)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) not supported") }

    var headPositionInParent: CGPoint {
        CGPoint(x: position.x + head.position.x * currentXScale, y: position.y + head.position.y * petScale)
    }

    func land(_ amount: CGFloat = 0.24) { squash = amount }

    // MARK: - Species hooks

    func targetPose(for mode: PetMode) -> PetPose { PetPose() }

    /// Extra per-frame motion (e.g. a dog's shake). Return adjusted tilt.
    func extraTilt(_ tilt: CGFloat) -> CGFloat { tilt }

    func updateHead(_ dt: CGFloat) {}

    func footTarget(_ i: Int, attach a: CGPoint, head h: CGPoint) -> CGPoint {
        defaultFootTarget(i, attach: a, head: h)
    }

    final func defaultFootTarget(_ i: Int, attach a: CGPoint, head h: CGPoint) -> CGPoint {
        let front = i < 2
        switch mode {
        case .stand, .speak, .shake:
            return CGPoint(x: a.x + (front ? 1 : -1), y: 0)
        case .walk, .run, .sniff:
            let run = mode == .run
            let amp = run ? rigSpec.runAmp : (mode == .sniff ? rigSpec.walkAmp * 0.7 : rigSpec.walkAmp)
            let lift: CGFloat = run ? 6 : 3.5
            let psi = gait + (run ? Self.runPhase[i] : Self.walkPhase[i])
            return CGPoint(x: a.x + amp * sin(psi), y: lift * max(0, cos(psi)))
        case .sit, .happy, .groom, .scratch:
            return front ? CGPoint(x: a.x + 1, y: 0) : CGPoint(x: a.x + 8, y: 0)
        case .beg:
            return front ? CGPoint(x: a.x + 6, y: a.y - 6 + 1.2 * sin(t * 8 + CGFloat(i))) : CGPoint(x: a.x + 8, y: 0)
        case .sleep:
            return CGPoint(x: a.x + 3, y: a.y - 2)
        case .crouch:
            return CGPoint(x: a.x + (front ? 5 : -1), y: 0)
        case .stretch, .playBow:
            return CGPoint(x: a.x + (front ? 13 : -3), y: 0)
        case .dig:
            if front {
                let ph = t * 22 + (i == 0 ? 0 : .pi)
                return CGPoint(x: a.x + 6 + 5 * sin(ph), y: max(0, 3 * cos(ph)))
            }
            return CGPoint(x: a.x - 2, y: 0)
        case .air:
            return front ? CGPoint(x: a.x + 9 + 1.5 * sin(t * 14), y: a.y - 10)
                         : CGPoint(x: a.x - 9, y: a.y - 10)
        case .rollOver:
            let kick = 2.5 * sin(t * 12 + CGFloat(i) * 1.7)
            return CGPoint(x: a.x + (front ? 3 : -3) + kick, y: a.y - 9)
        }
    }

    // MARK: - Frame

    func update(dt: CGFloat) {
        t += dt
        var target = targetPose(for: mode)
        if mode == .air { target.tilt = airTilt }
        pose.approach(target, 1 - exp(-dt * (mode == .air ? 14 : 9)))

        let moving = mode == .walk || mode == .run || mode == .sniff
        let amp = mode == .run ? rigSpec.runAmp : rigSpec.walkAmp * (mode == .sniff ? 0.7 : 1)
        if moving { gait += (gaitSpeed / petScale) * dt * .pi / (2 * amp) }

        var bodyY = pose.bodyY
        var bodyX: CGFloat = 0
        var tilt = pose.tilt
        var breathe: CGFloat = 0
        switch mode {
        case .walk, .sniff: bodyY += 0.9 * cos(2 * gait)
        case .run:
            bodyY += 2.2 * cos(2 * gait)
            tilt += 0.06 * sin(2 * gait)
        case .crouch:
            tilt += 0.035 * sin(t * 24)
            bodyX = -0.8 * sin(t * 24)
        case .sleep: breathe = 0.05 * sin(t * 1.5)
        case .stand, .sit, .happy, .speak, .groom, .beg, .scratch: breathe = 0.022 * sin(t * 2.4)
        default: break
        }
        tilt = extraTilt(tilt)

        body.position = CGPoint(x: bodyX, y: bodyY)
        body.zRotation = tilt
        body.yScale = 1 + breathe
        body.xScale = 1 - breathe * 0.3

        let c = cos(tilt), s = sin(tilt)
        let place = { (p: CGPoint) -> CGPoint in
            CGPoint(x: p.x * c - p.y * s + bodyX, y: p.x * s + p.y * c + bodyY)
        }

        var hp = place(rigSpec.headAnchor)
        hp.x += pose.headX
        hp.y += pose.headY
        if moving { hp.y += (mode == .run ? 1.4 : 0.4) * cos(2 * gait + 0.6) }
        head.position = hp
        head.zRotation = pose.headTilt + tilt * 0.35

        let footK = 1 - exp(-dt * (moving || mode == .dig ? 40 : 13))
        for i in 0..<4 {
            let a = place(rigSpec.attach[i])
            let goal = footTarget(i, attach: a, head: hp)
            feet[i].x += (goal.x - feet[i].x) * footK
            feet[i].y += (goal.y - feet[i].y) * footK
            let dx = feet[i].x - a.x, dy = feet[i].y - a.y
            let len = hypot(dx, dy)
            legs[i].position = a
            legs[i].zRotation = atan2(dx, -dy)
            legs[i].yScale = max(0.15, len / rigSpec.legLength)
            let vis = pose.legsVisible * clamp((len - 3) / 4, 0, 1)
            legs[i].alpha = vis
            paws[i].alpha = vis
            paws[i].position = feet[i]
        }

        updateTail(place: place, tilt: tilt)
        updateHead(dt)

        squash *= exp(-dt * 9)
        rig.yScale = 1 - squash
        rig.xScale = 1 + squash * 0.6
        currentXScale += (facing * petScale - currentXScale) * (1 - exp(-dt * 16))
        xScale = currentXScale
        pivot.zRotation = spin + pose.roll
    }

    /// Tapered, outlined tail built along a wavy spine.
    private func updateTail(place: (CGPoint) -> CGPoint, tilt: CGFloat) {
        let n = rigSpec.tailSegments
        var p = place(rigSpec.tailAnchor)
        var angle = pose.tailAngle + tilt
        var pts = [p]
        var grounded = false
        let canGround = mode != .air && mode != .rollOver
        for i in 0..<n {
            let fi = CGFloat(i)
            if !grounded {
                angle += pose.tailCurl + pose.tailWave * sin(t * pose.tailSpeed - fi * 0.6) * (0.25 + fi * 0.07)
            }
            p = CGPoint(x: p.x + cos(angle) * rigSpec.tailSegmentLength, y: p.y + sin(angle) * rigSpec.tailSegmentLength)
            if canGround && p.y < 2.5 {
                p.y = 2.5
                if !grounded { angle = cos(angle) >= 0 ? 0 : .pi }
                grounded = true
            }
            pts.append(p)
        }

        var left: [CGPoint] = [], right: [CGPoint] = []
        for k in 0...n {
            let a = pts[max(0, k - 1)], b = pts[min(n, k + 1)]
            var tx = b.x - a.x, ty = b.y - a.y
            let len = max(hypot(tx, ty), 0.001)
            tx /= len; ty /= len
            let w = (rigSpec.tailBaseWidth + (rigSpec.tailTipWidth - rigSpec.tailBaseWidth) * CGFloat(k) / CGFloat(n)) / 2
            left.append(CGPoint(x: pts[k].x - ty * w, y: pts[k].y + tx * w))
            right.append(CGPoint(x: pts[k].x + ty * w, y: pts[k].y - tx * w))
        }
        let path = CGMutablePath()
        path.move(to: left[0])
        for k in 1..<n { path.addQuadCurve(to: mid(left[k], left[k + 1]), control: left[k]) }
        path.addLine(to: left[n])
        // Rounded tip
        let tip = pts[n], prev = pts[n - 1]
        let dl = max(hypot(tip.x - prev.x, tip.y - prev.y), 0.001)
        let cap = CGPoint(x: tip.x + (tip.x - prev.x) / dl * rigSpec.tailTipWidth,
                          y: tip.y + (tip.y - prev.y) / dl * rigSpec.tailTipWidth)
        path.addQuadCurve(to: right[n], control: cap)
        for k in stride(from: n - 1, to: 0, by: -1) { path.addQuadCurve(to: mid(right[k], right[k - 1]), control: right[k]) }
        path.addLine(to: right[0])
        path.closeSubpath()
        tail.path = path

        if tail.children.isEmpty, tailRings.parent != nil {
            let rings = CGMutablePath()
            for k in rigSpec.tailRings where k < n {
                rings.move(to: CGPoint(x: left[k].x * 0.85 + pts[k].x * 0.15, y: left[k].y * 0.85 + pts[k].y * 0.15))
                rings.addLine(to: CGPoint(x: right[k].x * 0.85 + pts[k].x * 0.15, y: right[k].y * 0.85 + pts[k].y * 0.15))
            }
            tailRings.path = rings
        }
    }
}
