import AppKit
import SceneKit
import SpriteKit
import simd

final class LeavesMischief: Mischief {
    let id = "leaves"
    let title = "Autumn Leaves"
    let symbolName = "leaf.fill"
    let emoji = "🍁"
    let tagline = "Real leaves drift down and pile up on your windows. Swish your cursor to scatter them."
    let colors: [UInt32] = [0xE8743B, 0xA8432B]

    func makeLayer(for scene: OverlayScene) -> MischiefLayer? {
        guard let stage = scene.acquireStage3D?() ?? nil else { return nil }
        return LeafLayer(mischiefID: id, overlay: scene, stage: stage,
                         release: { [weak scene] in scene?.releaseStage3D?() })
    }
}

/// Shared textures, materials and meshes (built once, in the background).
@MainActor
final class LeafAssets {
    static private(set) var shared: LeafAssets?
    private static var waiting: [(LeafAssets) -> Void] = []
    private static var loading = false

    let materials: [SCNMaterial]
    let meshes: [[LeafArt.Mesh]]          // [variant][bend]
    let geometries: [[SCNGeometry]]

    private init(atlas: CGImage, meshes: [[LeafArt.Mesh]]) {
        let mats = LeafArt.materials(atlas: atlas)
        materials = mats
        self.meshes = meshes
        geometries = meshes.map { row in row.map { LeafArt.geometry($0, materials: mats) } }
    }

    static func load(_ done: @escaping (LeafAssets) -> Void) {
        if let shared { done(shared); return }
        waiting.append(done)
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let atlas = LeafArt.makeAtlas()
            let meshes = (0..<LeafArt.variants).map { v in (0..<LeafArt.bends).map { LeafArt.mesh(variant: v, bend: $0) } }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let assets = LeafAssets(atlas: atlas, meshes: meshes)
                    shared = assets
                    loading = false
                    waiting.forEach { $0(assets) }
                    waiting.removeAll()
                }
            }
        }
    }
}

/// Realistic 3D autumn leaves: fluttering pendulum glides and tumbles, wind
/// gusts, heaps on window tops and above the Dock, and a cursor "leaf blower".
final class LeafLayer: MischiefLayer {
    final class Leaf {
        enum State { case falling, settling, resting, decaying }
        var state: State = .falling
        var node: SCNNode?
        let variant: Int
        let bend: Int
        let size: Float
        var pos: V3
        var ext = SIMD2<Float>(0, 0)
        var phase: Float
        var omega: Float
        var amp: Float
        var fall: Float
        var rollAmp: Float
        var pitchBase: Float
        var spin: Float = 0
        var spinRate: Float
        var tumbler: Bool
        var tumbleTime: Float = 0
        var tumbleAxis: V3
        var tumbleRate: Float
        var orient: simd_quatf
        var startPos = V3.zero
        var startOrient = simd_quatf(angle: 0, axis: V3(0, 0, 1))
        var restPos = V3.zero
        var restOrient = simd_quatf(angle: 0, axis: V3(0, 0, 1))
        var settleT: Float = 0
        weak var pile: LeafPile?
        var contribution: [(Int, Float)] = []
        var baked = false
        var decay: Float = 0

        init(variant: Int, bend: Int, size: Float, pos: V3) {
            self.variant = variant
            self.bend = bend
            self.size = size
            self.pos = pos
            phase = .random(in: 0...(2 * .pi))
            omega = .random(in: 1.8...3.2)
            amp = .random(in: 18...40)
            fall = .random(in: 30...50)
            rollAmp = .random(in: 0.55...1.05)
            pitchBase = .random(in: -0.45...0.6)
            spinRate = .random(in: 0.2...0.9) * (Bool.random() ? 1 : -1)
            tumbler = Float.random(in: 0...1) < 0.35
            tumbleAxis = simd_normalize(V3(.random(in: -1...1), .random(in: -1...1), .random(in: -0.3...0.3)))
            tumbleRate = .random(in: 3...6.5) * (Bool.random() ? 1 : -1)
            orient = simd_quatf(angle: .random(in: 0...(2 * .pi)), axis: simd_normalize(V3(.random(in: -1...1), .random(in: -1...1), 1)))
        }
    }

    final class LeafPile {
        static let column: Float = 4
        let windowID: CGWindowID?
        let frame: CGRect
        let baseY: Float
        let minX: Float
        let count: Int
        let maxHeight: Float
        var heights: [Float]
        var visible: [Bool]
        var leaves: [Leaf] = []

