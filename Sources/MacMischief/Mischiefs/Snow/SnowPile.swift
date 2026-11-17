import SpriteKit

/// A height-map of snow resting on one horizontal edge (a window top or the floor).
final class SnowPile {
    static let column: CGFloat = 3

    let frame: CGRect
    let minX: CGFloat
    let maxX: CGFloat
    let baseY: CGFloat
    let count: Int
    private(set) var heights: [CGFloat]
    private(set) var visible: [Bool]
    private let limits: [CGFloat]

    let node = SKNode()
    private let fill = SKShapeNode()
    private let shade = SKShapeNode()
    private var dirty = true
    private var settle = 0

    init(frame: CGRect, minX: CGFloat, maxX: CGFloat, baseY: CGFloat, maxHeight: CGFloat, taper: Bool) {
        self.frame = frame
        self.minX = minX
        self.baseY = baseY
        let n = max(1, Int((maxX - minX) / Self.column))
        count = n
        self.maxX = minX + CGFloat(n) * Self.column
        heights = Array(repeating: 0, count: n)
        visible = Array(repeating: true, count: n)
        limits = (0..<n).map { i in
            guard taper else { return maxHeight }
            let d = (CGFloat(min(i, n - 1 - i)) + 0.5) * Self.column
            return maxHeight * pow(min(1, d / 18), 0.55)
        }

        // Fill-only shapes (no strokes) are much cheaper for SpriteKit to redraw.
        shade.fillColor = .hex(0x6F86A8, 0.55)
        shade.strokeColor = .clear
        shade.lineWidth = 0
        shade.position = CGPoint(x: 0, y: -1.4)
        shade.zPosition = 0
        fill.fillColor = .hex(0xFBFDFF)
        fill.strokeColor = .clear
        fill.lineWidth = 0
        fill.isAntialiased = true
        fill.zPosition = 0.1
        node.addChild(shade)
        node.addChild(fill)
    }

    var hasSnow: Bool { heights.contains { $0 > 0.5 } }

    func column(at x: CGFloat) -> Int? {
        guard x >= minX, x < maxX else { return nil }
        return min(count - 1, Int((x - minX) / Self.column))
    }

    func surface(_ c: Int) -> CGFloat { baseY + heights[c] }

    func setVisibleSpans(_ spans: [ClosedRange<CGFloat>]) {
        var changed = false
        for i in 0..<count {
            let x = minX + (CGFloat(i) + 0.5) * Self.column
            let v = spans.contains { $0.contains(x) }
            if v != visible[i] { visible[i] = v; changed = true }
        }
        if changed { dirty = true }
    }

    private static let kernel: [(Int, CGFloat)] = [(-2, 0.3), (-1, 0.65), (0, 1), (1, 0.65), (2, 0.3)]

    func deposit(at c: Int, amount: CGFloat) {
        for (offset, weight) in Self.kernel {
            let j = c + offset
            guard j >= 0, j < count, limits[j] > 0 else { continue }
            let fullness = heights[j] / limits[j]
            heights[j] = min(limits[j], heights[j] + amount * weight * (1 - 0.6 * fullness))
        }
        settle = 24
        dirty = true
    }

    /// Lets snow slump like a real pile, then redraws if needed.
    func step() {
        if settle > 0 {
            settle -= 1
            for i in 0..<(count - 1) {
                let d = heights[i] - heights[i + 1]
                if abs(d) > 0.8 {
                    let m = (abs(d) - 0.8) * 0.25 * (d > 0 ? 1 : -1)
                    heights[i] = max(0, heights[i] - m)
                    heights[i + 1] = max(0, min(limits[i + 1], heights[i + 1] + m))
                }
            }
            dirty = true
        }
        if dirty { rebuild() }
    }

    /// Highest snow within ±span columns of x (0 if none / hidden).
    func localMax(at x: CGFloat, span: Int = 2) -> CGFloat {
        guard let c = column(at: x) else { return 0 }
        var m: CGFloat = 0
        for j in max(0, c - span)...min(count - 1, c + span) where visible[j] { m = max(m, heights[j]) }
        return m
    }

