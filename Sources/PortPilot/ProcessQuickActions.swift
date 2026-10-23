import SwiftUI

/// Inline confirmation stays inside the nonactivating menu panel, which dismisses on key loss.
struct ProcessQuickActions: View {
    let port: PortProcess
    @ObservedObject var viewModel: PortViewModel
    @State private var stopTarget: PortProcess?
    @State private var captureTarget: PortProcess?

    private func endpoint(_ target: PortProcess) -> String {
        target.isUnixSocket ? "UNIX socket" : "\(target.protocolName.uppercased()) :\(target.port)"
    }
    private func targetHelp(_ action: String, _ target: PortProcess) -> String {
        "\(action) \(target.command) · \(endpoint(target)) · PID \(target.pid). Affects every port owned by this process."
    }

    private var canSignal: Bool {
        port.pid > 1 && port.pid != Int(ProcessInfo.processInfo.processIdentifier)
            && ProcessIdentity(process: port) != nil && !viewModel.isLoading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let target = stopTarget {
                Text("Stop \(target.command) · \(endpoint(target)) (PID \(String(target.pid)))?")
                    .font(.system(size: 11, weight: .semibold))
                Text("All ports owned by this process are affected. Unsaved work can be lost."
                     + (viewModel.isReserved(port: target.port) ? " This port is reserved." : ""))
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel") { stopTarget = nil }
                    Button("Stop " + target.command, role: .destructive) {
                        stopTarget = nil
                        viewModel.killPort(target)
                    }.disabled(viewModel.isLoading)
                        .help(targetHelp("Stop", target))
                }
            } else {
                HStack(spacing: 8) {
                    Button {
                        if port.isStopped { viewModel.resumeProcess(port) }
                        else { viewModel.pauseProcess(port) }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label((port.isStopped ? "Resume " : "Pause ") + port.command,
                                  systemImage: port.isStopped ? "play.fill" : "pause.fill")
                                .lineLimit(1).truncationMode(.middle)
                            Text(endpoint(port)).font(.system(size: 9, design: .monospaced))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.disabled(!canSignal)
                        .help(targetHelp(port.isStopped ? "Resume" : "Pause", port))
                    Button(role: .destructive) { stopTarget = port } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Stop " + port.command + "…").lineLimit(1).truncationMode(.middle)
                            Text(endpoint(port)).font(.system(size: 9, design: .monospaced))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.disabled(!canSignal).help(targetHelp("Stop", port))
                    if !port.isUnixSocket {
                        Button { captureTarget = port } label: { Image(systemName: "waveform.path") }
                            .help("Inspect packets for this port")
                            .accessibilityLabel("Inspect packets for port \(String(port.port))")
                    }
                }
                Text("PID " + String(port.pid) + (port.isStopped ? " · paused, port remains occupied" : " · controls affect the whole process"))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
        .buttonStyle(.bordered).controlSize(.small)
        .frame(maxWidth: 400, alignment: .leading)
        .sheet(item: $captureTarget) { target in PacketCaptureView(port: target) }
        .onChange(of: port.id) { _ in stopTarget = nil }
    }
}
