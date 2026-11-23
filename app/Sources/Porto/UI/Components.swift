import SwiftUI

/// The two port-coloured dots before every port: solid, glowing for attention, outlined when idle.
struct ColonStatus: View {
    let status: ServerStatus
    let color: Color
    var dot: CGFloat = 4
    var gap: CGFloat = 3

    var body: some View {
        VStack(spacing: gap) {
            mark
            mark
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var mark: some View {
        switch status {
        case .running:
            Circle().fill(color).frame(width: dot, height: dot)
        case .attention:
            Circle().fill(Theme.amber).frame(width: dot, height: dot).shadow(color: Theme.amber.opacity(0.7), radius: 2.5)
        case .idle:
            Circle().strokeBorder(color, lineWidth: max(1.1, dot / 5)).frame(width: dot, height: dot)
        }
    }
}

struct PortLabel: View {
    let port: Int
    let status: ServerStatus
    let color: Color
    var large = false

    var body: some View {
        HStack(spacing: large ? 7 : 5) {
            ColonStatus(status: status, color: color, dot: large ? 6 : 4, gap: large ? 7 : 3)
            Text(String(port))
                .font(large ? Theme.hero : Theme.monoMedium)
                .foregroundStyle(color)
        }
        // Ports read left to right in every language.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(":\(String(port))")
    }
}

/// A number with its unit set smaller and quieter, so columns of readings scan by the digits.
struct Amount: View {
    let value: (number: String, unit: String)
    var font = Theme.monoMedium
    var unitFont = Theme.monoCaption
    var color = Theme.text1
    var unitColor = Theme.text3
    var spacing: CGFloat = 3

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            Text(value.number).font(font).foregroundStyle(color).contentTransition(.numericText())
            Text(value.unit).font(unitFont).foregroundStyle(unitColor)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .combine)
    }
}

/// The small label above a reading or a section: tracked capitals where the script has them.
struct Eyebrow: View {
    let text: String
    var color = Theme.text3

    init(_ text: String, color: Color = Theme.text3) {
        self.text = text
        self.color = color
    }

    private static var hasCapitals: Bool {
        switch L10n.language {
        case .japanese, .simplifiedChinese, .hebrew: return false
        default: return true
        }
    }

    var body: some View {
        Text(text)
            .font(Self.hasCapitals ? Theme.eyebrow : Theme.captionMedium)
            .tracking(Self.hasCapitals ? 0.9 : 0)
            .textCase(Self.hasCapitals ? .uppercase : nil)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Memory over the recorded history, scaled to its own range, with a soft fill
/// and a dot on the latest reading; a dashed rule until there's history.
struct Sparkline: View {
    let values: [Double]
    var color: Color = Theme.text1.opacity(0.7)
    var lineWidth: CGFloat = 1.25

    var body: some View {
        GeometryReader { geometry in
            if values.count > 1, let low = values.min(), let high = values.max() {
                let range = max(high - low, high * 0.05, 1)
                let inset = lineWidth + 1.5
                let width = geometry.size.width - inset
                let points = values.enumerated().map { index, value in
                    CGPoint(x: width * CGFloat(index) / CGFloat(values.count - 1),
                            y: geometry.size.height * (1 - CGFloat((value - low) / range)) * 0.7 + geometry.size.height * 0.15)
                }
                Path { path in
                    path.move(to: CGPoint(x: points[0].x, y: geometry.size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { path in
                    path.move(to: points[0])
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                Circle().fill(color).frame(width: lineWidth * 2 + 1.5, height: lineWidth * 2 + 1.5)
                    .position(points[points.count - 1])
            } else {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height * 0.66))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height * 0.66))
                }
                .stroke(Theme.text3, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 3]))
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}

/// The title row of a pushed popover page: back on the leading edge, a centred
/// title, and the page's own actions on the trailing edge.
struct PageHeader<Trailing: View>: View {
    let title: String
    var back: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            Text(title)
                .font(Theme.bodyMedium)
                .foregroundStyle(Theme.text1)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(title)
                .padding(.horizontal, 72)
            HStack(spacing: Theme.Space.xxs) {
                if let back {
                    IconButton(systemName: "chevron.left", tint: Theme.text2, background: .clear, help: L10n.text("Back"), action: back)
                        .keyboardShortcut(.cancelAction)
                        .flipsForRightToLeftLayoutDirection(true)
                }
                Spacer()
                trailing
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Theme.iconButton)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, back: (() -> Void)? = nil) {
        self.init(title: title, back: back) { EmptyView() }
    }
}

struct SectionDivider: View {
    @Environment(\.displayScale) private var scale

