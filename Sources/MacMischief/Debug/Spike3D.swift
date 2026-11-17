import AppKit
import SceneKit
import SpriteKit
import Metal

/// Feasibility test for the 3D pipeline: SK3DNode inside SpriteKit, PBR lighting,
/// transparency, and a procedurally skinned mesh. Run: MacMischief --spike3d <dir>
@MainActor
enum Spike3D {
    static func run(outDir: String) {
        let size = CGSize(width: 600, height: 300)
        let sk = SKScene(size: size)
        sk.anchorPoint = .zero
        sk.backgroundColor = .clear
        let bg = SKSpriteNode(color: .hex(0x3B5A86), size: CGSize(width: 300, height: 300))
        bg.anchorPoint = .zero
        sk.addChild(bg)

        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera!.usesOrthographicProjection = true
        cam.camera!.orthographicScale = 100
        cam.camera!.zNear = 1
        cam.camera!.zFar = 2000
        cam.position = SCNVector3(0, 60, 300)
        scene.rootNode.addChildNode(cam)

        let light = SCNNode()
        light.light = SCNLight()
        light.light!.type = .directional
        light.eulerAngles = SCNVector3(-0.8, -0.6, 0)
        scene.rootNode.addChildNode(light)
        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light!.type = .ambient
        amb.light!.intensity = 300
        scene.rootNode.addChildNode(amb)

        let ball = SCNNode(geometry: SCNSphere(radius: 25))
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor.systemRed
        m.metalness.contents = 0.8
        m.roughness.contents = 0.3
        ball.geometry!.materials = [m]
        ball.position = SCNVector3(-50, 40, 0)
        scene.rootNode.addChildNode(ball)

        // Skinned tube: 2 bones, the second bent 60°.
        let model = SCNNode()
        model.position = SCNVector3(30, 10, 0)
        model.eulerAngles.y = 0.4
        scene.rootNode.addChildNode(model)
        let b0 = SCNNode(); b0.position = SCNVector3(0, 0, 0)
        let b1 = SCNNode(); b1.position = SCNVector3(0, 40, 0)
        model.addChildNode(b0)
        b0.addChildNode(b1)
        var verts: [SCNVector3] = [], norms: [SCNVector3] = [], weights: [Float] = [], idx: [UInt16] = []
        var tris: [UInt32] = []
        let rings = 20, seg = 16
        for r in 0...rings {
            let y = CGFloat(r) / CGFloat(rings) * 80
            for s in 0..<seg {
                let a = CGFloat(s) / CGFloat(seg) * 2 * .pi
                verts.append(SCNVector3(cos(a) * 8, y, sin(a) * 8))
                norms.append(SCNVector3(cos(a), 0, sin(a)))
                let w1 = Float(clamp((y - 30) / 20, 0, 1))
                weights += [1 - w1, w1, 0, 0]
                idx += [0, 1, 0, 0]
            }
        }
        for r in 0..<rings {
            for s in 0..<seg {
                let a = UInt32(r * seg + s), b = UInt32(r * seg + (s + 1) % seg)
                let c = a + UInt32(seg), d = b + UInt32(seg)
                tris += [a, c, b, b, c, d]
            }
        }
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms)],
                              elements: [SCNGeometryElement(indices: tris, primitiveType: .triangles)])
        let gm = SCNMaterial()
        gm.lightingModel = .physicallyBased
        gm.diffuse.contents = NSColor.orange
        gm.roughness.contents = 0.6
        geo.materials = [gm]
        let meshNode = SCNNode(geometry: geo)
        model.addChildNode(meshNode)
        let wData = weights.withUnsafeBufferPointer { Data(buffer: $0) }
        let iData = idx.withUnsafeBufferPointer { Data(buffer: $0) }
        let wSrc = SCNGeometrySource(data: wData, semantic: .boneWeights, vectorCount: verts.count,
                                     usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4,
                                     dataOffset: 0, dataStride: 16)
        let iSrc = SCNGeometrySource(data: iData, semantic: .boneIndices, vectorCount: verts.count,
                                     usesFloatComponents: false, componentsPerVector: 4, bytesPerComponent: 2,
                                     dataOffset: 0, dataStride: 8)
        let bones = [b0, b1]
        let ib = bones.map { NSValue(scnMatrix4: SCNMatrix4Invert($0.convertTransform(SCNMatrix4Identity, to: meshNode))) }
        let skinner = SCNSkinner(baseGeometry: geo, bones: bones, boneInverseBindTransforms: ib,
                                 boneWeights: wSrc, boneIndices: iSrc)
        skinner.skeleton = model
        meshNode.skinner = skinner
        b1.eulerAngles.z = 1.0
        model.eulerAngles.z = -0.2

        scene.background.contents = NSColor(srgbRed: 0.23, green: 0.35, blue: 0.53, alpha: 1)
        light.light!.castsShadow = true
        light.light!.shadowMode = .deferred
        light.light!.shadowRadius = 6
        light.light!.shadowSampleCount = 16
        light.light!.shadowColor = NSColor(white: 0, alpha: 0.5)
        light.light!.orthographicScale = 150
        let floor = SCNNode(geometry: SCNPlane(width: 400, height: 200))
        floor.eulerAngles.x = -.pi / 2
        let fm = SCNMaterial()
        fm.lightingModel = .shadowOnly
        floor.geometry!.materials = [fm]
        scene.rootNode.addChildNode(floor)

        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = cam
        let img = renderer.snapshot(atTime: 0, with: CGSize(width: 600, height: 400), antialiasingMode: .multisampling4X)
        let url = URL(fileURLWithPath: outDir).appendingPathComponent("spike3d.png")
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        print("wrote \(url.path)")
    }
}
