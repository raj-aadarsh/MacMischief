import AppKit
import SceneKit
import simd

/// Procedurally painted, realistic autumn leaves packed into one texture atlas
/// (4x4 cells), plus curved 3D leaf meshes that map into the atlas.
enum LeafArt {
    static let cells = 4
    static let cellSize = 256
    static let variants = cells * cells
    static let bends = 3

    enum Shape: Sendable { case maple, oak, elm, birch }

    struct Palette: Sendable {
        var a: V3, b: V3, vein: V3, edge: V3
        var green: V3? = nil
        var radialMix = false
    }

    static func c(_ r: Float, _ g: Float, _ b: Float) -> V3 { V3(r, g, b) }

    /// The 16 leaf variants (shape + colouring).
    static let catalog: [(Shape, Palette)] = {
        let red = Palette(a: c(0.70, 0.10, 0.07), b: c(0.84, 0.22, 0.08), vein: c(0.93, 0.47, 0.22), edge: c(0.36, 0.09, 0.05))
        let scarlet = Palette(a: c(0.86, 0.30, 0.06), b: c(0.95, 0.48, 0.10), vein: c(1.0, 0.72, 0.32), edge: c(0.44, 0.17, 0.06))
        let golden = Palette(a: c(0.92, 0.66, 0.12), b: c(0.98, 0.80, 0.25), vein: c(1.0, 0.9, 0.55), edge: c(0.55, 0.35, 0.10),
                             green: c(0.6, 0.64, 0.18))
        let redYellow = Palette(a: c(0.95, 0.72, 0.15), b: c(0.80, 0.14, 0.07), vein: c(1.0, 0.82, 0.4), edge: c(0.42, 0.12, 0.05),
                                radialMix: true)
        let brown = Palette(a: c(0.46, 0.28, 0.13), b: c(0.60, 0.40, 0.19), vein: c(0.34, 0.19, 0.08), edge: c(0.24, 0.13, 0.06))
        let russet = Palette(a: c(0.62, 0.26, 0.10), b: c(0.73, 0.38, 0.14), vein: c(0.82, 0.54, 0.26), edge: c(0.30, 0.12, 0.05))
        let orangeBrown = Palette(a: c(0.78, 0.45, 0.15), b: c(0.64, 0.35, 0.12), vein: c(0.88, 0.62, 0.30), edge: c(0.32, 0.17, 0.06))
        let tan = Palette(a: c(0.70, 0.55, 0.32), b: c(0.58, 0.43, 0.24), vein: c(0.48, 0.34, 0.18), edge: c(0.32, 0.22, 0.12))
        let yellow = Palette(a: c(0.95, 0.78, 0.20), b: c(0.90, 0.68, 0.15), vein: c(1.0, 0.92, 0.6), edge: c(0.55, 0.40, 0.12),
                             green: c(0.66, 0.70, 0.2))
        let yellowGreen = Palette(a: c(0.84, 0.78, 0.22), b: c(0.62, 0.68, 0.2), vein: c(0.95, 0.92, 0.55), edge: c(0.48, 0.40, 0.14),
                                  green: c(0.42, 0.55, 0.16))
        let orange = Palette(a: c(0.90, 0.48, 0.10), b: c(0.96, 0.62, 0.18), vein: c(1.0, 0.8, 0.4), edge: c(0.45, 0.2, 0.06))
        let crimson = Palette(a: c(0.48, 0.05, 0.07), b: c(0.62, 0.10, 0.10), vein: c(0.78, 0.26, 0.16), edge: c(0.24, 0.04, 0.04))
        return [
            (.maple, red), (.maple, scarlet), (.maple, golden), (.maple, redYellow),
            (.oak, brown), (.oak, russet), (.oak, orangeBrown), (.oak, tan),
            (.elm, yellow), (.elm, yellowGreen), (.elm, orange),
            (.birch, golden), (.birch, yellow), (.birch, orange),
            (.maple, crimson), (.elm, brown),
        ]
    }()

    // MARK: - Noise

