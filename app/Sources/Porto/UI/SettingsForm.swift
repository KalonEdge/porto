import SwiftUI

// Porto's own grouped form. The system one paints its section cards with a
// translucent grey that can't be turned off, and every Porto surface is pure
// white or pure black, so Settings lays out the same cards itself: same
// margins, row heights and dividers, with an outline instead of a fill.

/// The metrics of the system grouped form, measured from a render of it.
private enum FormMetrics {
    static let pageInset: CGFloat = 20
    static let pageTop: CGFloat = 20
    static let sectionGap: CGFloat = 10
    /// Extra room above a headed section when the card before it has no footnote.
    static let headerLead: CGFloat = 20
    static let cardRadius: CGFloat = 6
    static let rowInset: CGFloat = 10
    static let minRowHeight: CGFloat = 36
    static let labelGap: CGFloat = 10
    /// A stacked row's control sits this far under its label.
    static let stackedGap: CGFloat = 6
    /// A control drops under its label when it would leave the label less than this share of the row.
    static let stackLabelShare: CGFloat = 0.5
    /// Beside a stretchy control the label keeps this share, and the control grows to its own.
    static let minLabelShare: CGFloat = 0.45
    static let controlShare: CGFloat = 0.55
}

// MARK: - Page

/// A scrolling Settings pane: its sections, top to bottom, on the window's surface.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            SettingsPageLayout { content }
                .padding(.horizontal, FormMetrics.pageInset)
                .padding(.top, FormMetrics.pageTop)
                .padding(.bottom, FormMetrics.pageInset)
        }
        .background(Theme.windowBackground)
    }
}

private struct SectionHasHeader: LayoutValueKey { static let defaultValue = false }
private struct SectionHasFooter: LayoutValueKey { static let defaultValue = false }

/// Stacks sections with the grouped form's rhythm: cards sit close together,
/// and a heading gets more room unless a footnote already gave it some.
private struct SettingsPageLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        var height: CGFloat = 0
        for index in subviews.indices {
            height += gap(before: index, in: subviews)
            height += subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for index in subviews.indices {
            y += gap(before: index, in: subviews)
            let size = ProposedViewSize(width: bounds.width, height: nil)
            subviews[index].place(at: CGPoint(x: bounds.minX, y: y), proposal: size)
            y += subviews[index].sizeThatFits(size).height
        }
    }

    private func gap(before index: Int, in subviews: Subviews) -> CGFloat {
        guard index > 0 else { return 0 }
        let lead = subviews[index][SectionHasHeader.self] && !subviews[index - 1][SectionHasFooter.self]
        return FormMetrics.sectionGap + (lead ? FormMetrics.headerLead : 0)
    }
}

// MARK: - Section

/// A card of rows with hairline dividers between them, under an optional
/// heading and over an optional footnote.
struct SettingsSection<Header: View, Footer: View, Content: View>: View {
    private let header: Header
    private let footer: Footer
    private let content: Content

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer) {
        self.header = header()
        self.footer = footer()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if Header.self != EmptyView.self {
                header
                    .padding(.leading, FormMetrics.rowInset)
                    .padding(.bottom, 10)
            }
            _VariadicView.Tree(SettingsCard()) { content }
            if Footer.self != EmptyView.self {
                footer
                    .padding(.top, 10)
                    .padding(.bottom, 20)
            }
        }
        .layoutValue(key: SectionHasHeader.self, value: Header.self != EmptyView.self)
        .layoutValue(key: SectionHasFooter.self, value: Footer.self != EmptyView.self)
    }
}

extension SettingsSection where Header == EmptyView, Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
}

extension SettingsSection where Header == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }
}

extension SettingsSection where Header == PaneHeader, Footer == EmptyView {
    /// A section under an eyebrow heading.
    init(eyebrow: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { PaneHeader(eyebrow) }, footer: { EmptyView() })
    }
}