        init(windowID: CGWindowID?, frame: CGRect, minX: CGFloat, maxX: CGFloat, baseY: CGFloat, maxHeight: Float) {
            self.windowID = windowID
            self.frame = frame
            self.minX = Float(minX)
            self.baseY = Float(baseY)
            count = max(1, Int((Float(maxX) - Float(minX)) / Self.column))
            self.maxHeight = maxHeight
            heights = Array(repeating: 0, count: count)
            visible = Array(repeating: true, count: count)
        }

        var maxX: Float { minX + Float(count) * Self.column }

        func column(at x: Float) -> Int? {
            guard x >= minX, x < maxX else { return nil }
            return min(count - 1, Int((x - minX) / Self.column))
        }

        func surface(at x: Float) -> Float? {
            guard let c = column(at: x), visible[c] else { return nil }
            var s: Float = 0, n: Float = 0
            for j in max(0, c - 1)...min(count - 1, c + 1) { s += heights[j]; n += 1 }
            return baseY + s / n
        }

        func setVisible(_ spans: [ClosedRange<CGFloat>]) -> Bool {
            var changed = false
            for i in 0..<count {
                let x = CGFloat(minX + (Float(i) + 0.5) * Self.column)
                let v = spans.contains { $0.contains(x) }
                if v != visible[i] { visible[i] = v; changed = true }
            }
            return changed
        }

        func addHeight(for leaf: Leaf) {
            guard let c = column(at: leaf.restPos.x) else { return }
            let k = max(1, Int(leaf.size * 0.45 / Self.column))
            leaf.contribution = []
            for o in -k...k {
                let j = c + o
                guard j >= 0, j < count else { continue }
                let w = 1 - Float(abs(o)) / Float(k + 1)
                let add = min(maxHeight - heights[j], 1.5 * w)
                guard add > 0 else { continue }
                heights[j] += add
                leaf.contribution.append((j, add))
            }
        }

        func removeHeight(for leaf: Leaf) {
            for (j, a) in leaf.contribution where j < count { heights[j] = max(0, heights[j] - a) }
            leaf.contribution = []
        }
    }

    private let stage: Stage3D
    private let release: () -> Void
    private let world = SCNNode()
    private let bakedNode = SCNNode()
    private var assets: LeafAssets?
    private var leaves: [Leaf] = []
    private var piles: [CGWindowID: LeafPile] = [:]
    private var floorPile: LeafPile?
    private var pileList: [LeafPile] = []
    private var restingOrder: [Leaf] = []
    private var bakeDirty = false
    private var bakeTimer: Float = 0
    private var time: Float = 0
    private var gustTimer: Float = .random(in: 6...14)
    private var gustT: Float = 0
    private var gustDur: Float = 0
    private var gustAmp: Float = 0
    private var gustKickAcc: Float = 0
    private var mouse = SIMD2<Float>(-9999, -9999)
    private var mouseVel = SIMD2<Float>(0, 0)
    private var hasMouse = false
    private var stopping = false
    private var stopTimer: Float = 0
    private var dismissal: (() -> Void)?
    private var detached = false
    private let maxResting = 320

