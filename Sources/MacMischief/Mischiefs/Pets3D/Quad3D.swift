import AppKit
import SceneKit
import SpriteKit
import simd

/// What PetLayer needs from a pet body (2D or 3D).
@MainActor
protocol PetBody: SKNode {
    var mode: PetMode { get set }
    var gaitSpeed: CGFloat { get set }
    var facing: CGFloat { get set }
    var lookTarget: CGPoint? { get set }
    var spin: CGFloat { get set }
    var airTilt: CGFloat { get set }
    var petScale: CGFloat { get }
    var headPositionInParent: CGPoint { get }
    func land(_ amount: CGFloat)
    func update(dt: CGFloat)
    /// Return true if the body draws its own ground shadow.
    func placeShadow(at ground: CGPoint, strength: CGFloat, width: CGFloat) -> Bool
    func detach()
}

extension PetBody {
    func land() { land(0.24) }
}

extension QuadrupedNode: PetBody {
    func placeShadow(at ground: CGPoint, strength: CGFloat, width: CGFloat) -> Bool { false }
    func detach() {}
}

/// Skeleton layout for a 3D quadruped.
struct QuadSpec: Sendable {
    var bodyY: Float = 23
    var hips = SIMD2<Float>(-14, 0)
    var chest = SIMD2<Float>(12, 0)
    var headAnchor = SIMD2<Float>(24, 10)
    /// Ear root relative to the head (for the +z ear; mirrored for -z).
    var ear = V3(-0.5, 6.5, 4.6)
    var tailAnchor = SIMD2<Float>(-25, 3)
    var tailCount = 6
    var tailSeg: Float = 5.2
    var tailBindAngle: Float = 1.9
    var tailBindCurl: Float = 0.12
    /// near-front, far-front, near-hind, far-hind (relative to body centre)
    var legAttach: [V3] = [V3(13, -3, 5), V3(13, -3, -5), V3(-15, -2, 5.2), V3(-15, -2, -5.2)]
    var upper: [Float] = [11, 11, 11.5, 11.5]
    var lower: [Float] = [10, 10, 9.5, 9.5]
    var wristHeight: Float = 2.6
    var walkAmp: Float = 6.5
    var runAmp: Float = 10

    var tail0: Int { 5 }
    func leg(_ l: Int, _ seg: Int) -> Int { 5 + tailCount + l * 3 + seg }
    var boneCount: Int { 5 + tailCount + 12 }

    /// Bind-pose (model space) position of every bone, plus the tail tip.
    func bindPositions() -> (bones: [V3], tailTip: V3) {
        var p = [V3](repeating: .zero, count: boneCount)
        let body = V3(0, bodyY, 0)
        p[0] = body + V3(hips.x, hips.y, 0)
        p[1] = body + V3(chest.x, chest.y, 0)
        let head = body + V3(headAnchor.x, headAnchor.y, 0)
        p[2] = head
        p[3] = head + ear
        p[4] = head + V3(ear.x, ear.y, -ear.z)
        var q = body + V3(tailAnchor.x, tailAnchor.y, 0)
        var a = tailBindAngle
        for i in 0..<tailCount {
            p[tail0 + i] = q
            q += V3(cos(a), sin(a), 0) * tailSeg
            a += tailBindCurl
        }
        for l in 0..<4 {
            let u = body + legAttach[l]
            p[leg(l, 0)] = u
            p[leg(l, 1)] = u - V3(0, upper[l], 0)
            p[leg(l, 2)] = u - V3(0, upper[l] + lower[l], 0)
        }
        return (p, q)
    }
}

/// Species-specific look and behaviour for a 3D pet.
@MainActor
struct PetSpecies3D {
    var key: String
    var spec: QuadSpec
    var scale: CGFloat
    var sdf: (_ bind: [V3], _ tailTip: V3) -> SDFBody
    var decorate: (_ head: SCNNode, _ rig: QuadRig3D) -> PetFeatures
    var pose: (PetMode) -> PetPose
    /// Ear animation: returns (swing about z, flare about x) for the +z ear.
    var ears: (_ rig: QuadRig3D, _ dt: Float) -> (Float, Float)
    /// Tail motion style: dogs wag side to side, cats swish up and down.
    var lateralWag: Float = 0.35
    var sagittalWag: Float = 1
}

