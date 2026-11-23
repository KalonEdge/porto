import SwiftUI

/// The popover's main page: the whole Mac's memory, then one row per server.
/// Clean up is a mode of this page: checkboxes slide in and the footer turns into Cancel and Stop.
struct ServersView: View {
    @ObservedObject var monitor: ServerMonitor
    let openServer: (Server) -> Void
    let openSettings: () -> Void

    private let maxVisibleRows = 7
    /// The memory-bar segment under the pointer.
    @State private var focus: BarFocus?
    /// The row under the pointer, which lights up its bar segment without changing the header.
    @State private var hoveredRow: Int?
    @State private var isCleaning: Bool
    @State private var selection: Set<Int>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(monitor: ServerMonitor, startCleaning: Bool = false, openServer: @escaping (Server) -> Void, openSettings: @escaping () -> Void) {
        self.monitor = monitor
        self.openServer = openServer
        self.openSettings = openSettings
        _isCleaning = State(initialValue: startCleaning)
        _selection = State(initialValue: startCleaning ? monitor.suggestedCleanUp : [])
    }

    private var focusedPort: Int? {
        if case .server(let port) = focus { return port }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            summary
            SectionDivider()
            if visibleServers.isEmpty {
                emptyState
            } else if visibleServers.count > maxVisibleRows {
                ScrollView { rows }.frame(height: CGFloat(maxVisibleRows) * ServerRow.height + 12)
            } else {
                rows
            }
            SectionDivider()
            footer
        }
    }

    /// Protected processes (databases) can't be stopped from Clean up, so they aren't listed there.
    private var visibleServers: [Server] {
        isCleaning ? monitor.servers.filter { !$0.isProtected } : monitor.servers
    }

    private var selectedServers: [Server] { visibleServers.filter { selection.contains($0.port) } }

    // MARK: - Summary

    /// Two readings side by side, each a quiet label over a number: memory on
    /// the leading edge, CPU on the trailing one. Then where the Mac's memory goes.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Theme.Space.xs) {
                summaryTitle
                Spacer(minLength: Theme.Space.xs)
                if focus == nil, !isCleaning { CPUToggle(monitor: monitor, part: .label) }
            }
            .frame(height: 16)
            HStack(alignment: .lastTextBaseline, spacing: Theme.Space.xs) {
                Amount(value: summaryAmount, font: Theme.hero, unitFont: Theme.mono, spacing: 5)
                Spacer(minLength: Theme.Space.xs)
                summaryDetail
            }
            .padding(.top, 2)
            MemoryShareBar(servers: visibleServers, monitor: monitor, focus: $focus, highlightedPort: hoveredRow,
                           selection: isCleaning ? selection : nil) { server in
                if isCleaning { toggle(server.port) } else { openServer(server) }
            }
            .frame(height: 18)
            .padding(.top, Theme.Space.s)
            MemoryLegend(monitor: monitor)
                .padding(.top, Theme.Space.xs)
        }
        .padding(EdgeInsets(top: 14, leading: Theme.inset, bottom: 14, trailing: Theme.inset))
    }

    /// What the big number is: the page, or whatever bar segment is under the pointer.
    @ViewBuilder private var summaryTitle: some View {
        switch focus {
        case .server(let port):
            HStack(spacing: 6) {
                Text(":" + String(port)).font(Theme.monoCaptionMedium)
                    .foregroundStyle(Theme.portColor(at: monitor.colorIndex(for: port)))
                    .environment(\.layoutDirection, .leftToRight)
                Text(monitor.server(port: port)?.project.name ?? L10n.text("Servers"))
                    .font(Theme.captionMedium).foregroundStyle(Theme.text2).lineLimit(1)
            }
        case .app(let id):
            let app = monitor.otherApps.first { $0.id == id }
            HStack(spacing: 6) {
                if let path = app?.bundlePath {
                    Image(nsImage: AppIcons.icon(for: path)).resizable().frame(width: 14, height: 14)
                } else if let agent = app?.agent {
                    AgentGlyph(kind: agent, size: 11, color: Theme.text1)
                } else {
                    Image(systemName: "terminal").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.text2)
                }
                Text(app?.name ?? L10n.text("App")).font(Theme.captionMedium).foregroundStyle(Theme.text2).lineLimit(1)
            }
        case .rest:
            HStack(spacing: 6) {
                Image(systemName: "macbook").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.text2)
                Text(L10n.text("Everything else")).font(Theme.captionMedium).foregroundStyle(Theme.text2)
            }
        case nil:
            HStack(spacing: 6) {
                Eyebrow(isCleaning ? L10n.text("Clean up") : L10n.text("Servers"))
                if !isCleaning, !monitor.servers.isEmpty {
                    Text(String(monitor.servers.count)).font(Theme.monoCaptionMedium).foregroundStyle(Theme.text2)
                        .contentTransition(.numericText())
                }
            }
        }
    }

    private var summaryAmount: (number: String, unit: String) {
        switch focus {
        case .server(let port): return Format.bytes(monitor.server(port: port)?.memory ?? 0)
        case .app(let id): return Format.bytes(monitor.otherApps.first { $0.id == id }?.memory ?? 0)
        case .rest: return Format.total(MemoryBreakdown(monitor: monitor).everythingElse)
        case nil: return Format.total(isCleaning ? selectedServers.reduce(0) { $0 + $1.memory } : monitor.totalMemory)
        }
    }

    @ViewBuilder private var summaryDetail: some View {
        let ram = monitor.systemMemory?.total ?? 0
        switch focus {
        case .server(let port):
            if let server = monitor.server(port: port) {
                Text(L10n.format("%@ of RAM · CPU %@", share(server.memory, of: ram), Format.percent(server.cpu)))
                    .font(Theme.mono).foregroundStyle(Theme.text2)
            }
        case .app(let id):
            if let app = monitor.otherApps.first(where: { $0.id == id }) {
                Text(L10n.format("%@ of RAM", share(app.memory, of: ram))).font(Theme.mono).foregroundStyle(Theme.text2)
            }
        case .rest:
            Text(L10n.text("System and smaller apps")).font(Theme.body).foregroundStyle(Theme.text2)
        case nil:
            if isCleaning {
                Text(selection.isEmpty ? L10n.text("Pick servers to stop") : L10n.format("freed by stopping %d", selectedServers.count))
                    .font(Theme.body).foregroundStyle(Theme.text2)
            } else {
                CPUToggle(monitor: monitor, part: .value)
            }
        }
    }

    private func share(_ bytes: UInt64, of total: UInt64) -> String {
        Format.percent(Double(bytes) / Double(max(total, 1)) * 100)
    }

    private var rows: some View {
        // One column width for every row, wide enough for the longest port.
        let portWidth: CGFloat = visibleServers.contains { $0.port >= 10_000 } ? 66 : 58
        return VStack(spacing: 0) {
            ForEach(visibleServers) { server in
                ServerRow(server: server, monitor: monitor, portWidth: portWidth,
                          isFocused: focusedPort == server.port,
                          isDimmed: focus != nil && focusedPort != server.port,
                          cleaning: isCleaning ? CleaningState(isSelected: selection.contains(server.port), reason: monitor.cleanUpReason(for: server)) : nil,
                          onHover: { hovering in
                              if hovering { hoveredRow = server.port } else if hoveredRow == server.port { hoveredRow = nil }
                          },
                          open: { isCleaning ? toggle(server.port) : openServer(server) })
            }
        }
        .padding(6)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            DotGridView(glyph: .idle, size: 40)
            Text(monitor.hasScanned ? L10n.text("Nothing listening") : L10n.text("Scanning…"))
                .font(Theme.bodyMedium)
                .foregroundStyle(Theme.text1)
                .padding(.top, Theme.Space.m)
            Text(L10n.format("Dev servers on ports %@–%@ show up here.", String(monitor.minPort), String(monitor.maxPort)))
                .font(Theme.caption)
                .foregroundStyle(Theme.text3)
                .multilineTextAlignment(.center)
                .padding(.top, Theme.Space.xxs)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.inset)
        .padding(.vertical, 36)
    }

    // MARK: - Footer

    @ViewBuilder private var footer: some View {
        if isCleaning {
            HStack(spacing: Theme.Space.xs) {
                Button(L10n.text("Cancel")) { setCleaning(false) }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button {
                    Usage.record(.cleanUp)
                    selectedServers.forEach(monitor.stop)
                    setCleaning(false)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill").font(.system(size: 9, weight: .semibold))
                        Text(selection.isEmpty
                             ? L10n.text("Stop servers")
                             : L10n.format("Stop %d %@ · free %@", selectedServers.count, L10n.counted("server", "servers", count: selectedServers.count),
                                           Format.bytesString(selectedServers.reduce(0) { $0 + $1.memory })))
                            .contentTransition(.numericText())
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(kind: .destructive))
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
            }
            .padding(Theme.Space.s)
            .transition(.opacity)
        } else {
            HStack(spacing: Theme.Space.xs) {
                Button { setCleaning(true) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "paintbrush").font(.system(size: 11, weight: .medium))
                        Text(L10n.text("Clean up"))
                        let count = monitor.suggestedCleanUp.count
                        if count > 0 {
                            // How many servers Clean up would suggest stopping.
                            Text(String(count)).font(Theme.monoCaptionMedium).foregroundStyle(Theme.onPrimary)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Theme.text1, in: Capsule())
                        }
                    }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(monitor.servers.isEmpty)

                Spacer()

                IconButton(systemName: "gearshape", tint: Theme.text2, background: .clear, symbolSize: 14,
                           help: L10n.text("Settings"), action: openSettings)
                    .keyboardShortcut(",", modifiers: .command)
            }
            .padding(Theme.Space.s)
            .transition(.opacity)
        }
    }

    // MARK: - Clean up

    private func setCleaning(_ cleaning: Bool) {
        withAnimation(Theme.Motion.state(reduceMotion: reduceMotion)) {
            // Everything Clean up suggests, except leaking servers, which are usually still in use.
            selection = cleaning ? monitor.suggestedCleanUp : []
            isCleaning = cleaning
        }
    }

    private func toggle(_ port: Int) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.15)) {
            if selection.contains(port) { selection.remove(port) } else { selection.insert(port) }
        }
    }
}

