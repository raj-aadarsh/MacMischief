import CoreGraphics

/// The visible top edge of one window, in scene coordinates.
struct WindowEdge {
    let windowID: CGWindowID
    let frame: CGRect
    /// Horizontal ranges of the top edge that are not hidden behind windows in front.
    let spans: [ClosedRange<CGFloat>]
    var y: CGFloat { frame.maxY }
}

/// Window layout for one screen, converted into that screen's scene coordinates.
struct SceneGeometry {
    var size: CGSize
    var floorY: CGFloat
    var windows: [CGRect] = []
    var edges: [WindowEdge] = []
    var floorSpans: [ClosedRange<CGFloat>]
    var isFullScreenCovered = false

    init(size: CGSize, floorY: CGFloat) {
        self.size = size
        self.floorY = floorY
        floorSpans = [0...size.width]
    }

    init(snapshot: WindowSnapshot, screenFrame: CGRect, floorY: CGFloat) {
        self.init(size: screenFrame.size, floorY: floorY)
        let bounds = CGRect(origin: .zero, size: size)
        var ids: [CGWindowID] = []

        for w in snapshot.windows {
            let f = w.frame.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
            guard f.intersects(bounds) else { continue }
            windows.append(f)
            ids.append(w.id)
            if f.minX <= 2, f.minY <= 2, f.maxX >= size.width - 2, f.maxY >= size.height - 2 {
                isFullScreenCovered = true
            }
        }

        for (i, f) in windows.enumerated() {
            let top = f.maxY
            guard top < size.height - 6, top > floorY + 4 else { continue }
            let lo = max(f.minX, 0), hi = min(f.maxX, size.width)
            guard hi - lo > 6 else { continue }
            var spans: [ClosedRange<CGFloat>] = [lo...hi]
            // Windows in front that overlap the strip just around this top edge hide it.
            for g in windows[..<i] where g.minY < top + 8 && g.maxY > top - 1 {
                spans = Self.subtract(spans, g.minX...g.maxX)
                if spans.isEmpty { break }
            }
            edges.append(WindowEdge(windowID: ids[i], frame: f, spans: spans.filter { $0.upperBound - $0.lowerBound >= 6 }))
        }

        for g in windows where g.minY < floorY + 6 && g.maxY > floorY + 1 {
            floorSpans = Self.subtract(floorSpans, g.minX...g.maxX)
        }
    }

    static func subtract(_ spans: [ClosedRange<CGFloat>], _ cut: ClosedRange<CGFloat>) -> [ClosedRange<CGFloat>] {
        var out: [ClosedRange<CGFloat>] = []
        for s in spans {
            if cut.upperBound <= s.lowerBound || cut.lowerBound >= s.upperBound {
                out.append(s)
                continue
            }
            if cut.lowerBound > s.lowerBound { out.append(s.lowerBound...cut.lowerBound) }
            if cut.upperBound < s.upperBound { out.append(cut.upperBound...s.upperBound) }
        }
        return out
    }
}