/// Animatable face parts.
@MainActor
final class PetFeatures {
    struct Eye {
        let socket: SCNNode
        let ball: SCNNode
        let pupil: SCNNode?
        let rest: simd_quatf
    }
    var eyes: [Eye] = []
    var mouth: SCNNode?
    var tongue: SCNNode?
    var slitPupils = false
}

/// The 3D skeleton + skinned mesh, driven with the same PetPose/PetMode
/// language as the 2D pets.
@MainActor
final class QuadRig3D {
    let spec: QuadSpec
    let species: PetSpecies3D
    let root = SCNNode()
    private let tiltNode = SCNNode()
    private let yawNode = SCNNode()
    private let pivot = SCNNode()
    let content = SCNNode()
    let body = SCNNode()
    private(set) var bones: [SCNNode] = []
    private var inverseBinds: [simd_float4x4] = []
    private var features = PetFeatures()

    var mode: PetMode = .stand
    var gaitSpeed: Float = 50
    var facing: Float = 1
    var spin: Float = 0
    var airTilt: Float = 0
    var lookTarget: V3?
    private(set) var pose = PetPose()
    private(set) var t: Float = 0
    private(set) var gait: Float = 0
    private var feet: [SIMD2<Float>]
    private var yaw: Float = -0.62
    private var squash: Float = 0
    private var lookYaw: Float = 0
    private var lookPitch: Float = 0
    private var blinkTimer: Float = 2
    private var blinkLeft: Float = 0
    private var dilation: Float = 0.35
    private var runBlend: Float = 0
    private var stride: Float = 6.5
    var earSwing: Float = 0
    var earFlare: Float = 0
    var earVelocity = SIMD2<Float>(0, 0)
    var twitch: [Float] = [0, 0]
    var twitchTimer: Float = 3

    init(species: PetSpecies3D) {
        self.species = species
        let localSpec = species.spec
        spec = localSpec
        let bind = localSpec.bindPositions()
        feet = (0..<4).map { SIMD2(bind.bones[localSpec.leg($0, 2)].x, 0) }

        root.addChildNode(tiltNode)
        tiltNode.simdEulerAngles = V3(0.16, 0, 0)
        tiltNode.addChildNode(yawNode)
        yawNode.addChildNode(pivot)
        pivot.simdPosition = V3(0, 20, 0)
        pivot.addChildNode(content)
        content.simdPosition = V3(0, -20, 0)
        content.addChildNode(body)
        root.simdScale = V3(repeating: Float(species.scale))

        // Bones in bind pose.
        bones = (0..<spec.boneCount).map { _ in SCNNode() }
        body.simdPosition = V3(0, spec.bodyY, 0)
        func attach(_ i: Int, to parent: SCNNode, at p: V3, angle: Float = 0) {
            parent.addChildNode(bones[i])
            bones[i].simdPosition = p
            bones[i].simdOrientation = simd_quatf(angle: angle, axis: V3(0, 0, 1))
        }
        attach(0, to: body, at: V3(spec.hips.x, spec.hips.y, 0))
        attach(1, to: body, at: V3(spec.chest.x, spec.chest.y, 0))
        attach(2, to: body, at: V3(spec.headAnchor.x, spec.headAnchor.y, 0))
        attach(3, to: bones[2], at: spec.ear)
        attach(4, to: bones[2], at: V3(spec.ear.x, spec.ear.y, -spec.ear.z))
        for i in 0..<spec.tailCount {
            if i == 0 {
                attach(spec.tail0, to: body, at: V3(spec.tailAnchor.x, spec.tailAnchor.y, 0), angle: spec.tailBindAngle)
            } else {
                attach(spec.tail0 + i, to: bones[spec.tail0 + i - 1], at: V3(spec.tailSeg, 0, 0), angle: spec.tailBindCurl)
            }
        }
        for l in 0..<4 {
            attach(spec.leg(l, 0), to: body, at: spec.legAttach[l])
            attach(spec.leg(l, 1), to: bones[spec.leg(l, 0)], at: V3(0, -spec.upper[l], 0))
            attach(spec.leg(l, 2), to: bones[spec.leg(l, 1)], at: V3(0, -spec.lower[l], 0))
        }
        inverseBinds = bones.map { simd_inverse(content.simdConvertTransform(matrix_identity_float4x4, from: $0)) }
        features = species.decorate(bones[2], self)
    }

    /// Attaches the sculpted, skinned body mesh (built in the background).
    func attachMesh(_ mesh: SkinnedMeshData) {
        let material = Studio.fur()
        let node = Studio.skinnedNode(mesh, bones: bones, skeleton: content, material: material,
                                      inverseBinds: inverseBinds)
        node.renderingOrder = 0
    }

