import Foundation
import simd

typealias V3 = SIMD3<Float>
typealias V4 = SIMD4<Float>

/// One sculpting primitive of a signed-distance-field body. Primitives are
/// smoothly blended together into a single seamless surface.
struct SDFPrim: Sendable {
    enum Shape: Sendable {
        case sphere(c: V3, r: Float)
        /// Capsule that tapers from radius ra at a to rb at b.
        case cone(a: V3, b: V3, ra: Float, rb: Float)
        case ellipsoid(c: V3, r: V3)
    }

    var shape: Shape
    /// Index of the skeleton bone this part follows.
    var bone: Int
    /// Paint region (decides colour).
    var region: Int
    /// Smooth-union radius: how softly it melts into the rest of the body.
    var blend: Float = 3
    /// Optional squash along an axis (e.g. to make thin ears).
    var squashAxis: V3 = .zero
    var squashFactor: Float = 1
    var squashCenter: V3 = .zero

    func distance(_ q: V3) -> Float {
        var p = q
        if squashFactor != 1 {
            let d = p - squashCenter
            p = squashCenter + d + squashAxis * (simd_dot(d, squashAxis) * (squashFactor - 1))
        }
        switch shape {
        case let .sphere(c, r):
            return simd_length(p - c) - r
        case let .ellipsoid(c, r):
            let d = p - c
            let k0 = simd_length(d / r)
            let k1 = simd_length(d / (r * r))
            return k1 > 1e-6 ? k0 * (k0 - 1) / k1 : -simd_reduce_min(r)
        case let .cone(a, b, ra, rb):
            return Self.roundCone(p, a, b, ra, rb)
        }
    }

    var bounds: (V3, V3) {
        let pad: Float = squashFactor < 1 ? 0 : 0
        switch shape {
        case let .sphere(c, r): return (c - r - pad, c + r + pad)
        case let .ellipsoid(c, r): return (c - r, c + r)
        case let .cone(a, b, ra, rb):
            let r = max(ra, rb)
            return (simd_min(a, b) - r, simd_max(a, b) + r)
        }
    }

    /// Exact SDF of a round cone (Inigo Quilez).
    static func roundCone(_ p: V3, _ a: V3, _ b: V3, _ r1: Float, _ r2: Float) -> Float {
        let ba = b - a
        let l2 = simd_dot(ba, ba)
        guard l2 > 1e-6 else { return simd_length(p - a) - r1 }
        let rr = r1 - r2
        let a2 = l2 - rr * rr
        let il2 = 1 / l2
        let pa = p - a
        let y = simd_dot(pa, ba)
        let z = y - l2
        let xv = pa * l2 - ba * y
        let x2 = simd_dot(xv, xv)
        let y2 = y * y * l2
        let z2 = z * z * l2
        let k = sgn(rr) * rr * rr * x2
        if sgn(z) * a2 * z2 > k { return sqrt(x2 + z2) * il2 - r2 }
        if sgn(y) * a2 * y2 < k { return sqrt(x2 + y2) * il2 - r1 }
        return (sqrt(x2 * a2 * il2) + y * rr) * il2 - r1
    }

    private static func sgn(_ v: Float) -> Float { v > 0 ? 1 : (v < 0 ? -1 : 0) }
}

/// Mesh ready for SceneKit, with smooth normals, painted vertex colours and
/// up-to-4 bone weights per vertex for skeletal deformation.
struct SkinnedMeshData: Sendable {
    var positions: [V3] = []
    var normals: [V3] = []
    var colors: [V4] = []
    var boneIndices: [SIMD4<UInt16>] = []
    var boneWeights: [V4] = []
    var indices: [UInt32] = []
}

struct SDFBody: Sendable {
    var prims: [SDFPrim]
    var boneCount: Int
    /// Colour for a surface point that belongs (mostly) to a given region.
    var paint: @Sendable (V3, Int) -> V3

    @inline(__always)
    func field(_ p: V3) -> Float {
        var d = prims[0].distance(p)
        for i in 1..<prims.count {
            let di = prims[i].distance(p)
            let k = prims[i].blend
            let h = max(k - abs(d - di), 0) / k
            d = min(d, di) - h * h * k * 0.25
        }
        return d
    }

    func gradient(_ p: V3, _ e: Float = 0.25) -> V3 {
        let dx = field(p + V3(e, 0, 0)) - field(p - V3(e, 0, 0))
        let dy = field(p + V3(0, e, 0)) - field(p - V3(0, e, 0))
        let dz = field(p + V3(0, 0, e)) - field(p - V3(0, 0, e))
        return V3(dx, dy, dz) / (2 * e)
    }

