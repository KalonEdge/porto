import AppKit
import SwiftUI

/// A 5×5 dot-matrix glyph. `#` is lit, `a` is lit amber, `.` is unlit.
struct DotGlyph: Equatable {
    let rows: [String]

    /// Porto's mark: a porthole, a ring of dots around a lit centre.
    static let porthole = DotGlyph(rows: [".###.", "#...#", "#.#.#", "#...#", ".###."])
    static let idle = DotGlyph(rows: [".....", ".....", ".....", ".....", "....."])
    /// The porthole turned amber: a server needs attention.
    static let alert = DotGlyph(rows: [".aaa.", "a...a", "a.a.a", "a...a", ".aaa."])
    static let question = DotGlyph(rows: [".###.", "#...#", "..##.", ".....", "..#.."])
    static let prompt = DotGlyph(rows: ["#....", ".#...", "..#..", ".#...", "#.###"])
    static let leak = DotGlyph(rows: ["....a", "...a.", "..#..", ".#...", "#...."])
    static let burst = DotGlyph(rows: ["#.#.#", ".....", "#...#", ".....", "#.#.#"])
    static let triangle = DotGlyph(rows: [".....", "..#..", ".###.", "#####", "....."])
    /// The porthole with a cursor after it, for the terminal.
    static let cursor = DotGlyph(rows: [".....", ".#...", ".....", ".#.##", "....."])
    static let bars = DotGlyph(rows: ["....#", "..#.#", "..#.#", "#.#.#", "#.#.#"])
    static let rising = DotGlyph(rows: ["....#", "...##", ".#.##", ".####", "#####"])
    static let letterP = DotGlyph(rows: ["####.", "#...#", "####.", "#....", "#...."])

    private static let digits: [[String]] = [
        [".###.", "#..##", "#.#.#", "##..#", ".###."],
        ["..#..", ".##..", "..#..", "..#..", ".###."],
        ["####.", "....#", ".###.", "#....", "#####"],
        ["####.", "....#", ".###.", "....#", "####."],
        ["#..#.", "#..#.", "#####", "...#.", "...#."],
        ["#####", "#....", "####.", "....#", "####."],
        [".###.", "#....", "####.", "#...#", ".###."],
        ["#####", "....#", "...#.", "..#..", "..#.."],
        [".###.", "#...#", ".###.", "#...#", ".###."],
        [".###.", "#...#", ".####", "....#", ".###."],
    ]

    /// A single digit drawn in the grid, for the "Count" menu bar style.
    static func digit(_ value: Int) -> DotGlyph? {
        (0...9).contains(value) ? DotGlyph(rows: digits[value]) : nil
    }

    func dot(row: Int, column: Int) -> Character {
        let line = Array(rows[row])
        return column < line.count ? line[column] : "."
    }

    var isAlert: Bool { rows.joined().contains("a") }

    /// A loading loop: a short arc of dots running around the grid's edge.
    static let loading: [DotGlyph] = [
        DotGlyph(rows: [".###.", "....#", "....#", ".....", "....."]),
        DotGlyph(rows: ["...#.", "....#", "....#", "....#", "...#."]),
        DotGlyph(rows: [".....", ".....", "....#", "....#", ".###."]),
        DotGlyph(rows: [".....", ".....", "#....", "#....", ".###."]),
        DotGlyph(rows: [".#...", "#....", "#....", "#....", ".#..."]),
        DotGlyph(rows: [".###.", "#....", "#....", ".....", "....."]),
    ]

    /// A checkmark drawn a dot at a time, short stroke first; the last frame is the finished mark.
    static let checkStrokes: [DotGlyph] = [
        DotGlyph(rows: [".....", ".....", "#....", ".....", "....."]),
        DotGlyph(rows: [".....", ".....", "#....", ".#...", "....."]),
        DotGlyph(rows: [".....", ".....", "#.#..", ".#...", "....."]),
        DotGlyph(rows: [".....", "...#.", "#.#..", ".#...", "....."]),
        DotGlyph(rows: ["....#", "...#.", "#.#..", ".#...", "....."]),
    ]
}

/// Draws a glyph with Flicker-style geometry: dots two-thirds of their pitch.
private func drawDots(_ glyph: DotGlyph, in context: GraphicsContext, size: CGFloat, on: Color, off: Color, amber: Color = Theme.amber) {
    let pitch = size / 5
    let diameter = pitch * 2 / 3
    for row in 0..<5 {
        for column in 0..<5 {
            let rect = CGRect(x: CGFloat(column) * pitch + (pitch - diameter) / 2, y: CGFloat(row) * pitch + (pitch - diameter) / 2,
                              width: diameter, height: diameter)
            let dot = glyph.dot(row: row, column: column)
            context.fill(Path(ellipseIn: rect), with: .color(dot == "a" ? amber : dot == "#" ? on : off))
        }
    }
}

