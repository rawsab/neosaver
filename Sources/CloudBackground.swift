import AppKit

// Moving cloud luminance is sampled through stationary screen-space dithering and grain.
enum CloudBackground {
    private static let motionSpeed = 1.5
    private static let brightness: Float = 0.55
    static let motionCycleDuration: TimeInterval = 480 / motionSpeed
    static func hash(_ x: Int, _ y: Int) -> Double {
        var n = UInt64(bitPattern: Int64(x &* 374761393 &+ y &* 668265263))
        n = (n ^ (n >> 13)) &* 1274126177
        return Double((n ^ (n >> 16)) & 65535) / 65535
    }
    static func noise(_ x: Double, _ y: Double) -> Double {
        let ix = Int(floor(x)), iy = Int(floor(y))
        let fx = x - floor(x), fy = y - floor(y)
        let u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy)
        let a = hash(ix, iy), b = hash(ix + 1, iy), c = hash(ix, iy + 1), d = hash(ix + 1, iy + 1)
        return (a + (b - a) * u) * (1 - v) + (c + (d - c) * u) * v
    }
    private static let textureWidth = 1600
    private static let textureHeight = 1000
    // Only undithered light is cached. Motion is sampled before the screen-space pattern.
    private static let luminance: [Float] = {
        var values = [Float](repeating: 0, count: textureWidth * textureHeight)
        for y in 0..<textureHeight {
            for x in 0..<textureWidth {
                let u = Double(x) / Double(textureWidth), v = Double(y) / Double(textureHeight)
                let variation = noise(u * 1.5 + 7.3, v * 1.2 + 1.7)
                let center = 0.94 - 0.36 * v + 0.045 * sin(v * 3.0)
                let bank = exp(-pow((u - center + (variation - 0.5) * 0.07) / 0.32, 2))
                let vignette = max(0.45, 1 - 0.48 * pow(hypot((u - 0.55) * 1.25, v - 0.48), 1.5))
                values[y * textureWidth + x] = Float(min(0.42, max(0.015,
                    (0.025 + bank * 0.34 + variation * 0.035) * vignette)))
            }
        }
        return values
    }()

    final class Renderer {
        private let light: [Float]
        private let sourceWidth: Int
        private let sourceHeight: Int
        private var width = 0, height = 0
        private var thresholds = [Float]()
        private var grain = [Float]()
        private var pixels = [UInt8]()
        private var lastFrame: Int?
        private var cachedImage: CGImage?

        init() {
            light = CloudBackground.luminance
            sourceWidth = CloudBackground.textureWidth
            sourceHeight = CloudBackground.textureHeight
        }
        // A uniform light field lets tests isolate the stationary pattern from cloud motion.
        init(light: [Float], width: Int, height: Int) {
            precondition(width > 1 && height > 1 && light.count == width * height)
            self.light = light; sourceWidth = width; sourceHeight = height
        }
        func frame(width: Int, height: Int, elapsed: TimeInterval) -> CGImage {
            precondition(width > 0 && height > 0)
            if self.width != width || self.height != height {
                self.width = width; self.height = height
                pixels = [UInt8](repeating: 255, count: width * height * 4)
                thresholds = [Float](repeating: 0, count: width * height)
                grain = thresholds
                let bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
                for y in 0..<height {
                    for x in 0..<width {
                        let index = y * width + x
                        thresholds[index] = (Float(bayer[((y / 2) % 4) * 4 + (x / 2) % 4]) + 0.5) / 16
                        grain[index] = Float((CloudBackground.hash(x + 4096, y + 8192) - 0.5) * 0.028 * 255)
                    }
                }
                lastFrame = nil
            }
            let frameNumber = Int(elapsed * 30)
            if lastFrame == frameNumber, let cachedImage { return cachedImage }
            let bounds = NSRect(x: 0, y: 0, width: width, height: height)
            let cloudRect = CloudBackground.imageRect(in: bounds,
                imageSize: NSSize(width: sourceWidth, height: sourceHeight), elapsed: elapsed)
            var columns = [Int](repeating: 0, count: width)
            var fractions = [Float](repeating: 0, count: width)
            for x in 0..<width {
                let sx = min(Double(sourceWidth - 1), max(0,
                    (Double(x) + 0.5 - cloudRect.minX) / cloudRect.width * Double(sourceWidth - 1)))
                columns[x] = min(sourceWidth - 2, Int(sx))
                fractions[x] = Float(sx - Double(columns[x]))
            }
            for y in 0..<height {
                let sy = min(Double(sourceHeight - 1), max(0,
                    (Double(y) + 0.5 - cloudRect.minY) / cloudRect.height * Double(sourceHeight - 1)))
                let y0 = min(sourceHeight - 2, Int(sy)), fy = Float(sy - Double(y0))
                let row0 = y0 * sourceWidth, row1 = row0 + sourceWidth
                for x in 0..<width {
                    let x0 = columns[x], fx = fractions[x]
                    let a = light[row0 + x0], b = light[row0 + x0 + 1]
                    let c = light[row1 + x0], d = light[row1 + x0 + 1]
                    let top = a + (b - a) * fx, bottom = c + (d - c) * fx
                    let movingLight = top + (bottom - top) * fy
                    let index = y * width + x
                    // Threshold/grain depend only on the output pixel, never the cloud offset.
                    let value = floor(movingLight * 11 + thresholds[index]) * (255 / Float(11)) + grain[index]
                    let byte = UInt8(min(255, max(0, value * CloudBackground.brightness)))
                    let pixel = index * 4
                    pixels[pixel] = byte; pixels[pixel + 1] = byte; pixels[pixel + 2] = byte
                }
            }
            let provider = CGDataProvider(data: Data(pixels) as CFData)!
            let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            lastFrame = frameNumber; cachedImage = image
            return image
        }
    }
    // Overscan covers the entire viewport throughout two slow, continuous drift cycles.
    static func imageRect(in bounds: NSRect, imageSize: NSSize, elapsed: TimeInterval) -> NSRect {
        let factor = max(bounds.width / imageSize.width, bounds.height / imageSize.height) * 1.24
        let width = imageSize.width * factor, height = imageSize.height * factor
        let motionTime = elapsed * motionSpeed
        let dx = bounds.width * 0.10 * sin(motionTime * 2 * .pi / 120)
        let dy = bounds.height * 0.075 * sin(motionTime * 2 * .pi / 160)
        return NSRect(x: bounds.midX - width / 2 + dx, y: bounds.midY - height / 2 + dy,
                      width: width, height: height)
    }
}
