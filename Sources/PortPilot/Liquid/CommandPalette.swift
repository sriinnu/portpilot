import SwiftUI
import AppKit

// MARK: - Command Item

/// A single row shown in the command palette.
///
/// Ports and actions share this one row type so the list logic stays flat
/// and arrow-key navigation works uniformly regardless of what kind of
/// thing the user is highlighting.
struct CommandItem: Identifiable {
    /// Stable identity so SwiftUI can diff and animate rows cleanly.
    let id = UUID()
    /// SF Symbol name drawn in the leading icon chip.
    let icon: String
    /// Primary label shown on the row.
    let title: String
    /// Optional secondary label rendered under the title in a smaller font.
    let subtitle: String?
    /// Accent colour used for the icon chip and hover surface.
    let tint: Color
    /// Closure I invoke when the user activates the row via click or Return.
    let action: () -> Void

    /// Convenience factory that shapes a `PortProcess` into a palette row.
    /// - Parameters:
    ///   - port: The port whose summary fields populate the row.
    ///   - tint: Accent colour — typically the connection-type colour.
    ///   - action: Fired when the row is selected.
    static func port(_ port: PortProcess, tint: Color, action: @escaping () -> Void) -> CommandItem {
        CommandItem(
            icon: "network",
            title: port.isUnixSocket ? "PID \(port.pid)" : ":\(port.port)",
            subtitle: port.command,
            tint: tint,
            action: action
        )
    }
}

// MARK: - Command Palette Controller

/// Tiny state holder any view can bind against to present or dismiss the
/// palette and track its search text and highlighted row.
///
/// I install a local `NSEvent` monitor while the palette is open to
/// intercept arrow keys, Return, and Escape. Going through AppKit here is
/// cleaner than fighting SwiftUI's focus model for raw keyDown events.
@MainActor
final class CommandPaletteController: ObservableObject {
    /// `true` while the palette overlay is visible. Views bind their
    /// presentation logic to this flag.
    @Published var isPresented = false
    /// Current search query. Updated live as the user types.
    @Published var searchText = ""
    /// Index of the highlighted row in the flattened results list.
    /// Arrow keys bump this; Return executes the row at this index.
    @Published var selection = 0

    private var keyMonitor: Any?

    /// Flips visibility — opens if closed, dismisses if open.
    func toggle() {
        if isPresented { dismiss() } else { show() }
    }

    /// Resets query and selection, then shows the palette.
    func show() {
        searchText = ""
        selection = 0
        isPresented = true
    }

    /// Hides the palette and uninstalls the key monitor.
    func dismiss() {
        isPresented = false
        uninstallMonitor()
    }

    /// Installs a local `NSEvent` keyDown monitor that drives arrow navigation,
    /// Return to execute, and Escape to dismiss while the palette is open.
    ///
    /// I install this when the view appears and tear it down when it
    /// vanishes, so the palette doesn't eat keystrokes when closed.
    /// - Parameters:
    ///   - itemCount: Closure returning the current number of result rows,
    ///     so arrow wrap-around matches live filtering without me snapshotting.
    ///   - onExecute: Closure invoked on Return or Enter to activate the
    ///     currently selected row.
    func installMonitor(itemCount: @escaping () -> Int, onExecute: @escaping () -> Void) {
        uninstallMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isPresented else { return event }
            switch event.keyCode {
            case 125:  // arrow down
                let count = itemCount()
                if count > 0 { self.selection = (self.selection + 1) % count }
                return nil
            case 126:  // arrow up
                let count = itemCount()
                if count > 0 { self.selection = (self.selection - 1 + count) % count }
                return nil
            case 36, 76:  // return / enter
                onExecute()
                return nil
            case 53:  // escape
                self.dismiss()
                return nil
            default:
                return event
            }
        }
    }

    /// Removes the key monitor if installed. Safe to call when nothing is
    /// registered — I no-op in that case.
    func uninstallMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }
}

// MARK: - Command Palette View

/// The visible palette overlay: dimmed backdrop, floating card, search
/// input, grouped results, and a keyboard-hint footer.
///
/// I take the action list and the port-select closure as inputs so the
/// caller (`ContentView`) can bind whichever commands make sense in its
/// context — this view stays agnostic to what "execute" means.
struct CommandPaletteView: View {
    /// The palette's shared state holder.
    @ObservedObject var controller: CommandPaletteController
    /// View model I filter ports against when the user types.
    @ObservedObject var viewModel: PortViewModel
    @ObservedObject private var appSettings = AppSettings.shared
    /// Callable actions the caller wants surfaced in the "Actions" section.
    let actions: [CommandItem]
    /// Invoked when the user picks a port row — caller decides what it means.
    let onSelectPort: (PortProcess) -> Void

    @FocusState private var searchFocused: Bool

    private var filteredPorts: [PortProcess] {
        let q = controller.searchText.lowercased()
        guard !q.isEmpty else { return Array(viewModel.ports.prefix(6)) }
        return viewModel.ports.filter {
            String($0.port).contains(q) ||
            $0.command.lowercased().contains(q) ||
            String($0.pid).contains(q)
        }
        .prefix(8)
        .map { $0 }
    }

    private var filteredActions: [CommandItem] {
        let q = controller.searchText.lowercased()
        guard !q.isEmpty else { return actions }
        return actions.filter { $0.title.lowercased().contains(q) }
    }