/// Plays glyph frames with a hard cut every 150ms, held on the first frame when
/// Reduce Motion is on. A single frame draws as a still glyph.
struct DotSpinner: View {
    var frames: [DotGlyph] = DotGlyph.loading
    var size: CGFloat = 16
    var color: Color = Theme.text1
    var unlitColor: Color?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let frameInterval: TimeInterval = 0.15

    var body: some View {
        let off = unlitColor ?? color.opacity(0.12)
        if frames.count < 2 || reduceMotion {
            Canvas { context, _ in drawDots(frames.first ?? .idle, in: context, size: size, on: color, off: off) }
                .frame(width: size, height: size)
        } else {
            TimelineView(.periodic(from: .now, by: Self.frameInterval)) { timeline in
                let index = Int(timeline.date.timeIntervalSinceReferenceDate / Self.frameInterval) % frames.count
                Canvas { context, _ in drawDots(frames[index], in: context, size: size, on: color, off: off) }
            }
            .frame(width: size, height: size)
        }
    }
}

/// A still glyph, as in the popover's empty state and Settings' sidebar.
struct DotGridView: View {
    let glyph: DotGlyph
    var size: CGFloat = 64
    var color: Color = Theme.text1

    var body: some View {
        let pitch = size / 5
        Canvas { context, _ in
            for row in 0..<5 {
                for column in 0..<5 {
                    let rect = CGRect(x: CGFloat(column) * pitch + pitch * 0.18, y: CGFloat(row) * pitch + pitch * 0.18,
                                      width: pitch * 0.64, height: pitch * 0.64)
                    let dot = glyph.dot(row: row, column: column)
                    context.fill(Path(ellipseIn: rect), with: .color(dot == "a" ? Theme.amber : dot == "#" ? color : color.opacity(0.12)))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// A dot matrix whose dots animate one by one between glyphs, staggered by
/// column, so any glyph can morph into any other.
struct DotMatrixView: View {
    let glyph: DotGlyph
    var size: CGFloat = 110
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pitch = size / 5
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { column in
                        let dot = glyph.dot(row: row, column: column)
                        Circle()
                            .fill(dot == "a" ? Theme.amber : Theme.text1)
                            .opacity(dot == "." ? 0.12 : 1)
                            .frame(width: pitch * 0.64, height: pitch * 0.64)
                            .frame(width: pitch, height: pitch)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.28).delay(Double(column) * 0.04), value: glyph)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// The menu bar icon: a glyph, optionally followed by a count.
enum MenuBarIcon {
    static func image(glyph: DotGlyph, count: Int?) -> NSImage {
        let height: CGFloat = 18
        let gridSize: CGFloat = 16
        let font = FontLoader.nsFont("GeistMono-Medium", size: 13)
        let text = count.map(String.init)
        let textWidth = text.map { ($0 as NSString).size(withAttributes: [.font: font]).width } ?? 0
        let width = gridSize + (text == nil ? 0 : 5 + ceil(textWidth))
        let isAlert = glyph.isAlert

        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let pitch = gridSize / 5
            let top = (height - gridSize) / 2
            for row in 0..<5 {
                for column in 0..<5 {
                    let rect = CGRect(x: CGFloat(column) * pitch + pitch * 0.12, y: top + CGFloat(row) * pitch + pitch * 0.12,
                                      width: pitch * 0.76, height: pitch * 0.76)
                    let color: NSColor
                    switch glyph.dot(row: row, column: column) {
                    case "a":
                        color = isDark ? NSColor(srgbRed: 1, green: 0.7, blue: 0.14, alpha: 1) : NSColor(srgbRed: 0.886, green: 0.604, blue: 0, alpha: 1)
                    case "#":
                        color = .black
                    default:
                        // Unlit dots only show while the grid is saying something (an alert);
                        // at rest the icon is just its lit dots, like other menu bar icons.
                        guard isAlert else { continue }
                        color = isDark ? NSColor(white: 1, alpha: 0.28) : NSColor(white: 0, alpha: 0.22)
                    }
                    color.setFill()
                    NSBezierPath(ovalIn: rect).fill()
                }
            }
            if let text {
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: isAlert ? NSColor.labelColor : NSColor.black]
                let size = (text as NSString).size(withAttributes: attributes)
                (text as NSString).draw(at: CGPoint(x: gridSize + 5, y: (height - size.height) / 2), withAttributes: attributes)
            }
            return true
        }
        // Template images follow the menu bar's appearance and highlight.
        image.isTemplate = !isAlert
        return image
    }
}
