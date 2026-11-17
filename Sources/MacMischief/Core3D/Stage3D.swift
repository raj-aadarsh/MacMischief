import AppKit
@preconcurrency import Metal
import QuartzCore
import SceneKit
import simd

/// Layer-hosting view backed by a CAMetalLayer that we render into ourselves.
final class MetalStageView: NSView {
    let metalLayer = CAMetalLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = metalLayer
        wantsLayer = true
        metalLayer.isOpaque = false
        metalLayer.pixelFormat = .bgra8Unorm_srgb
        metalLayer.framebufferOnly = true
        metalLayer.maximumDrawableCount = 3
        metalLayer.backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func makeBackingLayer() -> CALayer { metalLayer }

    var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }
}

/// A transparent full-screen 3D layer under the SpriteKit overlay.
/// World units = screen points (orthographic camera). Rendering is driven
/// from the SpriteKit frame (one 3D frame per animation step, same thread),
/// which keeps motion perfectly smooth and avoids cross-thread lock contention.
@MainActor
final class Stage3D {
    let view: MetalStageView
    let scene = SCNScene()
    let camera = SCNNode()
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let renderer: SCNRenderer
    private var msaa: MTLTexture?
    private var depth: MTLTexture?
    private var running = false
    private let start = CACurrentMediaTime()
    private let sampleCount = 4
    /// Developer aid: grabs the next presented frame.
    var captureNextFrame: ((CGImage) -> Void)?

    init(size: CGSize) {
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        view = MetalStageView(frame: CGRect(origin: .zero, size: size))
        view.metalLayer.device = device
        view.autoresizingMask = [.width, .height]
        renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        Self.configure(scene: scene, camera: camera, size: size)
        renderer.pointOfView = camera
        view.isHidden = true
    }

    func setRunning(_ running: Bool) {
        self.running = running
        view.isHidden = !running
    }

    /// Renders one frame into the view (called once per SpriteKit update).
    func render() {
        guard running else { return }
        let layer = view.metalLayer
        let scale = view.backingScale
        let size = CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale)
        guard size.width >= 1, size.height >= 1 else { return }
        if layer.drawableSize != size {
            layer.drawableSize = size
            layer.contentsScale = scale
        }
        let wantCapture = captureNextFrame != nil
        layer.framebufferOnly = !wantCapture
        guard let drawable = layer.nextDrawable(),
              let cb = queue.makeCommandBuffer() else { return }
        encode(into: drawable.texture, commandBuffer: cb)
        if wantCapture, let capture = captureNextFrame {
            captureNextFrame = nil
            let tex = drawable.texture
            cb.addCompletedHandler { _ in
                let img = Stage3D.cgImage(from: tex)
                DispatchQueue.main.async { if let img { capture(img) } }
            }
        }
        cb.present(drawable)
        cb.commit()
    }

    private func encode(into target: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let w = target.width, h = target.height
        if msaa?.width != w || msaa?.height != h || msaa?.pixelFormat != target.pixelFormat {
            let cd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: target.pixelFormat, width: w, height: h, mipmapped: false)
            cd.textureType = .type2DMultisample
            cd.sampleCount = sampleCount
            cd.usage = .renderTarget
            cd.storageMode = .memoryless
            msaa = device.makeTexture(descriptor: cd)
            let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float_stencil8, width: w, height: h, mipmapped: false)
            dd.textureType = .type2DMultisample
            dd.sampleCount = sampleCount
            dd.usage = .renderTarget
            dd.storageMode = .memoryless
            depth = device.makeTexture(descriptor: dd)
        }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = msaa
        rpd.colorAttachments[0].resolveTexture = target
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .multisampleResolve
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        rpd.depthAttachment.texture = depth
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .dontCare
        rpd.depthAttachment.clearDepth = 1
        rpd.stencilAttachment.texture = depth
        rpd.stencilAttachment.loadAction = .clear
        rpd.stencilAttachment.storeAction = .dontCare
        renderer.render(atTime: CACurrentMediaTime() - start, viewport: CGRect(x: 0, y: 0, width: w, height: h),
                        commandBuffer: commandBuffer, passDescriptor: rpd)
    }

    /// Offscreen render through the exact same path (for tests/previews).
    func renderOffscreen(size: CGSize) -> CGImage? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: Int(size.width),
                                                         height: Int(size.height), mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: d), let cb = queue.makeCommandBuffer() else { return nil }
        encode(into: tex, commandBuffer: cb)
        cb.commit()
        cb.waitUntilCompleted()
        return Stage3D.cgImage(from: tex)
    }

    nonisolated static func cgImage(from tex: MTLTexture) -> CGImage? {
        let w = tex.width, h = tex.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Shared lighting/camera setup (also used by the offscreen snapshot renderer).
    static func configure(scene: SCNScene, camera: SCNNode, size: CGSize) {
        scene.background.contents = NSColor.clear
        scene.lightingEnvironment.contents = Studio.environment
        scene.lightingEnvironment.intensity = 1.35

        let cam = SCNCamera()
        cam.usesOrthographicProjection = true
        cam.orthographicScale = Double(size.height / 2)
        cam.zNear = 10
        cam.zFar = 4000
        cam.wantsHDR = false
        camera.camera = cam
        camera.position = SCNVector3(size.width / 2, size.height / 2, 1500)
        scene.rootNode.addChildNode(camera)

        func light(_ type: SCNLight.LightType, _ intensity: CGFloat, _ color: NSColor, _ euler: SCNVector3) {
            let n = SCNNode()
            n.light = SCNLight()
            n.light!.type = type
            n.light!.intensity = intensity
            n.light!.color = color
            n.eulerAngles = euler
            scene.rootNode.addChildNode(n)
        }
        // Key light: warm, from upper front-left.
        light(.directional, 1250, NSColor(srgbRed: 1, green: 0.96, blue: 0.9, alpha: 1), SCNVector3(-0.75, -0.55, 0))
        // Rim light: cool, from behind, outlines the silhouette.
        light(.directional, 900, NSColor(srgbRed: 0.8, green: 0.88, blue: 1, alpha: 1), SCNVector3(-0.35, 2.7, 0))
        // Soft fill from the right.
        light(.directional, 350, NSColor(srgbRed: 0.9, green: 0.92, blue: 1, alpha: 1), SCNVector3(-0.2, 0.9, 0))
        light(.ambient, 160, NSColor(white: 1, alpha: 1), SCNVector3(0, 0, 0))
    }
}