    var headWorld: V3 { bones[2].simdWorldPosition }

    func land(_ amount: Float) { squash = amount }

    // MARK: - Frame

    func update(dt: Float) {
        t += dt
        var target = species.pose(mode)
        if mode == .air { target.tilt = CGFloat(airTilt) }
        pose.approach(target, CGFloat(1 - exp(-dt * (mode == .air ? 14 : 8))))

        let moving = mode == .walk || mode == .run || mode == .sniff
        // Smoothly blend walk <-> run gaits; longer strides at higher speed keep
        // the leg cadence natural instead of frantic.
        runBlend += ((mode == .run ? 1 : 0) - runBlend) * min(1, dt * 5)
        let speed = gaitSpeed / Float(species.scale)
        let runStride = min(spec.runAmp * 1.45, max(spec.runAmp, speed * spec.runAmp / 170))
        let walkStride = spec.walkAmp * (mode == .sniff ? 0.7 : 1)
        let wantStride = walkStride + (runStride - walkStride) * runBlend
        stride += (wantStride - stride) * min(1, dt * 6)
        if moving { gait += speed * dt * .pi / (2 * stride) }

        var bodyY = Float(pose.bodyY)
        var bodyX: Float = 0
        var tilt = Float(pose.tilt)
        var breathe: Float = 0
        switch mode {
        case .walk, .sniff, .run:
            bodyY += (0.8 + 0.9 * runBlend) * cos(2 * gait)
            tilt += 0.045 * runBlend * sin(2 * gait)
        case .crouch:
            tilt += 0.03 * sin(t * 24)
            bodyX = -0.8 * sin(t * 24)
        case .shake: tilt += 0.1 * sin(t * 34)
        case .sleep: breathe = 0.045 * sin(t * 1.5)
        case .stand, .sit, .happy, .speak, .groom, .beg, .scratch: breathe = 0.02 * sin(t * 2.4)
        default: break
        }

        body.simdPosition = V3(bodyX, bodyY, 0)
        body.simdOrientation = simd_quatf(angle: tilt, axis: V3(0, 0, 1))
        bones[0].simdScale = V3(1, 1 + breathe, 1 + breathe * 0.7)
        bones[1].simdScale = V3(1, 1 + breathe * 0.8, 1 + breathe * 0.6)
        // Galloping spine: hips and chest flex in opposition.
        let flex = 0.09 * runBlend * sin(2 * gait)
        bones[0].simdOrientation = simd_quatf(angle: -flex, axis: V3(0, 0, 1))
        bones[1].simdOrientation = simd_quatf(angle: flex, axis: V3(0, 0, 1))
        if mode == .shake {
            // Whole-body shimmy around the spine.
            body.simdOrientation = simd_quatf(angle: tilt, axis: V3(0, 0, 1)) * simd_quatf(angle: 0.35 * sin(t * 34), axis: V3(1, 0, 0))
        }

        let c = cos(tilt), s = sin(tilt)
        func place(_ p: SIMD2<Float>) -> SIMD2<Float> {
            SIMD2(p.x * c - p.y * s + bodyX, p.x * s + p.y * c + bodyY)
        }

        // Head (position offsets are in model space, like the 2D rig).
        var headOffset = SIMD2<Float>(Float(pose.headX), Float(pose.headY))
        if moving { headOffset.y += (0.35 + 0.6 * runBlend) * cos(2 * gait + 0.6) }
        let localOffset = SIMD2(headOffset.x * c + headOffset.y * s, -headOffset.x * s + headOffset.y * c)
        bones[2].simdPosition = V3(spec.headAnchor.x + localOffset.x, spec.headAnchor.y + localOffset.y, 0)
        var headRoll = Float(pose.headTilt) + tilt * 0.35 - tilt
        if mode == .groom { headRoll += 0.08 * sin(t * 5) }
        updateLook(dt)
        bones[2].simdOrientation = simd_quatf(angle: headRoll, axis: V3(0, 0, 1))
            * simd_quatf(angle: lookYaw, axis: V3(0, 1, 0))
            * simd_quatf(angle: lookPitch, axis: V3(0, 0, 1))
        let headModel = place(SIMD2(spec.headAnchor.x, spec.headAnchor.y)) + headOffset

        // Legs via 2-bone IK.
        let footK = 1 - exp(-dt * (moving || mode == .dig ? 40 : 13))
        for l in 0..<4 {
            let att = spec.legAttach[l]
            let a = place(SIMD2(att.x, att.y))
            let goal = footTarget(l, attach: a, head: headModel)
            feet[l] += (goal - feet[l]) * footK
            let wrist = feet[l] + SIMD2(0, spec.wristHeight)
            let (t1, t2) = Self.solveIK(a: a, f: wrist, l1: spec.upper[l], l2: spec.lower[l])
            bones[spec.leg(l, 0)].simdOrientation = simd_quatf(angle: t1 - tilt, axis: V3(0, 0, 1))
            bones[spec.leg(l, 1)].simdOrientation = simd_quatf(angle: t2 - t1, axis: V3(0, 0, 1))
            var pawAngle = -t2
            if mode == .air || mode == .rollOver { pawAngle += 0.6 }
            bones[spec.leg(l, 2)].simdOrientation = simd_quatf(angle: pawAngle, axis: V3(0, 0, 1))
        }

        updateTail(place: place, tilt: tilt)

        // Ears
        let (swing, flare) = species.ears(self, dt)
        bones[3].simdOrientation = simd_quatf(angle: swing, axis: V3(0, 0, 1)) * simd_quatf(angle: -flare, axis: V3(1, 0, 0))
        bones[4].simdOrientation = simd_quatf(angle: swing, axis: V3(0, 0, 1)) * simd_quatf(angle: flare, axis: V3(1, 0, 0))

        updateFace(dt)

        // Facing: smooth 3D turn (passes through facing the viewer).
        let yawTarget: Float = facing >= 0 ? -0.62 : -(.pi - 0.62)
        yaw += (yawTarget - yaw) * (1 - exp(-dt * 10))
        yawNode.simdOrientation = simd_quatf(angle: yaw, axis: V3(0, 1, 0))
        pivot.simdOrientation = simd_quatf(angle: spin + Float(pose.roll), axis: V3(0, 0, 1))

        squash *= exp(-dt * 9)
        content.simdScale = V3(1 + squash * 0.5, 1 - squash, 1 + squash * 0.5)
    }

