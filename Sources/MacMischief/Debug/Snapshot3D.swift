import AppKit
import Metal
import SceneKit
import simd

/// Offscreen preview of the 3D characters. Run: MacMischief --snapshot3d <dir>
@MainActor
enum Snapshot3D {
    static func renderHero(_ dir: URL) {
        let poses: [(HeroPose, CGFloat, CGFloat, CGFloat, CGFloat)] = [   // pose, bodyAngle, boot, palm, facing
            (.stand, 0, 0, 0, 1), (.hover, 0, 0.5, 0.7, 1), (.hover, -0.3, 0.6, 0.5, -1), (.flight, -.pi / 2, 1, 0.1, 1),
            (.dash, -.pi / 2 + 0.25, 1.2, 0, -1), (.landing, 0, 0, 0, 1), (.crouch, 0, 0, 0, -1), (.wave, 0, 0.5, 0.6, 1),
        ]
        let size = CGSize(width: CGFloat(poses.count) * 130 + 60, height: 200)
        let stage = Stage3D(size: size)
        stage.scene.background.contents = NSColor(srgbRed: 0.3, green: 0.42, blue: 0.6, alpha: 1)
        for (i, item) in poses.enumerated() {
            let h = Hero3DNode(stage: stage, release: {})
            h.target = item.0
            h.bodyAngle = item.1
            h.bootThrust = item.2
            h.palmThrust = item.3
            h.facing = item.4
            h.waving = item.0.nS > 2.5 && item.0.spine > 0
            h.position = CGPoint(x: 80 + CGFloat(i) * 130, y: 95)
            for _ in 0..<120 { h.update(dt: 1.0 / 60.0) }
            if item.1 == 0 && item.2 == 0 { h.position.y += 20 - h.lowestPoint(); h.update(dt: 0) }
        }
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = stage.scene
        renderer.pointOfView = stage.camera
        let img = renderer.snapshot(atTime: 0, with: CGSize(width: size.width * 2, height: size.height * 2), antialiasingMode: .multisampling4X)
        let url = dir.appendingPathComponent("hero-3d.png")
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("wrote \(url.path)")
        }
    }

    static func writePNG(_ img: CGImage?, _ url: URL) {
        guard let img else { print("no image"); return }
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)")
    }

    static func backdrop(_ stage: Stage3D, _ size: CGSize, color: NSColor) {
        let bg = SCNNode(geometry: SCNPlane(width: size.width * 2, height: size.height * 2))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        bg.geometry!.materials = [m]
        bg.position = SCNVector3(size.width / 2, size.height / 2, -800)
        stage.scene.rootNode.addChildNode(bg)
    }

    static func renderLeaves(_ dir: URL) {
        let t0 = Date()
        let atlas = LeafArt.makeAtlas()
        print("leaf atlas in \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        writePNG(atlas, dir.appendingPathComponent("leaf-atlas.png"))

        // Close-up of every variant at a few angles.
        let mats = LeafArt.materials(atlas: atlas)
        let closeSize = CGSize(width: 1300, height: 560)
        let close = Stage3D(size: closeSize)
        backdrop(close, closeSize, color: NSColor(srgbRed: 0.85, green: 0.88, blue: 0.92, alpha: 1))
        for v in 0..<LeafArt.variants {
            let geo = LeafArt.geometry(LeafArt.mesh(variant: v, bend: v % 3), materials: mats)
            let n = SCNNode(geometry: geo)
            let col = v % 8, row = v / 8
            n.simdPosition = V3(Float(90 + col * 160), Float(420 - row * 270), 0)
            n.simdScale = V3(repeating: 140)
            n.simdOrientation = simd_quatf(angle: Float(v % 4) * 0.25 - 0.3, axis: V3(0, 0, 1))
                * simd_quatf(angle: Float(v % 3) * 0.35 - 0.2, axis: V3(1, 0, 0))
                * simd_quatf(angle: Float(v % 5) * 0.2 - 0.4, axis: V3(0, 1, 0))
            close.scene.rootNode.addChildNode(n)
        }
        close.setRunning(true)
        _ = close.renderOffscreen(size: CGSize(width: 64, height: 64))
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        writePNG(close.renderOffscreen(size: CGSize(width: closeSize.width * 2, height: closeSize.height * 2)),
                 dir.appendingPathComponent("leaves-closeup.png"))

        // Full simulation on a fake desktop.
        let size = CGSize(width: 1400, height: 820)
        let stage = Stage3D(size: size)
        backdrop(stage, size, color: NSColor(srgbRed: 0.3, green: 0.4, blue: 0.55, alpha: 1))
        let windows: [(CGWindowID, CGRect)] = [
            (2, CGRect(x: 460, y: 140, width: 560, height: 300)),
            (3, CGRect(x: 920, y: 330, width: 420, height: 330)),
            (1, CGRect(x: 90, y: 230, width: 520, height: 380)),
        ]
        for (i, (_, f)) in windows.enumerated() {
            let win = SCNNode(geometry: SCNBox(width: f.width, height: f.height, length: 2, chamferRadius: 8))
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = NSColor(white: 0.95 - CGFloat(i) * 0.02, alpha: 1)
            win.geometry!.materials = [m]
            win.position = SCNVector3(f.midX, f.midY, CGFloat(-300 - i * 40))
            stage.scene.rootNode.addChildNode(win)
        }
        let scene = OverlayScene(screenFrame: CGRect(origin: .zero, size: size), floorY: 64, displayID: 0, isPrimary: true)
        scene.mouseOverride = CGPoint(x: -5000, y: -5000)
        scene.acquireStage3D = { stage }
        scene.releaseStage3D = {}
        scene.updateGeometry(snapshot: WindowSnapshot(windows: windows.map { TrackedWindow(id: $0.0, frame: $0.1) }), floorY: 64)
        guard let layer = LeavesMischief().makeLayer(for: scene) else { print("no leaf layer"); return }
        scene.addLayer(layer)
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))   // let assets load
        for _ in 0..<(60 * 45) { scene.step(1.0 / 60.0) }
        print((layer as? LeafLayer)?.debugSummary ?? "?")
        stage.setRunning(true)
        _ = stage.renderOffscreen(size: CGSize(width: 64, height: 64))
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        writePNG(stage.renderOffscreen(size: CGSize(width: size.width * 2, height: size.height * 2)),
                 dir.appendingPathComponent("leaves-desktop.png"))
    }

    static func run(outDir: String) {
        let dir = URL(fileURLWithPath: outDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let modes: [PetMode] = [.stand, .walk, .run, .sit, .sleep, .crouch, .playBow, .air, .groom, .happy, .speak, .sniff, .beg, .rollOver]
        renderHero(dir)
        renderLeaves(dir)
        for species in [PetSpecies3D.cat3D, PetSpecies3D.dog3D] {
            let t0 = Date()
            let bind = species.spec.bindPositions()
            let mesh = species.sdf(bind.bones, bind.tailTip).mesh(cell: 0.7)
            print("\(species.key): \(mesh.positions.count) verts, \(mesh.indices.count / 3) tris in \(Int(Date().timeIntervalSince(t0) * 1000)) ms")

            let size = CGSize(width: CGFloat(modes.count) * 112 + 40, height: 300)
            let scene = SCNScene()
            let cam = SCNNode()
            Stage3D.configure(scene: scene, camera: cam, size: size)
            scene.background.contents = NSColor(srgbRed: 0.3, green: 0.42, blue: 0.6, alpha: 1)
            for (row, facing) in [Float(1), -1].enumerated() {
                for (i, mode) in modes.enumerated() {
                    let rig = QuadRig3D(species: species)
                    rig.attachMesh(mesh)
                    scene.rootNode.addChildNode(rig.root)
                    let x = Float(70 + i * 112), y = Float(170 - row * 150)
                    rig.root.simdPosition = V3(x, y, 0)
                    rig.mode = mode
                    rig.facing = facing
                    rig.gaitSpeed = mode == .run ? 220 : 55
                    rig.lookTarget = V3(x + facing * 80, y + 60, 90)
                    for _ in 0..<80 { rig.update(dt: 1.0 / 60.0) }
                }
            }
            let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
            renderer.scene = scene
            renderer.pointOfView = cam
            let img = renderer.snapshot(atTime: 0, with: CGSize(width: size.width * 2, height: size.height * 2), antialiasingMode: .multisampling4X)
            let url = dir.appendingPathComponent("\(species.key)-3d.png")
            if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                print("wrote \(url.path)")
            }
        }
    }
}
