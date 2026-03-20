import SwiftUI

// MARK: - Tunnel Type
enum TunnelType: String, CaseIterable, Identifiable {
    case ssh = "SSH"
    case kubernetes = "Kubernetes"
    case cloudflare = "Cloudflare"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ssh: return Theme.Icon.ssh
        case .kubernetes: return Theme.Icon.kubernetes
        case .cloudflare: return Theme.Icon.cloudflare
        }
    }

    var color: Color {
        switch self {
        case .ssh: return Theme.Section.ssh
        case .kubernetes: return Theme.Section.kubernetes
        case .cloudflare: return Theme.Section.cloudflare
        }
    }
}

// MARK: - Port Forward Sheet
struct PortForwardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTunnelType: TunnelType = .ssh
    @State private var localPort: String = ""
    @State private var remotePort: String = ""
    @State private var remoteHost: String = ""
    @State private var showInstructions: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create Port Forward")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Tunnel Type Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tunnel Type")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            ForEach(TunnelType.allCases) { type in
                                TunnelTypeButton(
                                    type: type,
                                    isSelected: selectedTunnelType == type,
                                    action: { selectedTunnelType = type }
                                )
                            }
                        }
                    }

                    // Local Port
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Local Port")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        TextField("e.g., 8080", text: $localPort)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, design: .monospaced))
                    }

                    // Remote Port (for tunnels)
                    if selectedTunnelType != .cloudflare {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Remote Port")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            TextField("e.g., 80", text: $remotePort)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13, design: .monospaced))
                        }
                    }

                    // Remote Host (for SSH and K8s)
                    if selectedTunnelType == .ssh || selectedTunnelType == .kubernetes {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Remote Host")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            TextField("e.g., localhost or service.namespace.svc.cluster.local", text: $remoteHost)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13))
                        }
                    }

                    // Instructions
                    Button(action: { showInstructions.toggle() }) {
                        HStack {
                            Image(systemName: showInstructions ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10))
                            Text("View Instructions")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    if showInstructions {
                        TunnelInstructions(tunnelType: selectedTunnelType, localPort: localPort, remotePort: remotePort, remoteHost: remoteHost)
                    }
                }
                .padding()
            }

            Divider()

            // Footer buttons
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Create") {
                    // Create the port forward and show confirmation
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 480, height: 500)
    }
}

// MARK: - Tunnel Type Button
struct TunnelTypeButton: View {
    let type: TunnelType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? type.color : .secondary)

                Text(type.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .frame(width: 80, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? type.color.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? type.color : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tunnel Instructions
struct TunnelInstructions: View {
    let tunnelType: TunnelType
    let localPort: String
    let remotePort: String
    let remoteHost: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Command to create tunnel:")
                .font(.system(size: 12, weight: .medium))

            Text(commandText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .textSelection(.enabled)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
        )
    }

    private var commandText: String {
        switch tunnelType {
        case .ssh:
            if remoteHost.isEmpty {
                return "ssh -L \(localPort):localhost:\(remotePort) user@remote-host"
            } else {
                return "ssh -L \(localPort):\(remoteHost):\(remotePort) user@remote-host"
            }
        case .kubernetes:
            if remoteHost.isEmpty {
                return "kubectl port-forward svc/service-name \(localPort):\(remotePort) -n namespace"
            } else {
                return "kubectl port-forward \(remoteHost) \(localPort):\(remotePort) -n namespace"
            }
        case .cloudflare:
            return "cloudflared tunnel --url localhost:\(localPort)"
        }
    }
}

// MARK: - Preview
#Preview {
    PortForwardSheet()
}