    private func footTarget(_ i: Int, attach a: SIMD2<Float>, head h: SIMD2<Float>) -> SIMD2<Float> {
        let front = i < 2
        switch mode {
        case .stand, .speak, .shake:
            return SIMD2(a.x + (front ? 1 : -1), 0)
        case .walk, .run, .sniff:
            let walkPhase: [Float] = [.pi / 2, 1.5 * .pi, 0, .pi]
            let runPhase: [Float] = [0, 0.4, .pi, .pi + 0.4]
            let lift = (3.2 + 2.8 * runBlend) * (spec.wristHeight / 2.6)
            let psi = gait + walkPhase[i] + (runPhase[i] - walkPhase[i]) * runBlend
            return SIMD2(a.x + stride * sin(psi), lift * max(0, cos(psi)))
        case .sit, .happy, .scratch:
            if mode == .scratch && i == 2 {
                return SIMD2(h.x - 12 + 2 * sin(t * 30), h.y - 6 + 2.5 * cos(t * 30))
            }
            return front ? SIMD2(a.x + 1, 0) : SIMD2(a.x + 9, 0)
        case .groom:
            if i == 0 { return SIMD2(h.x + 3, h.y - 8 + 1.5 * sin(t * 11)) }
            return front ? SIMD2(a.x + 1, 0) : SIMD2(a.x + 9, 0)
        case .beg:
            return front ? SIMD2(a.x + 6, a.y - 7 + 1.2 * sin(t * 8 + Float(i))) : SIMD2(a.x + 9, 0)
        case .sleep:
            return SIMD2(a.x + (front ? 9 : -6), 0.5)
        case .crouch:
            return SIMD2(a.x + (front ? 5 : -1), 0)
        case .stretch, .playBow:
            return SIMD2(a.x + (front ? 13 : -3), 0)
        case .dig:
            if front {
                let ph = t * 22 + (i == 0 ? 0 : .pi)
                return SIMD2(a.x + 6 + 5 * sin(ph), max(0, 3 * cos(ph)))
            }
            return SIMD2(a.x - 2, 0)
        case .air:
            return front ? SIMD2(a.x + 9 + 1.5 * sin(t * 14), a.y - 12) : SIMD2(a.x - 9, a.y - 12)
        case .rollOver:
            let kick = 2.5 * sin(t * 12 + Float(i) * 1.7)
            return SIMD2(a.x + (front ? 3 : -3) + kick, a.y - 11)
        }
    }