    var body: some View {
        // One device pixel on Retina, one point otherwise.
        Rectangle().fill(Theme.separator).frame(height: max(1 / max(scale, 1), 0.5))
            .accessibilityHidden(true)
    }
}

/// A square symbol button with hover, pressed and disabled states and a tooltip.
struct IconButton: View {
    let systemName: String
    var tint: Color = Theme.text1
    var background: Color = Theme.fill
    var size: CGFloat = Theme.iconButton
    var symbolSize: CGFloat = 12
    var help = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: symbolSize, weight: .semibold))
        }
        .buttonStyle(IconButtonStyle(tint: tint, background: background, size: size))
        .help(help)
        .accessibilityLabel(help)
    }
}

struct IconButtonStyle: ButtonStyle {
    var tint: Color = Theme.text1
    var background: Color = Theme.fill
    var size: CGFloat = Theme.iconButton

    func makeBody(configuration: Configuration) -> some View {
        Chrome(style: self, configuration: configuration)
    }

    private struct Chrome: View {
        let style: IconButtonStyle
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: min(Theme.Radius.control, style.size / 3.5), style: .continuous)
            configuration.label
                .foregroundStyle(style.tint)
                .frame(width: style.size, height: style.size)
                .background(style.background, in: shape)
                .background(configuration.isPressed ? Theme.pressed : (isHovered && isEnabled ? Theme.hover : .clear), in: shape)
                .opacity(isEnabled ? 1 : 0.35)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .animation(Theme.Motion.quick, value: isHovered)
        }
    }
}

/// Porto's buttons. Primary is solid ink and there is one per page; secondary is
/// a hairline outline; destructive is solid red and only used for the action a
/// page exists for.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        Chrome(kind: kind, configuration: configuration)
    }

    private struct Chrome: View {
        let kind: Kind
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            configuration.label
                .font(Theme.bodyMedium)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .padding(.horizontal, Theme.Space.s)
                .frame(height: Theme.controlHeight)
                .background(background, in: shape)
                .overlay { if hasOutline { shape.strokeBorder(Theme.outline, lineWidth: 1) } }
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .animation(Theme.Motion.quick, value: isHovered)
                .animation(Theme.Motion.quick, value: isEnabled)
        }

        private var hasOutline: Bool { kind == .secondary || !isEnabled }

        private var foreground: Color {
            guard isEnabled else { return Theme.text3 }
            return kind == .secondary ? Theme.text1 : Theme.onPrimary
        }

        private var background: Color {
            guard isEnabled else { return .clear }
            let dim = configuration.isPressed ? 0.72 : (isHovered ? 0.86 : 1)
            switch kind {
            case .primary: return Theme.text1.opacity(dim)
            case .destructive: return Theme.red.opacity(dim)
            case .secondary: return configuration.isPressed ? Theme.pressed : (isHovered ? Theme.hover : .clear)
            }
        }
    }
}

/// Small monochrome marks for the agent that started a server.
struct AgentGlyph: View {
    let kind: AgentKind
    var size: CGFloat = 12
    var color: Color = Theme.text1.opacity(0.75)

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 12
            switch kind {
            case .claudeCode:
                var path = Path()
                for (from, to) in [((6.0, 1.0), (6.0, 11.0)), ((1.0, 6.0), (11.0, 6.0)), ((2.5, 2.5), (9.5, 9.5)), ((9.5, 2.5), (2.5, 9.5))] {
                    path.move(to: CGPoint(x: from.0 * s, y: from.1 * s))
                    path.addLine(to: CGPoint(x: to.0 * s, y: to.1 * s))
                }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.4 * s, lineCap: .round))
            case .codex:
                context.stroke(Path(roundedRect: CGRect(x: 1 * s, y: 1.5 * s, width: 10 * s, height: 9 * s), cornerRadius: 2.5 * s),
                               with: .color(color), lineWidth: 1.2 * s)
                var prompt = Path()
                prompt.move(to: CGPoint(x: 3.5 * s, y: 5 * s))
                prompt.addLine(to: CGPoint(x: 5 * s, y: 6.2 * s))
                prompt.addLine(to: CGPoint(x: 3.5 * s, y: 7.4 * s))
                prompt.move(to: CGPoint(x: 6.2 * s, y: 7.6 * s))
                prompt.addLine(to: CGPoint(x: 8.5 * s, y: 7.6 * s))
                context.stroke(prompt, with: .color(color), style: StrokeStyle(lineWidth: 1.2 * s, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

/// "N more" and "Less": a quiet text button with its chevron.
struct Disclosure: View {
    let title: String
    let expanded: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(Theme.caption)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .foregroundStyle(isHovered ? Theme.text1 : Theme.text3)
            .frame(minHeight: Theme.iconButton)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct Checkbox: View {
    let isOn: Bool
    var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.mark, style: .continuous)
        shape
            .fill(isOn ? Theme.text1 : .clear)
            .overlay {
                if isOn {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.onPrimary)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    shape.strokeBorder(isHovered ? Theme.text2 : Theme.text3, lineWidth: 1.25)
                }
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }
}

extension View {
    /// The hover highlight used across lists.
    func hoverHighlight(_ isHovered: Bool) -> some View {
        background(isHovered ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
    }
}
