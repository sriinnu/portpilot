import SwiftUI
import AppKit

/// Seven native compositions over the same observed model and effect handlers.
struct DesignWorkspace<Inspector: View, Schedules: View>: View {
    @ObservedObject var viewModel: PortViewModel
    @ObservedObject private var settings = AppSettings.shared
    @Binding var selectedTab: MainTab
    let onKill: (PortProcess) -> Void
    let onPauseResume: (PortProcess) -> Void
    let onCommands: () -> Void
    @ViewBuilder let inspector: () -> Inspector
    @ViewBuilder let schedules: () -> Schedules
    @State private var showInspector = false
    @State private var orbitList = false
    @State private var shellInput = ""
    @State private var shellReceipt = "Type help. This prompt navigates PortPilot; it does not execute system commands."

    private var direction: VisualTheme { settings.visualTheme }
    private var ports: [PortProcess] { viewModel.filteredPorts }
    private var title: String {
        switch direction {
        case .instrument: return "Listening ports"
        case .relay: return "LISTENERS / LOCAL SESSION"
        case .fieldwork: return "Your working landscape."
        case .focus: return "A closer look."
        case .shell: return "Know what’s listening."
        case .play: return "A place for every port."
        case .orbit: return "Everything has a place."
        }
    }
    private var isRail: Bool { direction == .focus || direction == .orbit }
    private var isSidebar: Bool { direction == .instrument }
    private func interfaceFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design? = nil) -> Font {
        PortPilotTypography.font(direction: direction, size: size, weight: weight, design: design)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isSidebar && !isRail { topNavigation }
            HStack(spacing: 0) {
                if isSidebar { LiquidSidebar(viewModel: viewModel, selectedMainTab: $selectedTab) }
                if isRail { rail }
                VStack(spacing: 0) {
                    if selectedTab == .ports { portsWorkspace }
                    else if selectedTab == .security { SecurityCenterView() }
                    else { schedules() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if direction == .shell { commandPrompt }
            MainStatusBar(viewModel: viewModel)
        }
        .font(interfaceFont(size: 12))
        .background(Theme.Surface.windowBackground)
        .tint(Theme.paletteAccent)
        .sheet(isPresented: $showInspector) {
            VStack(spacing: 0) {
                HStack { PortPilotIdentity(); Spacer(); Button("Done") { showInspector = false }.keyboardShortcut(.cancelAction) }.padding()
                Divider()
                inspector()
            }
            .frame(width: 660, height: 650)
            .background(Theme.Surface.windowBackground)
        }
    }

    private var topNavigation: some View {
        HStack(spacing: 20) {
            PortPilotIdentity()
            if direction == .shell { Text("/ interactive").foregroundStyle(.secondary).font(interfaceFont(size: 10, design: .monospaced)) }
            Spacer()
            sectionButtons
            Spacer()
            directionPicker
            Button(action: onCommands) { Image(systemName: "command") }.help("Commands (⌘K)")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22).padding(.vertical, 15)
        .background(Theme.Surface.chromeTint)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var sectionButtons: some View {
        HStack(spacing: 5) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button { selectedTab = tab } label: {
                    Text(tab == .security ? "Observations" : tab.rawValue)
                        .font(interfaceFont(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(selectedTab == tab ? Theme.paletteAccent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: direction.radius))
                        .foregroundStyle(selectedTab == tab ? Theme.paletteAccent : .secondary)
                }
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
    }

    private var directionPicker: some View {
        Menu {
            Picker("Interface", selection: $settings.visualTheme) {
                ForEach(VisualTheme.allCases) { theme in Text("\(theme.number) / \(theme.rawValue)").tag(theme) }
            }
        } label: { Text("\(direction.number) / \(direction.rawValue)").font(interfaceFont(size: 10, design: .monospaced)) }
        .help("Choose one of seven interfaces")
    }

    private var rail: some View {
        VStack(spacing: 16) {
            PortPilotIdentity(compact: true).padding(.vertical, 10)
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button { selectedTab = tab } label: {
                    Image(systemName: tab == .ports ? "powerplug" : tab == .security ? "exclamationmark.bubble" : "clock")
                        .font(interfaceFont(size: 17)).frame(width: 38, height: 38)
                        .background(selectedTab == tab ? Theme.paletteAccent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 11))
                        .foregroundStyle(selectedTab == tab ? Theme.paletteAccent : .secondary)
                }
                .help(tab == .security ? "Observations" : tab.rawValue)
                .accessibilityLabel(tab == .security ? "Observations" : tab.rawValue)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
            Button(action: onCommands) { Image(systemName: "command").frame(width: 38, height: 38) }.help("Commands (⌘K)")
            Spacer()
            Menu { Picker("Interface", selection: $settings.visualTheme) { ForEach(VisualTheme.allCases) { Text($0.rawValue).tag($0) } } }
                label: { Text(direction.number).font(interfaceFont(size: 11, design: .monospaced)).frame(width: 38, height: 34) }
                .help("Choose interface")
            Button { (NSApp.delegate as? AppDelegate)?.openSettingsWindow() } label: { Image(systemName: "gearshape").frame(width: 38, height: 38) }.help("Settings")
        }
        .buttonStyle(.plain).padding(.vertical, 14).frame(width: 66)
        .background(Theme.Surface.chromeTint).overlay(alignment: .trailing) { Divider() }
    }

    private var portsWorkspace: some View {
        VStack(spacing: 0) {
            if direction != .focus { heading }
            if let port = viewModel.selectedPort {
                HStack {
                    Text("\(port.command) · PID \(String(port.pid))").font(interfaceFont(size: 11)).lineLimit(1)
                    Spacer()
                    ProcessQuickActions(port: port, viewModel: viewModel)
                }.padding(.horizontal, 24).padding(.vertical, 10)
            }
            MainWindowToolbar(searchText: $viewModel.searchText, viewModel: viewModel,
                onRefresh: { viewModel.refreshPorts() }, onSettings: { (NSApp.delegate as? AppDelegate)?.openSettingsWindow() },
                isLoading: viewModel.isLoading, portCount: viewModel.portCount, totalCount: viewModel.totalCount, selectedMainTab: $selectedTab)
            if !isSidebar { filters }
            Divider()
            GeometryReader { geometry in
                if direction == .focus {
                    HSplitView { listenerList.frame(minWidth: 250, idealWidth: 280, maxWidth: 340); inspector().frame(minWidth: 340) }
                } else if direction == .relay {
                    VStack(spacing: 0) { listenerList; selectionTray }
                } else if geometry.size.width >= 800 {
                    HSplitView {
                        primarySurface.frame(minWidth: 380)
                        inspectorSurface.frame(minWidth: 340, idealWidth: 370, maxWidth: 470)
                    }
                } else {
                    VStack(spacing: 0) { primarySurface; selectionTray }
                }
            }
        }
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(direction == .shell ? "LOCAL USER SESSION / PORTPILOT" : "\(direction.number) / \(direction.rawValue.uppercased())")
                    .font(interfaceFont(size: 9, weight: .medium, design: .monospaced)).tracking(1.6).foregroundStyle(.secondary)
                Text(title).font(PortPilotTypography.heading(direction: direction)).tracking(direction == .fieldwork ? -1.2 : -0.8)
                if direction == .fieldwork { Text("Services grouped by observed repository or working directory.").font(interfaceFont(size: 11)).foregroundStyle(.secondary) }
                if direction == .orbit { Text("Your listeners. Their processes. One clear view.").font(interfaceFont(size: 11)).foregroundStyle(.secondary) }
            }
            Spacer()
            if isSidebar { directionPicker }
            if direction == .play {
                VStack(spacing: 0) { Text("\(ports.count)").font(interfaceFont(size: 29, weight: .bold, design: .monospaced)); Text("shown").font(interfaceFont(size: 9)) }
                    .frame(width: 68, height: 68).background(Theme.paletteAccent.opacity(0.12), in: Circle()).rotationEffect(.degrees(7))
            }
        }
        .padding(.horizontal, 24).padding(.vertical, direction == .relay ? 15 : 21)
    }

    private var filters: some View {
        HStack(spacing: 16) {
            Picker("Protocol", selection: $viewModel.selectedProtocol) {
                ForEach(PortViewModel.ProtocolFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).frame(maxWidth: 250)
            Menu("Source: \(viewModel.selectedSourceFilter.rawValue)") {
                Picker("Source", selection: $viewModel.selectedSourceFilter) { ForEach(PortSourceFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            }.frame(maxWidth: 160)
            Menu("Category") {
                Picker("Category", selection: $viewModel.selectedCategory) { ForEach(FilterCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            }.frame(maxWidth: 110)
            if viewModel.hasActiveFilters {
                Button { viewModel.clearFilters() } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                    .buttonStyle(.plain).help("Reset listener filters").accessibilityLabel("Reset listener filters")
            }
            Spacer()
            if direction == .orbit { Toggle("List view", isOn: $orbitList).toggleStyle(.switch).controlSize(.mini) }
        }.font(interfaceFont(size: 10)).padding(.horizontal, 20).padding(.vertical, 10)
    }

    @ViewBuilder private var primarySurface: some View {
        switch direction {
        case .fieldwork: projectGroups
        case .play: serviceTiles
        case .orbit: if orbitList { listenerList } else { orbitMap }
        default: listenerList
        }
    }

    @ViewBuilder private var inspectorSurface: some View {
        if direction == .shell {
            VStack(alignment: .leading, spacing: 0) {
                HStack { Text("PROCESS(1)"); Spacer(); Text("PORTPILOT MANUAL") }.font(interfaceFont(size: 9, design: .monospaced)).foregroundStyle(Theme.paletteAccent).padding(18)
                Divider(); inspector()
            }
        } else { inspector() }
    }

    private var listenerList: some View {
        VStack(spacing: 0) {
            HStack { Text("ENDPOINT").frame(width: 85, alignment: .leading); Text("PROCESS"); Spacer(); Text("PID / USER") }
                .font(interfaceFont(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary).padding(.horizontal, 17).padding(.vertical, 12)
            if ports.isEmpty { emptyState }
            else {
                ScrollView { LazyVStack(spacing: direction == .relay || direction == .shell ? 0 : 4) {
                    ForEach(ports) { port in listenerRow(port) }
                }.padding(.horizontal, direction == .relay || direction == .shell ? 0 : 8).padding(.vertical, 5) }
            }
        }
        .background(Theme.Surface.controlBackground)
    }

    private func listenerRow(_ port: PortProcess) -> some View {
        Button { viewModel.selectedPort = port } label: {
            HStack(spacing: 12) {
                Text(port.isUnixSocket ? "UNIX" : ":\(port.port)").font(interfaceFont(size: 12, weight: .semibold, design: .monospaced)).frame(width: 80, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(port.command).font(interfaceFont(size: 12, weight: .medium)).lineLimit(1)
                    Text(port.protocolName.uppercased() + (port.isStopped ? " · FROZEN" : "") + (port.framework.map { " · \($0)" } ?? ""))
                        .font(interfaceFont(size: 9, design: .monospaced)).foregroundStyle(port.isStopped ? Theme.Status.warning : .secondary)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) { Text("\(port.pid)").font(interfaceFont(size: 10, design: .monospaced)); Text(port.user).font(interfaceFont(size: 9)).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 12).padding(.vertical, direction == .relay ? 9 : 13)
            .contentShape(Rectangle())
            .background(viewModel.selectedPort?.id == port.id ? Theme.paletteAccent.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: direction.radius))
        }
        .buttonStyle(.plain).accessibilityLabel("Inspect \(port.command), \(port.protocolName), port \(port.port), PID \(port.pid)")
        .accessibilityAddTraits(viewModel.selectedPort?.id == port.id ? .isSelected : [])
        .contextMenu { processMenu(port) }
    }

    @ViewBuilder private func processMenu(_ port: PortProcess) -> some View {
        Button("Inspect") { viewModel.selectedPort = port; showInspector = true }
        Button(port.isStopped ? "Resume process" : "Freeze process") { onPauseResume(port) }
        Button("Stop process…", role: .destructive) { onKill(port) }
        Button(viewModel.isFavorite(port: port.port) ? "Remove favorite" : "Favorite port") { viewModel.toggleFavorite(port: port.port) }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer(); Image(systemName: viewModel.isLoading ? "hourglass" : "magnifyingglass").font(interfaceFont(size: 27)).foregroundStyle(.secondary)
            Text(viewModel.isLoading ? "Reading local listeners…" : viewModel.hasActiveFilters ? "No listeners match this view." : viewModel.lastRefresh == nil ? "No completed listener snapshot yet." : "Latest successful scan returned no listeners.")
                .font(interfaceFont(size: 12)).multilineTextAlignment(.center)
            if let error = viewModel.errorMessage { Text(error).font(interfaceFont(size: 11)).foregroundStyle(Theme.Status.error) }
            if viewModel.hasActiveFilters { Button("Clear filters") { viewModel.clearFilters() } }
            Spacer()
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func projectName(_ port: PortProcess) -> String {
        if let repo = port.gitRepo, !repo.isEmpty { return URL(fileURLWithPath: repo).lastPathComponent }
        if let cwd = port.workingDirectory, !cwd.isEmpty { return URL(fileURLWithPath: cwd).lastPathComponent + " · directory" }
        return "Unassigned"
    }
    private var projectGroups: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if ports.isEmpty { emptyState.frame(minHeight: 250) }
                ForEach(Array(Dictionary(grouping: ports, by: projectName).keys).sorted(), id: \.self) { name in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Image(systemName: "folder"); Text(name).font(interfaceFont(size: 20, design: .serif)); Spacer(); Text("\(ports.filter { projectName($0) == name }.count)").foregroundStyle(.secondary) }.padding(.bottom, 7)
                        ForEach(ports.filter { projectName($0) == name }) { listenerRow($0) }
                    }.padding(17).background(Theme.Surface.controlBackground, in: RoundedRectangle(cornerRadius: 11))
                }
            }.padding(22)
        }
    }

    private var serviceTiles: some View {
        ScrollView {
            if ports.isEmpty { emptyState.frame(minHeight: 300) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 15)], spacing: 15) {
                ForEach(ports) { port in
                    Button { viewModel.selectedPort = port } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { PortPilotPlug().stroke(lineWidth: 1.5).frame(width: 15, height: 15); Spacer(); Text(port.protocolName.uppercased()).font(interfaceFont(size: 9, design: .monospaced)) }
                            Text(port.isUnixSocket ? "UNIX" : ":\(port.port)").font(interfaceFont(size: 31, weight: .semibold, design: .monospaced)).tracking(-1)
                            Text(port.command).font(interfaceFont(size: 13, weight: .semibold)).lineLimit(1)
                            Text("PID \(port.pid) · \(port.user)").font(interfaceFont(size: 9)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        .background(Theme.paletteAccent.opacity(viewModel.selectedPort?.id == port.id ? 0.17 : 0.07), in: RoundedRectangle(cornerRadius: 17))
                        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(viewModel.selectedPort?.id == port.id ? Theme.paletteAccent : Color.secondary.opacity(0.2), lineWidth: viewModel.selectedPort?.id == port.id ? 2 : 1))
                    }.buttonStyle(.plain).contextMenu { processMenu(port) }
                    .accessibilityLabel("Inspect \(port.command) on port \(port.port), PID \(port.pid)")
                }
            }.padding(22)
        }
    }

    private var orbitMap: some View {
        GeometryReader { geometry in
            if ports.isEmpty { emptyState }
            else if geometry.size.width < 540 || geometry.size.height < 360 { listenerList }
            else {
                ZStack {
                    ForEach(0..<3) { ring in Ellipse().stroke(Theme.paletteAccent.opacity(ring == 0 ? 0.18 : 0.08), style: StrokeStyle(lineWidth: 1, dash: ring == 1 ? [3, 5] : [])).frame(width: geometry.size.width * (0.38 + Double(ring) * 0.2), height: geometry.size.height * (0.35 + Double(ring) * 0.14)) }
                    VStack(spacing: 10) {
                        Text("SELECTED ENDPOINT").font(interfaceFont(size: 9, design: .monospaced)).tracking(1.3).foregroundStyle(.secondary)
                        Text(viewModel.selectedPort.map { $0.isUnixSocket ? "UNIX" : ":\($0.port)" } ?? "This Mac").font(interfaceFont(size: 42, weight: .light)).foregroundStyle(Theme.paletteAccent)
                        Text(viewModel.selectedPort?.command ?? "Select a listener").font(interfaceFont(size: 10)).lineLimit(1)
                    }.frame(width: geometry.size.width * 0.36)
                    ForEach(Array(ports.prefix(9).enumerated()), id: \.element.id) { index, port in
                        orbitNode(port).position(orbitPosition(index, count: min(ports.count, 9), size: geometry.size))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) { Text("Selection layout, not a packet trace · showing \(min(ports.count, 9)) of \(ports.count) · use List for all")
                    .font(interfaceFont(size: 9)).foregroundStyle(.secondary).padding(.bottom, 10) }
            }
        }.padding(12)
    }
    private func orbitPosition(_ index: Int, count: Int, size: CGSize) -> CGPoint {
        let angle = -Double.pi / 2 + Double(index) * 2 * .pi / Double(max(count, 1))
        return CGPoint(x: size.width / 2 + cos(angle) * size.width * 0.37, y: size.height / 2 + sin(angle) * size.height * 0.35)
    }
    private func orbitNode(_ port: PortProcess) -> some View {
        Button { viewModel.selectedPort = port } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(port.isUnixSocket ? "UNIX" : ":\(port.port)").font(interfaceFont(size: 12, weight: .medium, design: .monospaced))
                Text(port.command).font(interfaceFont(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(width: 95, alignment: .leading).padding(12)
                .background(Theme.Surface.controlBackground, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(viewModel.selectedPort?.id == port.id ? Theme.paletteAccent : Color.secondary.opacity(0.25)))
        }.buttonStyle(.plain).contextMenu { processMenu(port) }
            .accessibilityLabel("Inspect \(port.command), port \(port.port), PID \(port.pid)")
    }

    private var selectionTray: some View {
        HStack(spacing: 14) {
            if let port = viewModel.selectedPort {
                Text(port.command).font(interfaceFont(size: 12, weight: .semibold))
                Text("PID \(port.pid) · \(port.protocolName.uppercased()) · :\(port.port)").font(interfaceFont(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Spacer(); Button("Inspect →") { showInspector = true }.buttonStyle(.borderedProminent)
            } else { Text("Select a listener to inspect its identity and controls.").foregroundStyle(.secondary); Spacer() }
        }.padding(16).background(Theme.Surface.chromeTint).overlay(alignment: .top) { Divider() }
    }

    private var commandPrompt: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(shellReceipt).font(interfaceFont(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
            HStack(spacing: 12) {
                Text("portpilot ❯").foregroundStyle(Theme.paletteAccent)
                TextField("help · ports · inspect 3000", text: $shellInput).textFieldStyle(.plain).onSubmit(runCommand)
                    .accessibilityLabel("PortPilot navigation command")
                Button("enter ↵", action: runCommand).buttonStyle(.plain)
            }.font(interfaceFont(size: 12, design: .monospaced))
            Text("NAVIGATION COMMANDS / NO SYSTEM SHELL").font(interfaceFont(size: 9, design: .monospaced)).tracking(1).foregroundStyle(.secondary)
        }.padding(.horizontal, 22).padding(.vertical, 13).background(Theme.Surface.chromeTint).overlay(alignment: .top) { Divider() }
    }
    private func runCommand() {
        let command = WorkspaceCommand.parse(shellInput)
        shellInput = ""
        switch command {
        case .help: shellReceipt = "ports / ls · find <text> · inspect <port> · refresh · observations · schedules · clear. Process controls live in the inspector."
        case .ports: selectedTab = .ports; shellReceipt = "Listener view. Existing filters retained."
        case .refresh: viewModel.refreshPorts(); shellReceipt = "Listener refresh requested; check the status bar for its result."
        case .observations: selectedTab = .security; shellReceipt = "Observations are heuristics, not malware verdicts."
        case .schedules: selectedTab = .schedules; viewModel.refreshCronjobs(); shellReceipt = "Schedules. Run Now is deliberate code execution under your user."
        case .find(let query): viewModel.searchText = query; selectedTab = .ports; shellReceipt = "Search applied."
        case .inspect(let port):
            let matches = viewModel.ports.filter { !$0.isUnixSocket && $0.port == port }
            if matches.count == 1 {
                viewModel.clearFilters()
                viewModel.selectedProtocol = matches[0].protocolName.lowercased() == "udp" ? .udp : .tcp
                viewModel.selectedPort = matches[0]; selectedTab = .ports; shellReceipt = "Selected :\(port)."
            }
            else { shellReceipt = matches.isEmpty ? "No observed listener on :\(port)." : "Several listeners use :\(port). Select the exact process in the list." }
        case .clear: shellReceipt = ""; viewModel.clearFilters()
        case .invalid: shellReceipt = "Unknown navigation command. Type help. No system command was executed."
        }
    }
}
