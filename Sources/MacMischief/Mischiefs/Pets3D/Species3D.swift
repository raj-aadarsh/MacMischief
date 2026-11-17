import AppKit
import SceneKit
import simd

private func ss(_ a: Float, _ b: Float, _ x: Float) -> Float {
    let t = max(0, min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
}

private func mix(_ a: V3, _ b: V3, _ t: Float) -> V3 { a + (b - a) * max(0, min(1, t)) }

private func band(_ v: Float) -> Float { ss(0.58, 0.82, sin(v) * 0.5 + 0.5) }

@MainActor
enum FaceParts {
    /// Builds an eye (socket for blinking, ball for looking) on a head.
    static func eye(on head: SCNNode, at p: V3, outward: V3, radius: Float, iris: NSColor,
                    pupil pupilColor: NSColor?, slit: Bool) -> PetFeatures.Eye {
        let socket = SCNNode()
        socket.simdPosition = p
        head.addChildNode(socket)
        let ball = SCNNode(geometry: SCNSphere(radius: CGFloat(radius)))
        (ball.geometry as! SCNSphere).segmentCount = 32
        ball.geometry!.materials = [Studio.pbr(iris, metal: 0, rough: 0.18, clearCoat: 1)]
        socket.addChildNode(ball)
        // Orientation with +z = outward and +y ≈ up (keeps slit pupils vertical).
        let z = simd_normalize(outward)
        let x = simd_normalize(simd_cross(V3(0, 1, 0), z))
        let y = simd_cross(z, x)
        let rest = simd_quatf(simd_float3x3(x, y, z))
        ball.simdOrientation = rest
        var pupil: SCNNode?
        if let pupilColor {
            let pu = SCNNode(geometry: SCNSphere(radius: CGFloat(radius * 0.88)))
            pu.geometry!.materials = [Studio.pbr(pupilColor, metal: 0, rough: 0.12, clearCoat: 1)]
            pu.simdPosition = V3(0, 0, radius * 0.8)
            pu.simdScale = slit ? V3(0.3, 0.92, 0.26) : V3(0.55, 0.58, 0.26)
            ball.addChildNode(pu)
            pupil = pu
        }
        return PetFeatures.Eye(socket: socket, ball: ball, pupil: pupil, rest: rest)
    }

    static func blob(_ r: Float, _ color: NSColor, scale: V3, at p: V3, rough: CGFloat = 0.35, coat: CGFloat = 0.5) -> SCNNode {
        let n = SCNNode(geometry: SCNSphere(radius: CGFloat(r)))
        n.geometry!.materials = [Studio.pbr(color, metal: 0, rough: rough, clearCoat: coat)]
        n.simdPosition = p
        n.simdScale = scale
        return n
    }

    static func whisker(on head: SCNNode, from a: V3, to b: V3) {
        let len = simd_length(b - a)
        let cyl = SCNCylinder(radius: 0.08, height: CGFloat(len))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor(white: 0.97, alpha: 0.85)
        cyl.materials = [m]
        let n = SCNNode(geometry: cyl)
        n.simdPosition = (a + b) / 2
        n.simdOrientation = simd_quatf(from: V3(0, 1, 0), to: simd_normalize(b - a))
        head.addChildNode(n)
    }

    static func tongue(on head: SCNNode, at p: V3) -> SCNNode {
        let tongue = SCNNode(geometry: SCNCapsule(capRadius: 1.3, height: 5.6))
        tongue.geometry!.materials = [Studio.pbr(NSColor(srgbRed: 0.98, green: 0.45, blue: 0.55, alpha: 1), rough: 0.35, clearCoat: 0.6)]
        let root = SCNNode()
        root.simdPosition = p
        head.addChildNode(root)
        tongue.simdPosition = V3(0.6, -2.4, 0)
        tongue.simdScale = V3(0.72, 1, 1.3)
        tongue.simdEulerAngles = V3(0, 0, 0.35)
        root.addChildNode(tongue)
        return root
    }
}

/// Helper for building a body out of smoothly blended primitives.
private struct Sculpt {
    var prims: [SDFPrim] = []
    mutating func add(_ shape: SDFPrim.Shape, _ bone: Int, _ region: Int, _ blend: Float,
                      squash: (V3, Float, V3)? = nil) {
        var p = SDFPrim(shape: shape, bone: bone, region: region, blend: blend)
        if let squash { p.squashAxis = squash.0; p.squashFactor = squash.1; p.squashCenter = squash.2 }
        prims.append(p)
    }
}

/// Erect-ear behaviour: little twitches, pinned back when happy or stalking.
@MainActor
private func erectEars(_ rig: QuadRig3D, _ dt: Float, back: Set<PetMode>, perk: Set<PetMode>) -> (Float, Float) {
    rig.twitchTimer -= dt
    if rig.twitchTimer <= 0 {
        rig.twitch[Int.random(in: 0...1)] = 1
        rig.twitchTimer = .random(in: 2.5...7)
    }
    for i in 0..<2 { rig.twitch[i] *= exp(-dt * 9) }
    let lay: Float = back.contains(rig.mode) ? 1 : (perk.contains(rig.mode) ? -0.3 : 0)
    var run: Float = 0
    if rig.mode == .run || rig.mode == .air { run = 0.45 }
    rig.earSwing += (lay * 0.6 + run - rig.earSwing) * min(1, dt * 8)
    rig.earFlare += (lay * 0.45 - rig.earFlare) * min(1, dt * 8)
    let tw = max(rig.twitch[0], rig.twitch[1]) * 0.35 * sin(rig.t * 40)
    return (rig.earSwing + tw, rig.earFlare + 0.1)
}

extension PetSpecies3D {
    // MARK: - Cat: Munchkin (short legs, long low body, round face)

    static let cat3D: PetSpecies3D = {
        var spec = QuadSpec()
        spec.bodyY = 15
        spec.hips = SIMD2(-14, 0)
        spec.chest = SIMD2(12, 0)
        spec.headAnchor = SIMD2(23.5, 11)
        spec.ear = V3(-0.6, 6.7, 4.9)
        spec.tailAnchor = SIMD2(-25, 3)
        spec.tailCount = 6
        spec.tailSeg = 5.0
        spec.tailBindAngle = 1.75
        spec.tailBindCurl = 0.1
        spec.legAttach = [V3(12, -3, 5.2), V3(12, -3, -5.2), V3(-14, -2.5, 5.4), V3(-14, -2.5, -5.4)]
        spec.upper = [5.8, 5.8, 6.4, 6.4]
        spec.lower = [5.0, 5.0, 4.8, 4.8]
        spec.wristHeight = 2.3
        spec.walkAmp = 4.0
        spec.runAmp = 6.5
        return PetSpecies3D(key: "munchkin", spec: spec, scale: 1.2, sdf: { bind, tip in
            munchkinBody(spec, bind, tip)
        }, decorate: { head, _ in
            let f = PetFeatures()
            f.slitPupils = true
            for side in [Float(1), -1] {
                f.eyes.append(FaceParts.eye(on: head, at: V3(5.9, 1.6, 4.0 * side), outward: V3(0.78, 0.16, 0.6 * side),
                                            radius: 3.05, iris: NSColor(srgbRed: 0.85, green: 0.72, blue: 0.2, alpha: 1),
                                            pupil: NSColor(srgbRed: 0.03, green: 0.03, blue: 0.03, alpha: 1), slit: true))
                for (dy, dz, end) in [(Float(-0.6), Float(0.3), V3(0, 1.4, 0)), (-1.2, 0.6, V3(0, 0, 0)), (-1.8, 0.9, V3(0, -1.6, 0))] {
                    let a = V3(7.8, -2.6 + dy, (1.6 + dz) * side)
                    FaceParts.whisker(on: head, from: a, to: a + V3(1.5, 0, 9 * side) + end)
                }
            }
            head.addChildNode(FaceParts.blob(1.3, NSColor(srgbRed: 0.93, green: 0.5, blue: 0.58, alpha: 1),
                                             scale: V3(0.75, 0.62, 1.2), at: V3(9.1, -1.3, 0)))
            let mouth = FaceParts.blob(1.4, NSColor(srgbRed: 0.42, green: 0.08, blue: 0.12, alpha: 1),
                                       scale: V3(0.5, 0.01, 1.1), at: V3(8.4, -4.1, 0), rough: 0.5, coat: 0)
            head.addChildNode(mouth)
            f.mouth = mouth
            return f
        }, pose: munchkinPose, ears: { rig, dt in
            erectEars(rig, dt, back: [.crouch], perk: [.happy, .speak, .beg])
        }, lateralWag: 0.35, sagittalWag: 1)
    }()

    static func munchkinPose(_ m: PetMode) -> PetPose {
        var p = PetPose()
        p.bodyY = 15
        p.tailAngle = 1.6; p.tailCurl = 0.08; p.tailWave = 0.1; p.tailSpeed = 2.2
        // The famous Munchkin "meerkat" sit: upright, front paws dangling.
        func sitting() {
            p.bodyY = 13; p.tilt = 0.78; p.headX = -6; p.headY = -1.5; p.headTilt = -0.22
            p.tailAngle = 4.1; p.tailCurl = 0.16; p.tailWave = 0.05; p.tailSpeed = 1.5
        }
        switch m {
        case .stand, .shake: break
        case .walk, .sniff:
            p.headX = 1; p.tailAngle = 1.45; p.tailCurl = 0.1; p.tailWave = 0.1; p.tailSpeed = 3.5
        case .run:
            p.bodyY = 14; p.tilt = -0.03; p.headX = 2; p.headY = -1.5
            p.tailAngle = 2.5; p.tailCurl = 0.04; p.tailWave = 0.12; p.tailSpeed = 9
        case .sit, .scratch, .beg: sitting()
        case .happy:
            sitting()
            p.headTilt = -0.32
            p.tailAngle = 2.0; p.tailCurl = -0.05; p.tailWave = 0.18; p.tailSpeed = 6
        case .speak:
            sitting()
            p.headY = 0.5; p.headTilt = -0.4
        case .groom:
            sitting()
            p.headX = -5; p.headY = -2.5; p.headTilt = 0.1
        case .sleep:
            p.bodyY = 9.2; p.headX = 1; p.headY = -6.5; p.headTilt = -0.15
            p.tailAngle = 3.4; p.tailCurl = 0.05; p.tailWave = 0.03; p.tailSpeed = 0.8
        case .crouch:
            p.bodyY = 11.5; p.tilt = -0.08; p.headX = 3; p.headY = -3
            p.tailAngle = 3.05; p.tailCurl = 0; p.tailWave = 0.07; p.tailSpeed = 10
        case .stretch, .playBow, .dig:
            p.bodyY = 12; p.tilt = -0.28; p.headX = 3; p.headY = -1; p.headTilt = 0.15
            p.tailAngle = 1.35; p.tailCurl = 0.1; p.tailWave = 0.08; p.tailSpeed = 2
        case .air:
            p.headX = 2; p.tailAngle = 2.8; p.tailCurl = 0.05; p.tailWave = 0.15; p.tailSpeed = 6
        case .rollOver:
            p.bodyY = 29.5; p.roll = .pi; p.headY = -9; p.headX = -2; p.headTilt = 0.35
            p.tailAngle = 2.6; p.tailWave = 0.2; p.tailSpeed = 4
        }
        return p
    }

    private static func munchkinBody(_ s: QuadSpec, _ P: [V3], _ tip: V3) -> SDFBody {
        let body = 0, belly = 1, chest = 2, head = 3, cheek = 4, muzzle = 5, ear = 6, tail = 7, leg = 8, paw = 9
        let H = P[2], hips = P[0], ch = P[1]
        var k = Sculpt()
        let flat = (V3(0, 0, 1), Float(1.1), V3(0, s.bodyY, 0))
        let mid = V3(-1, s.bodyY + 0.3, 0)
        k.add(.cone(a: hips + V3(-3, 0.4, 0), b: mid, ra: 9.0, rb: 8.7), 0, body, 3, squash: flat)
        k.add(.cone(a: mid, b: ch + V3(1, 0.4, 0), ra: 8.7, rb: 8.4), 1, body, 4, squash: flat)
        k.add(.ellipsoid(c: V3(-1, s.bodyY - 3.3, 0), r: V3(15, 6.2, 7)), 0, belly, 5)
        k.add(.sphere(c: ch + V3(3, -1.4, 0), r: 7.6), 1, chest, 5)
        for z in [Float(4.6), -4.6] {
            k.add(.sphere(c: hips + V3(-1, -1.4, z), r: 6.6), 0, body, 4)
            k.add(.sphere(c: ch + V3(0.5, -0.8, z * 0.85), r: 5.5), 1, body, 4)
        }
        let neckA = ch + V3(3, 2.6, 0), neckB = H + V3(-2.5, -3.5, 0)
        let neckM = (neckA + neckB) / 2
        k.add(.cone(a: neckA, b: neckM, ra: 6.4, rb: 6.0), 1, body, 4)
        k.add(.cone(a: neckM, b: neckB, ra: 6.0, rb: 5.6), 2, head, 3)
        // Round face
        k.add(.sphere(c: H, r: 9.0), 2, head, 3, squash: (V3(0, 0, 1), 0.9, H))
        k.add(.ellipsoid(c: H + V3(2.2, 2.2, 0), r: V3(6.4, 5, 6.8)), 2, head, 4)
        for z in [Float(4.5), -4.5] {
            k.add(.sphere(c: H + V3(1.4, -3.1, z), r: 5.2), 2, cheek, 4)
            k.add(.sphere(c: H + V3(7.0, -2.9, z * 0.36), r: 2.2), 2, muzzle, 2)
        }
        k.add(.sphere(c: H + V3(6.0, -4.6, 0), r: 1.8), 2, muzzle, 2)
        for (bone, side) in [(3, Float(1)), (4, Float(-1))] {
            let e = P[bone]
            k.add(.cone(a: e, b: e + V3(-0.8, 7.0, side * 1.7), ra: 3.9, rb: 0.95), bone, ear, 2, squash: (V3(1, 0, 0), 2.4, e))
        }
        let tailPts = (0..<s.tailCount).map { P[s.tail0 + $0] } + [tip]
        for i in 0..<s.tailCount {
            let r0 = 3.0 - Float(i) * 0.13, r1 = 3.0 - Float(i + 1) * 0.13
            k.add(.cone(a: tailPts[i], b: tailPts[i + 1], ra: r0, rb: r1), s.tail0 + i, tail, i == 0 ? 3 : 1.2)
        }
        // Short, stubby legs
        for l in 0..<4 {
            let u = P[s.leg(l, 0)], lo = P[s.leg(l, 1)], w = P[s.leg(l, 2)]
            let hind = l >= 2
            k.add(.cone(a: u + V3(0, 1.5, 0), b: lo, ra: hind ? 5.0 : 3.9, rb: 3.2), s.leg(l, 0), leg, 3.2)
            k.add(.cone(a: lo, b: w, ra: 3.2, rb: 2.9), s.leg(l, 1), leg, 1.4)
            k.add(.ellipsoid(c: w + V3(1.2, -0.4, 0), r: V3(3.4, 2.1, 2.9)), s.leg(l, 2), paw, 1.4)
        }

        let ginger = V3(0.93, 0.56, 0.26), stripe = V3(0.70, 0.33, 0.12), cream = V3(1.0, 0.93, 0.83), pink = V3(0.94, 0.6, 0.64)
        let bodyY = s.bodyY
        let earL = P[3], earR = P[4]
        let tail0 = P[s.tail0]
        let legTop = bodyY - 3
        return SDFBody(prims: k.prims, boneCount: s.boneCount) { p, region in
            switch region {
            case body:
                let st = band(p.x * 0.55 + sin(p.z * 0.3) * 0.8) * ss(bodyY - 2, bodyY + 4, p.y)
                return mix(mix(ginger, stripe, st * 0.85), cream, ss(bodyY - 4, bodyY - 8, p.y))
            case belly: return mix(ginger, cream, ss(bodyY - 1.5, bodyY - 5, p.y))
            case chest: return mix(ginger, cream, ss(bodyY + 1, bodyY - 4, p.y) * ss(ch.x + 1, ch.x + 5, p.x))
            case head:
                let m = band(p.z * 1.35) * ss(H.y + 3.5, H.y + 7, p.y) * ss(H.x + 7, H.x + 3, p.x)
                return mix(ginger, stripe, m * 0.9)
            case cheek: return mix(ginger, cream, ss(H.y - 3.5, H.y - 6.5, p.y) * 0.8)
            case muzzle: return cream
            case ear:
                let e = p.z > 0 ? earL : earR
                let side: Float = p.z > 0 ? 1 : -1
                let along = (p.y - e.y) / 7.0
                let centerZ = e.z + side * 1.7 * along
                let inner = p.x > e.x - 0.2 && abs(p.z - centerZ) < 2.4 * (1 - along) && along > 0.08 && along < 0.85
                return inner ? pink : mix(ginger, stripe, ss(0.75, 0.95, along))
            case tail:
                let d = simd_length(p - tail0)
                return mix(ginger, stripe, band(d * 0.85) * 0.9 + ss(24, 30, d) * 0.6)
            case leg:
                return mix(mix(ginger, stripe, band(p.y * 1.3) * 0.5 * ss(legTop - 6, legTop - 2, p.y)), cream, ss(legTop - 9, legTop - 12, p.y))
            case paw: return cream
            default: return ginger
            }
        }
    }

    // MARK: - Dog: Pomsky (husky mask, blue eyes, erect ears, curled plume tail)

    static let dog3D: PetSpecies3D = {
        var spec = QuadSpec()
        spec.bodyY = 21
        spec.hips = SIMD2(-13, 0)
        spec.chest = SIMD2(12, 0)
        spec.headAnchor = SIMD2(22.5, 12.5)
        spec.ear = V3(-0.4, 7.0, 4.4)
        spec.tailAnchor = SIMD2(-23, 6)
        spec.tailCount = 6
        spec.tailSeg = 4.3
        spec.tailBindAngle = 1.45
        spec.tailBindCurl = 0.3
        spec.legAttach = [V3(12, -3, 5.4), V3(12, -3, -5.4), V3(-13, -2, 5.6), V3(-13, -2, -5.6)]
        spec.upper = [9.6, 9.6, 10, 10]
        spec.lower = [8.6, 8.6, 8.2, 8.2]
        spec.wristHeight = 2.7
        spec.walkAmp = 6
        spec.runAmp = 10
        return PetSpecies3D(key: "pomsky", spec: spec, scale: 1.18, sdf: { bind, tip in
            pomskyBody(spec, bind, tip)
        }, decorate: { head, _ in
            let f = PetFeatures()
            for side in [Float(1), -1] {
                f.eyes.append(FaceParts.eye(on: head, at: V3(6.6, 1.9, 3.9 * side), outward: V3(0.8, 0.12, 0.58 * side),
                                            radius: 2.5, iris: NSColor(srgbRed: 0.42, green: 0.7, blue: 0.97, alpha: 1),
                                            pupil: NSColor(srgbRed: 0.02, green: 0.02, blue: 0.03, alpha: 1), slit: false))
            }
            head.addChildNode(FaceParts.blob(1.9, NSColor(srgbRed: 0.05, green: 0.05, blue: 0.06, alpha: 1),
                                             scale: V3(0.85, 0.72, 1.15), at: V3(13.4, -2.9, 0), rough: 0.25, coat: 0.8))
            f.tongue = FaceParts.tongue(on: head, at: V3(10.2, -6.2, 0))
            let mouth = FaceParts.blob(1.7, NSColor(srgbRed: 0.35, green: 0.06, blue: 0.1, alpha: 1),
                                       scale: V3(0.7, 0.01, 1.2), at: V3(10.6, -5.7, 0), rough: 0.5, coat: 0)
            head.addChildNode(mouth)
            f.mouth = mouth
            return f
        }, pose: pomskyPose, ears: { rig, dt in
            erectEars(rig, dt, back: [.happy, .rollOver, .beg, .playBow, .crouch], perk: [.speak, .stand, .sniff])
        }, lateralWag: 1.0, sagittalWag: 0.25)
    }()

    static func pomskyPose(_ m: PetMode) -> PetPose {
        var p = PetPose()
        p.bodyY = 22.5
        p.headY = 1.5
        // Fluffy tail curled up over the back, wagging side to side.
        p.tailAngle = 1.45; p.tailCurl = 0.3; p.tailWave = 0.3; p.tailSpeed = 9
        func sitting() {
            p.bodyY = 16; p.tilt = 0.45; p.headX = -2; p.headY = 3; p.headTilt = 0.02
            p.tailAngle = 3.5; p.tailCurl = 0.28; p.tailWave = 0.35; p.tailSpeed = 12
        }
        switch m {
        case .stand: break
        case .walk: p.headY = 0.5; p.tailWave = 0.35; p.tailSpeed = 11
        case .run:
            p.bodyY = 21; p.tilt = -0.05; p.headX = 3; p.headY = -1
            p.tailAngle = 1.9; p.tailCurl = 0.2; p.tailWave = 0.25; p.tailSpeed = 14
        case .sit, .scratch:
            sitting()
            if m == .scratch { p.headTilt = 0.35; p.headX = -4 }
        case .happy:
            sitting()
            p.headTilt = 0.12; p.tailWave = 0.6; p.tailSpeed = 18
        case .beg:
            sitting()
            p.tilt = 0.6; p.headY = 6; p.headTilt = -0.15; p.tailWave = 0.55; p.tailSpeed = 18
        case .speak:
            sitting()
            p.headY = 5; p.headTilt = -0.25; p.tailWave = 0.45; p.tailSpeed = 16
        case .groom: sitting()
        case .sleep:
            p.bodyY = 11.5; p.headX = 2; p.headY = -8.5; p.headTilt = -0.12
            p.tailAngle = 3.4; p.tailCurl = 0.32; p.tailWave = 0.03; p.tailSpeed = 0.8
        case .crouch:
            p.bodyY = 15; p.tilt = -0.15; p.headX = 3; p.headY = -3
            p.tailWave = 0.45; p.tailSpeed = 16
        case .stretch:
            p.bodyY = 17; p.tilt = -0.32; p.headX = 3; p.headY = -1; p.headTilt = 0.15
            p.tailWave = 0.25; p.tailSpeed = 6
        case .playBow:
            p.bodyY = 18; p.tilt = -0.38; p.headX = 4; p.headY = 0; p.headTilt = 0.25
            p.tailWave = 0.65; p.tailSpeed = 19
        case .sniff:
            p.bodyY = 21; p.tilt = -0.12; p.headX = 5; p.headY = -9.5; p.headTilt = -0.35
            p.tailWave = 0.35; p.tailSpeed = 12
        case .dig:
            p.bodyY = 19; p.tilt = -0.25; p.headX = 4; p.headY = -6; p.headTilt = -0.2
            p.tailWave = 0.35; p.tailSpeed = 14
        case .rollOver:
            p.bodyY = 26; p.roll = .pi; p.headY = -11; p.headX = -2; p.headTilt = 0.35
            p.tailAngle = 2.4; p.tailCurl = 0.15; p.tailWave = 0.5; p.tailSpeed = 18
        case .shake: p.headY = 1; p.tailWave = 0.45; p.tailSpeed = 30
        case .air: p.headX = 2; p.tailAngle = 2.1; p.tailCurl = 0.15; p.tailWave = 0.2; p.tailSpeed = 10
        }
        return p
    }

    private static func pomskyBody(_ s: QuadSpec, _ P: [V3], _ tip: V3) -> SDFBody {
        let body = 0, belly = 1, chest = 2, head = 3, cheek = 4, muzzle = 5, ear = 6, tail = 7, leg = 8, paw = 9, tailTip = 10, ruff = 11
        let H = P[2], hips = P[0], ch = P[1]
        var k = Sculpt()
        let flat = (V3(0, 0, 1), Float(1.06), V3(0, s.bodyY, 0))
        let mid = V3(-0.5, s.bodyY + 0.3, 0)
        k.add(.cone(a: hips + V3(-3, 0.5, 0), b: mid, ra: 9.6, rb: 9.4), 0, body, 3, squash: flat)
        k.add(.cone(a: mid, b: ch + V3(1, 0.4, 0), ra: 9.4, rb: 9.2), 1, body, 4, squash: flat)
        k.add(.ellipsoid(c: V3(-1, s.bodyY - 3.6, 0), r: V3(13.5, 7, 7.6)), 0, belly, 6)
        k.add(.sphere(c: ch + V3(3, -1.4, 0), r: 8.6), 1, chest, 5)
        for z in [Float(4.8), -4.8] {
            k.add(.sphere(c: hips + V3(-1, -1.2, z), r: 7.4), 0, body, 4)
            k.add(.sphere(c: ch + V3(0.5, -0.5, z * 0.85), r: 6.2), 1, body, 4)
        }
        // Thick fluffy neck ruff
        let neckA = ch + V3(3, 3.5, 0), neckB = H + V3(-3, -4, 0)
        let neckM = (neckA + neckB) / 2
        k.add(.cone(a: neckA, b: neckM, ra: 7.6, rb: 7.2), 1, ruff, 4)
        k.add(.cone(a: neckM, b: neckB, ra: 7.2, rb: 6.6), 2, ruff, 3)
        k.add(.ellipsoid(c: neckM + V3(1.5, -1.5, 0), r: V3(7.4, 8.4, 9.4)), 1, ruff, 4)
        // Fox-like head: round skull, fluffy cheeks, tapered muzzle
        k.add(.sphere(c: H, r: 9.2), 2, head, 3, squash: (V3(0, 0, 1), 0.95, H))
        k.add(.ellipsoid(c: H + V3(2.5, 2.2, 0), r: V3(6.5, 5, 6.5)), 2, head, 4)
        for z in [Float(5.4), -5.4] {
            k.add(.sphere(c: H + V3(1.2, -3.8, z), r: 5.2), 2, cheek, 4)
        }
        k.add(.cone(a: H + V3(5, -3.0, 0), b: H + V3(11.8, -3.9, 0), ra: 4.2, rb: 2.6), 2, muzzle, 3)
        k.add(.sphere(c: H + V3(7.4, -6.0, 0), r: 2.4), 2, muzzle, 2.5)
        // Upright, pointed ears
        for (bone, side) in [(3, Float(1)), (4, Float(-1))] {
            let e = P[bone]
            k.add(.cone(a: e, b: e + V3(-1.2, 8.6, side * 1.4), ra: 4.1, rb: 0.5), bone, ear, 2, squash: (V3(1, 0, 0), 2.2, e))
        }
        // Big fluffy plume tail
        let tailPts = (0..<s.tailCount).map { P[s.tail0 + $0] } + [tip]
        let radii: [Float] = [3.3, 4.2, 4.6, 4.5, 4.0, 3.2, 2.0]
        for i in 0..<s.tailCount {
            k.add(.cone(a: tailPts[i], b: tailPts[i + 1], ra: radii[i], rb: radii[i + 1]), s.tail0 + i,
                  i == s.tailCount - 1 ? tailTip : tail, i == 0 ? 3 : 2.2)
        }
        for l in 0..<4 {
            let u = P[s.leg(l, 0)], lo = P[s.leg(l, 1)], w = P[s.leg(l, 2)]
            let hind = l >= 2
            k.add(.cone(a: u + V3(0, 1.5, 0), b: lo, ra: hind ? 5.6 : 4.2, rb: 3.3), s.leg(l, 0), leg, 3.5)
            k.add(.cone(a: lo, b: w, ra: 3.2, rb: 2.9), s.leg(l, 1), leg, 1.5)
            k.add(.ellipsoid(c: w + V3(1.5, -0.4, 0), r: V3(3.9, 2.4, 3.3)), s.leg(l, 2), paw, 1.5)
        }

        let dark = V3(0.2, 0.21, 0.24), grey = V3(0.46, 0.48, 0.52), white = V3(0.97, 0.97, 0.98), inner = V3(0.95, 0.85, 0.85)
        let bodyY = s.bodyY
        let earL = P[3], earR = P[4]
        let tail0 = P[s.tail0]
        let legTop = bodyY - 3
        return SDFBody(prims: k.prims, boneCount: s.boneCount) { p, region in
            switch region {
            case body:
                let c = mix(white, grey, ss(bodyY - 5, bodyY - 1, p.y))
                return mix(c, dark, ss(bodyY + 1, bodyY + 6, p.y))
            case belly, chest: return white
            case ruff:
                let front = ss(neckM.x - 2, neckM.x + 3, p.x) * ss(H.y - 1, H.y - 6, p.y)
                let c = mix(grey, dark, ss(neckM.y, neckM.y + 6, p.y))
                return mix(c, white, max(front, ss(neckM.y - 2, neckM.y - 7, p.y)))
            case head:
                // Classic husky mask: dark cap, white face, widow's peak, white brows.
                var c = dark
                let front = ss(H.x + 1, H.x + 4.5, p.x) * ss(H.y + 3.4, H.y + 0.8, p.y)
                c = mix(c, white, max(front, ss(H.y - 1, H.y - 3.5, p.y)))
                let peak = ss(1.7, 0.8, abs(p.z)) * ss(H.y - 0.5, H.y + 1.5, p.y) * ss(H.x + 2, H.x + 4, p.x)
                c = mix(c, dark, peak)
                for z in [Float(3.5), -3.5] {
                    c = mix(c, white, ss(2.0, 1.2, simd_length(p - (H + V3(6.2, 4.6, z)))))
                }
                return c
            case cheek: return mix(white, grey, ss(H.y + 0.5, H.y + 3, p.y) * ss(H.x + 1, H.x - 3, p.x))
            case muzzle:
                let bridge = ss(H.y - 2.2, H.y - 0.8, p.y) * ss(1.3, 0.5, abs(p.z)) * ss(H.x + 6, H.x + 8, p.x)
                return mix(white, grey, bridge * 0.7)
            case ear:
                let e = p.z > 0 ? earL : earR
                let side: Float = p.z > 0 ? 1 : -1
                let along = (p.y - e.y) / 8.6
                let centerZ = e.z + side * 1.4 * along
                let isInner = p.x > e.x - 0.1 && abs(p.z - centerZ) < 2.4 * (1 - along) && along > 0.06 && along < 0.82
                return isInner ? inner : dark
            case tail:
                let under = ss(tail0.y + 4, tail0.y - 1, p.y)
                return mix(mix(grey, dark, 0.55), white, under)
            case tailTip: return mix(grey, white, 0.35)
            case leg: return mix(white, grey, ss(legTop - 5, legTop + 1, p.y) * 0.8)
            case paw: return white
            default: return dark
            }
        }
    }
}
