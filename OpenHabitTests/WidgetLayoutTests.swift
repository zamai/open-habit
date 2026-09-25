import XCTest
import SwiftUI
import WidgetKit
import OpenHabitCore
@testable import OpenHabit

final class WidgetLayoutTests: XCTestCase {
    @MainActor func testCompletionGlyphStatesRender() throws {
        let view = HStack(spacing: 20) {
            CompletionGlyph(count: 0, target: 1, color: .orange)
            CompletionGlyph(count: 0, target: 8, color: .blue)
            CompletionGlyph(count: 3, target: 8, color: .blue)
            CompletionGlyph(count: 8, target: 8, color: .blue)
        }
        .padding(12)
        .background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertGreaterThan(try coloredPixelCount(image), 500)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Completion glyph states"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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

    @MainActor func testSingleHabitWidgetDrawsEmptyCellsThroughTheEndOfTheCurrentWeek() throws {
        let habit = Habit(name: "Exercise", emoji: "🏃", color: .yellow)
        var data = Dataset()
        data.habits = [habit]
        data.settings.weekStart = .monday
        let end = try XCTUnwrap(LocalDay.date("2026-09-23")) // Wednesday
        let view = WidgetHistory(habit: habit, data: data, weeks: 10, spacing: 0, end: end)
            .frame(width: 100, height: 70)
            .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        let pixels = try rgbaPixels(image)

        // Thursday is in the final/current-week column and must remain visibly empty, not absent.
        XCTAssertTrue(isColored(pixels, image: image, x: 95, y: 35))
    }

    @MainActor func testHabitDetailGridDrawsEmptyCellsThroughTheEndOfTheCurrentWeek() throws {
        let habit = Habit(name: "Exercise", emoji: "🏃", color: .yellow)
        var data = Dataset()
        data.habits = [habit]
        data.settings.weekStart = .monday
        let end = try XCTUnwrap(LocalDay.date("2026-09-23")) // Wednesday
        let view = HistoryGrid(habit: habit, data: data, weeks: 10, spacing: 0, maxTileSide: 10, end: end)
            .frame(width: 100, height: 70)
            .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        let pixels = try rgbaPixels(image)

        // Thursday is in the final/current-week column and must remain visibly empty, not absent.
        XCTAssertTrue(isVisible(pixels, image: image, x: 95, y: 35))
    }

    @MainActor func testTenMemberSharedHabitSectionRendersAtPhoneWidth() throws {
        let habit = Habit(name: "Exercise", emoji: "🏃", target: 3, streakGoal: StreakGoal(period: .weekly, target: 3))
        let definition = SharedHabitDefinition(habit: habit, weekStart: .monday)
        let members = (0..<10).map { index in
            SharedMember(name: index == 0 ? "Taylor Montgomery" : "Member \(index + 1)", colorIndex: index, role: index == 0 ? .owner : .member)
        }
        let view = VStack(spacing: 0) {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                SharedMemberRow(member: member, definition: definition)
                if index < members.count - 1 { Divider().padding(.leading, 54) }
            }
        }
        .padding()
        .frame(width: 390, height: 900)
        .background(Color(.systemGroupedBackground))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size, CGSize(width: 390, height: 900))
        XCTAssertGreaterThan(try coloredPixelCount(image), 1_000, "Member colors and progress must render visibly")
        let attachment = XCTAttachment(image: image)
        attachment.name = "Ten Member Shared Habit"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testHabitMetricCardsHaveEqualBackgroundHeights() throws {
        let view = HStack(spacing: 10) {
            HabitMetric(value: "1", label: "Daily Target", color: .green)
            HabitMetric(value: "4", label: "Sep Total", color: .green)
            HabitMetric(value: "0", label: "Week Streak\n0 / 3 this week", color: .green)
        }
        .frame(width: 600, height: 180)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        let pixels = try rgbaPixels(image)
        let cardWidth = (image.cgImage!.width - 20) / 3
        let heights = (0..<3).map { card in
            nonBlackRowBounds(pixels, image: image, xRange: (card * (cardWidth + 10))..<(card * (cardWidth + 10) + cardWidth))
        }
        XCTAssertEqual(heights[0], heights[1])
        XCTAssertEqual(heights[1], heights[2])
    }

    private func coloredPixelCount(_ image: UIImage) throws -> Int {
        let pixels = try rgbaPixels(image)
        return stride(from: 0, to: pixels.count, by: 4).reduce(into: 0) { total, offset in
            let channels = pixels[offset..<(offset + 3)]
            if Int(channels.max()!) - Int(channels.min()!) > 20 { total += 1 }
        }
    }

    private func rgbaPixels(_ image: UIImage) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height,
                                            bitsPerComponent: 8, bytesPerRow: width * 4,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    private func isColored(_ pixels: [UInt8], image: UIImage, x: Int, y: Int) -> Bool {
        let width = image.cgImage!.width
        let offset = (y * width + x) * 4
        let channels = pixels[offset..<(offset + 3)]
        return Int(channels.max()!) - Int(channels.min()!) > 20
    }

    private func isVisible(_ pixels: [UInt8], image: UIImage, x: Int, y: Int) -> Bool {
        let width = image.cgImage!.width
        let offset = (y * width + x) * 4
        return pixels[offset..<(offset + 3)].max()! > 5
    }

    private func nonBlackRowBounds(_ pixels: [UInt8], image: UIImage, xRange: Range<Int>) -> ClosedRange<Int>? {
        let width = image.cgImage!.width
        let height = image.cgImage!.height
        let rows = (0..<height).filter { y in
            xRange.contains { x in
                let offset = (y * width + x) * 4
                return pixels[offset] > 10 || pixels[offset + 1] > 10 || pixels[offset + 2] > 10
            }
        }
        guard let first = rows.first, let last = rows.last else { return nil }
        return first...last
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