    static func solveIK(a: SIMD2<Float>, f: SIMD2<Float>, l1: Float, l2: Float) -> (Float, Float) {
        var d = f - a
        var dist = simd_length(d)
        let maxD = l1 + l2 - 0.05, minD = abs(l1 - l2) + 0.6
        if dist > maxD {
            d *= maxD / dist
            dist = maxD
        } else if dist < minD {
            d = dist < 1e-4 ? SIMD2(0, -minD) : d * (minD / dist)
            dist = minD
        }
        let phi = atan2(d.x, -d.y)
        let cosA = max(-1, min(1, (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)))
        let t1 = phi - acos(cosA)
        let j = a + SIMD2(sin(t1), -cos(t1)) * l1
        let g = a + d
        let t2 = atan2(g.x - j.x, -(g.y - j.y))
        return (t1, t2)
    }

    private func updateTail(place: (SIMD2<Float>) -> SIMD2<Float>, tilt: Float) {
        var p = place(spec.tailAnchor)
        var angle = Float(pose.tailAngle) + tilt
        var prevAngle = tilt
        var grounded = false
        let canGround = mode != .air && mode != .rollOver
        for i in 0..<spec.tailCount {
            let fi = Float(i)
            if !grounded {
                if i > 0 { angle += Float(pose.tailCurl) }
                angle += species.sagittalWag * Float(pose.tailWave) * sin(t * Float(pose.tailSpeed) - fi * 0.6) * (0.25 + fi * 0.09)
            }
            let lateral = species.lateralWag * Float(pose.tailWave) * sin(t * Float(pose.tailSpeed) - fi * 0.5) * (0.35 + fi * 0.12)
            var next = p + SIMD2(cos(angle), sin(angle)) * spec.tailSeg
            if canGround && next.y < 3 && !grounded {
                // Lay the rest of the tail along the ground.
                angle = cos(angle) >= 0 ? 0 : .pi
                grounded = true
                next = p + SIMD2(cos(angle), sin(angle)) * spec.tailSeg
            }
            bones[spec.tail0 + i].simdOrientation = simd_quatf(angle: angle - prevAngle, axis: V3(0, 0, 1))
                * simd_quatf(angle: lateral, axis: V3(0, 1, 0))
            prevAngle = angle
            p = next
        }
    }

    private func updateLook(_ dt: Float) {
        var wantYaw: Float = 0, wantPitch: Float = 0
        if let target = lookTarget, let parent = bones[2].parent {
            let local = parent.simdConvertPosition(target, from: nil) - bones[2].simdPosition
            let horiz = sqrt(local.x * local.x + local.z * local.z)
            if local.x > -4 {
                wantYaw = max(-0.75, min(0.75, atan2(-local.z, local.x)))
                wantPitch = max(-0.4, min(0.5, atan2(local.y, horiz)))
            }
        }
        let busy = [.sleep, .groom, .dig, .sniff, .rollOver, .shake, .scratch].contains(mode)
        if busy { wantYaw = 0; wantPitch = 0 }
        let k = 1 - exp(-dt * 6)
        lookYaw += (wantYaw - lookYaw) * k
        lookPitch += (wantPitch - lookPitch) * k
    }

