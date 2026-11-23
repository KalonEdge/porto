import Charts
import SwiftUI

struct ServerDetailView: View {
    let server: Server
    @ObservedObject var monitor: ServerMonitor
    @ObservedObject var github: GitHubLookup
    let back: () -> Void

    init(server: Server, monitor: ServerMonitor, back: @escaping () -> Void) {
        self.server = server
        self.monitor = monitor
        self.github = monitor.github
        self.back = back
    }

    @AppStorage(Preferences.infoExpanded) private var infoExpanded = false
    @AppStorage(Preferences.processesExpanded) private var processesExpanded = false
    /// Shared by both charts, so hovering one scrubs the other.
    @State private var hoverTime: Date?
    /// For a model server: whether it's generating and how many models it holds.
    @State private var kalon: (status: KalonStatus, models: Int)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color { Theme.portColor(at: monitor.colorIndex(for: server.port)) }

    var body: some View {
        VStack(spacing: 0) {
            header(status: monitor.status(of: server))
            SectionDivider()
            infoList
            SectionDivider()
            charts
            SectionDivider()
            processes
            SectionDivider()
            footer
        }
        .onAppear { github.refresh(server, maxAge: 30) }
        .task(id: server.port) {
            guard server.kind == .ai else { return }
            let client = KalonClient(baseURL: server.url)
            guard let status = await client.status() else { return }
            kalon = (status, await client.loadedModels().count)
        }
    }

    // MARK: - Header