/// The card itself: each child of the section is a padded row.
private struct SettingsCard: _VariadicView_MultiViewRoot {
    @ViewBuilder func body(children: _VariadicView.Children) -> some View {
        SettingsCardChrome {
            VStack(spacing: 0) {
                ForEach(children) { child in
                    if child.id != children.first?.id {
                        SettingsRowDivider()
                    }
                    child
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(FormMetrics.rowInset)
                        .frame(minHeight: FormMetrics.minRowHeight)
                }
            }
        }
    }
}

private struct SettingsCardChrome<Content: View>: View {
    @Environment(\.displayScale) private var scale
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FormMetrics.cardRadius, style: .circular)
        content
            .background(Theme.windowBackground, in: shape)
            // One device pixel on Retina, one point otherwise.
            .overlay(shape.strokeBorder(Theme.separator, lineWidth: max(1 / max(scale, 1), 0.5)))
    }
}

/// The hairline between two rows, inset like the rows' content.
private struct SettingsRowDivider: View {
    var body: some View {
        SectionDivider()
            .frame(height: 1, alignment: .top)
            .padding(.horizontal, FormMetrics.rowInset)
    }
}

// MARK: - Rows

extension VerticalAlignment {
    private enum SettingsFirstLine: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[VerticalAlignment.center] }
    }

    /// The middle of a row label's first line, which a row's control centres on.
    static let settingsFirstLine = VerticalAlignment(SettingsFirstLine.self)
}

/// A label on the leading edge and its control on the trailing edge. The
/// control lines up with the label's first line; when the two can't share the
/// row the control drops underneath at full width.
struct SettingsRow<Label: View, Control: View>: View {
    private let label: Label
    private let control: Control
    private var title: String?

    init(@ViewBuilder control: () -> Control, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.control = control()
    }

    var body: some View {
        SettingsRowLayout {
            label
            if let title {
                control.accessibilityElement(children: .contain).accessibilityLabel(title)
            } else {
                control
            }
        }
    }
}

extension SettingsRow where Label == AnyView {
    /// A titled row whose controls are read out under that title.
    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.init(control: control) { AnyView(Text(title)) }
        self.title = title
    }
}