    private func updateFace(_ dt: Float) {
        blinkTimer -= dt
        if blinkTimer <= 0 {
            blinkLeft = 0.14
            blinkTimer = .random(in: 2...6)
        }
        blinkLeft -= dt
        var open: Float = blinkLeft > 0 ? 0.08 : 1
        switch mode {
        case .sleep: open = 0.06
        case .groom: open = features.slitPupils ? 0.06 : open
        case .happy, .rollOver: open = 0.32
        case .shake, .beg: open = features.slitPupils ? open : 0.4
        default: break
        }
        let wantDilation: Float = [.crouch, .air, .run].contains(mode) ? 0.85 : (lookTarget == nil ? 0.3 : 0.45)
        dilation += (wantDilation - dilation) * min(1, dt * 6)

        for eye in features.eyes {
            var y = eye.socket.simdScale.y
            y += (open - y) * min(1, dt * 22)
            eye.socket.simdScale = V3(1, y, 1)
            if let pupil = eye.pupil, features.slitPupils {
                pupil.simdScale = V3(dilation, 0.92, 0.26)
            }
            // Eyes track the target a little beyond what the head does.
            var q = eye.rest
            if let target = lookTarget, let parent = eye.ball.parent {
                let dir = simd_normalize(parent.simdConvertPosition(target, from: nil) - eye.ball.simdPosition)
                let fwd = eye.rest.act(V3(0, 0, 1))
                var turn = simd_quatf(from: fwd, to: dir)
                if turn.angle > 0.32 { turn = simd_quatf(angle: 0.32, axis: turn.axis) }
                if turn.angle.isFinite { q = turn * eye.rest }
            }
            eye.ball.simdOrientation = simd_slerp(eye.ball.simdOrientation, q, min(1, dt * 12))
        }

        if let mouth = features.mouth {
            let wantOpen: Float = mode == .speak ? 0.6 + 0.4 * abs(sin(t * 7)) : 0.01
            var sc = mouth.simdScale
            sc.y += (wantOpen - sc.y) * min(1, dt * 18)
            mouth.simdScale = sc
            mouth.isHidden = sc.y < 0.05
        }
        if let tongue = features.tongue {
            let panting = [.run, .walk, .happy, .beg, .playBow, .rollOver, .dig].contains(mode)
                || ([.stand, .sit].contains(mode) && t.truncatingRemainder(dividingBy: 9) < 5)
            let want: Float = panting && mode != .speak ? 0.9 + 0.15 * sin(t * (mode == .run ? 16 : 9)) : 0.01
            var sc = tongue.simdScale
            sc.y += (want - sc.y) * min(1, dt * 12)
            tongue.simdScale = sc
            tongue.isHidden = sc.y < 0.05
        }
    }
}

/// SpriteKit-facing wrapper: lets PetLayer drive a 3D pet exactly like a 2D one.
final class Pet3DNode: SKNode, PetBody {
    var mode: PetMode = .stand
    var gaitSpeed: CGFloat = 50
    var facing: CGFloat = 1
    var lookTarget: CGPoint?
    var spin: CGFloat = 0
    var airTilt: CGFloat = 0
    let petScale: CGFloat

    private let rig: QuadRig3D
    private weak var stage: Stage3D?
    private let shadow = Studio.shadowNode()
    private let release: () -> Void
    private var detached = false

    @MainActor private static var meshCache: [String: SkinnedMeshData] = [:]

    init(species: PetSpecies3D, stage: Stage3D, release: @escaping () -> Void) {
        rig = QuadRig3D(species: species)
        petScale = species.scale
        self.stage = stage
        self.release = release
        super.init()
        stage.scene.rootNode.addChildNode(rig.root)
        stage.scene.rootNode.addChildNode(shadow)
        rig.root.isHidden = true

        if let cached = Self.meshCache[species.key] {
            rig.attachMesh(cached)
            rig.root.isHidden = false
        } else {
            let bind = species.spec.bindPositions()
            let sdf = species.sdf(bind.bones, bind.tailTip)
            let key = species.key
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let mesh = sdf.mesh(cell: 0.7)
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        Pet3DNode.meshCache[key] = mesh
                        guard let self, !self.detached else { return }
                        self.rig.attachMesh(mesh)
                        self.rig.root.isHidden = false
                    }
                }
            }
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) not supported") }

    var headPositionInParent: CGPoint {
        let h = rig.headWorld
        return CGPoint(x: CGFloat(h.x), y: CGFloat(h.y))
    }

    func land(_ amount: CGFloat) { rig.land(Float(amount)) }

    func update(dt: CGFloat) {
        rig.mode = mode
        rig.gaitSpeed = Float(gaitSpeed)
        rig.facing = Float(facing)
        rig.spin = Float(spin)
        rig.airTilt = Float(airTilt)
        rig.lookTarget = lookTarget.map { V3(Float($0.x), Float($0.y), 90) }
        rig.root.simdPosition = V3(Float(position.x), Float(position.y), 0)
        rig.update(dt: Float(dt))
    }

    func placeShadow(at ground: CGPoint, strength: CGFloat, width: CGFloat) -> Bool {
        shadow.simdPosition = V3(Float(ground.x), Float(ground.y) + 1, -60)
        let w = Float(width * 62)
        shadow.simdScale = V3(w, w * 0.2, 1)
        shadow.opacity = strength
        return true
    }

    func detach() {
        guard !detached else { return }
        detached = true
        rig.root.removeFromParentNode()
        shadow.removeFromParentNode()
        release()
    }
}
