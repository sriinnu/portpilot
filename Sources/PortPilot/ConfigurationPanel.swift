import SwiftUI

// MARK: - Configuration Panel
struct ConfigurationPanel: View {
    let port: PortProcess?
    @ObservedObject var viewModel: PortViewModel
    @ObservedObject private var appSettings = AppSettings.shared

    @State private var isExpanded = true
    @State private var connectionName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            configHeader

            if isExpanded {
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let port = port {
                            connectionSection(port: port)
                            portMappingSection(port: port)
                            visualPortMapperSection(port: port)
                            optionsSection(port: port)
                            proxySection(port: port)
                        } else {
                            noSelectionView
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Theme.Surface.controlBackground)
        .onChange(of: port?.port) { _ in
            if let port = port {
                connectionName = viewModel.connectionName(for: port)
                    ?? viewModel.tunnelName(for: port)
                    ?? ""
            } else {
                connectionName = ""
            }
        }
        .onAppear {
            if let port = port {
                connectionName = viewModel.connectionName(for: port)
                    ?? viewModel.tunnelName(for: port)
                    ?? ""
            }
        }
    }

    // MARK: - Header

    private var configHeader: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? Theme.Icon.chevronDown : Theme.Icon.chevronRight)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 12)

                Text("Configuration")
                    .font(.system(size: 13, weight: .semibold))

                if port != nil {
                    // Connected badge: green dot + pill
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Theme.Status.connected)
                            .frame(width: Theme.Size.statusDotSmall, height: Theme.Size.statusDotSmall)
                        Text("Connected")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Theme.Badge.connectedText)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.Badge.connectedBackground)
                    .cornerRadius(9)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.Surface.headerTint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - No Selection

    private var noSelectionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.4))
            Text("Select a port to view configuration")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Connection Section

    private func connectionSection(port: PortProcess) -> some View {
        ConfigSection(title: "Connection") {
            VStack(alignment: .leading, spacing: 10) {
                ConfigField(label: "Name", icon: Theme.Icon.name, iconColor: Theme.ConfigIcon.name) {
                    TextField("Connection name", text: $connectionName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onSubmit {
                            viewModel.setConnectionName(
                                port: port.port,
                                protocol: port.protocolName,
                                name: connectionName
                            )
                        }
                }

                ConfigField(label: "Type", icon: Theme.Icon.type, iconColor: Theme.ConfigIcon.type) {
                    let type = viewModel.connectionType(for: port)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: type.icon)
                                .font(.system(size: 11))
                                .foregroundColor(type.color)
                            Text(type.rawValue)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        if let detail = viewModel.tunnelDetail(for: port) {
                            Text(detail)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                }

                ConfigField(label: "Process", icon: Theme.Icon.process, iconColor: Theme.ConfigIcon.process) {
                    Text(port.command)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                ConfigField(label: "PID", icon: Theme.Icon.pid, iconColor: Theme.ConfigIcon.pid) {
                    Text("\(port.pid)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                }

                ConfigField(label: "User", icon: Theme.Icon.user, iconColor: Theme.ConfigIcon.user) {
                    Text(port.user)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                }

                let processType = viewModel.processType(for: port)
                ConfigField(label: "Class", icon: processType.icon, iconColor: classificationColor(processType)) {
                    HStack(spacing: 4) {
                        Text(processType.rawValue)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                        if let path = port.processPath {
                            Text(path)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.7))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                if let ppid = port.parentPID, let parentName = viewModel.parentProcessName(for: port) {
                    ConfigField(label: "Parent", icon: Theme.Icon.ppid, iconColor: Theme.ConfigIcon.ppid) {
                        HStack(spacing: 4) {
                            Text("\(ppid)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.primary)
                            Text("(\(parentName))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if let uptime = viewModel.processUptime(for: port) {
                    ConfigField(label: "Uptime", icon: Theme.Icon.uptime, iconColor: Theme.ConfigIcon.uptime) {
                        Text(uptime)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                }

                if let cwd = port.workingDirectory, !cwd.isEmpty {
                    ConfigField(label: "CWD", icon: Theme.Icon.workingDirectory, iconColor: Theme.ConfigIcon.workingDirectory) {
                        Text(cwd)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    // MARK: - Port Mapping Section

    private func portMappingSection(port: PortProcess) -> some View {
        let mapping = viewModel.portMappingInfo(for: port)

        return ConfigSection(title: "Port Mapping") {
            HStack(spacing: 8) {
                // Remote box (only for tunnels)
                if let remotePort = mapping.remotePort {
                    VStack(spacing: 2) {
                        Text("Remote")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(":\(remotePort)")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.PortMapping.remoteFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Size.cornerRadius)
                                    .stroke(Theme.PortMapping.remoteStroke, lineWidth: 1.5)
                            )
                            .cornerRadius(Theme.Size.cornerRadius)
                    }

                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }

                // Local port box
                VStack(spacing: 2) {
                    Text("Local")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(":\(port.port)")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.PortMapping.localFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Size.cornerRadius)
                                .stroke(Theme.PortMapping.localStroke, lineWidth: 1.5)
                        )
                        .cornerRadius(Theme.Size.cornerRadius)
                }

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)

                // Protocol box
                VStack(spacing: 2) {
                    Text("Protocol")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(port.protocolName.uppercased())
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.PortMapping.protocolFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Size.cornerRadius)
                                .stroke(Theme.PortMapping.protocolStroke, lineWidth: 1.5)
                        )
                        .cornerRadius(Theme.Size.cornerRadius)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Options Section

    private func optionsSection(port: PortProcess) -> some View {
        ConfigSection(title: "Options") {
            VStack(alignment: .leading, spacing: 8) {
                ConfigToggle(label: "Auto Reconnect", isOn: .constant(false), disabled: true,
                             icon: Theme.Icon.autoReconnect, iconColor: Theme.OptionIcon.autoReconnect)
                ConfigToggle(label: "Enabled", isOn: .constant(true), disabled: true,
                             icon: Theme.Icon.enabled, iconColor: Theme.OptionIcon.enabled)
                ConfigToggle(label: "Notify on Connect", isOn: .constant(false), disabled: true,
                             icon: Theme.Icon.notifyConnect, iconColor: Theme.OptionIcon.notifyConnect)
                ConfigToggle(label: "Notify on Disconnect", isOn: .constant(false), disabled: true,
                             icon: Theme.Icon.notifyDisconnect, iconColor: Theme.OptionIcon.notifyDisconnect)
            }
        }
    }

    // MARK: - Proxy Section
    private func proxySection(port: PortProcess) -> some View {
        ConfigSection(title: "Quick Proxy") {
            VStack(alignment: .leading, spacing: 10) {
                // Show active proxy for this port if any
                let activeProxy = viewModel.proxySessions.first { $0.listenPort == port.port || $0.targetPort == port.port }

                if let proxy = activeProxy {
                    // Active proxy info
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Proxying :\(proxy.listenPort) \u{2192} \(proxy.targetHost):\(proxy.targetPort)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary)
                        Spacer()
                        Button(action: { viewModel.stopProxy(id: proxy.id) }) {
                            Text("Stop")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.Action.kill)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.green.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                    )

                    if proxy.bytesForwarded > 0 {
                        Text("Forwarded: \(ByteCountFormatter.string(fromByteCount: Int64(proxy.bytesForwarded), countStyle: .memory))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                } else {
                    // Create proxy form
                    ProxyCreateForm(sourcePort: port.port, viewModel: viewModel)
                }
            }
        }
    }

    // MARK: - Visual Port Mapper Section

    private func visualPortMapperSection(port: PortProcess) -> some View {
        let type = viewModel.connectionType(for: port)
        let mapping = viewModel.portMappingInfo(for: port)

        return ConfigSection(title: "Port Flow") {
            VStack(alignment: .leading, spacing: 8) {
                // ASCII diagram
                Text(asciiPortFlow(type: type, mapping: mapping, port: port))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )

                // Container info for Docker
                if type == .local {
                    let containerInfo = viewModel.dockerInfo(for: port)
                    if let info = containerInfo {
                        DockerInfoRow(containerName: info.containerName, imageName: info.imageName, containerId: info.containerId)
                    }
                }
            }
        }
    }

    private func classificationColor(_ type: ProcessType) -> Color {
        switch type {
        case .system: return Theme.Classification.system
        case .userApp: return Theme.Classification.userApp
        case .developerTool: return Theme.Classification.developerTool
        case .other: return Theme.Classification.other
        }
    }

    private func asciiPortFlow(type: ConnectionType, mapping: PortMappingInfo, port: PortProcess) -> String {
        switch type {
        case .ssh, .kubernetes, .cloudflare:
            let remoteHost = mapping.remoteHost ?? "*"
            let remotePort = mapping.remotePort.map { String($0) } ?? "*"
            return """
            [\(remoteHost):\(remotePort)] --> [:\(port.port)] --> [\(port.protocolName.uppercased())]
            """
        case .database:
            return """
            [:\(port.port)] --> [\(port.protocolName.uppercased())] --> [\(port.command)]
            """
        case .local:
            return """
            [:\(port.port)] --> [\(port.protocolName.uppercased())]
            """
        }
    }
}

// MARK: - Config Section

struct ConfigSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            content
        }
    }
}

// MARK: - Config Field

struct ConfigField<Content: View>: View {
    let label: String
    var icon: String? = nil
    var iconColor: Color? = nil
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let icon = icon, let iconColor = iconColor {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(iconColor)
                    .frame(width: 14, alignment: .center)
            }
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 64, alignment: .trailing)
            content
        }
    }
}

// MARK: - Config Toggle

struct ConfigToggle: View {
    let label: String
    @Binding var isOn: Bool
    var disabled: Bool = false
    var icon: String? = nil
    var iconColor: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon, let iconColor = iconColor {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(iconColor)
                    .frame(width: 14, alignment: .center)
            }
            Toggle(label, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 12))
                .disabled(disabled)
                .opacity(disabled ? 0.6 : 1)
        }
    }
}

// MARK: - Proxy Create Form
struct ProxyCreateForm: View {
    let sourcePort: Int
    @ObservedObject var viewModel: PortViewModel

    @State private var targetHost: String = "localhost"
    @State private var targetPort: String = ""
    @State private var listenPort: String = ""
    @State private var proxyDirection: ProxyDirection = .fromPort

    enum ProxyDirection: String, CaseIterable {
        case fromPort = "Forward FROM this port"
        case toPort = "Forward TO this port"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Direction picker
            Picker("Direction", selection: $proxyDirection) {
                ForEach(ProxyDirection.allCases, id: \.self) { dir in
                    Text(dir.rawValue).tag(dir)
                }
            }
            .pickerStyle(.segmented)
            .font(.system(size: 11))

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target Host")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("localhost", text: $targetHost)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(proxyDirection == .fromPort ? "Target Port" : "Listen Port")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("e.g. 9090", text: proxyDirection == .fromPort ? $targetPort : $listenPort)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 80)
                }
            }

            Button(action: startProxy) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.system(size: 12))
                    Text("Start Proxy")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.Section.ssh)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(!isValid)
            .opacity(isValid ? 1.0 : 0.5)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.Surface.headerTint.opacity(0.7))
        )
    }

    private var isValid: Bool {
        if proxyDirection == .fromPort {
            return Int(targetPort) != nil && !targetHost.isEmpty
        } else {
            return Int(listenPort) != nil && !targetHost.isEmpty
        }
    }

    private func startProxy() {
        if proxyDirection == .fromPort {
            guard let tPort = Int(targetPort) else { return }
            viewModel.startProxy(listenPort: sourcePort, targetHost: targetHost, targetPort: tPort)
        } else {
            guard let lPort = Int(listenPort) else { return }
            viewModel.startProxy(listenPort: lPort, targetHost: targetHost, targetPort: sourcePort)
        }
    }
}

// MARK: - Docker Info Row

struct DockerInfoRow: View {
    let containerName: String
    let imageName: String
    let containerId: String

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "docker")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(containerName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                        Text(imageName)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Container ID:")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(containerId.prefix(12).description)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button(action: stopContainer) {
                            Label("Stop", systemImage: "stop.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)

                        Button(action: restartContainer) {
                            Label("Restart", systemImage: "arrow.clockwise")
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.Surface.headerTint.opacity(0.65))
        )
    }

    private func stopContainer() {
        let id = containerId
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/local/bin/docker")
            process.arguments = ["stop", id]
            try? process.run()
            process.waitUntilExit()
        }
    }

    private func restartContainer() {
        let id = containerId
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/local/bin/docker")
            process.arguments = ["restart", id]
            try? process.run()
            process.waitUntilExit()
        }
    }
}
