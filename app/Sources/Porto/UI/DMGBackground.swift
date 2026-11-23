import SwiftUI

/// The disk image window, 660 × 400: Porto on the left, Applications on the
/// right (see dmg/settings.py), and a dot-matrix arrow between them that
/// sweeps through the port colours like the icon's ring.
///
/// Finder draws the icon labels itself, black in light mode and white in dark
/// mode, so the ground is a mid-tone dusk that keeps both readable (~4.6:1).
struct DMGBackground: View {
    static let size = CGSize(width: 660, height: 400)
    /// Icon centres, shared with dmg/settings.py.
    static let appCenter = CGPoint(x: 170, y: 164)
    static let applicationsCenter = CGPoint(x: 490, y: 164)

    private static let columns = 9
    private static let rows = 5
    private static let pitch: CGFloat = 12

    /// The arrow: a trail along the middle row into a chevron.
    private static func isLit(_ row: Int, _ column: Int) -> Bool {
        let head = abs(row - 2)
        return (row == 2 && column <= 8) || column == 8 - head && head > 0 && column >= 6
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.42, green: 0.47, blue: 0.68), Color(red: 0.37, green: 0.42, blue: 0.62)],
                           startPoint: .top, endPoint: .bottom)
            // A faint porthole glow behind each icon.
            ForEach([Self.appCenter, Self.applicationsCenter], id: \.x) { center in
                RadialGradient(colors: [.white.opacity(0.1), .clear], center: .center, startRadius: 0, endRadius: 110)
                    .frame(width: 220, height: 220)
                    .position(center)
            }
            arrow.position(x: (Self.appCenter.x + Self.applicationsCenter.x) / 2, y: Self.appCenter.y)
            VStack(spacing: 7) {
                Text("Drag Porto into Applications")
                    .font(.custom("Geist-Medium", fixedSize: 13))
                    .foregroundStyle(.white)
                Text("Then open it. It lives in your menu bar, not the Dock.")
                    .font(.custom("Geist-Regular", fixedSize: 11))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .position(x: Self.size.width / 2, y: 322)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .dark)
    }

    private var arrow: some View {
        let dot = Self.pitch * 0.62
        return ZStack {
            ForEach(0..<Self.rows, id: \.self) { row in
                ForEach(0..<Self.columns, id: \.self) { column in
                    let lit = Self.isLit(row, column)
                    let progress = Double(column) / Double(Self.columns - 1)
                    // Sky at the tail to pink at the head.
                    let color = AppIconView.sweep(progress * 0.66)
                    Circle()
                        .fill(lit ? color : .white.opacity(0.1))
                        // The trail brightens towards the head.
                        .opacity(lit ? 0.6 + 0.4 * progress : 1)
                        .frame(width: dot, height: dot)
                        .shadow(color: lit ? color.opacity(0.9 * progress) : .clear, radius: dot * 0.55)
                        .position(x: (CGFloat(column) + 0.5) * Self.pitch, y: (CGFloat(row) + 0.5) * Self.pitch)
                }
            }
        }
        .frame(width: CGFloat(Self.columns) * Self.pitch, height: CGFloat(Self.rows) * Self.pitch)
    }
}