/// One CPU reading at a time; click to switch between the servers and the whole Mac.
/// Drawn as two parts, so its label and its number sit on the summary's two rows.
private struct CPUToggle: View {
    enum Part { case label, value }
    @ObservedObject var monitor: ServerMonitor
    let part: Part
    @AppStorage(Preferences.cpuShowsAll) private var showsAll = false
    @State private var isHovered = false

    var body: some View {
        Button {
            showsAll.toggle()
        } label: {
            Group {
                switch part {
                case .label:
                    HStack(spacing: 4) {
                        Eyebrow(showsAll ? L10n.text("CPU (all)") : L10n.text("CPU (servers)"), color: isHovered ? Theme.text1 : Theme.text3)
                        Image(systemName: "arrow.left.arrow.right").font(.system(size: 7, weight: .bold))
                            .foregroundStyle(isHovered ? Theme.text1 : Theme.text3)
                    }
                case .value:
                    Text(Format.percent(showsAll ? (monitor.systemCPU ?? 0) : monitor.serversShareOfCPU))
                        .font(Theme.readout)
                        .foregroundStyle(Theme.text1)
                        .contentTransition(.numericText())
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(showsAll ? L10n.text("Whole Mac. Click for servers only.") : L10n.text("Dev servers, as a share of the whole Mac. Click for all."))
    }
}

// MARK: - Row

struct CleaningState {
    let isSelected: Bool
    let reason: CleanUpReason?
}

struct ServerRow: View {
    let server: Server
    @ObservedObject var monitor: ServerMonitor
    /// Shared by every row so the names line up.
    var portWidth: CGFloat = 58
    var isFocused = false
    var isDimmed = false
    /// Set while the page is in Clean up mode.
    var cleaning: CleaningState?
    var onHover: (Bool) -> Void = { _ in }
    let open: () -> Void
    @State private var isHovered = false
    @ObservedObject private var autopilot = AutopilotController.shared

    /// Every row is the same height, so the list reads as a table.
    static let height: CGFloat = 52

    var body: some View {
        let status = monitor.status(of: server)
        let isPaused = autopilot.isPaused(server)
        let attention = status == .attention && !isPaused
        let color = Theme.portColor(at: monitor.colorIndex(for: server.port))
        HStack(spacing: 0) {
            if let cleaning {
                Checkbox(isOn: cleaning.isSelected, isHovered: isHovered)
                    .padding(.trailing, Theme.Space.s)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            PortLabel(port: server.port, status: status, color: color)
                .frame(width: portWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(primaryName.replacingOccurrences(of: "-", with: " "))
                    .font(Theme.bodyMedium)
                    .foregroundStyle(Theme.text1)
                    .lineLimit(1)
                    .help(primaryName)
                if let reason = cleaning?.reason {
                    HStack(spacing: 4) {
                        Image(systemName: reason.symbol).font(.system(size: 9, weight: .semibold))
                        Text(reason.label).lineLimit(1)
                    }
                    .font(Theme.caption)
                    .foregroundStyle(reason.isLeak ? Theme.amber : Theme.text2)
                } else if isPaused {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.fill").font(.system(size: 8, weight: .semibold))
                        Text(L10n.text("Paused by Autopilot")).lineLimit(1)
                    }
                    .font(Theme.caption)
                    .foregroundStyle(Theme.text3)
                } else {
                    context(status: status)
                }
            }
            .padding(.trailing, 10)

            Spacer(minLength: 0)

            Group {
                if isHovered && cleaning == nil {
                    HStack(spacing: 2) {
                        IconButton(systemName: "arrow.up.right", background: .clear, size: 26, symbolSize: 11, help: L10n.text("Open in browser")) {
                            Usage.record(.openBrowser)
                            autopilot.resume(port: server.port)
                            NSWorkspace.shared.open(server.url)
                        }
                        IconButton(systemName: "stop.fill", tint: Theme.softRed, background: .clear, size: 26, symbolSize: 10, help: L10n.text("Stop")) {
                            Usage.record(.stop)
                            monitor.stop(server)
                        }
                    }
                } else {
                    // The port's own colour, amber once it needs attention.
                    Sparkline(values: server.history.map { Double($0.memory) },
                              color: attention ? Theme.amber : (isPaused ? Theme.text3 : color),
                              lineWidth: attention ? 1.5 : 1.25)
                        .frame(width: 40, height: 18)
                }
            }
            .frame(width: 54, height: 26, alignment: .trailing)

            Amount(value: Format.bytes(server.memory),
                   color: attention ? Theme.amber : (isPaused ? Theme.text3 : Theme.text1),
                   unitColor: attention ? Theme.amber : Theme.text3)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .opacity(isDimmed ? 0.35 : (status == .idle && !server.cwdExists ? 0.6 : 1))
        .hoverHighlight(isHovered || isFocused)
        .animation(Theme.Motion.quick, value: isDimmed)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Amber never travels alone: a warning mark and the words come with it.
    @ViewBuilder private func context(status: ServerStatus) -> some View {
        if status == .attention {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9, weight: .semibold))
                if server.isLeaking() {
                    Text(L10n.format("+%@ in %@", Format.bytesString(UInt64(server.memoryGrowth)), L10n.duration(historySpan))).lineLimit(1)
                } else {
                    Text(L10n.format("Over %@ GB", Format.trim(Double(monitor.alertThreshold) / Format.gigabyte))).lineLimit(1)
                }
            }
            .font(Theme.captionMedium)
            .foregroundStyle(Theme.amber)
        } else {
            HStack(spacing: 5) {
                if let agent = server.agent { AgentGlyph(kind: agent.kind, size: 10) }
                if server.cwdExists, server.project.branch != nil {
                    HStack(spacing: 3) {
                        Text(server.project.name.replacingOccurrences(of: "-", with: " "))
                            .lineLimit(1).truncationMode(.tail).help(server.project.name)
                        Text("· " + contextText).fixedSize()
                    }
                } else {
                    Text(contextText).lineLimit(1)
                }
            }
            .font(Theme.caption)
            .foregroundStyle(Theme.text2)
        }
    }

    private var primaryName: String { server.project.branch ?? server.project.name }

    /// Uptime or idle time, after the location when there's no branch.
    private var contextText: String {
        if !server.cwdExists { return L10n.format("Worktree deleted · idle %@", L10n.duration(server.idleFor, short: true)) }
        let time = server.idleFor > 60 * 60
            ? L10n.format("idle %@", L10n.duration(server.idleFor, short: true))
            : server.uptime.map { L10n.format("up %@", L10n.duration($0, short: true)) } ?? ""
        if server.project.branch != nil || server.kind == .ai { return time }
        return [server.locationLabel, time].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var historySpan: TimeInterval {
        guard let first = server.history.first, let last = server.history.last else { return 0 }
        return last.time.timeIntervalSince(first.time)
    }
}

extension CleanUpReason {
    var symbol: String {
        switch self {
        case .worktreeDeleted: return "folder.badge.minus"
        case .idle: return "clock"
        case .longRunning: return "calendar"
        case .leaking: return "chart.line.uptrend.xyaxis"
        }
    }

    var label: String {
        switch self {
        case .worktreeDeleted: return L10n.text("Worktree deleted")
        case .idle(let duration): return L10n.format("Idle %@ · no connections", L10n.duration(duration, short: true))
        case .longRunning(let duration): return L10n.format("Running for %@", L10n.duration(duration, short: true))
        case .leaking(let growth): return L10n.format("Leaking · +%@", Format.bytesString(growth))
        }
    }
}

// MARK: - Memory bar

enum BarFocus: Equatable {
    case server(Int)
    case app(String)
    case rest
}

/// The Mac's whole memory: each dev server a raised segment, then the biggest
/// other apps and "everything else" on a thin baseline, free memory as the empty
/// track. Every segment can be hovered.
struct MemoryShareBar: View {
    let servers: [Server]
    @ObservedObject var monitor: ServerMonitor
    @Binding var focus: BarFocus?
    /// A server whose row is hovered in the list.
    var highlightedPort: Int?
    /// In Clean up, selected servers stay bright and the rest dim.
    var selection: Set<Int>?
    let activate: (Server) -> Void

    private let spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let breakdown = MemoryBreakdown(monitor: monitor)
            let apps = breakdown.topApps
            let segments = servers.count + apps.count + (breakdown.everythingElse > 0 ? 1 : 0)
            let filled = breakdown.devServers + apps.reduce(0) { $0 + $1.memory } + breakdown.everythingElse
            let capacity = max(breakdown.total ?? filled, filled, 1)
            let unit = max(geometry.size.width - CGFloat(max(segments - 1, 0)) * spacing, 0) / CGFloat(capacity)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.memoryTrack)
                    .frame(height: 6)
                    .help(L10n.format("Free · %@", Format.bytesString(breakdown.free)))
                HStack(spacing: spacing) {
                    ForEach(servers) { server in
                        serverSegment(server, width: max(unit * CGFloat(server.memory), 4), height: geometry.size.height)
                    }
                    ForEach(apps) { app in
                        baselineSegment(.app(app.id), width: unit * CGFloat(app.memory), height: geometry.size.height,
                                        help: "\(app.name) · \(Format.bytesString(app.memory))")
                    }
                    if breakdown.everythingElse > 0 {
                        baselineSegment(.rest, width: unit * CGFloat(breakdown.everythingElse), height: geometry.size.height,
                                        help: L10n.format("Everything else · %@", Format.bytesString(breakdown.everythingElse)))
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .animation(Theme.Motion.quick, value: focus)
            .animation(Theme.Motion.quick, value: highlightedPort)
        }
    }

    private func serverSegment(_ server: Server, width: CGFloat, height: CGFloat) -> some View {
        let isFocused = focus == .server(server.port) || (focus == nil && highlightedPort == server.port)
        let isSelected = selection?.contains(server.port) ?? false
        let someoneFocused = focus != nil || highlightedPort != nil
        let isDimmed = (someoneFocused && !isFocused) || (selection != nil && !isSelected && !isFocused)
        return RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(Theme.portColor(at: monitor.colorIndex(for: server.port)))
            .frame(height: isFocused ? 16 : 12)
            .opacity(isDimmed ? 0.35 : 1)
            // A tall, invisible hit area, so thin segments are easy to hover.
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onHover { setFocus(.server(server.port), $0) }
            .onTapGesture {
                if selection == nil { focus = nil }
                activate(server)
            }
            .help("\(server.project.name) :\(String(server.port)) · \(Format.bytesString(server.memory))")
    }

    /// Other apps sit on the thin baseline; hovering one lifts and brightens it.
    private func baselineSegment(_ target: BarFocus, width: CGFloat, height: CGFloat, help: String) -> some View {
        let isFocused = focus == target
        return RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(isFocused ? Theme.text1.opacity(0.75) : Theme.memoryOther)
            .frame(height: isFocused ? 10 : 6)
            .opacity((focus != nil || highlightedPort != nil) && !isFocused ? 0.6 : 1)
            .frame(width: max(width, 1), height: height)
            .contentShape(Rectangle())
            .onHover { setFocus(target, $0) }
            .help(help)
    }

    private func setFocus(_ target: BarFocus, _ hovering: Bool) {
        if hovering { focus = target } else if focus == target { focus = nil }
    }
}

/// Where the Mac's memory goes: dev servers, the biggest other apps, the rest, and what's free.
struct MemoryBreakdown {
    let devServers: UInt64
    let otherApps: UInt64
    let free: UInt64
    let total: UInt64?
    /// Apps big enough for their own segment: at least 2% of RAM, at most eight.
    let topApps: [AppMemory]
    /// Used memory not covered by dev servers or top apps: the system and small apps.
    let everythingElse: UInt64

    @MainActor
    init(monitor: ServerMonitor) {
        devServers = monitor.totalMemory
        let used = monitor.systemMemory?.used ?? devServers
        otherApps = used > devServers ? used - devServers : 0
        free = monitor.systemMemory?.free ?? 0
        total = monitor.systemMemory?.total
        let minimum = UInt64(Double(total ?? 0) * 0.02)
        var budget = otherApps
        var picked: [AppMemory] = []
        for app in monitor.otherApps.prefix(8) where app.memory >= minimum && app.memory <= budget {
            picked.append(app)
            budget -= app.memory
        }
        topApps = picked
        everythingElse = budget
    }
}

/// Servers · Other apps · Free of the Mac's total, each keyed to its mark on the bar.
struct MemoryLegend: View {
    @ObservedObject var monitor: ServerMonitor

    var body: some View {
        let breakdown = MemoryBreakdown(monitor: monitor)
        HStack(spacing: Theme.Space.s) {
            item(label: L10n.text("Servers"), value: Format.totalString(breakdown.devServers)) { serverSwatch }
            item(label: L10n.text("Other apps"), value: Format.totalString(breakdown.otherApps)) {
                RoundedRectangle(cornerRadius: 1.5).fill(Theme.memoryOther).frame(width: 8, height: 5)
            }
            if let total = breakdown.total {
                item(label: L10n.text("Free"), value: L10n.format("%@ of %@", Format.total(breakdown.free).number, Format.totalString(total))) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Theme.memoryTrack)
                        .overlay(RoundedRectangle(cornerRadius: 1.5).strokeBorder(Theme.outline, lineWidth: 0.5))
                        .frame(width: 8, height: 5)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The servers' own colours in miniature, so the key matches the bar.
    private var serverSwatch: some View {
        let ports = monitor.servers.prefix(3).map(\.port)
        return HStack(spacing: 1) {
            if ports.isEmpty {
                RoundedRectangle(cornerRadius: 1).fill(Theme.text3).frame(width: 8, height: 9)
            } else {
                ForEach(ports, id: \.self) { port in
                    RoundedRectangle(cornerRadius: 1).fill(Theme.portColor(at: monitor.colorIndex(for: port)))
                        .frame(width: (8 - CGFloat(ports.count - 1)) / CGFloat(ports.count), height: 9)
                }
            }
        }
    }

    private func item<Swatch: View>(label: String, value: String, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: 5) {
            swatch()
            Text(label).font(Theme.caption).foregroundStyle(Theme.text3)
            Text(value).font(Theme.monoCaption).foregroundStyle(Theme.text2)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
