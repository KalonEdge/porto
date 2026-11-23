import SwiftUI

/// Porto's app icon: the porthole in dots on an ink squircle. The ring is the
/// servers Porto watches, white, with three in green for the ones running; the
/// centre is the app itself.
struct AppIconView: View {
    var size: CGFloat = 88
    /// Square and edge to edge, for platforms that round the corners themselves
    /// (the website's apple-touch-icon).
    var fullBleed = false

    /// Clockwise from the top: the ring of the 5×5 porthole, as (row, column).
    private static let ring: [(Int, Int)] = [
        (0, 1), (0, 2), (0, 3), (1, 4), (2, 4), (3, 4), (4, 3), (4, 2), (4, 1), (3, 0), (2, 0), (1, 0),
    ]

    /// Sky → periwinkle → lavender → lilac → pink, then back towards sky.
    private static let stops: [(Double, Double, Double)] = [
        (0x6E, 0xC7, 0xED), (0x7D, 0x9C, 0xF2), (0xB5, 0x99, 0xF0), (0xD9, 0xA3, 0xF2), (0xEB, 0x9C, 0xD4), (0x7D, 0xDB, 0xE0),
    ]

    private static func ringColor(_ index: Int) -> Color { sweep(Double(index) / Double(ring.count)) }

    /// The port-colour sweep at `fraction` (0…1) of the way round.
    static func sweep(_ fraction: Double) -> Color {
        let position = fraction * Double(stops.count)
        let from = stops[Int(position) % stops.count], to = stops[(Int(position) + 1) % stops.count]
        let t = position - floor(position)
        return Color(.sRGB, red: (from.0 + (to.0 - from.0) * t) / 255, green: (from.1 + (to.1 - from.1) * t) / 255,
                     blue: (from.2 + (to.2 - from.2) * t) / 255)
    }

    /// Ring positions lit green: the servers that are running. The rest of the
    /// ring is white, the unlit dots sit faint, and the centre is the app itself.
    private static let running: Set<Int> = [0, 4, 7]
    private static let green = Color(.sRGB, red: 0x30 / 255.0, green: 0xD1 / 255.0, blue: 0x58 / 255.0)

    /// Flat on purpose: one ink fill, solid dots, no gradients, glows or sheen,
    /// so the mark reads the same at 16 px as at 1024. The website draws the
    /// same artwork (kalonedge public/img/apps/porto.svg).
    var body: some View {
        let corner = fullBleed ? 0 : size * 0.2237
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let grid = size * 0.66
        let pitch = grid / 5
        let dot = pitch * 0.62
        ZStack {
            shape.fill(Color(red: 0.071, green: 0.071, blue: 0.078))
            ZStack {
                ForEach(0..<5, id: \.self) { row in
                    ForEach(0..<5, id: \.self) { column in
                        Circle()
                            .fill(.white.opacity((row == 0 || row == 4) && (column == 0 || column == 4) ? 0.22 : 0.16))
                            .frame(width: dot, height: dot)
                            .position(x: (CGFloat(column) + 0.5) * pitch, y: (CGFloat(row) + 0.5) * pitch)
                    }
                }
                ForEach(Array(Self.ring.enumerated()), id: \.offset) { index, cell in
                    Circle()
                        .fill(Self.running.contains(index) ? Self.green : .white)
                        .frame(width: dot, height: dot)
                        .position(x: (CGFloat(cell.1) + 0.5) * pitch, y: (CGFloat(cell.0) + 0.5) * pitch)
                }
                Circle().fill(.white)
                    .frame(width: dot, height: dot)
                    .position(x: 2.5 * pitch, y: 2.5 * pitch)
            }
            .frame(width: grid, height: grid)
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .compositingGroup()
        .shadow(color: .black.opacity(fullBleed ? 0 : 0.3), radius: size * 0.06, y: size * 0.03)
        .environment(\.colorScheme, .dark)
    }
}
