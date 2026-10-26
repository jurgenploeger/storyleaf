import SpriteKit

nonisolated struct PixelColor: Equatable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8

    static let clear = PixelColor(r: 0, g: 0, b: 0, a: 0)
    static let white = PixelColor(0xFFFFFF)

    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(_ hex: UInt32) {
        self.init(r: UInt8((hex >> 16) & 0xFF), g: UInt8((hex >> 8) & 0xFF), b: UInt8(hex & 0xFF))
    }

    func shaded(_ factor: Double) -> PixelColor {
        func scale(_ channel: UInt8) -> UInt8 { UInt8(min(255, Double(channel) * factor)) }
        return PixelColor(r: scale(r), g: scale(g), b: scale(b), a: a)
    }
}

/// A tiny pixel buffer (top-left origin, like an image editor) for drawing placeholder art.
struct PixelCanvas {
    let width: Int
    let height: Int
    private var pixels: [PixelColor]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = Array(repeating: .clear, count: width * height)
    }

    subscript(x: Int, y: Int) -> PixelColor {
        get { contains(x, y) ? pixels[y * width + x] : .clear }
        set { if contains(x, y) { pixels[y * width + x] = newValue } }
    }

    func contains(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height
    }

    mutating func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: PixelColor) {
        guard w > 0, h > 0 else { return }
        for py in y..<(y + h) {
            for px in x..<(x + w) { self[px, py] = color }
        }
    }

    mutating func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ color: PixelColor) {
        for py in 0..<height {
            for px in 0..<width {
                let dx = (Double(px) + 0.5 - cx) / rx
                let dy = (Double(py) + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1 { self[px, py] = color }
            }
        }
    }

    /// Wraps every opaque shape in a 1px outline — the classic pixel-art look.
    mutating func outline(_ color: PixelColor) {
        let source = self
        for y in 0..<height {
            for x in 0..<width where source[x, y].a == 0 {
                if source[x - 1, y].a > 0 || source[x + 1, y].a > 0 || source[x, y - 1].a > 0 || source[x, y + 1].a > 0 {
                    self[x, y] = color
                }
            }
        }
    }

    func mirrored() -> PixelCanvas {
        var copy = self
        for y in 0..<height {
            for x in 0..<width { copy[x, y] = self[width - 1 - x, y] }
        }
        return copy
    }

    func texture() -> SKTexture {
        let texture = SKTexture(cgImage: cgImage())
        texture.filteringMode = .nearest
        return texture
    }

    func cgImage() -> CGImage {
        let bytes = pixels.flatMap { [$0.r, $0.g, $0.b, $0.a] }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}

/// An image of premultiplied RGBA pixels, rows top down, that holds its own copy of them. Never
/// the image of a bitmap context drawn into memory lent to it (an array's, through a pointer): that
/// image can go on reading the context's memory, which is gone once the array is, and then shows
/// whatever moved in there (playtesting 2026-10-13: blocks of coloured garbage over a monster).
nonisolated enum PixelImage {
    static func make(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, bytes.count >= width * height * 4,
              let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// `image`'s pixels (premultiplied RGBA, rows top down), drawn into an array only while it's lent.
    static func pixels(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? bytes : nil
    }
}
