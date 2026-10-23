import SwiftUI
import Darwin

@MainActor
final class PacketCaptureModel: ObservableObject {
    @Published var running = false
    @Published var stopping = false
    @Published var packets: [PacketSummary] = []
    @Published var message = "Capture is off. Choose an interface, then start a bounded observation."
    @Published var failed = false
    @Published var truncated = false
    static private(set) var activeSession: PacketCaptureSession?
    private static weak var menuOwner: NSWindow?
    private var session: PacketCaptureSession?

    static func interfaces() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var names = Set<String>()
        var entry = head
        while let current = entry {
            let item = current.pointee
            if (item.ifa_flags & UInt32(IFF_UP)) != 0 { names.insert(String(cString: item.ifa_name)) }
            entry = item.ifa_next
        }
        return names.sorted()
    }
    func start(interface: String, port: Int, transport: String) {
        guard !running else { return }
        if let previous = Self.activeSession, previous.waitUntilFinished(timeout: 0) {
            Self.activeSession = nil
            Self.menuOwner = nil
        }
        guard Self.activeSession == nil else {
            message = "Another packet capture is already running. Stop it before starting a new one."
            failed = true
            return
        }
        do {
            let request = try PacketCaptureRequest(interface: interface, port: port, transport: transport)
            let session = PacketCaptureSession(request: request)
            self.session = session
            Self.activeSession = session
            let key = NSApp.keyWindow
            Self.menuOwner = (key?.sheetParent as? MenuBarPanel) ?? (key as? MenuBarPanel)
            running = true; stopping = false; packets = []; failed = false; truncated = false
            message = "Observing \(transport.uppercased()) port \(port) on \(interface)…"
            Task {
                let result = await Task.detached(priority: .utility) { session.run() }.value
                packets = result.packets
                message = result.message; failed = result.failed; truncated = result.truncated
                running = false; stopping = false; self.session = nil
                if Self.activeSession === session, session.waitUntilFinished(timeout: 0) {
                    Self.activeSession = nil
                    Self.menuOwner = nil
                }
            }
        } catch { message = "Choose a valid TCP or UDP port and interface."; failed = true }
    }
    static func cancelCapture(ownedBy panel: NSWindow) {
        if menuOwner === panel { activeSession?.cancel() }
    }
    func stop() { guard running else { return }; stopping = true; message = "Stopping capture…"; session?.cancel() }
    deinit { session?.cancel() }
}

struct PacketCaptureView: View {
    let port: PortProcess
    @StateObject private var model = PacketCaptureModel()
    @Environment(\.dismiss) private var dismiss
    @State private var interfaces = PacketCaptureModel.interfaces()
    @State private var interface = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PortPilotIdentity()
                Spacer()
                Button("Done") { model.stop(); dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Packet inspection").font(.system(size: 25, weight: .semibold))
            Text("\(port.protocolName.uppercased()) :\(String(port.port)) · \(port.command)")
                .font(.system(size: 12, design: .monospaced))
            Text("Observe this port on the selected interface for up to 10 seconds or 200 packets. Numeric endpoints and protocol summaries only; no payload display, file storage, or decryption.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Text("A port can match several processes or transit traffic. These are sampled interface observations; endpoint details can be private.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Picker("Interface", selection: $interface) {
                    Text("Choose…").tag("")
                    ForEach(interfaces, id: \.self) { Text($0).tag($0) }
                }.disabled(model.running)
                if model.running {
                    Button(model.stopping ? "Stopping…" : "Stop capture") { model.stop() }.disabled(model.stopping)
                    ProgressView().controlSize(.small)
                } else {
                    Button("Start 10-second capture") {
                        model.start(interface: interface, port: port.port, transport: port.protocolName)
                    }.disabled(interface.isEmpty).buttonStyle(.borderedProminent)
                }
            }
            Text(model.message).font(.system(size: 12)).foregroundStyle(model.failed ? Color.red : Color.secondary)
            if model.truncated { Text("Output was incomplete or exceeded the memory limit. These are partial observations.").foregroundStyle(.orange) }
            if !model.packets.isEmpty {
                Text("\(model.packets.count) packet summaries · observed endpoints")
                    .font(.system(size: 11, weight: .semibold))
            }
            if model.packets.isEmpty {
                Text(model.running ? "Waiting for the bounded capture to finish…" : "No packet summaries to display.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(model.packets.enumerated()), id: \.offset) { _, packet in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(packet.source) → \(packet.destination)").font(.system(size: 11, design: .monospaced))
                        Text("\(packet.timestamp) · \(packet.detail)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }.textSelection(.enabled)
                }
            }
            Text("Capture uses your existing macOS permissions and stays off until you start it.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 720, height: 590)
        .background(Theme.Surface.windowBackground)
        .onDisappear { model.stop() }
    }
}
