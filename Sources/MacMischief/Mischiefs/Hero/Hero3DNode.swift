import AppKit
import SceneKit
import SpriteKit
import simd

/// What HeroLayer needs from Skybolt's body (2D or 3D).
@MainActor
protocol HeroBody: SKNode {
    var target: HeroPose { get set }
    var poseRate: CGFloat { get set }
    var bodyAngle: CGFloat { get set }
    var roll: CGFloat { get set }
    var facing: CGFloat { get set }
    var bootThrust: CGFloat { get set }
    var palmThrust: CGFloat { get set }
    var waving: Bool { get set }
    func lowestPoint() -> CGFloat
    func thrusters(in node: SKNode) -> [(CGPoint, CGFloat)]
    func update(dt: CGFloat)
    func detach()
}

extension HeroNode: HeroBody {
    func detach() {}
}

/// Skybolt as a real 3D armoured figure: crimson metal plates over a gunmetal
/// frame, white-hot visor band and chevron chest light, back-mounted jetpack.
final class Hero3DNode: SKNode, HeroBody {
    var target = HeroPose.hover
    private(set) var pose = HeroPose.hover
    var poseRate: CGFloat = 8
    var bodyAngle: CGFloat = 0
    var roll: CGFloat = 0
    var facing: CGFloat = 1
    var bootThrust: CGFloat = 0.5
    var palmThrust: CGFloat = 0.5
    var waving = false

    private let root = SCNNode()
    private let tiltNode = SCNNode()
    private let pitchNode = SCNNode()
    private let yawNode = SCNNode()
    private let figure = SCNNode()
    private let torsoJoint = SCNNode()
    private let neck = SCNNode()
    private var shoulders: [SCNNode] = []   // [far, near]
    private var elbows: [SCNNode] = []
    private var hips: [SCNNode] = []
    private var knees: [SCNNode] = []
    private var ankles: [SCNNode] = []
    private var soles: [SCNNode] = []
    private var bootGlows: [SCNNode] = []
    private var palmGlows: [SCNNode] = []
    private var packGlows: [SCNNode] = []
    private var contacts: [SCNNode] = []
    private var yaw: Float = -0.55
    private var t: Float = 0
    private let release: () -> Void
    private var detached = false

    private let crimson = Studio.pbr(NSColor(srgbRed: 0.6, green: 0.06, blue: 0.1, alpha: 1), metal: 0.75, rough: 0.27, clearCoat: 0.7)
    private let gunmetal = Studio.pbr(NSColor(srgbRed: 0.28, green: 0.31, blue: 0.35, alpha: 1), metal: 0.9, rough: 0.33)
    private let darkMetal = Studio.pbr(NSColor(srgbRed: 0.07, green: 0.08, blue: 0.1, alpha: 1), metal: 0.6, rough: 0.45)
    private let glow = Studio.emissive(NSColor(srgbRed: 1, green: 0.97, blue: 0.92, alpha: 1))

    init(stage: Stage3D, release: @escaping () -> Void) {
        self.release = release
        super.init()
        stage.scene.rootNode.addChildNode(root)
        root.addChildNode(tiltNode)
        tiltNode.simdEulerAngles = V3(0.1, 0, 0)
        tiltNode.addChildNode(pitchNode)
        pitchNode.addChildNode(yawNode)
        yawNode.addChildNode(figure)
        figure.simdScale = V3(repeating: 1.12)
        build()
        flattenStatics()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Construction

    /// Static armour pieces per joint; merged into one node after building.
    private var statics: [ObjectIdentifier: SCNNode] = [:]

    private func part(_ g: SCNGeometry, _ m: SCNMaterial, at p: V3, in parent: SCNNode,
                      scale: V3 = V3(1, 1, 1), rot: simd_quatf? = nil) -> SCNNode {
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.simdPosition = p
        n.simdScale = scale
        if let rot { n.simdOrientation = rot }
        let key = ObjectIdentifier(parent)
        let group = statics[key] ?? {
            let gNode = SCNNode()
            parent.addChildNode(gNode)
            statics[key] = gNode
            return gNode
        }()
        group.addChildNode(n)
        return n
    }

    /// Merge each joint's armour pieces into a single node (far fewer draw calls).
    private func flattenStatics() {
        for group in statics.values {
            guard let parent = group.parent else { continue }
            // Flatten as a detached root so no ancestor transform gets baked in.
            group.removeFromParentNode()
            let flat = group.flattenedClone()
            flat.simdTransform = matrix_identity_float4x4
            parent.addChildNode(flat)
        }
        statics.removeAll()
    }

    private func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ c: CGFloat) -> SCNBox {
        SCNBox(width: w, height: h, length: l, chamferRadius: c)
    }

