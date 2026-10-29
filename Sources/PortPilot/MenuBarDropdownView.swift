import SwiftUI

/// A compact front door for every direction. Effects remain in the full inspector.
struct MenuBarDropdownView: View {
    @ObservedObject var viewModel: PortViewModel
    @ObservedObject private var settings = AppSettings.shared
    let onOpenMainWindow: () -> Void
    let onQuit: () -> Void
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void
    let onSponsors: () -> Void
    @State private var search = ""
    @State private var pane: MainTab = .ports
    @State private var protocolFilter = "All"

    private var direction: VisualTheme { settings.visualTheme }
    private func interfaceFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design? = nil) -> Font {
        PortPilotTypography.font(direction: direction, size: size, weight: weight, design: design)
    }

    private var ports: [PortProcess] {
        viewModel.ports.filter { port in
            (protocolFilter == "All" || port.protocolName.uppercased() == protocolFilter) &&
            (search.isEmpty || "\(port.command) \(port.port) \(port.pid) \(port.user) \(port.protocolName)".localizedCaseInsensitiveContains(search))
        }
    }
    private var focused: PortProcess? { ports.first { $0.id == viewModel.selectedPort?.id } ?? ports.first }
    private var featuresSelection: Bool { direction == .focus || direction == .play || direction == .orbit }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let error = viewModel.errorMessage {
                HStack { Image(systemName: "exclamationmark.triangle"); Text(error).lineLimit(3); Spacer(); Button { viewModel.dismissError() } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss error") }
                    .font(interfaceFont(size: 10)).foregroundStyle(Theme.Status.error).padding(12).background(Theme.Status.error.opacity(0.1))
            }
            searchField
            tabs
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if pane == .ports { listeners }
                    else if pane == .security { MenuObservationSummary(monitor: viewModel.threatMonitor, onOpen: { open(.security) }) }
                    else { scheduleSummary }
                }.padding(.horizontal, 17).padding(.vertical, 12)
            }.frame(maxHeight: .infinity)
            if pane == .ports, let port = focused {
                if !featuresSelection { selectionShelf(port) }
                ProcessQuickActions(port: port, viewModel: viewModel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 19).padding(.vertical, 10)
            }
            if let message = viewModel.successMessage {
                Text(message).font(interfaceFont(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 19).padding(.bottom, 6)
            }
            footer
        }
        .font(interfaceFont(size: 11))
        .frame(width: Theme.Liquid.panelWidth, height: Theme.Liquid.panelHeight)
        .background(Theme.Surface.windowBackground)
        .tint(Theme.paletteAccent)
        .onChange(of: pane) { value in if value == .schedules { viewModel.refreshCronjobs() } }
        .onReceive(NotificationCenter.default.publisher(for: .toggleDropdownTreeView)) { _ in open(.ports) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if direction == .shell { Text("❯_").font(interfaceFont(size: 25, design: .monospaced)).foregroundStyle(Theme.paletteAccent) }
            else { PortPilotPlug().stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)).frame(width: 23, height: 23).padding(9).background(Theme.paletteAccent.opacity(0.13), in: RoundedRectangle(cornerRadius: direction.radius)).foregroundStyle(Theme.paletteAccent) }
            VStack(alignment: .leading, spacing: 5) {
                PortPilotIdentity(compact: true)
                Text(direction == .play ? "Hey, local host." : direction == .orbit ? "Your local observatory." : direction == .shell ? "interactive / local" : direction.rawValue + " / local session")
                    .font(interfaceFont(size: 9)).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Picker("Interface", selection: $settings.visualTheme) { ForEach(VisualTheme.allCases) { Text("\($0.number) / \($0.rawValue)").tag($0) } }
                Divider()
                Button("Settings") { onDismiss(); onOpenSettings() }
                Button("Support PortPilot") { onDismiss(); onSponsors() }
                Divider()
                Button("Quit PortPilot", action: onQuit)
            } label: { Image(systemName: "ellipsis").frame(width: 26, height: 26) }
            .menuStyle(.borderlessButton).frame(width: 26).help("Interface, settings, and app actions")
            VStack(spacing: 1) { Text("\(viewModel.ports.count)").font(interfaceFont(size: 25, weight: .light)); Text("TRACKED").font(interfaceFont(size: 9, design: .monospaced)).tracking(1) }.foregroundStyle(Theme.paletteAccent)
        }.padding(.horizontal, 19).padding(.top, 21).padding(.bottom, 17)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find a port, PID, or process…", text: $search).textFieldStyle(.plain).font(interfaceFont(size: 11))
                .accessibilityLabel("Search listeners")
            if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search") }
        }.padding(10).background(Theme.Surface.controlBackground, in: RoundedRectangle(cornerRadius: direction.radius))
            .overlay(RoundedRectangle(cornerRadius: direction.radius).strokeBorder(Color.secondary.opacity(0.18))).padding(.horizontal, 17).padding(.bottom, 12)
    }

    private var tabs: some View {
        HStack(spacing: 5) {
            tab("Listeners", count: viewModel.ports.count, target: .ports)
            MenuObservationTab(monitor: viewModel.threatMonitor, selected: pane == .security) { pane = .security }
            tab("Schedules", count: nil, target: .schedules)
        }.padding(.horizontal, 17).padding(.bottom, 10)
            .overlay(alignment: .bottom) { Divider().padding(.horizontal, 17) }
    }
    private func tab(_ name: String, count: Int?, target: MainTab) -> some View {
        Button { pane = target } label: {
            HStack(spacing: 5) { Text(name); if let count { Text("\(count)").opacity(0.65) } }
                .font(interfaceFont(size: 10, weight: pane == target ? .semibold : .regular))
                .padding(.vertical, 7).padding(.horizontal, 8).frame(maxWidth: .infinity)
                .foregroundStyle(pane == target ? Theme.paletteAccent : .secondary)
                .background(pane == target ? Theme.paletteAccent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: direction.radius))
        }.buttonStyle(.plain).accessibilityAddTraits(pane == target ? .isSelected : [])
    }

    @ViewBuilder private var listeners: some View {
        HStack {
            Text(direction == .shell ? "❯ pp ports" : "\(ports.count) shown").font(interfaceFont(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            Spacer()
            Picker("Protocol", selection: $protocolFilter) { ForEach(["All", "TCP", "UDP", "UNIX"], id: \.self) { Text($0).tag($0) } }
                .labelsHidden().frame(width: 90).controlSize(.mini).accessibilityLabel("Listener protocol")
        }
        if ports.isEmpty {
            VStack(spacing: 10) {
                Text(search.isEmpty ? (viewModel.isLoading ? "Reading listeners…" : viewModel.lastRefresh == nil ? "No completed snapshot yet." : "No listeners in this view.") : "No matching listeners.")
                if !search.isEmpty || protocolFilter != "All" { Button("Clear search and filter") { search = ""; protocolFilter = "All" } }
            }.font(interfaceFont(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 36)
        } else {
            if featuresSelection && search.isEmpty, let port = focused { featured(port) }
            if direction == .fieldwork {
                ForEach(Array(Dictionary(grouping: ports, by: groupName).keys).sorted(), id: \.self) { group in
                    Text(group).font(interfaceFont(size: 17, design: .serif)).padding(.top, 8)
                    ForEach(ports.filter { groupName($0) == group }.prefix(6)) { row($0) }
                }
            } else {
                ForEach(Array(ports.filter { !featuresSelection || !search.isEmpty || $0.id != focused?.id }.prefix(8))) { row($0) }
            }
            Button("All \(ports.count) matching listeners →") { open(.ports) }.font(interfaceFont(size: 10)).foregroundStyle(Theme.paletteAccent).padding(.vertical, 6)
        }
    }
    private func groupName(_ port: PortProcess) -> String {
        if let repo = port.gitRepo, !repo.isEmpty { return URL(fileURLWithPath: repo).lastPathComponent }
        return "Other listeners"
    }
    private func row(_ port: PortProcess) -> some View {
        Button { viewModel.selectedPort = port } label: {
            HStack(spacing: 11) {
                if direction == .shell || direction == .relay || direction == .instrument {
                    Text(port.isUnixSocket ? "UNIX" : "\(port.port)").font(interfaceFont(size: 12, weight: .medium, design: .monospaced)).frame(width: 48, alignment: .leading).foregroundStyle(Theme.paletteAccent)
                } else {
                    PortPilotPlug().stroke(lineWidth: 1.4).frame(width: 17, height: 17).padding(7).background(Theme.paletteAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(Theme.paletteAccent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(port.command).font(interfaceFont(size: 11, weight: .medium)).lineLimit(1)
                    Text("\(port.isUnixSocket ? "UNIX" : ":\(port.port)") · \(port.protocolName.uppercased()) · PID \(port.pid)")
                        .font(interfaceFont(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                if port.isStopped { Image(systemName: "pause.circle").foregroundStyle(Theme.Status.warning) }
                Image(systemName: "chevron.right").font(interfaceFont(size: 9)).foregroundStyle(.secondary)
            }.padding(.horizontal, 9).padding(.vertical, direction == .relay ? 7 : 10).contentShape(Rectangle())
                .background(viewModel.selectedPort?.id == port.id ? Theme.paletteAccent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: direction.radius))
        }.buttonStyle(.plain).accessibilityLabel("Select \(port.command), port \(port.port), PID \(port.pid)")
            .accessibilityAddTraits(viewModel.selectedPort?.id == port.id ? .isSelected : [])
    }
    private func featured(_ port: PortProcess) -> some View {
        Button { inspect(port) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("IN FOCUS").tracking(1.4); Spacer(); Text(port.protocolName.uppercased()) }.font(interfaceFont(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                HStack { Text(port.isUnixSocket ? "UNIX" : ":\(port.port)").font(interfaceFont(size: direction == .orbit ? 46 : 35, weight: .light)).tracking(-1.5); Spacer(); Image(systemName: "arrow.up.right").font(interfaceFont(size: 19, weight: .light)) }.foregroundStyle(Theme.paletteAccent)
                Text(port.command).font(interfaceFont(size: 12, weight: .semibold)).lineLimit(1)
                Text("PID \(port.pid) · \(port.user)").font(interfaceFont(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(18).background(Theme.paletteAccent.opacity(direction == .orbit ? 0.10 : 0.08), in: RoundedRectangle(cornerRadius: direction.radius))
                .overlay(RoundedRectangle(cornerRadius: direction.radius).strokeBorder(Theme.paletteAccent.opacity(0.35)))
                .overlay(alignment: .trailing) {
                    if direction == .orbit { Circle().stroke(Theme.paletteAccent.opacity(0.10)).frame(width: 145, height: 145).offset(x: 35, y: 15).allowsHitTesting(false) }
                }.clipShape(RoundedRectangle(cornerRadius: direction.radius))
        }.buttonStyle(.plain).accessibilityLabel("Inspect \(port.command) on port \(port.port)")
    }
    private func selectionShelf(_ port: PortProcess) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) { Text("SELECTED / \(port.isUnixSocket ? "UNIX" : ":\(port.port)")").font(interfaceFont(size: 9, design: .monospaced)).foregroundStyle(.secondary); Text(port.command).font(interfaceFont(size: 11, weight: .semibold)).lineLimit(1) }
            Spacer(); Button("Inspect →") { inspect(port) }.buttonStyle(.bordered).controlSize(.small)
        }.padding(.horizontal, 19).padding(.vertical, 13).background(Theme.Surface.chromeTint).overlay(alignment: .top) { Divider() }
    }
    private var scheduleSummary: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Schedules").font(interfaceFont(size: 23))
            if viewModel.isLoadingCronjobs { ProgressView("Reading schedules…") }
            else if let error = viewModel.cronDiscoveryError {
                Label("Schedule scan incomplete", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.Severity.warning)
                Text(error).foregroundStyle(.secondary).lineLimit(3)
                if !viewModel.cronjobs.isEmpty {
                    Text("Showing \(viewModel.cronjobs.count) entries from the last successful read.")
                        .foregroundStyle(.secondary)
                }
            }
            else {
                Text("\(viewModel.cronjobs.count) entries in the latest user crontab read.")
                Text("Review commands, run history, and output in the workspace. Run Now executes code with your user authority.").foregroundStyle(.secondary)
            }
            Button("Open schedules →") { open(.schedules) }.buttonStyle(.borderedProminent)
        }.font(interfaceFont(size: 11)).padding(.vertical, 8)
    }
    private var footer: some View {
        VStack(spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    MenuMonitorHeadline(monitor: viewModel.threatMonitor)
                    Text(viewModel.lastRefresh.map { "Last successful port scan: " + $0.formatted(date: .omitted, time: .standard) } ?? "Port snapshot pending")
                        .font(interfaceFont(size: 9)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { viewModel.refreshPorts(); viewModel.refreshAllConnections() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Refresh local observations")
            }
            Divider()
            HStack {
                Button { open(pane) } label: { HStack { Text("Open workspace"); Image(systemName: "arrow.right") } }.buttonStyle(.plain).foregroundStyle(Theme.paletteAccent)
                Spacer(); Text("⌘O").font(interfaceFont(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                Button { onDismiss(); onOpenSettings() } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Settings")
            }.font(interfaceFont(size: 11, weight: .medium))
            HStack {
                PortPilotFooterLinks(onSupport: { onDismiss(); onSponsors() })
                Spacer()
            }.padding(.top, 3)
        }.padding(.horizontal, 19).padding(.vertical, 13).background(Theme.Surface.chromeTint).overlay(alignment: .top) { Divider() }
    }
    private func inspect(_ port: PortProcess) { viewModel.selectedPort = port; open(.ports) }
    private func open(_ tab: MainTab) {
        onDismiss()
        NotificationCenter.default.post(name: .openMainWindow, object: tab)
    }
}

private struct MenuObservationTab: View {
    @ObservedObject var monitor: ThreatMonitorStore
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("Observations \(monitor.findings.count)").font(.system(size: 9, weight: selected ? .semibold : .regular))
                .padding(.vertical, 7).padding(.horizontal, 7).frame(maxWidth: .infinity)
                .foregroundStyle(selected ? Theme.paletteAccent : .secondary)
                .background(selected ? Theme.paletteAccent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: AppSettings.shared.visualTheme.radius))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
private struct MenuMonitorHeadline: View {
    @ObservedObject var monitor: ThreatMonitorStore
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(monitor.chromePresentation.chromeColor).frame(width: 4, height: 4)
            Text(monitor.chromePresentation.headline).font(.system(size: 9))
        }
    }
}
private struct MenuObservationSummary: View {
    @ObservedObject var monitor: ThreatMonitorStore
    let onOpen: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Observations").font(.system(size: 23, weight: .medium))
            Text(monitor.chromePresentation.headline).font(.system(size: 11)).foregroundStyle(monitor.chromePresentation.chromeColor)
            Text("Heuristics, not malware verdicts. Periodic, permission-limited connection snapshots.").font(.system(size: 10)).foregroundStyle(.secondary)
            ForEach(monitor.findings.prefix(5)) { finding in
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Image(systemName: Theme.Severity.icon(for: finding.severity)).foregroundStyle(Theme.Severity.color(for: finding.severity)); Text(finding.processName).font(.system(size: 12, weight: .semibold)); Spacer(); Text("PID \(finding.pid)").font(.system(size: 9, design: .monospaced)) }
                    if let signal = finding.signals.first { Text(signal.summary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(3) }
                }.padding(12).background(Theme.Surface.controlBackground, in: RoundedRectangle(cornerRadius: 10))
            }
            Button("Review in Security Center →", action: onOpen).buttonStyle(.borderedProminent)
        }.padding(.vertical, 8)
    }
}
