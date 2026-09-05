import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let destination = CommandLine.arguments[1]
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(red: 0.09, green: 0.27, blue: 0.20, alpha: 1), CGColor(red: 0.24, green: 0.57, blue: 0.36, alpha: 1)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 1024, y: 1024), options: [])
for column in 0..<3 {
    for row in 0..<3 {
        let rect = CGRect(x: 194 + column * 220, y: 194 + row * 220, width: 196, height: 196)
        context.setFillColor(CGColor(red: 0.90, green: 1, blue: 0.88, alpha: CGFloat(0.12 + Double(column + row) * 0.14)))
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 50, cornerHeight: 50, transform: nil)); context.fillPath()
    }
}
context.setStrokeColor(CGColor(red: 1, green: 1, blue: 0.97, alpha: 1))
context.setLineWidth(43); context.setLineCap(.round); context.setLineJoin(.round)
context.move(to: CGPoint(x: 443, y: 515)); context.addLine(to: CGPoint(x: 496, y: 461)); context.addLine(to: CGPoint(x: 591, y: 571)); context.strokePath()
let image = context.makeImage()!
let output = CGImageDestinationCreateWithURL(URL(fileURLWithPath: destination) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(output, image, nil); CGImageDestinationFinalize(output)