    private var flatItems: [PaletteEntry] {
        var entries: [PaletteEntry] = []
        for port in filteredPorts {
            entries.append(.port(port))
        }
        for action in filteredActions {
            entries.append(.action(action))
        }
        return entries
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Backdrop — tap to dismiss.
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { controller.dismiss() }

            VStack(spacing: 0) {
                searchField
                Divider()
                results
                footerHint
            }
            .frame(maxWidth: 560)
            .background(
                RoundedRectangle(cornerRadius: Theme.Liquid.panelCornerRadius, style: .continuous)
                    .fill(Theme.Surface.windowBackground)
                    .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Liquid.panelCornerRadius, style: .continuous)
                    .strokeBorder(Theme.Surface.groupedStroke, lineWidth: Theme.Liquid.cardStrokeWidth)
            )
            .padding(.top, 96)
            .padding(.horizontal, 40)
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            .onAppear {
                searchFocused = true
                controller.installMonitor(
                    itemCount: { flatItems.count },
                    onExecute: { execute() }
                )
            }
            .onDisappear { controller.uninstallMonitor() }
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "command")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.Liquid.accentPurple)
            TextField("Search ports, processes, actions...", text: $controller.searchText)
                .textFieldStyle(.plain)
                .font(appSettings.appFont(size: 15))
                .focused($searchFocused)
                .onChange(of: controller.searchText) { _ in controller.selection = 0 }
            if !controller.searchText.isEmpty {
                Button { controller.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text("ESC")
                .font(appSettings.appMonoFont(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Liquid.chipCornerRadius)
                        .fill(Theme.Surface.groupedFill)
                )
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        let items = flatItems
        if items.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !filteredPorts.isEmpty {
                        sectionHeader("Ports")
                        ForEach(Array(filteredPorts.enumerated()), id: \.element.id) { idx, port in
                            paletteRow(
                                icon: "network",
                                tint: viewModel.connectionType(for: port).color,
                                title: port.isUnixSocket ? "PID \(port.pid)" : ":\(port.port)",
                                subtitle: "\(port.command) • PID \(port.pid)",
                                selected: controller.selection == idx,
                                trailing: port.protocolName.uppercased()
                            ) {
                                onSelectPort(port)
                                controller.dismiss()
                            }
                        }
                    }
                    if !filteredActions.isEmpty {
                        sectionHeader("Actions")
                        let offset = filteredPorts.count
                        ForEach(Array(filteredActions.enumerated()), id: \.element.id) { idx, action in
                            paletteRow(
                                icon: action.icon,
                                tint: action.tint,
                                title: action.title,
                                subtitle: action.subtitle,
                                selected: controller.selection == offset + idx,
                                trailing: nil
                            ) {
                                action.action()
                                controller.dismiss()
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 360)
        }
    }

    private func sectionHeader(_ label: String) -> some View {
        Text(label)
            .font(appSettings.appFont(size: 9, weight: .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundColor(.secondary)
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 2)
    }

    private func paletteRow(icon: String, tint: Color, title: String, subtitle: String?, selected: Bool, trailing: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(selected ? .white : tint)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selected ? tint : tint.opacity(0.14))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(appSettings.appFont(size: 13, weight: .semibold))
                        .foregroundColor(selected ? .white : .primary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(appSettings.appFont(size: 11))
                            .foregroundColor(selected ? .white.opacity(0.85) : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                if let trailing = trailing {
                    Text(trailing)
                        .font(appSettings.appMonoFont(size: 9, weight: .semibold))
                        .foregroundColor(selected ? .white.opacity(0.85) : .secondary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Liquid.chipCornerRadius)
                                .fill(selected ? Color.white.opacity(0.15) : Theme.Surface.groupedFill)
                        )
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Theme.Liquid.accentPurple : Color.clear)
                    .padding(.horizontal, 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundColor(.secondary)
            Text("No matches")
                .font(appSettings.appFont(size: 13, weight: .semibold))
            Text("Try a port number, process name, or action.")
                .font(appSettings.appFont(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var footerHint: some View {
        HStack(spacing: 12) {
            hintChip(label: "↑ ↓", desc: "navigate")
            hintChip(label: "↵", desc: "select")
            hintChip(label: "esc", desc: "dismiss")
            Spacer()
            Text("PortPilot Command Palette")
                .font(appSettings.appFont(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Theme.Surface.chromeTint)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Surface.groupedStroke).frame(height: 0.5)
        }
    }

    private func hintChip(label: String, desc: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(appSettings.appMonoFont(size: 10, weight: .semibold))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Liquid.chipCornerRadius)
                        .fill(Theme.Surface.groupedFill)
                )
            Text(desc)
                .font(appSettings.appFont(size: 10))
                .foregroundColor(.secondary)
        }
    }

    // MARK: Execute

    private func execute() {
        let items = flatItems
        guard controller.selection >= 0, controller.selection < items.count else { return }
        switch items[controller.selection] {
        case .port(let port):
            onSelectPort(port)
        case .action(let action):
            action.action()
        }
        controller.dismiss()
    }

    // MARK: Entry enum

    private enum PaletteEntry {
        case port(PortProcess)
        case action(CommandItem)
    }
}
