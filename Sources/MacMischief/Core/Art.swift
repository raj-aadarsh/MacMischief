import AppKit
import SpriteKit

/// Draws vector art with Core Graphics into a crisp (3x) SpriteKit texture.
enum TextureFactory {
    static func make(_ size: CGSize, scale: CGFloat = 3, _ draw: (CGContext) -> Void) -> SKTexture {
        let w = Int(ceil(size.width * scale)), h = Int(ceil(size.height * scale))
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        draw(ctx)
        let texture = SKTexture(cgImage: ctx.makeImage()!)
        texture.filteringMode = .linear
        return texture
    }
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

extension SKColor {
    static func hex(_ hex: UInt32, _ alpha: CGFloat = 1) -> SKColor {
        SKColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }
}

extension CGContext {
    func paint(_ path: CGPath, fill color: CGColor) {
        saveGState()
        addPath(path)
        setFillColor(color)
        fillPath()
        restoreGState()
    }

    func paint(_ path: CGPath, stroke color: CGColor, width: CGFloat) {
        saveGState()
        addPath(path)
        setStrokeColor(color)
        setLineWidth(width)
        setLineCap(.round)
        setLineJoin(.round)
        strokePath()
        restoreGState()
    }
}

func polygon(_ points: [CGPoint]) -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: points)
    p.closeSubpath()
    return p
}

func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: x, y: y, width: w, height: h), transform: nil)
}

func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
}

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }
