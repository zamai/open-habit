import XCTest
import SwiftUI
import WidgetKit
@testable import OpenHabit

final class WidgetLayoutTests: XCTestCase {
    @MainActor func testAllWidgetSizesRender() throws {
        let cases: [(name: String, size: CGSize, rows: Int?)] = [
            ("One Habit widget", CGSize(width: 164, height: 164), nil),
            ("Three Habits widget", CGSize(width: 350, height: 164), 3),
            ("Six Habits widget", CGSize(width: 350, height: 354), 6)
        ]
        for item in cases {
            let view = HabitWidgetContent(entry: .example, compactRows: item.rows)
                .frame(width: item.size.width, height: item.size.height)
                .environment(\.colorScheme, .light)
                .background(Color.black)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size, item.size)
            try assertVisibleContent(image, minimumHabitRows: item.rows ?? 1)
            let attachment = XCTAttachment(image: image)
            attachment.name = item.name
            attachment.lifetime = .keepAlways
            add(attachment)
            let filename = item.rows == nil ? "small-widget.png" : item.rows == 3 ? "medium-widget.png" : "large-widget.png"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try image.pngData()!.write(to: url)
            print("WIDGET_RENDER: \(url.path)")
        }
    }

    // A successfully allocated image can still contain an entirely blank widget.
    private func assertVisibleContent(_ image: UIImage, minimumHabitRows: Int) throws {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height,
                                            bitsPerComponent: 8, bytesPerRow: width * 4,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var colored = 0
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let channels = Array(pixels[offset..<(offset + 3)])
                if Int(channels.max()!) - Int(channels.min()!) > 20 { colored += 1 }
            }
            let edge = y * width * 4
            XCTAssertEqual(Array(pixels[edge..<(edge + 3)]), [0, 0, 0], "Content must stay inside the black widget margin")
        }
        XCTAssertGreaterThan(colored, 500 * minimumHabitRows, "Every configured habit row must contribute visible content")
    }
}