    /// Smoothed snow surface height (absolute y) under x, or nil if not on a visible part.
    func surfaceY(at x: CGFloat) -> CGFloat? {
        guard let c = column(at: x), visible[c] else { return nil }
        var sum: CGFloat = 0, n: CGFloat = 0
        for j in max(0, c - 2)...min(count - 1, c + 2) where visible[j] {
            sum += heights[j]
            n += 1
        }
        return baseY + (n > 0 ? sum / n : heights[c])
    }

    /// Scoops snow out around x (for a growing snowball). Returns the area removed.
    func scoop(at x: CGFloat, radius: CGFloat, amount: CGFloat) -> CGFloat {
        guard let c = column(at: x), amount > 0 else { return 0 }
        let span = max(1, Int(radius / Self.column))
        var weights: [(Int, CGFloat)] = []
        var total: CGFloat = 0
        for o in -span...span {
            let j = c + o
            guard j >= 0, j < count, visible[j], heights[j] > 0.05 else { continue }
            let w = 1 - CGFloat(abs(o)) / CGFloat(span + 1)
            weights.append((j, w))
            total += w
        }
        guard total > 0 else { return 0 }
        let perUnit = amount / Self.column / total
        var removed: CGFloat = 0
        for (j, w) in weights {
            let take = min(heights[j], perUnit * w)
            heights[j] -= take
            removed += take * Self.column
        }
        settle = 24
        dirty = true
        return removed
    }

    /// Adds snow back (a splatted or melted snowball).
    func addSnow(at x: CGFloat, area: CGFloat, radius: CGFloat) {
        guard let c = column(at: x), area > 0 else { return }
        let span = max(2, Int(radius / Self.column))
        var total: CGFloat = 0
        for o in -span...span { total += 1 - CGFloat(abs(o)) / CGFloat(span + 1) }
        let perUnit = area / Self.column / total
        for o in -span...span {
            let j = c + o
            guard j >= 0, j < count, limits[j] > 0 else { continue }
            let w = 1 - CGFloat(abs(o)) / CGFloat(span + 1)
            heights[j] = min(limits[j], heights[j] + perUnit * w)
        }
        settle = 24
        dirty = true
    }

    /// Positions + sizes to turn into falling clumps when the pile is knocked off.
    func clumpSeeds() -> [(CGPoint, CGFloat)] {
        stride(from: 0, to: count, by: 3).compactMap { i in
            guard visible[i], heights[i] > 1 else { return nil }
            return (CGPoint(x: minX + (CGFloat(i) + 0.5) * Self.column, y: baseY + heights[i] * 0.5), heights[i])
        }
    }

    private func rebuild() {
        dirty = false
        let path = CGMutablePath()
        var i = 0
        while i < count {
            guard visible[i], heights[i] > 0.35 else { i += 1; continue }
            var j = i
            while j + 1 < count && visible[j + 1] && heights[j + 1] > 0.35 { j += 1 }
            addRun(to: path, from: i, to: j)
            i = j + 1
        }
        fill.path = path
        shade.path = path
    }

    private func addRun(to path: CGMutablePath, from a: Int, to b: Int) {
        let col = Self.column
        let left = minX + CGFloat(a) * col
        let right = minX + CGFloat(b + 1) * col
        var pts = [CGPoint(x: left, y: baseY + heights[a] * 0.5)]
        var k = a
        while k <= b {
            pts.append(CGPoint(x: minX + (CGFloat(k) + 0.5) * col, y: baseY + heights[k]))
            k += 2
        }
        pts.append(CGPoint(x: right, y: baseY + heights[b] * 0.5))

        path.move(to: CGPoint(x: left, y: baseY))
        path.addLine(to: pts[0])
        if pts.count > 2 {
            for n in 1..<(pts.count - 1) {
                path.addQuadCurve(to: mid(pts[n], pts[n + 1]), control: pts[n])
            }
        }
        path.addLine(to: pts[pts.count - 1])
        path.addLine(to: CGPoint(x: right, y: baseY))
        path.closeSubpath()
    }
}