    /// The page's own actions ride in the title row; the port is the hero.
    private func header(status: ServerStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            PageHeader(title: server.project.name, back: back) {
                IconButton(systemName: "arrow.clockwise", tint: Theme.text2, background: .clear, help: restartHelp) {
                    Usage.record(.restart)
                    monitor.restart(server)
                }
                .disabled(server.launch == nil || !server.cwdExists || server.kind == .ai)
                IconButton(systemName: "stop.fill", tint: Theme.softRed, background: Theme.red.opacity(0.12), symbolSize: 10,
                           help: L10n.format("Stop %d processes", server.processes.count)) {
                    Usage.record(.stop)
                    monitor.stop(server)
                    back()
                }
            }
            .padding(.leading, -8)
            HStack(alignment: .lastTextBaseline, spacing: Theme.Space.xs) {
                PortLabel(port: server.port, status: status, color: color, large: true)
                Spacer(minLength: Theme.Space.xs)
                statusLine(status)
            }
        }
        .padding(EdgeInsets(top: 10, leading: Theme.inset, bottom: 14, trailing: Theme.inset))
    }

    /// State in words, with a mark: never colour alone.
    @ViewBuilder private func statusLine(_ status: ServerStatus) -> some View {
        if AutopilotController.shared.isPaused(server) {
            HStack(spacing: 5) {
                Image(systemName: "pause.fill").font(.system(size: 9, weight: .semibold))
                Text(L10n.text("Paused by Autopilot"))
            }
            .font(Theme.body).foregroundStyle(Theme.text2)
        } else if status == .attention {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10, weight: .semibold))
                if server.isLeaking() {
                    Text(L10n.format("Leaking · +%@", Format.bytesString(UInt64(server.memoryGrowth))))
                } else {
                    Text(L10n.format("Over %@ GB", Format.trim(Double(monitor.alertThreshold) / Format.gigabyte)))
                }
            }
            .font(Theme.bodyMedium).foregroundStyle(Theme.amber)
        } else if let uptime = server.uptime {
            Text(L10n.format("Running for %@", L10n.duration(uptime))).font(Theme.body).foregroundStyle(Theme.text2)
        }
    }

    private var restartHelp: String {
        if let agent = server.agent { return L10n.format("Restart. It will run outside the %@ session.", agent.kind.rawValue) }
        return L10n.text("Restart with the same command")
    }

    // MARK: - Info

    private static var labelWidth: CGFloat { L10n.language == .english ? 64 : 90 }

    private var infoList: some View {
        VStack(alignment: .leading, spacing: 0) {
            let secondary = secondaryRows
            ForEach(Array(primaryRows.enumerated()), id: \.offset) { $0.element }
            if infoExpanded { ForEach(Array(secondary.enumerated()), id: \.offset) { $0.element } }
            if !secondary.isEmpty {
                HStack(spacing: 12) {
                    Spacer().frame(width: Self.labelWidth)
                    Disclosure(title: infoExpanded ? L10n.text("Less") : L10n.format("%d more", secondary.count), expanded: infoExpanded) {
                        withAnimation(Theme.Motion.state(reduceMotion: reduceMotion)) { infoExpanded.toggle() }
                    }
                }
                .frame(height: 28)
            }
        }
        .padding(.horizontal, Theme.inset)
        .padding(.vertical, Theme.Space.xs)
    }

    /// Session and branch when an agent started it; the folder fills in when there's room.
    private var primaryRows: [InfoRow] {
        var rows: [InfoRow] = []
        if server.kind == .ai, let kalon {
            let isBusy = kalon.status.isBusy || server.cpu >= KalonClient.busyCPU
            let text = L10n.format("%@, %d %@", isBusy ? L10n.text("generating") : L10n.text("idle"), kalon.models,
                                   L10n.counted("model loaded", "models loaded", count: kalon.models))
            rows.append(InfoRow(label: kalon.status.flavor.rawValue, tooltip: text) { Text(text).font(Theme.body).foregroundStyle(Theme.text1) })
        }
        if let agent = server.agent {
            rows.append(InfoRow(label: L10n.text("Session"), tooltip: agent.title) { SessionValue(session: agent, server: server) })
        }
        if let branch = server.project.branch {
            rows.append(InfoRow(label: L10n.text("Branch"), tooltip: branch) { Text(branch).font(Theme.body).foregroundStyle(Theme.text1) })
        }
        if primaryShowsFolder, let folder = server.shortFolder {
            rows.append(InfoRow(label: L10n.text("Folder"), tooltip: server.cwd) { Text(folder).font(Theme.mono).foregroundStyle(Theme.text2) })
        }
        return rows
    }

    /// The folder fills in up top when fewer than two rows precede it, and then
    /// isn't repeated under "more".
    private var primaryShowsFolder: Bool {
        let rows = (server.kind == .ai && kalon != nil ? 1 : 0) + (server.agent != nil ? 1 : 0) + (server.project.branch != nil ? 1 : 0)
        return rows < 2 && server.shortFolder != nil
    }

    private var secondaryRows: [InfoRow] {
        var rows: [InfoRow] = []
        if let workspace = server.conductorWorkspace {
            rows.append(InfoRow(label: L10n.text("Workspace"), tooltip: "Conductor · \(workspace)") {
                Text("Conductor · \(workspace)").font(Theme.body).foregroundStyle(Theme.text2)
            })
        }
        if !primaryShowsFolder, server.agent != nil || server.project.branch != nil, let folder = server.shortFolder {
            rows.append(InfoRow(label: L10n.text("Folder"), tooltip: server.cwd) { Text(folder).font(Theme.mono).foregroundStyle(Theme.text2) })
        }
        if let framework = server.project.framework {
            rows.append(InfoRow(label: L10n.text("Framework"), tooltip: framework) { Text(framework).font(Theme.body).foregroundStyle(Theme.text2) })
        }
        if let command = server.command {
            rows.append(InfoRow(label: L10n.text("Command"), tooltip: command) { Text(command).font(Theme.mono).foregroundStyle(Theme.text2) })
        }
        if let started = server.startedAt {
            rows.append(InfoRow(label: L10n.text("Started")) { Text(L10n.time(started)).font(Theme.mono).foregroundStyle(Theme.text2) })
        }
        if let pr = github.result(for: server)?.pullRequest {
            rows.append(InfoRow(label: L10n.text("Pull request"), tooltip: "#\(pr.number) \(pr.title)") {
                Link(destination: pr.url) {
                    HStack(spacing: 6) {
                        Text("#\(pr.number)").font(Theme.mono).foregroundStyle(Theme.text1)
                        Text(pr.title).font(Theme.body).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.tail)
                        Text(L10n.text(pr.state)).font(Theme.caption).foregroundStyle(Theme.text3).fixedSize()
                    }
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { Usage.record(.pullRequest) })
            })
        }
        if let agent = server.agent {
            rows.append(InfoRow(label: L10n.text("Session ID"), tooltip: agent.id) { Text(agent.id).font(Theme.mono).foregroundStyle(Theme.text2) })
        }
        if !server.addresses.isEmpty {
            let addresses = server.addresses.joined(separator: " · ")
            rows.append(InfoRow(label: L10n.text("Address"), tooltip: addresses) { Text(addresses).font(Theme.mono).foregroundStyle(Theme.text2) })
        }
        return rows
    }

    // MARK: - Charts

    private var charts: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            MemoryChart(server: server, threshold: monitor.alertThreshold, color: color, hoverTime: $hoverTime)
            CPUChart(server: server, color: color, hoverTime: $hoverTime)
        }
        .environment(\.layoutDirection, .leftToRight)
        .padding(EdgeInsets(top: 14, leading: Theme.inset, bottom: Theme.Space.m, trailing: Theme.inset))
    }

    // MARK: - Processes

    private var processes: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Button {
                withAnimation(Theme.Motion.state(reduceMotion: reduceMotion)) { processesExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Eyebrow(L10n.text("Processes"))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.text3)
                        .rotationEffect(.degrees(processesExpanded ? 90 : 0))
                        .flipsForRightToLeftLayoutDirection(true)
                    Spacer()
                    HStack(spacing: 6) {
                        Text(String(server.processes.count)).font(Theme.monoMedium).foregroundStyle(Theme.text2)
                        Text("·").font(Theme.mono).foregroundStyle(Theme.text3)
                        Amount(value: Format.bytes(server.memory))
                    }
                }
                .frame(minHeight: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if processesExpanded {
                let largest = max(server.processes.map(\.memory).max() ?? 1, 1)
                VStack(spacing: 6) {
                    ForEach(server.processes) { process in
                        let isListener = process.pid == server.pid
                        HStack(spacing: 0) {
                            Text((process.depth > 0 ? String(repeating: "  ", count: process.depth - 1) + "└ " : "") + process.name)
                                .font(isListener ? Theme.monoMedium : Theme.mono)
                                .foregroundStyle(isListener ? Theme.text1 : Theme.text2)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(process.name)
                            Spacer(minLength: 8)
                            Text(String(process.pid)).font(Theme.monoCaption).foregroundStyle(Theme.text3).frame(width: 52, alignment: .leading)
                            // The listener carries the port's colour; its children stay neutral.
                            Capsule().fill(Theme.memoryTrack).frame(width: 64, height: 4)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(isListener ? color : Theme.text3)
                                        .frame(width: max(64 * CGFloat(process.memory) / CGFloat(largest), 3), height: 4)
                                }
                            Amount(value: Format.bytes(process.memory), font: Theme.mono, color: Theme.text1)
                                .frame(width: 70, alignment: .trailing)
                        }
                        .environment(\.layoutDirection, .leftToRight)
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .padding(EdgeInsets(top: Theme.Space.s, leading: Theme.inset, bottom: Theme.Space.s, trailing: Theme.inset))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                Usage.record(.openBrowser)
                AutopilotController.shared.resume(port: server.port)
                NSWorkspace.shared.open(server.url)
            } label: {
                HStack(spacing: 6) {
                    Text(L10n.format("Open localhost:%@", String(server.port)))
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle(kind: .primary))
            .keyboardShortcut(.defaultAction)

            if let preview = github.result(for: server)?.preview {
                Button {
                    Usage.record(.vercelPreview)
                    NSWorkspace.shared.open(preview.url)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "triangle.fill").font(.system(size: 9))
                        Text(preview.state == .building ? L10n.text("Building") : L10n.text("Preview"))
                    }
                    .foregroundStyle(preview.state == .failed ? Theme.softRed : Theme.text1)
                }
                .buttonStyle(PillButtonStyle())
                .help(preview.state == .failed ? L10n.format("Preview build failed · %@", preview.url.host ?? "") : preview.url.absoluteString)
            }

            Menu {
                Button(L10n.text("Copy URL")) { copy(server.url.absoluteString) }
                if let command = server.command { Button(L10n.text("Copy command")) { copy(command) } }
                Divider()
                if let root = server.project.root ?? server.cwd, server.cwdExists {
                    Button(L10n.text("Open in editor")) {
                        Usage.record(.openEditor)
                        EditorLauncher.open(root)
                    }
                    Button(L10n.text("Reveal in Finder")) { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: root) }
                }
                Divider()
                if server.kind == .ai {
                    Button(L10n.text("Unload idle models")) {
                        let client = KalonClient(baseURL: server.url)
                        let cpu = server.cpu
                        Task {
                            _ = await client.unloadIdlePoolModels(processCPU: cpu)
                            if let status = await client.status() { kalon = (status, await client.loadedModels().count) }
                        }
                    }
                } else {
                    Toggle(L10n.text("Keep running"), isOn: keepRunning)
                }
            } label: {
                MoreLabel()
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L10n.text("More actions"))
            .accessibilityLabel(L10n.text("More actions"))
        }
        .padding(Theme.Space.s)
    }

    /// Autopilot never pauses or stops a pinned port.
    private var keepRunning: Binding<Bool> {
        let port = server.port
        return Binding {
            ((UserDefaults.standard.array(forKey: Preferences.autopilotPinned) as? [Int]) ?? []).contains(port)
        } set: { pinned in
            var ports = Set((UserDefaults.standard.array(forKey: Preferences.autopilotPinned) as? [Int]) ?? [])
            if pinned { ports.insert(port) } else { ports.remove(port) }
            UserDefaults.standard.set(ports.sorted(), forKey: Preferences.autopilotPinned)
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

/// The ⋯ menu's button: an outlined square the height of the buttons beside it.
private struct MoreLabel: View {
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        Image(systemName: "ellipsis")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.text1)
            .frame(width: Theme.controlHeight, height: Theme.controlHeight)
            .background(isHovered ? Theme.hover : .clear, in: shape)
            .overlay(shape.strokeBorder(Theme.outline, lineWidth: 1))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

// MARK: - Info rows

struct InfoRow: View {
    let label: String
    let tooltip: String?
    let value: AnyView

    /// `tooltip` shows the whole value on hover, for anything that can truncate.
    init<V: View>(label: String, tooltip: String? = nil, @ViewBuilder value: () -> V) {
        self.label = label
        self.tooltip = tooltip
        self.value = AnyView(value())
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(Theme.caption).foregroundStyle(Theme.text3)
                .frame(width: L10n.language == .english ? 64 : 90, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            value.lineLimit(1).truncationMode(.middle)
                .environment(\.layoutDirection, .leftToRight)
                .help(tooltip ?? "")
            Spacer(minLength: 0)
        }
        .frame(minHeight: 28)
    }
}

/// The session title, which opens a menu to resume it, reveal it or copy its ID.
struct SessionValue: View {
    let session: AgentSession
    let server: Server

    var body: some View {
        Menu {
            Section("\(session.kind.rawValue)\(session.startedAt.map { L10n.format(" · started %@", L10n.time($0)) } ?? "")") {
                if let workspace = server.conductorWorkspace {
                    Button(L10n.format("Reveal %@ workspace", workspace)) {
                        if let path = server.project.root ?? server.cwd { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) }
                    }
                }
                Button(L10n.format("Resume in %@", TerminalLauncher.current.name)) {
                    Usage.record(.resumeSession)
                    SessionLauncher.resume(session, fallbackDirectory: server.cwd)
                }
                if let transcript = session.transcript {
                    Button(L10n.text("Show transcript")) { NSWorkspace.shared.selectFile(transcript.path, inFileViewerRootedAtPath: "") }
                }
                Divider()
                Button(L10n.text("Copy session ID")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.id, forType: .string)
                }
            }
        } label: {
            HStack(spacing: 6) {
                AgentGlyph(kind: session.kind)
                Text(session.title ?? session.kind.rawValue)
                    .font(Theme.body)
                    .foregroundStyle(Theme.text1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.text3)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

// MARK: - Charts

struct MemoryChart: View {
    let server: Server
    let threshold: UInt64
    var color: Color = Theme.text1
    @Binding var hoverTime: Date?

    var body: some View {
        let values = server.history.map { (time: $0.time, gb: Double($0.memory) / Format.gigabyte) }
        let thresholdGB = Double(threshold) / Format.gigabyte
        let top = max(thresholdGB, (values.map(\.gb).max() ?? 0) * 1.1)
        let hovered = ChartHover.sample(in: server.history, near: hoverTime)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                Eyebrow(L10n.text("Memory"))
                Amount(value: Format.bytes(hovered?.memory ?? server.memory))
                Spacer()
                Text(hovered.map { ChartHover.timestamp($0.time) } ?? L10n.text("10 min"))
                    .font(Theme.monoCaption)
                    .foregroundStyle(hovered == nil ? Theme.text3 : Theme.text2)
            }
            Chart {
                RuleMark(y: .value(L10n.text("Alert"), thresholdGB))
                    .foregroundStyle(Theme.amber.opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    AreaMark(x: .value(L10n.text("Time"), value.time), y: .value("GB", value.gb))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.24), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value(L10n.text("Time"), value.time), y: .value("GB", value.gb))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if let hovered {
                    RuleMark(x: .value(L10n.text("Time"), hovered.time))
                        .foregroundStyle(Theme.text1.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value(L10n.text("Time"), hovered.time), y: .value("GB", Double(hovered.memory) / Format.gigabyte))
                        .foregroundStyle(color)
                        .symbolSize(36)
                } else if let last = values.last {
                    PointMark(x: .value(L10n.text("Time"), last.time), y: .value("GB", last.gb))
                        .foregroundStyle(color)
                        .symbolSize(28)
                }
            }
            .chartXScale(domain: Date().addingTimeInterval(-ScanEngine.historyWindow)...Date())
            .chartYScale(domain: 0...top)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, thresholdGB]) { value in
                    AxisValueLabel {
                        if let gb = value.as(Double.self) {
                            Text(gb == 0 ? "0" : "\(Format.trim(gb)) GB")
                                .font(Theme.monoCaption)
                                .foregroundStyle(gb == 0 ? Theme.text3 : Theme.amber)
                        }
                    }
                }
            }
            .chartPlotStyle(content: ChartHover.axes)
            .chartOverlay { ChartHover.overlay(proxy: $0, hoverTime: $hoverTime) }
            .frame(height: ChartHover.height)
        }
    }
}