    init(mischiefID: String, overlay: OverlayScene, stage: Stage3D, release: @escaping () -> Void) {
        self.stage = stage
        self.release = release
        super.init(mischiefID: mischiefID, overlay: overlay)
        stage.scene.rootNode.addChildNode(world)
        world.addChildNode(bakedNode)
        LeafAssets.load { [weak self] assets in
            guard let self, !self.detached else { return }
            self.assets = assets
            self.seedInitialLeaves()
            self.geometryDidChange()
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) not supported") }

    override var preferredFPS: Int { 60 }

    private var size: CGSize { overlay?.size ?? CGSize(width: 1400, height: 900) }

    // MARK: - Leaves

    private var targetCount: Int { Int(clamp(size.width * size.height / 42000, 18, 48)) }

    private func spawn(initial: Bool) {
        guard let assets else { return }
        let variant = Int.random(in: 0..<LeafArt.variants)
        let bend = Int.random(in: 0..<LeafArt.bends)
        let sizeF = Float.random(in: 25...40)
        let w = Float(size.width), h = Float(size.height)
        let y = initial ? Float.random(in: h * 0.15...(h * 1.6)) : h + .random(in: 20...120)
        let x = Float.random(in: -80...(w + 80)) - windSpeed * 1.5
        let leaf = Leaf(variant: variant, bend: bend, size: sizeF, pos: V3(x, y, .random(in: -60...60)))
        let node = SCNNode(geometry: assets.geometries[variant][bend])
        world.addChildNode(node)
        leaf.node = node
        leaves.append(leaf)
        syncNode(leaf)
    }

    private func seedInitialLeaves() {
        for _ in 0..<targetCount { spawn(initial: true) }
    }

    private func syncNode(_ leaf: Leaf) {
        guard let node = leaf.node else { return }
        node.simdPosition = leaf.pos
        node.simdOrientation = leaf.orient
        let s = leaf.state == .decaying ? leaf.size * max(0.2, 1 - leaf.decay * 0.6) : leaf.size
        node.simdScale = V3(repeating: s)
        if leaf.state == .decaying { node.opacity = CGFloat(max(0, 1 - leaf.decay)) }
    }

    private var windSpeed: Float {
        let base = 14 * sin(time * 0.06) + 8 * sin(time * 0.21 + 1.3)
        let gust = gustT < gustDur ? gustAmp * sin(.pi * gustT / gustDur) : 0
        return base + gust
    }

    // MARK: - World

    override func geometryDidChange() {
        guard assets != nil, let g = overlay?.geometry else { return }
        var seen = Set<CGWindowID>()
        for edge in g.edges {
            seen.insert(edge.windowID)
            if let pile = piles[edge.windowID] {
                if abs(pile.frame.minX - edge.frame.minX) < 0.5, abs(pile.frame.maxY - edge.frame.maxY) < 0.5,
                   abs(pile.frame.width - edge.frame.width) < 0.5 {
                    if pile.setVisible(edge.spans) { bakeDirty = true }
                    continue
                }
                knockOff(pile, push: SIMD2(Float(edge.frame.midX - pile.frame.midX), Float(edge.frame.maxY - pile.frame.maxY)))
                piles[edge.windowID] = nil
            }
            guard !stopping else { continue }
            let lo = max(edge.frame.minX, 0), hi = min(edge.frame.maxX, g.size.width)
            guard hi - lo > 24 else { continue }
            let pile = LeafPile(windowID: edge.windowID, frame: edge.frame, minX: lo, maxX: hi, baseY: edge.y, maxHeight: 16)
            _ = pile.setVisible(edge.spans)
            piles[edge.windowID] = pile
        }
        for (id, pile) in piles where !seen.contains(id) {
            knockOff(pile, push: .zero)
            piles[id] = nil
        }
        if let floor = floorPile, abs(floor.baseY - Float(g.floorY)) > 0.5 {
            knockOff(floor, push: .zero)
            floorPile = nil
        }
        if floorPile == nil && !stopping {
            floorPile = LeafPile(windowID: nil, frame: CGRect(x: 0, y: g.floorY, width: g.size.width, height: 0),
                                 minX: 0, maxX: g.size.width, baseY: g.floorY, maxHeight: 30)
        }
        if let floor = floorPile, floor.setVisible(g.floorSpans) { bakeDirty = true }
        pileList = Array(piles.values) + (floorPile.map { [$0] } ?? [])
    }

    private func knockOff(_ pile: LeafPile, push: SIMD2<Float>) {
        for leaf in pile.leaves {
            launch(leaf, velocity: SIMD2(push.x * 0.4 + .random(in: -40...40), .random(in: 20...90)))
        }
        pile.leaves.removeAll()
        bakeDirty = true
    }

    /// Turns a resting leaf back into a flying one.
    private func launch(_ leaf: Leaf, velocity: SIMD2<Float>) {
        guard let assets else { return }
        if let pile = leaf.pile {
            pile.removeHeight(for: leaf)
            pile.leaves.removeAll { $0 === leaf }
        }
        leaf.pile = nil
        restingOrder.removeAll { $0 === leaf }
        if leaf.node == nil {
            let node = SCNNode(geometry: assets.geometries[leaf.variant][leaf.bend])
            world.addChildNode(node)
            leaf.node = node
        }
        if leaf.state == .resting || leaf.state == .settling {
            leaf.pos = leaf.state == .resting ? leaf.restPos : leaf.pos
            leaf.orient = leaf.state == .resting ? leaf.restOrient : leaf.orient
        }
        leaf.baked = false
        leaf.state = .falling
        leaf.ext = velocity
        leaf.tumbler = true
        leaf.tumbleTime = .random(in: 0.8...1.8)
        leaf.tumbleRate = .random(in: 5...9) * (Bool.random() ? 1 : -1)
        leaf.tumbleAxis = simd_normalize(V3(.random(in: -1...1), .random(in: -1...1), .random(in: -0.4...0.4)))
        bakeDirty = true
        syncNode(leaf)
    }

    private func beginSettle(_ leaf: Leaf, on pile: LeafPile, surface: Float) {
        leaf.state = .settling
        leaf.settleT = 0
        leaf.pile = pile
        leaf.startPos = leaf.pos
        leaf.startOrient = leaf.orient
        let yaw = Float.random(in: 0...(2 * .pi))
        let tiltTowardViewer = Float.random(in: 0.45...1.05)
        let inPlane = Float.random(in: 0...(2 * .pi))
        let mess = Float.random(in: -0.28...0.28)
        leaf.restOrient = simd_quatf(angle: mess, axis: V3(0, 0, 1))
            * simd_quatf(angle: tiltTowardViewer, axis: V3(1, 0, 0))
            * simd_quatf(angle: yaw, axis: V3(0, 1, 0))
            * simd_quatf(angle: -.pi / 2, axis: V3(1, 0, 0))
            * simd_quatf(angle: inPlane, axis: V3(0, 0, 1))
        let x = clamp(leaf.pos.x + .random(in: -3...3), pile.minX + 2, pile.maxX - 2)
        leaf.restPos = V3(x, surface + leaf.size * Float.random(in: 0.04...0.16), .random(in: -28...28))
        pile.addHeight(for: leaf)
    }

    // MARK: - Frame

    override func update(dt: CGFloat) {
        guard let assets, let scene = overlay else { return }
        let d = Float(dt)
        time += d
        trackMouse(scene, d)
        updateGusts(d)
        let wind = windSpeed
        let w = Float(size.width)

        if !stopping {
            var spawned = 0
            while leaves.lazy.filter({ $0.state == .falling }).count < targetCount && spawned < 2 {
                spawn(initial: false)
                spawned += 1
            }
        }

        let mouseSpeed = simd_length(mouseVel)
        var i = 0
        while i < leaves.count {
            let leaf = leaves[i]
            switch leaf.state {
            case .falling:
                stepFalling(leaf, d, wind: wind, mouseSpeed: mouseSpeed, width: w)
                if leaf.pos.y < -60 {
                    leaf.node?.removeFromParentNode()
                    leaves.remove(at: i)
                    continue
                }
            case .settling:
                leaf.settleT += d / 0.45
                let t = min(1, leaf.settleT)
                let e = t * t * (3 - 2 * t)
                leaf.pos = leaf.startPos + (leaf.restPos - leaf.startPos) * e
                leaf.orient = simd_slerp(leaf.startOrient, leaf.restOrient, e)
                if t >= 1, let pile = leaf.pile {
                    leaf.state = .resting
                    leaf.pos = leaf.restPos
                    leaf.orient = leaf.restOrient
                    pile.leaves.append(leaf)
                    restingOrder.append(leaf)
                    bakeDirty = true
                }
            case .resting:
                break
            case .decaying:
                leaf.decay += d / 2
                if leaf.decay >= 1 {
                    leaf.node?.removeFromParentNode()
                    leaves.remove(at: i)
                    continue
                }
            }
            if leaf.state != .resting || !leaf.baked { syncNode(leaf) }
            i += 1
        }

        if mouseSpeed > 200 { blowRestingLeaves(mouseSpeed) }

        // Too many leaves on the ground: the oldest ones crumble away.
        while restingOrder.count > maxResting {
            let old = restingOrder.removeFirst()
            if let pile = old.pile {
                pile.removeHeight(for: old)
                pile.leaves.removeAll { $0 === old }
            }
            if old.node == nil {
                let node = SCNNode(geometry: assets.geometries[old.variant][old.bend])
                world.addChildNode(node)
                old.node = node
            }
            old.baked = false
            old.state = .decaying
            bakeDirty = true
        }

        bakeTimer += d
        if bakeDirty && bakeTimer > 0.35 {
            bake()
            bakeTimer = 0
        }

        if stopping {
            stopTimer += d
            if stopTimer > 0.2, let leaf = restingOrder.randomElement() {
                launch(leaf, velocity: SIMD2(gustAmp.sign == .minus ? -180 : 180, .random(in: 60...200)))
            }
            if leaves.isEmpty || stopTimer > 6 {
                let done = dismissal
                dismissal = nil
                done?()
            }
        }
    }

    private func stepFalling(_ leaf: Leaf, _ d: Float, wind: Float, mouseSpeed: Float, width w: Float) {
        leaf.phase += leaf.omega * d
        var vx: Float, vy: Float
        if leaf.tumbler {
            vx = wind * 0.85 + 6 * sin(leaf.phase)
            vy = -leaf.fall * 1.35
            leaf.orient = simd_normalize(leaf.orient * simd_quatf(angle: leaf.tumbleRate * d, axis: leaf.tumbleAxis))
            if leaf.tumbleTime > 0 {
                leaf.tumbleTime -= d
                if leaf.tumbleTime <= 0 { leaf.tumbler = Float.random(in: 0...1) < 0.3 }
            }
        } else {
            // Pendulum glide: swing side to side, tilting with the swing.
            let sway = leaf.amp * leaf.omega * cos(leaf.phase)
            vx = wind * 0.75 + sway
            vy = -leaf.fall * (0.75 + 0.6 * sin(leaf.phase) * sin(leaf.phase))
            leaf.spin += leaf.spinRate * d
            let roll = leaf.rollAmp * sin(leaf.phase + 0.6)
            let pitch = leaf.pitchBase + 0.35 * sin(leaf.phase * 0.5 + leaf.spin)
            let target = simd_quatf(angle: roll, axis: V3(0, 0, 1))
                * simd_quatf(angle: pitch, axis: V3(1, 0, 0))
                * simd_quatf(angle: leaf.spin, axis: V3(0, 0, 1))
            leaf.orient = simd_slerp(leaf.orient, target, min(1, d * 6))
        }

        // Cursor "leaf blower".
        if hasMouse {
            let delta = SIMD2(leaf.pos.x, leaf.pos.y) - mouse
            let dist = simd_length(delta)
            if dist < 110 {
                let f = 1 - dist / 110
                let away = dist > 0.01 ? delta / dist : SIMD2(0, 1)
                leaf.ext += away * f * f * (90 + mouseSpeed * 0.9) * d * 6
                leaf.ext += mouseVel * f * d * 2.2
                if mouseSpeed > 300 && f > 0.4 && !leaf.tumbler {
                    leaf.tumbler = true
                    leaf.tumbleTime = .random(in: 0.6...1.4)
                }
            }
        }
        leaf.ext *= exp(-d * 1.3)

        let prevY = leaf.pos.y
        leaf.pos.x += (vx + leaf.ext.x) * d
        leaf.pos.y += (vy + leaf.ext.y) * d
        if leaf.pos.x < -90 { leaf.pos.x += w + 180 } else if leaf.pos.x > w + 90 { leaf.pos.x -= w + 180 }

        guard leaf.ext.y < 40, !stopping else { return }
        let bottomPrev = prevY - leaf.size * 0.22, bottom = leaf.pos.y - leaf.size * 0.22
        var hit: (LeafPile, Float)?
        for pile in pileList {
            guard let s = pile.surface(at: leaf.pos.x), bottomPrev >= s - 1, bottom <= s else { continue }
            if hit == nil || s > hit!.1 { hit = (pile, s) }
        }
        if let (pile, s) = hit { beginSettle(leaf, on: pile, surface: s) }
    }

    private func blowRestingLeaves(_ mouseSpeed: Float) {
        var kicked = 0
        for pile in pileList where kicked < 14 {
            guard mouse.x >= pile.minX - 40, mouse.x <= pile.maxX + 40,
                  abs(mouse.y - pile.baseY) < 70 else { continue }
            for leaf in pile.leaves where kicked < 14 {
                let delta = SIMD2(leaf.restPos.x, leaf.restPos.y) - mouse
                let dist = simd_length(delta)
                guard dist < 48 else { continue }
                let away = dist > 0.01 ? delta / dist : SIMD2(0, 1)
                launch(leaf, velocity: mouseVel * 0.55 + away * 110 + SIMD2(0, .random(in: 150...320)))
                kicked += 1
            }
        }
    }

    private func updateGusts(_ d: Float) {
        if gustT < gustDur {
            gustT += d
            // Strong gusts lift a few leaves off the piles.
            let strength = abs(gustAmp * sin(.pi * gustT / gustDur))
            gustKickAcc += d * strength / 150 * 2.5
            while gustKickAcc > 1, let leaf = restingOrder.randomElement() {
                gustKickAcc -= 1
                if let pile = leaf.pile, let c = pile.column(at: leaf.restPos.x), pile.visible[c] {
                    launch(leaf, velocity: SIMD2((gustAmp > 0 ? 1 : -1) * .random(in: 60...150), .random(in: 60...170)))
                }
            }
        } else {
            gustKickAcc = 0
            gustTimer -= d
            if gustTimer <= 0 {
                gustDur = .random(in: 3.5...5.5)
                gustAmp = .random(in: 70...150) * (Bool.random() ? 1 : -1)
                gustT = 0
                gustTimer = .random(in: 12...28)
            }
        }
    }

    private func trackMouse(_ scene: OverlayScene, _ d: Float) {
        let m = scene.mouseLocation
        let p = SIMD2(Float(m.x), Float(m.y))
        if hasMouse {
            let raw = (p - mouse) / max(d, 0.001)
            mouseVel += (raw - mouseVel) * min(1, d * 12)
        }
        mouse = p
        hasMouse = true
    }

    // MARK: - Baking resting leaves into one mesh

    private func bake() {
        bakeDirty = false
        guard let assets else { return }
        var positions: [SCNVector3] = [], normals: [SCNVector3] = [], uvs: [CGPoint] = []
        var front: [UInt32] = [], back: [UInt32] = []
        positions.reserveCapacity(restingOrder.count * 162)
        for leaf in restingOrder where leaf.state == .resting {
            guard let pile = leaf.pile, let c = pile.column(at: leaf.restPos.x) else { continue }
            if !pile.visible[c] {
                // Hidden behind a window in front: don't draw it.
                leaf.node?.removeFromParentNode()
                leaf.node = nil
                leaf.baked = true
                continue
            }
            let mesh = assets.meshes[leaf.variant][leaf.bend]
            let base = UInt32(positions.count)
            let rot = simd_float3x3(leaf.restOrient)
            for k in 0..<mesh.positions.count {
                let p = rot * (mesh.positions[k] * leaf.size) + leaf.restPos
                positions.append(SCNVector3(p))
                normals.append(SCNVector3(rot * mesh.normals[k]))
                uvs.append(CGPoint(x: CGFloat(mesh.uvs[k].x), y: CGFloat(mesh.uvs[k].y)))
            }
            front += mesh.front.map { $0 + base }
            back += mesh.back.map { $0 + base }
            leaf.node?.removeFromParentNode()
            leaf.node = nil
            leaf.baked = true
        }
        guard !positions.isEmpty else {
            bakedNode.geometry = nil
            return
        }
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals),
                                        SCNGeometrySource(textureCoordinates: uvs)],
                              elements: [SCNGeometryElement(indices: front, primitiveType: .triangles),
                                         SCNGeometryElement(indices: back, primitiveType: .triangles)])
        geo.materials = assets.materials
        bakedNode.geometry = geo
    }

    var debugSummary: String {
        let states = Dictionary(grouping: leaves, by: { "\($0.state)" }).mapValues(\.count)
        let pileInfo = pileList.map { "[y=\(Int($0.baseY)) x=\(Int($0.minX))-\(Int($0.maxX)) leaves=\($0.leaves.count) maxH=\(String(format: "%.1f", $0.heights.max() ?? 0)) vis=\($0.visible.filter { $0 }.count)/\($0.count)]" }
        let bakedVerts = (bakedNode.geometry?.sources(for: .vertex).first?.vectorCount) ?? 0
        return "leaves=\(leaves.count) states=\(states) resting=\(restingOrder.count) baked=\(bakedVerts) piles=\(pileInfo.joined(separator: " "))"
    }

    // MARK: - Lifecycle

    override func dismiss(completion: @escaping () -> Void) {
        stopping = true
        dismissal = completion
        gustDur = 4.5
        gustT = 0
        gustAmp = 240 * (Bool.random() ? 1 : -1)
        if assets == nil { completion(); dismissal = nil }
    }

    override func willRemove() {
        guard !detached else { return }
        detached = true
        world.removeFromParentNode()
        release()
    }
}