    private func sphere(_ r: CGFloat) -> SCNSphere {
        let s = SCNSphere(radius: r)
        s.segmentCount = 36
        return s
    }

    private func bar(from a: V3, to b: V3, radius: CGFloat, in parent: SCNNode, material: SCNMaterial) {
        let len = simd_length(b - a)
        _ = part(SCNCapsule(capRadius: radius, height: CGFloat(len) + radius * 2), material, at: (a + b) / 2, in: parent,
                 rot: simd_quatf(from: V3(0, 1, 0), to: simd_normalize(b - a)))
    }

    private func marker(_ p: V3, in parent: SCNNode) -> SCNNode {
        let n = SCNNode()
        n.simdPosition = p
        parent.addChildNode(n)
        return n
    }

    private func build() {
        // Pelvis + belt
        _ = part(box(12, 7, 10, 2.5), gunmetal, at: V3(0.3, 1.2, 0), in: figure)
        _ = part(box(3, 3.6, 6, 1), crimson, at: V3(5.6, 2.2, 0), in: figure)

        // Legs (far = -z first, near = +z)
        for z in [Float(-3.4), 3.4] {
            let hip = SCNNode()
            hip.simdPosition = V3(0, 0, z)
            figure.addChildNode(hip)
            _ = part(sphere(3.1), darkMetal, at: .zero, in: hip)
            _ = part(SCNCapsule(capRadius: 3.3, height: 15), crimson, at: V3(0, -7.6, 0), in: hip)
            let knee = SCNNode()
            knee.simdPosition = V3(0, -16.5, 0)
            hip.addChildNode(knee)
            _ = part(sphere(2.6), darkMetal, at: .zero, in: knee)
            _ = part(sphere(2.5), gunmetal, at: V3(1.7, 0.2, 0), in: knee, scale: V3(0.75, 1, 1))
            _ = part(SCNCapsule(capRadius: 2.9, height: 14), crimson, at: V3(0, -7.4, 0), in: knee)
            _ = part(box(1.4, 9, 3.2, 0.6), gunmetal, at: V3(2.6, -6.6, 0), in: knee)
            let ankle = SCNNode()
            ankle.simdPosition = V3(0, -15.5, 0)
            knee.addChildNode(ankle)
            _ = part(box(10.5, 5, 6.2, 2), crimson, at: V3(2.6, -3.0, 0), in: ankle)
            _ = part(box(10.6, 1.3, 6.3, 0.5), darkMetal, at: V3(2.6, -5.4, 0), in: ankle)
            let g = Studio.glowNode(size: 13)
            g.simdPosition = V3(0.6, -6.4, 0)
            ankle.addChildNode(g)
            bootGlows.append(g)
            soles.append(marker(V3(0.6, -6, 0), in: ankle))
            contacts.append(marker(V3(-2.4, -6.0, 0), in: ankle))
            contacts.append(marker(V3(7.6, -5.9, 0), in: ankle))
            contacts.append(marker(V3(2.6, -1, 0), in: knee))
            hips.append(hip)
            knees.append(knee)
            ankles.append(ankle)
        }

        // Torso
        torsoJoint.simdPosition = V3(0, 4, 0)
        figure.addChildNode(torsoJoint)
        _ = part(box(10, 8, 10, 3), gunmetal, at: V3(0.5, 4.5, 0), in: torsoJoint)
        for i in 0..<3 {
            _ = part(box(1.6, 1.9, 7.2, 0.6), crimson, at: V3(5.3, 2.4 + Float(i) * 2.4, 0), in: torsoJoint)
        }
        _ = part(box(14, 12.5, 16, 5), crimson, at: V3(1.5, 15.5, 0), in: torsoJoint)
        _ = part(box(3, 7, 10, 1.4), gunmetal, at: V3(7.2, 13.2, 0), in: torsoJoint, scale: V3(0.6, 1, 1))
        // Chevron chest light
        bar(from: V3(8.6, 18.6, 2.9), to: V3(8.9, 15.2, 0), radius: 0.55, in: torsoJoint, material: glow)
        bar(from: V3(8.6, 18.6, -2.9), to: V3(8.9, 15.2, 0), radius: 0.55, in: torsoJoint, material: glow)
        // Collar ring
        _ = part(SCNTorus(ringRadius: 3.4, pipeRadius: 0.9), gunmetal, at: V3(-0.5, 23.4, 0), in: torsoJoint)
        // Jetpack with twin nozzles
        _ = part(box(6, 13, 11, 2.2), gunmetal, at: V3(-9.6, 15, 0), in: torsoJoint)
        for z in [Float(-3), 3] {
            _ = part(SCNCone(topRadius: 1.4, bottomRadius: 2.2, height: 3.4), darkMetal, at: V3(-9.6, 7.2, z), in: torsoJoint)
            _ = part(SCNCylinder(radius: 1.5, height: 0.3), glow, at: V3(-9.6, 5.4, z), in: torsoJoint)
            let g = Studio.glowNode(size: 10)
            g.simdPosition = V3(-9.6, 4.6, z)
            torsoJoint.addChildNode(g)
            packGlows.append(g)
            for y in [Float(13), 16, 19] {
                _ = part(box(0.4, 0.5, 3.4, 0.2), glow, at: V3(-12.6, y, z * 0.9), in: torsoJoint)
            }
        }

        // Helmet
        neck.simdPosition = V3(-0.5, 24, 0)
        torsoJoint.addChildNode(neck)
        _ = part(sphere(6.2), crimson, at: V3(1.0, 7.0, 0), in: neck, scale: V3(1.0, 1.12, 0.95))
        _ = part(sphere(5.4), gunmetal, at: V3(4.7, 6.2, 0), in: neck, scale: V3(0.5, 1.0, 0.82))
        _ = part(box(4.6, 3, 6, 1.4), gunmetal, at: V3(4.1, 2.4, 0), in: neck)
        _ = part(SCNCapsule(capRadius: 0.75, height: 7.4), glow, at: V3(6.85, 8.4, 0), in: neck,
                 scale: V3(0.8, 1, 1), rot: simd_quatf(angle: .pi / 2, axis: V3(1, 0, 0)))
        _ = part(box(9, 1.3, 1.6, 0.6), crimson, at: V3(1, 13.7, 0), in: neck)
        for z in [Float(-5.9), 5.9] {
            _ = part(SCNCylinder(radius: 2, height: 1.2), gunmetal, at: V3(0.3, 7, z), in: neck,
                     rot: simd_quatf(angle: .pi / 2, axis: V3(1, 0, 0)))
            _ = part(sphere(0.6), glow, at: V3(0.3, 7, z * 1.1), in: neck)
        }

        // Arms (far = -z first)
        for (i, z) in [Float(-8.3), 8.3].enumerated() {
            let shoulder = SCNNode()
            shoulder.simdPosition = V3(i == 1 ? 1.2 : -0.8, 20.5, z)
            torsoJoint.addChildNode(shoulder)
            _ = part(sphere(2.9), darkMetal, at: .zero, in: shoulder)
            _ = part(sphere(4.3), crimson, at: V3(0, 1.2, 0), in: shoulder, scale: V3(1.15, 0.85, 1.05))
            _ = part(SCNCapsule(capRadius: 2.5, height: 11.5), crimson, at: V3(0, -6, 0), in: shoulder)
            let elbow = SCNNode()
            elbow.simdPosition = V3(0, -12.2, 0)
            shoulder.addChildNode(elbow)
            _ = part(sphere(2.3), darkMetal, at: .zero, in: elbow)
            _ = part(SCNCone(topRadius: 2.4, bottomRadius: 2.9, height: 10), crimson, at: V3(0, -5.6, 0), in: elbow)
            _ = part(SCNTorus(ringRadius: 2.75, pipeRadius: 0.45), gunmetal, at: V3(0, -8.8, 0), in: elbow)
            _ = part(box(4.4, 5.2, 4.4, 1.6), gunmetal, at: V3(0, -13.4, 0), in: elbow)
            let g = Studio.glowNode(size: 11)
            g.simdPosition = V3(0, -16.4, 0)
            elbow.addChildNode(g)
            palmGlows.append(g)
            contacts.append(marker(V3(0, -16.4, 0), in: elbow))
            shoulders.append(shoulder)
            elbows.append(elbow)
        }
    }