struct CPUChart: View {
    let server: Server
    var color: Color = Theme.text1
    @Binding var hoverTime: Date?

    var body: some View {
        let samples = server.history
        let hovered = ChartHover.sample(in: samples, near: hoverTime)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                Eyebrow("CPU")
                Text(Format.percent(hovered?.cpu ?? server.cpu)).font(Theme.monoMedium).foregroundStyle(Theme.text1)
                    .contentTransition(.numericText())
                Spacer()
                if let hovered {
                    Text(ChartHover.timestamp(hovered.time)).font(Theme.monoCaption).foregroundStyle(Theme.text2)
                }
            }
            Chart {
                ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                    let isHighlighted = hovered.map { $0.time == sample.time } ?? (index == samples.count - 1)
                    BarMark(x: .value(L10n.text("Time"), sample.time, unit: .second), y: .value("CPU", min(sample.cpu, 100)), width: .fixed(3))
                        .foregroundStyle(color.opacity(isHighlighted ? 1 : 0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 1))
                }
                if let hovered {
                    RuleMark(x: .value(L10n.text("Time"), hovered.time, unit: .second))
                        .foregroundStyle(Theme.text1.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXScale(domain: Date().addingTimeInterval(-ScanEngine.historyWindow)...Date())
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 100]) { value in
                    AxisValueLabel {
                        if let percent = value.as(Double.self) {
                            Text(percent == 0 ? "0" : "100%").font(Theme.monoCaption).foregroundStyle(Theme.text3)
                        }
                    }
                }
            }
            .chartPlotStyle(content: ChartHover.axes)
            .chartOverlay { ChartHover.overlay(proxy: $0, hoverTime: $hoverTime) }
            .frame(height: ChartHover.height)
        }
    }
}

enum ChartHover {
    static let height: CGFloat = 60

    /// The plot's left and bottom axis lines.
    static func axes(_ plot: ChartPlotContent) -> some View {
        plot.overlay(alignment: .leading) { Rectangle().fill(Theme.outline).frame(width: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.outline).frame(height: 1) }
    }

    /// A transparent layer that turns the pointer's position into a time on the x axis.
    static func overlay(proxy: ChartProxy, hoverTime: Binding<Date?>) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard let plotFrame = proxy.plotFrame else { return }
                        hoverTime.wrappedValue = proxy.value(atX: location.x - geometry[plotFrame].origin.x, as: Date.self)
                    case .ended:
                        hoverTime.wrappedValue = nil
                    }
                }
        }
    }

    static func sample(in history: [Sample], near time: Date?) -> Sample? {
        guard let time, !history.isEmpty else { return nil }
        return history.min { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) }
    }

    static func timestamp(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }
}