private struct SettingsRowLayout: Layout {
    private struct Arrangement {
        var size: CGSize
        var label: CGRect
        var control: CGRect
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let ideal = subviews[0].sizeThatFits(.unspecified).width + FormMetrics.labelGap + subviews[1].sizeThatFits(.unspecified).width
        return arrange(subviews, width: width(proposal, ideal: ideal)).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let arrangement = arrange(subviews, width: bounds.width)
        for (subview, frame) in [(subviews[0], arrangement.label), (subviews[1], arrangement.control)] {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func width(_ proposal: ProposedViewSize, ideal: CGFloat) -> CGFloat {
        guard let width = proposal.width, width.isFinite else { return ideal }
        return width
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> Arrangement {
        let label = subviews[0], control = subviews[1]
        let ideal = control.sizeThatFits(.unspecified).width
        let labelIdeal = label.sizeThatFits(.unspecified).width

        if ideal <= width - FormMetrics.labelGap - min(labelIdeal, width * FormMetrics.stackLabelShare) {
            // A stretchy control, like a row of segments, grows towards its share
            // of the row; a fixed one keeps its own width. The label has the rest.
            let most = width - FormMetrics.labelGap - min(labelIdeal, width * FormMetrics.minLabelShare)
            let wanted = min(max(ideal, width * FormMetrics.controlShare), most)
            let controlSize = control.sizeThatFits(ProposedViewSize(width: wanted, height: nil))
            let proposal = ProposedViewSize(width: max(width - FormMetrics.labelGap - controlSize.width, 0), height: nil)
            let labelSize = label.sizeThatFits(proposal)
            let firstLine = label.dimensions(in: proposal)[VerticalAlignment.settingsFirstLine]
            let controlY = max(0, firstLine - controlSize.height / 2)
            let height = max(labelSize.height, controlY + controlSize.height)
            return Arrangement(size: CGSize(width: width, height: height),
                               label: CGRect(origin: .zero, size: labelSize),
                               control: CGRect(x: width - controlSize.width, y: controlY, width: controlSize.width, height: controlSize.height))
        }

        let full = ProposedViewSize(width: width, height: nil)
        let labelSize = label.sizeThatFits(full)
        let stretched = control.sizeThatFits(full)
        let controlY = labelSize.height + FormMetrics.stackedGap
        return Arrangement(size: CGSize(width: width, height: controlY + stretched.height),
                           label: CGRect(origin: .zero, size: labelSize),
                           control: CGRect(x: width - stretched.width, y: controlY, width: stretched.width, height: stretched.height))
    }
}

// MARK: - Controls

/// A switch on the trailing edge of its label. The label is drawn once and
/// read out once: VoiceOver gets it from the switch.
struct SettingsToggle<Label: View>: View {
    @Binding private var isOn: Bool
    private let label: Label

    init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {
        _isOn = isOn
        self.label = label()
    }

    var body: some View {
        SettingsRow {
            Toggle(isOn: $isOn) { label }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        } label: {
            label.accessibilityHidden(true)
        }
    }
}

extension SettingsToggle where Label == AnyView {
    init(_ title: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { AnyView(Text(title)) }
    }
}

/// A picker on the trailing edge of its label: a pop-up, or segments after `.segmented()`.
struct SettingsPicker<Selection: Hashable, Label: View, Options: View>: View {
    @Binding private var selection: Selection
    private let label: Label
    private let options: Options
    private var isSegmented = false

    init(selection: Binding<Selection>, @ViewBuilder content: () -> Options, @ViewBuilder label: () -> Label) {
        _selection = selection
        self.label = label()
        options = content()
    }

    func segmented() -> Self {
        var copy = self
        copy.isSegmented = true
        return copy
    }

    var body: some View {
        SettingsRow {
            let picker = Picker(selection: $selection) { options } label: { label }.labelsHidden()
            if isSegmented {
                picker.pickerStyle(.segmented).offset(y: -1).frame(height: 20)
            } else {
                picker.pickerStyle(.menu).buttonStyle(.borderless).fixedSize()
                    .overlay(alignment: .trailing) { PopUpChip().offset(x: 1.5, y: 1) }
                    .offset(x: -1, y: -0.5)
                    .padding(.trailing, 2.5)
            }
        } label: {
            label.accessibilityHidden(true)
        }
    }
}

/// The pop-up's arrows on their chip, as the grouped form draws them. It covers
/// the plain arrows of the borderless pop-up underneath, which still takes the clicks.
private struct PopUpChip: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4.5, style: .continuous)
        Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.text1.opacity(0.85))
            .frame(width: 16, height: 16)
            .background(Theme.fill, in: shape)
            .background(Theme.windowBackground, in: shape)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension SettingsPicker where Label == AnyView {
    init(_ title: String, selection: Binding<Selection>, @ViewBuilder content: () -> Options) {
        self.init(selection: selection, content: content) { AnyView(Text(title)) }
    }
}

extension View {
    /// The form's text field: an outlined box on the surface, with no bezel or
    /// shadow. `inset` keeps the box that far inside the field's own width.
    func settingsField(inset: CGFloat = 0) -> some View { modifier(SettingsFieldChrome(inset: inset)) }

    /// The form's stepper: small, unlabelled, and tucked against its value.
    func settingsStepper() -> some View {
        labelsHidden().controlSize(.small).offset(x: -3)
    }
}

private struct SettingsFieldChrome: ViewModifier {
    let inset: CGFloat
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        content
            .textFieldStyle(.plain)
            .focused($isFocused)
            .padding(.top, 1)
            .padding(.leading, 5)
            .padding(.trailing, 4)
            .frame(height: 22)
            .background(Theme.windowBackground, in: shape)
            .overlay(shape.strokeBorder(Theme.separator, lineWidth: 1))
            .overlay {
                if isFocused {
                    shape.inset(by: -1.5).stroke(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                }
            }
            .padding(.horizontal, inset)
    }
}