@MainActor
enum Studio {
    /// Procedural studio environment (equirectangular): bright sky, soft boxes,
    /// darker floor. Gives metal and glossy eyes believable reflections.
    static let environment: NSImage = {
        let w = 512, h = 256
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let g = CGGradient(colorsSpace: nil, colors: [rgb(0xF4F7FF), rgb(0xC9D6EA), rgb(0x9AA4B4), rgb(0x4A4F58), rgb(0x2A2D33)] as CFArray,
                           locations: [0, 0.35, 0.5, 0.56, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: h), end: .zero, options: [])
        // Soft boxes (bright highlights)
        for (x, y, r) in [(140.0, 200.0, 38.0), (330.0, 180.0, 28.0), (430.0, 215.0, 22.0)] {
            let sg = CGGradient(colorsSpace: nil, colors: [rgb(0xFFFFFF, 1), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(sg, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                                   endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
        }
        return NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: w, height: h))
    }()

    static let radialShadow: NSImage = {
        let s = 128
        let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let g = CGGradient(colorsSpace: nil, colors: [rgb(0x000000, 0.42), rgb(0x000000, 0.18), rgb(0x000000, 0)] as CFArray,
                           locations: [0, 0.45, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: s / 2, y: s / 2), startRadius: 0,
                               endCenter: CGPoint(x: s / 2, y: s / 2), endRadius: CGFloat(s / 2), options: [])
        return NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: s, height: s))
    }()

    static let glowImage: NSImage = {
        let s = 64
        let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let g = CGGradient(colorsSpace: nil, colors: [rgb(0xFFFFFF, 1), rgb(0xFFF1E0, 0.7), rgb(0xFFB070, 0.2), rgb(0xFF8040, 0)] as CFArray,
                           locations: [0, 0.15, 0.45, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: s / 2, y: s / 2), startRadius: 0,
                               endCenter: CGPoint(x: s / 2, y: s / 2), endRadius: CGFloat(s / 2), options: [])
        return NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: s, height: s))
    }()

    static func pbr(_ color: NSColor, metal: CGFloat = 0, rough: CGFloat = 0.6, clearCoat: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metal
        m.roughness.contents = rough
        if clearCoat > 0 {
            m.clearCoat.contents = clearCoat
            m.clearCoatRoughness.contents = 0.04
        }
        return m
    }

    /// Soft fur look: matte PBR plus a gentle light-catching fuzz on the silhouette.
    static func fur(rough: CGFloat = 0.82) -> SCNMaterial {
        let m = pbr(.white, metal: 0, rough: rough)
        m.shaderModifiers = [.surface: """
        float rim = 1.0 - saturate(dot(_surface.normal, _surface.view));
        _surface.emission.rgb += pow(rim, 3.0) * _surface.diffuse.rgb * 0.22;
        """]
        return m
    }

    static func emissive(_ color: NSColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.emission.contents = color
        return m
    }

    /// Billboard additive glow sprite (thrusters, palms).
    static func glowNode(size: CGFloat) -> SCNNode {
        let plane = SCNPlane(width: size, height: size)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = glowImage
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.constraints = [SCNBillboardConstraint()]
        n.renderingOrder = 10
        return n
    }

    static func shadowNode() -> SCNNode {
        let plane = SCNPlane(width: 1, height: 1)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = radialShadow
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = true
        m.isDoubleSided = true
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.renderingOrder = -10
        return n
    }

    /// Builds a skinned SceneKit node from mesher output.
    static func skinnedNode(_ mesh: SkinnedMeshData, bones: [SCNNode], skeleton: SCNNode, material: SCNMaterial,
                            inverseBinds: [simd_float4x4]? = nil) -> SCNNode {
        let n = mesh.positions.count
        let posData = mesh.positions.withUnsafeBufferPointer { b in
            Data(bytes: b.baseAddress!, count: n * MemoryLayout<V3>.stride)
        }
        let norData = mesh.normals.withUnsafeBufferPointer { b in
            Data(bytes: b.baseAddress!, count: n * MemoryLayout<V3>.stride)
        }
        let colData = mesh.colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let wData = mesh.boneWeights.withUnsafeBufferPointer { Data(buffer: $0) }
        let iData = mesh.boneIndices.withUnsafeBufferPointer { Data(buffer: $0) }
        let stride3 = MemoryLayout<V3>.stride
        let pos = SCNGeometrySource(data: posData, semantic: .vertex, vectorCount: n, usesFloatComponents: true,
                                    componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: stride3)
        let nor = SCNGeometrySource(data: norData, semantic: .normal, vectorCount: n, usesFloatComponents: true,
                                    componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: stride3)
        let col = SCNGeometrySource(data: colData, semantic: .color, vectorCount: n, usesFloatComponents: true,
                                    componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let element = SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)
        let geo = SCNGeometry(sources: [pos, nor, col], elements: [element])
        geo.materials = [material]
        let node = SCNNode(geometry: geo)
        skeleton.addChildNode(node)

        let wSrc = SCNGeometrySource(data: wData, semantic: .boneWeights, vectorCount: n, usesFloatComponents: true,
                                     componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let iSrc = SCNGeometrySource(data: iData, semantic: .boneIndices, vectorCount: n, usesFloatComponents: false,
                                     componentsPerVector: 4, bytesPerComponent: 2, dataOffset: 0, dataStride: 8)
        let binds: [NSValue]
        if let inverseBinds {
            binds = inverseBinds.map { NSValue(scnMatrix4: SCNMatrix4($0)) }
        } else {
            binds = bones.map { NSValue(scnMatrix4: SCNMatrix4Invert($0.convertTransform(SCNMatrix4Identity, to: node))) }
        }
        let skinner = SCNSkinner(baseGeometry: geo, bones: bones, boneInverseBindTransforms: binds,
                                 boneWeights: wSrc, boneIndices: iSrc)
        skinner.skeleton = skeleton
        node.skinner = skinner
        return node
    }
}

extension SCNVector3 {
    init(_ v: V3) { self.init(CGFloat(v.x), CGFloat(v.y), CGFloat(v.z)) }
}
