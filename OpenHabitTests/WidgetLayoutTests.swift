import XCTest
import SwiftUI
import WidgetKit
@testable import OpenHabit

final class WidgetLayoutTests: XCTestCase {
    @MainActor func testBothWidgetSizesRender() throws {
        for medium in [false, true] {
            let size = CGSize(width: medium ? 350 : 164, height: 164)
            let view = HabitWidgetContent(entry: .example, medium: medium)
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .light)
                .background(Color.black)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size, size)
            try assertVisibleRows(image, rows: medium ? 3 : 1)
            let attachment = XCTAttachment(image: image)
            attachment.name = medium ? "Three Habits widget" : "One Habit widget"
            attachment.lifetime = .keepAlways
            add(attachment)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(medium ? "medium-widget.png" : "small-widget.png")
            try image.pngData()!.write(to: url)
            print("WIDGET_RENDER: \(url.path)")
        }
    }

    // A successfully allocated image can still contain an entirely blank widget.
    private func assertVisibleRows(_ image: UIImage, rows: Int) throws {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height,
                                            bitsPerComponent: 8, bytesPerRow: width * 4,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        for row in 0..<rows {
            var colored = 0
            for y in (row * height / rows)..<((row + 1) * height / rows) {
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let channels = Array(pixels[offset..<(offset + 3)])
                    if Int(channels.max()!) - Int(channels.min()!) > 20 { colored += 1 }
                }
                let edge = y * width * 4
                XCTAssertEqual(Array(pixels[edge..<(edge + 3)]), [0, 0, 0], "Content must stay inside the black widget margin")
            }
            XCTAssertGreaterThan(colored, 500, "Widget row \(row) must contain visible habit content")
        }
    }
}