    struct Noise: Sendable {
        let seed: UInt32
        func hash(_ x: Int32, _ y: Int32) -> Float {
            var h = UInt32(bitPattern: x) &* 374_761_393 &+ UInt32(bitPattern: y) &* 668_265_263 &+ seed &* 2_246_822_519
            h = (h ^ (h >> 13)) &* 1_274_126_177
            h ^= h >> 16
            return Float(h & 0xFFFFFF) / Float(0xFFFFFF)
        }
        func value(_ x: Float, _ y: Float) -> Float {
            let xi = Int32(floor(x)), yi = Int32(floor(y))
            let fx = x - floor(x), fy = y - floor(y)
            let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
            let a = hash(xi, yi), b = hash(xi + 1, yi), c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1)
            return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
        }
        func fbm(_ x: Float, _ y: Float, octaves: Int = 4) -> Float {
            var sum: Float = 0, amp: Float = 0.5, f: Float = 1, norm: Float = 0
            for _ in 0..<octaves {
                sum += value(x * f, y * f) * amp
                norm += amp
                amp *= 0.5
                f *= 2.03
            }
            return sum / norm
        }
    }

    private static func ss(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }
    private static func tri(_ x: Float) -> Float {
        let f = x - floor(x)
        return f < 0.5 ? f * 2 : (1 - f) * 2
    }

    // MARK: - Shapes (unit coords, leaf tip up, stem at the bottom)

    struct Outline {
        var points: [CGPoint]
        var junction: CGPoint
        var veins: [[CGPoint]]       // polylines; first is the midrib
        var stem: [CGPoint]
    }

    static func outline(_ shape: Shape, _ rng: inout Noise, _ seed: UInt32) -> Outline {
        func pt(_ x: Float, _ y: Float) -> CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }
        let jitter = Noise(seed: seed &+ 11)
        switch shape {
        case .maple:
            let C = SIMD2<Float>(0.5, 0.45)
            // (angle, length, half-width) of each broad, pointed lobe
            let lobes: [(Float, Float, Float)] = [(0, 0.40, 0.66), (1.08, 0.36, 0.62), (-1.08, 0.36, 0.62), (2.15, 0.2, 0.5), (-2.15, 0.2, 0.5)]
            func angDiff(_ a: Float, _ b: Float) -> Float {
                var d: Float = a - b
                while d > .pi { d -= 2 * .pi }
                while d < -.pi { d += 2 * .pi }
                return d
            }
            func r(_ a: Float) -> Float {
                let base: Float = 0.13
                var v: Float = base
                for (ang, len, w) in lobes {
                    let dd: Float = abs(angDiff(a, ang))
                    let body: Float = max(0, 1 - dd / w)
                    // Convex flanks (broad lobe) narrowing to a point.
                    let lobe: Float = len * pow(body, 0.8) * (0.55 + 0.45 * pow(body, 3))
                    v = max(v, base + lobe)
                    // A big pointed tooth on each flank.
                    for side: Float in [-1, 1] {
                        let td: Float = abs(angDiff(a, ang + side * w * 0.5))
                        if td < 0.1 {
                            let spike: Float = pow(1 - td / 0.1, 1.3)
                            let toothR: Float = base + len * 0.52 * pow(max(0, 1 - (w * 0.5) / w), 0.8) + len * 0.2 * spike
                            v = max(v, toothR)
                        }
                    }
                }
                let fine: Float = (jitter.value(a * 9 + 5, 1) - 0.5) * 0.012
                return v + fine
            }
            var pts: [CGPoint] = []
            for i in 0..<1080 {
                let a = -Float.pi + 2 * .pi * Float(i) / 1080
                let rr = r(a)
                pts.append(pt(C.x + rr * sin(a), C.y + rr * cos(a)))
            }
            let J = SIMD2<Float>(0.5, C.y - 0.1)
            var veins: [[CGPoint]] = []
            for (ang, _, _) in lobes {
                let tip = C + SIMD2(sin(ang), cos(ang)) * (r(ang) - 0.03)
                var line: [CGPoint] = []
                for k in 0...12 {
                    let t = Float(k) / 12
                    let p = J + (tip - J) * t + SIMD2(0.01 * sin(t * .pi), 0)
                    line.append(pt(p.x, p.y))
                }
                veins.append(line)
                // side veins toward the teeth
                for f in [Float(0.38), 0.62] {
                    let base = J + (tip - J) * f
                    for side in [Float(-1), 1] {
                        let dir = simd_normalize(tip - J)
                        let perp = SIMD2(-dir.y, dir.x) * side
                        let end = base + (dir * 0.5 + perp) * (0.11 * (1 - f * 0.5))
                        veins.append([pt(base.x, base.y), pt((base.x + end.x) / 2 + perp.x * 0.01, (base.y + end.y) / 2 + perp.y * 0.01), pt(end.x, end.y)])
                    }
                }
            }
            return Outline(points: pts, junction: pt(J.x, J.y), veins: veins,
                           stem: [pt(J.x, J.y + 0.02), pt(J.x + 0.01, J.y - 0.12), pt(J.x - 0.005, 0.05)])

        case .oak, .elm, .birch:
            let y0: Float = 0.16, y1: Float = 0.95
            func halfWidth(_ t: Float, _ side: Float) -> Float {
                switch shape {
                case .oak:
                    let env = pow(sin(.pi * pow(t, 0.85)), 0.85)
                    let phase: Float = side > 0 ? 0.15 : 0.23
                    return 0.31 * env * (0.5 + 0.5 * pow(abs(sin(.pi * (t * 4.2 + phase))), 0.7))
                case .elm:
                    var w = 0.27 * pow(sin(.pi * pow(t, 0.7)), 0.8)
                    if side < 0 && t < 0.18 { w *= 0.8 }
                    let k = t * 40 + jitter.value(t * 12, side) * 0.35
                    let saw = k - floor(k)
                    return w * (1 + 0.035 * pow(saw, 1.6) * min(1, t * 6))
                default:
                    let base: Float = t < 0.3 ? pow(sin(t / 0.3 * .pi / 2), 0.6) : pow((1 - t) / 0.7, 0.85)
                    let k = t * 36 + jitter.value(t * 10, side + 3) * 0.35
                    let saw = k - floor(k)
                    return 0.33 * base * (1 + 0.032 * pow(saw, 1.5) * min(1, t * 5))
                }
            }
            func mid(_ t: Float) -> Float { 0.5 + 0.015 * sin(.pi * t) }
            var right: [CGPoint] = [], left: [CGPoint] = []
            for i in 0...300 {
                let t = Float(i) / 300
                let y = y0 + (y1 - y0) * t
                right.append(pt(mid(t) + halfWidth(t, 1), y))
                left.append(pt(mid(t) - halfWidth(t, -1), y))
            }
            let pts = right + left.reversed()
            var midrib: [CGPoint] = []
            for i in 0...20 {
                let t = Float(i) / 20
                midrib.append(pt(mid(t), y0 + (y1 - y0) * t * 0.97))
            }
            var veins = [midrib]
            let pairs = shape == .oak ? 4 : (shape == .elm ? 9 : 6)
            for k in 0..<pairs {
                let t: Float = shape == .oak ? ((Float(k) + 0.5) - 0.15) / 4.2 : 0.1 + 0.8 * Float(k) / Float(pairs)
                for side in [Float(-1), 1] {
                    let tEnd = min(0.98, t + (shape == .oak ? 0.03 : 0.07))
                    let w = halfWidth(tEnd, side) * 0.92
                    let a = pt(mid(t), y0 + (y1 - y0) * t)
                    let b = pt(mid(tEnd) + side * w, y0 + (y1 - y0) * tEnd)
                    let m = pt((Float(a.x) + Float(b.x)) / 2, (Float(a.y) + Float(b.y)) / 2 + 0.012)
                    veins.append([a, m, b])
                }
            }
            return Outline(points: pts, junction: pt(mid(0), y0), veins: veins,
                           stem: [pt(mid(0), y0 + 0.02), pt(mid(0) + 0.01, y0 - 0.06), pt(mid(0) - 0.004, 0.04)])
        }
    }

    // MARK: - Painting

    /// Paints one leaf into an RGBA (premultiplied) buffer of cellSize².
    static func paint(_ shape: Shape, _ pal: Palette, seed: UInt32) -> [UInt8] {
        let N = cellSize
        var rng = Noise(seed: seed)
        let o = outline(shape, &rng, seed)

        func gray(_ draw: (CGContext) -> Void) -> [Float] {
            var buf = [UInt8](repeating: 0, count: N * N)
            buf.withUnsafeMutableBytes { raw in
                let ctx = CGContext(data: raw.baseAddress, width: N, height: N, bitsPerComponent: 8, bytesPerRow: N,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
                ctx.scaleBy(x: CGFloat(N), y: CGFloat(N))
                ctx.setShouldAntialias(true)
                draw(ctx)
            }
            return buf.map { Float($0) / 255 }
        }
        let mask = gray { ctx in
            ctx.addLines(between: o.points)
            ctx.closePath()
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fillPath()
        }
        let stem = gray { ctx in
            ctx.addLines(between: o.stem)
            ctx.setStrokeColor(gray: 1, alpha: 1)
            ctx.setLineWidth(0.016)
            ctx.setLineCap(.round)
            ctx.strokePath()
        }
        let veins = gray { ctx in
            ctx.setStrokeColor(gray: 1, alpha: 1)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for (i, v) in o.veins.enumerated() {
                // Taper: draw segments with decreasing width.
                let base: CGFloat = i == 0 ? 0.011 : (shape == .maple && i % 5 == 0 ? 0.008 : 0.0045)
                for k in 0..<(v.count - 1) {
                    let t = CGFloat(k) / CGFloat(max(1, v.count - 1))
                    ctx.setLineWidth(base * (1 - t * 0.7))
                    ctx.move(to: v[k])
                    ctx.addLine(to: v[k + 1])
                    ctx.strokePath()
                }
            }
        }
        let edgeField = blur(mask, N, radius: 6, passes: 2)
        let veinGlow = blur(veins, N, radius: 4, passes: 2)

        // Random tar spots and insect-bite holes.
        var spots: [(SIMD2<Float>, Float)] = []
        var holes: [(SIMD2<Float>, Float)] = []
        let spotCount = shape == .maple && rng.hash(1, 1) < 0.45 ? Int(1 + rng.hash(1, 2) * 4) : 0
        for i in 0..<spotCount {
            spots.append((SIMD2(0.3 + 0.4 * rng.hash(Int32(i), 7), 0.35 + 0.45 * rng.hash(Int32(i), 9)), 0.005 + 0.007 * rng.hash(Int32(i), 13)))
        }
        if rng.hash(3, 3) < 0.35 {
            for i in 0..<Int(1 + rng.hash(4, 4) * 2) {
                holes.append((SIMD2(0.3 + 0.4 * rng.hash(Int32(i), 21), 0.35 + 0.45 * rng.hash(Int32(i), 23)), 0.006 + 0.01 * rng.hash(Int32(i), 29)))
            }
        }
        let edgeAmount: Float = 0.45 + 0.45 * rng.hash(8, 8)
        let J = SIMD2<Float>(Float(o.junction.x), Float(o.junction.y))

        var out = [UInt8](repeating: 0, count: N * N * 4)
        for row in 0..<N {
            for col in 0..<N {
                let i = row * N + col
                let u = (Float(col) + 0.5) / Float(N)
                let v = 1 - (Float(row) + 0.5) / Float(N)
                let m = max(mask[i], stem[i])
                guard m > 0.003 else { continue }
                let p = SIMD2(u, v)
                let radial = min(1, simd_length(p - J) / 0.5)
                let n = rng.fbm(u * 5 + 3, v * 5 + 1)
                let n2 = rng.fbm(u * 22 + 7, v * 22 + 3, octaves: 3)
                var col3: V3
                if pal.radialMix {
                    col3 = pal.a + (pal.b - pal.a) * ss(0.25, 0.9, radial * 0.85 + (n - 0.5) * 0.6)
                } else {
                    col3 = pal.a + (pal.b - pal.a) * ss(0.25, 0.75, n * 0.8 + radial * 0.35)
                }
                col3 *= 0.9 + 0.2 * n2
                if let g = pal.green {
                    col3 = col3 + (g - col3) * min(1, veinGlow[i] * 1.6) * 0.55 * (1 - radial * 0.6)
                }
                col3 = col3 + (pal.vein - col3) * min(1, veins[i]) * 0.55
                let blotch = ss(0.64, 0.8, rng.fbm(u * 3.5 + Float(seed % 97), v * 3.5 + 9))
                col3 = col3 + (pal.edge * 1.25 - col3) * blotch * 0.5
                let edgeF = 1 - ss(0.5, 0.9, edgeField[i])
                col3 = col3 + (pal.edge - col3) * edgeF * edgeAmount
                for (c, r) in spots {
                    // Irregular edge so spots don't look like perfect dots.
                    let d = simd_length(p - c) * (0.8 + 0.4 * rng.value(u * 90, v * 90))
                    col3 = col3 + (V3(0.88, 0.7, 0.3) - col3) * ss(r * 2.4, r, d) * 0.28
                    col3 = col3 + (V3(0.2, 0.11, 0.06) - col3) * ss(r, r * 0.5, d) * 0.85
                }
                // Fine surface grain + faint network of tiny veins.
                let grain = rng.fbm(u * 70 + 11, v * 70 + 5, octaves: 2)
                col3 *= 0.94 + 0.12 * grain
                let ridge = 1 - abs(2 * rng.fbm(u * 34 + 3, v * 34 + 8, octaves: 2) - 1)
                col3 = col3 + (pal.vein - col3) * pow(ridge, 10) * 0.12
                // Thin darker margin right at the leaf edge.
                let margin = ss(0.62, 0.45, edgeField[i]) * ss(0.2, 0.4, edgeField[i])
                col3 *= 1 - margin * 0.25
                // Real leaves are a touch less saturated than paint.
                let lum = simd_dot(col3, V3(0.3, 0.59, 0.11))
                col3 = col3 + (V3(repeating: lum) - col3) * 0.1
                var alpha = mask[i]
                if stem[i] > mask[i] {
                    col3 = pal.edge * 0.9 + V3(0.05, 0.03, 0.01)
                    alpha = stem[i]
                }
                for (c, r) in holes { alpha *= ss(r * 0.7, r, simd_length(p - c)) }
                col3 = simd_clamp(col3, V3(repeating: 0), V3(repeating: 1))
                out[i * 4 + 0] = UInt8(col3.x * alpha * 255)
                out[i * 4 + 1] = UInt8(col3.y * alpha * 255)
                out[i * 4 + 2] = UInt8(col3.z * alpha * 255)
                out[i * 4 + 3] = UInt8(alpha * 255)
            }
        }
        return out
    }

    static func blur(_ src: [Float], _ n: Int, radius: Int, passes: Int) -> [Float] {
        var a = src, b = src
        for _ in 0..<passes {
            for y in 0..<n {
                var acc: Float = 0
                for x in -radius...radius { acc += a[y * n + max(0, min(n - 1, x))] }
                for x in 0..<n {
                    b[y * n + x] = acc / Float(2 * radius + 1)
                    acc += a[y * n + min(n - 1, x + radius + 1)] - a[y * n + max(0, x - radius)]
                }
            }
            for x in 0..<n {
                var acc: Float = 0
                for y in -radius...radius { acc += b[max(0, min(n - 1, y)) * n + x] }
                for y in 0..<n {
                    a[y * n + x] = acc / Float(2 * radius + 1)
                    acc += b[min(n - 1, y + radius + 1) * n + x] - b[max(0, y - radius) * n + x]
                }
            }
        }
        return a
    }

    /// Builds the full 4x4 atlas (painted in parallel).
    static func makeAtlas() -> CGImage {
        let N = cellSize, W = N * cells
        var cellsData = [[UInt8]](repeating: [], count: variants)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: variants) { k in
            let (shape, pal) = catalog[k]
            let data = paint(shape, pal, seed: UInt32(k * 7919 + 17))
            lock.lock()
            cellsData[k] = data
            lock.unlock()
        }
        var atlas = [UInt8](repeating: 0, count: W * W * 4)
        for k in 0..<variants {
            let cx = k % cells, cy = k / cells
            let data = cellsData[k]
            for row in 0..<N {
                let dst = ((cy * N + row) * W + cx * N) * 4
                atlas.replaceSubrange(dst..<(dst + N * 4), with: data[(row * N * 4)..<((row + 1) * N * 4)])
            }
        }
        let provider = CGDataProvider(data: Data(atlas) as CFData)!
        return CGImage(width: W, height: W, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }

    // MARK: - Meshes

    /// A unit-size, gently curled, two-sided leaf mesh (front + paler back).
    struct Mesh: Sendable {
        var positions: [V3] = []
        var normals: [V3] = []
        var uvs: [SIMD2<Float>] = []
        var front: [UInt32] = []
        var back: [UInt32] = []
    }

    static func mesh(variant: Int, bend: Int) -> Mesh {
        let curls: [(Float, Float, Float)] = [(0.22, 0.12, 0.06), (0.32, -0.06, -0.1), (0.12, 0.22, 0.02)]
        let (curl, along, twist) = curls[bend % curls.count]
        let g = 8
        var m = Mesh()
        let cx = Float(variant % cells), cy = Float(variant / cells)
        func z(_ x: Float, _ y: Float) -> Float { curl * x * x * 1.6 + along * y * y + twist * x * y }
        for side in 0..<2 {
            for j in 0...g {
                for i in 0...g {
                    let s = Float(i) / Float(g), t = Float(j) / Float(g)
                    let x = s - 0.5, y = t - 0.5
                    let p = V3(x, y, z(x, y))
                    var n = simd_normalize(V3(-(curl * 3.2 * x + twist * y), -(2 * along * y + twist * x), 1))
                    if side == 1 { n = -n }
                    m.positions.append(p)
                    m.normals.append(n)
                    // Inset the UVs a hair so mipmaps don't bleed between cells.
                    let us = 0.004 + s * 0.992, ts = 0.004 + t * 0.992
                    m.uvs.append(SIMD2((cx + us) / Float(cells), (cy + (1 - ts)) / Float(cells)))
                }
            }
        }
        let stride = UInt32(g + 1), offset = UInt32((g + 1) * (g + 1))
        for j in 0..<UInt32(g) {
            for i in 0..<UInt32(g) {
                let a = j * stride + i, b = a + 1, c = a + stride, d = c + 1
                m.front += [a, b, d, a, d, c]
                m.back += [a + offset, d + offset, b + offset, a + offset, c + offset, d + offset]
            }
        }
        return m
    }

    @MainActor static func materials(atlas: CGImage) -> [SCNMaterial] {
        func make(back: Bool) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = atlas
            m.diffuse.mipFilter = .linear
            m.diffuse.wrapS = .clamp
            m.diffuse.wrapT = .clamp
            m.diffuse.intensity = 0.8
            m.metalness.contents = 0.0
            m.roughness.contents = back ? 0.75 : 0.62
            m.clearCoat.contents = back ? 0.0 : 0.12
            m.clearCoatRoughness.contents = 0.35
            m.blendMode = .replace
            m.writesToDepthBuffer = true
            m.isDoubleSided = false
            var surface = ""
            if back {
                // Undersides are paler and duller.
                surface = """
                float3 lum = float3(dot(_surface.diffuse.rgb, float3(0.3, 0.59, 0.11)));
                _surface.diffuse.rgb = mix(_surface.diffuse.rgb, lum, 0.25) * 1.07;
                """
            }
            var mods: [SCNShaderModifierEntryPoint: String] = [
                .fragment: """
                if (_output.color.a < 0.42) { discard_fragment(); }
                _output.color.a = 1.0;
                """,
            ]
            if !surface.isEmpty { mods[.surface] = surface }
            m.shaderModifiers = mods
            return m
        }
        return [make(back: false), make(back: true)]
    }

    @MainActor static func geometry(_ mesh: Mesh, materials: [SCNMaterial]) -> SCNGeometry {
        let pos = SCNGeometrySource(vertices: mesh.positions.map { SCNVector3($0) })
        let nor = SCNGeometrySource(normals: mesh.normals.map { SCNVector3($0) })
        let uv = SCNGeometrySource(textureCoordinates: mesh.uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
        let geo = SCNGeometry(sources: [pos, nor, uv], elements: [
            SCNGeometryElement(indices: mesh.front, primitiveType: .triangles),
            SCNGeometryElement(indices: mesh.back, primitiveType: .triangles),
        ])
        geo.materials = materials
        return geo
    }
}
