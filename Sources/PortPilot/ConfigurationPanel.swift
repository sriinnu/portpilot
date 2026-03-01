import SwiftUI
import PortManagerLib

// MARK: - Configuration Panel
struct ConfigurationPanel: View {
    let port: PortProcess?
    @ObservedObject var viewModel: PortViewModel

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
                            optionsSection(port: port)
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
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.Badge.connectedText)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.Badge.connectedBackground)
                    .cornerRadius(10)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
}

// MARK: - Config Section

struct ConfigSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        HStack(alignment: .top, spacing: 6) {
            if let icon = icon, let iconColor = iconColor {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(iconColor)
                    .frame(width: 14, alignment: .center)
            }
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 55, alignment: .trailing)
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