    /// Naive Surface Nets meshing (one vertex per surface cell, quads across
    /// sign-changing edges), then per-vertex skinning + paint.
    func mesh(cell h: Float) -> SkinnedMeshData {
        var lo = V3(repeating: .greatestFiniteMagnitude), hi = V3(repeating: -.greatestFiniteMagnitude)
        for p in prims {
            let (a, b) = p.bounds
            lo = simd_min(lo, a)
            hi = simd_max(hi, b)
        }
        lo -= 2 * h
        hi += 2 * h
        let nx = Int((hi.x - lo.x) / h) + 2, ny = Int((hi.y - lo.y) / h) + 2, nz = Int((hi.z - lo.z) / h) + 2
        let total = nx * ny * nz

        // 1. Sample the field (in parallel, one z-slice per task).
        var values = [Float](repeating: 0, count: total)
        values.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: nz) { k in
                for j in 0..<ny {
                    for i in 0..<nx {
                        let p = lo + V3(Float(i), Float(j), Float(k)) * h
                        base[i + nx * (j + ny * k)] = field(p)
                    }
                }
            }
        }
        @inline(__always) func vIdx(_ i: Int, _ j: Int, _ k: Int) -> Int { i + nx * (j + ny * k) }

        // 2. One vertex per cell that straddles the surface.
        let cx = nx - 1, cy = ny - 1, cz = nz - 1
        var cellVertex = [Int32](repeating: -1, count: cx * cy * cz)
        @inline(__always) func cIdx(_ i: Int, _ j: Int, _ k: Int) -> Int { i + cx * (j + cy * k) }
        let corners: [(Int, Int, Int)] = [(0, 0, 0), (1, 0, 0), (0, 1, 0), (1, 1, 0), (0, 0, 1), (1, 0, 1), (0, 1, 1), (1, 1, 1)]
        let edges: [(Int, Int)] = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]
        var out = SkinnedMeshData()
        for k in 0..<cz {
            for j in 0..<cy {
                for i in 0..<cx {
                    var v = [Float](repeating: 0, count: 8)
                    var inside = 0
                    for (n, c) in corners.enumerated() {
                        v[n] = values[vIdx(i + c.0, j + c.1, k + c.2)]
                        if v[n] < 0 { inside += 1 }
                    }
                    if inside == 0 || inside == 8 { continue }
                    var sum = V3.zero
                    var count: Float = 0
                    for (a, b) in edges where (v[a] < 0) != (v[b] < 0) {
                        let t = v[a] / (v[a] - v[b])
                        let pa = V3(Float(corners[a].0), Float(corners[a].1), Float(corners[a].2))
                        let pb = V3(Float(corners[b].0), Float(corners[b].1), Float(corners[b].2))
                        sum += pa + (pb - pa) * t
                        count += 1
                    }
                    let p = lo + (V3(Float(i), Float(j), Float(k)) + sum / count) * h
                    cellVertex[cIdx(i, j, k)] = Int32(out.positions.count)
                    out.positions.append(p)
                }
            }
        }

        // 3. Snap vertices onto the true surface and compute smooth normals (parallel).
        let n = out.positions.count
        var positions = out.positions
        var normals = [V3](repeating: .zero, count: n)
        positions.withUnsafeMutableBufferPointer { pos in
            normals.withUnsafeMutableBufferPointer { nor in
                let pb = pos.baseAddress!, nb = nor.baseAddress!
                DispatchQueue.concurrentPerform(iterations: max(1, n / 256 + 1)) { chunk in
                    let start = chunk * 256, end = min(n, start + 256)
                    guard start < end else { return }
                    for q in start..<end {
                        var p = pb[q]
                        for _ in 0..<2 {
                            let g = gradient(p)
                            let gl = simd_length_squared(g)
                            if gl > 1e-8 { p -= g * (field(p) / gl) }
                        }
                        pb[q] = p
                        nb[q] = simd_normalize(gradient(p))
                    }
                }
            }
        }
        out.positions = positions
        out.normals = normals

        // 4. Quads across every sign-changing grid edge.
        func quad(_ a: Int, _ b: Int, _ c: Int, _ d: Int, flip: Bool) {
            let ia = cellVertex[a], ib = cellVertex[b], ic = cellVertex[c], id = cellVertex[d]
            guard ia >= 0, ib >= 0, ic >= 0, id >= 0 else { return }
            var q = [UInt32(ia), UInt32(ib), UInt32(ic), UInt32(id)]
            if flip { q = [q[0], q[3], q[2], q[1]] }
            // Make sure the winding faces outward.
            let pa = positions[Int(q[0])], pb = positions[Int(q[1])], pc = positions[Int(q[2])]
            let fn = simd_cross(pb - pa, pc - pa)
            let avg = normals[Int(q[0])] + normals[Int(q[1])] + normals[Int(q[2])] + normals[Int(q[3])]
            if simd_dot(fn, avg) < 0 { q = [q[0], q[3], q[2], q[1]] }
            out.indices += [q[0], q[1], q[2], q[0], q[2], q[3]]
        }
        for k in 1..<cz {
            for j in 1..<cy {
                for i in 0..<cx {
                    let a = values[vIdx(i, j, k)], b = values[vIdx(i + 1, j, k)]
                    if (a < 0) != (b < 0) {
                        quad(cIdx(i, j - 1, k - 1), cIdx(i, j, k - 1), cIdx(i, j, k), cIdx(i, j - 1, k), flip: a < 0)
                    }
                }
            }
        }
        for k in 1..<cz {
            for j in 0..<cy {
                for i in 1..<cx {
                    let a = values[vIdx(i, j, k)], b = values[vIdx(i, j + 1, k)]
                    if (a < 0) != (b < 0) {
                        quad(cIdx(i - 1, j, k - 1), cIdx(i, j, k - 1), cIdx(i, j, k), cIdx(i - 1, j, k), flip: a < 0)
                    }
                }
            }
        }
        for k in 0..<cz {
            for j in 1..<cy {
                for i in 1..<cx {
                    let a = values[vIdx(i, j, k)], b = values[vIdx(i, j, k + 1)]
                    if (a < 0) != (b < 0) {
                        quad(cIdx(i - 1, j - 1, k), cIdx(i, j - 1, k), cIdx(i, j, k), cIdx(i - 1, j, k), flip: a < 0)
                    }
                }
            }
        }

        // 5. Skin weights + paint per vertex (parallel).
        var colors = [V4](repeating: .zero, count: n)
        var bIdx = [SIMD4<UInt16>](repeating: .zero, count: n)
        var bW = [V4](repeating: .zero, count: n)
        colors.withUnsafeMutableBufferPointer { col in
            bIdx.withUnsafeMutableBufferPointer { bi in
                bW.withUnsafeMutableBufferPointer { bw in
                    let cb = col.baseAddress!, ib = bi.baseAddress!, wb = bw.baseAddress!
                    DispatchQueue.concurrentPerform(iterations: max(1, n / 256 + 1)) { chunk in
                        let start = chunk * 256, end = min(n, start + 256)
                        guard start < end else { return }
                        var boneAcc = [Float](repeating: 0, count: boneCount)
                        var dist = [Float](repeating: 0, count: prims.count)
                        for q in start..<end {
                            let p = positions[q]
                            var dmin = Float.greatestFiniteMagnitude
                            for (pi, prim) in prims.enumerated() {
                                dist[pi] = prim.distance(p)
                                dmin = min(dmin, dist[pi])
                            }
                            for b in 0..<boneCount { boneAcc[b] = 0 }
                            var color = V3.zero
                            var cw: Float = 0
                            for (pi, prim) in prims.enumerated() {
                                let rel = dist[pi] - dmin
                                if rel < 6 {
                                    boneAcc[prim.bone] += exp(-rel / 1.3)
                                }
                                if rel < 2 {
                                    let w = exp(-rel / 0.35)
                                    color += paint(p, prim.region) * w
                                    cw += w
                                }
                            }
                            // Top 4 bones
                            var top: [(Int, Float)] = []
                            for b in 0..<boneCount where boneAcc[b] > 1e-4 { top.append((b, boneAcc[b])) }
                            top.sort { $0.1 > $1.1 }
                            if top.count > 4 { top.removeLast(top.count - 4) }
                            let sum = top.reduce(0) { $0 + $1.1 }
                            var ids = SIMD4<UInt16>(0, 0, 0, 0), ws = V4.zero
                            for (slot, entry) in top.enumerated() {
                                ids[slot] = UInt16(entry.0)
                                ws[slot] = entry.1 / sum
                            }
                            ib[q] = ids
                            wb[q] = ws
                            let c = color / max(cw, 1e-5)
                            // Paint is authored in sRGB; SceneKit wants linear vertex colours.
                            cb[q] = V4(pow(c.x, 2.2), pow(c.y, 2.2), pow(c.z, 2.2), 1)
                        }
                    }
                }
            }
        }
        out.colors = colors
        out.boneIndices = bIdx
        out.boneWeights = bW
        return out
    }
}