    // MARK: - HeroBody

    func lowestPoint() -> CGFloat {
        root.simdPosition = V3(Float(position.x), Float(position.y), 0)
        let low = contacts.map { $0.simdWorldPosition.y }.min() ?? Float(position.y)
        return CGFloat(low)
    }

    func thrusters(in node: SKNode) -> [(CGPoint, CGFloat)] {
        soles.map { sole in
            let a = sole.simdWorldPosition
            let b = sole.simdConvertPosition(V3(0, -10, 0), to: nil)
            return (CGPoint(x: CGFloat(a.x), y: CGFloat(a.y)), CGFloat(atan2(b.y - a.y, b.x - a.x)))
        }
    }

    func update(dt: CGFloat) {
        let d = Float(dt)
        t += d
        pose.approach(target, 1 - exp(-dt * poseRate))
        var p = pose
        if waving { p.nE += 0.45 * sin(CGFloat(t) * 11) }

        func z(_ a: CGFloat) -> simd_quatf { simd_quatf(angle: Float(a), axis: V3(0, 0, 1)) }
        torsoJoint.simdOrientation = z(p.spine)
        neck.simdOrientation = z(p.head)
        shoulders[1].simdOrientation = z(p.nS); elbows[1].simdOrientation = z(p.nE)
        shoulders[0].simdOrientation = z(p.fS); elbows[0].simdOrientation = z(p.fE)
        hips[1].simdOrientation = z(p.nH); knees[1].simdOrientation = z(p.nK); ankles[1].simdOrientation = z(p.nF)
        hips[0].simdOrientation = z(p.fH); knees[0].simdOrientation = z(p.fK); ankles[0].simdOrientation = z(p.fF)

        // Facing: turn in 3D through the front; flight pitch follows facing.
        let yawTarget: Float = facing >= 0 ? -0.55 : -(.pi - 0.55)
        yaw += (yawTarget - yaw) * (1 - exp(-d * 9))
        let facingValue = max(-1, min(1, cos(yaw) / cos(0.55)))
        pitchNode.simdOrientation = simd_quatf(angle: Float(bodyAngle) * facingValue, axis: V3(0, 0, 1))
        yawNode.simdOrientation = simd_quatf(angle: yaw + Float(roll), axis: V3(0, 1, 0))
        root.simdPosition = V3(Float(position.x), Float(position.y), 0)

        let flicker = CGFloat(0.88 + 0.12 * sin(t * 53) * sin(t * 31))
        for g in bootGlows {
            g.opacity = min(1, bootThrust) * flicker
            g.simdScale = V3(repeating: Float(0.6 + 0.7 * bootThrust))
        }
        for g in packGlows {
            g.opacity = min(1, bootThrust * 0.9) * flicker
            g.simdScale = V3(repeating: Float(0.5 + 0.6 * bootThrust))
        }
        for g in palmGlows {
            g.opacity = min(1, palmThrust) * flicker
            g.simdScale = V3(repeating: Float(0.5 + 0.6 * palmThrust))
        }
    }

    func detach() {
        guard !detached else { return }
        detached = true
        root.removeFromParentNode()
        release()
    }

    /// For the offscreen preview renderer.
    var sceneNode: SCNNode { root }
}
