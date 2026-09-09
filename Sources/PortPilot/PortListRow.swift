import SwiftUI

// MARK: - Port Row
// Rebuilt for Concept 8's Liquid Glass Control Deck — fixed-column layout,
// inline activity sparkline, soft hover chrome, and actions that fade in when
// the row becomes the focus.
struct PortListRow: View {
    let port: PortProcess
    let isSelected: Bool
    let isFavorite: Bool
    let onSelect: () -> Void
    let onKill: () -> Void
    let onPauseResume: () -> Void
    let onToggleFavorite: () -> Void
    var processType: ProcessType = .other
    var typeColor: Color = Theme.Status.connected
    var typeIcon: String = Theme.Icon.local
    var tunnelName: String? = nil
    var parentProcessName: String? = nil
    var processUptime: String? = nil
    var cpuUsage: Double? = nil
    var history: [Double] = []

    @ObservedObject private var appSettings = AppSettings.shared
    @State private var isHovered = false
    // I arm the button for 3s before the second tap fires it.
    @State private var killArmed = false

    private var infoTooltip: String {
        var lines: [String] = []
        lines.append("PID: \(port.pid)")
        if let ppid = port.parentPID {
            lines.append("PPID: \(ppid)" + (parentProcessName.map { " (\($0))" } ?? ""))
        }
        if let cpu = cpuUsage {
            lines.append("CPU: \(String(format: "%.1f", cpu))%")
        }
        if let mem = port.memoryMB {
            lines.append("Memory: \(formatMemoryCompact(mem))")
        }
        if let uptime = processUptime {
            lines.append("Uptime: \(uptime)")
        }
        if let cwd = port.workingDirectory, !cwd.isEmpty {
            lines.append("CWD: \(cwd)")
        }
        if let fullCmd = port.fullCommand, !fullCmd.isEmpty {
            lines.append("Command: \(fullCmd)")
        }
        return lines.joined(separator: "\n")
    }

    private var displayName: String {
        tunnelName ?? port.socketPath ?? port.fullCommand ?? port.command
    }

    var body: some View {
        HStack(spacing: 6) {
            // Status + favorite dot — a single 12-pt column, keeps the row quiet.
            ZStack {
                Circle()
                    .fill(typeColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: typeColor.opacity(0.55), radius: 2)
                    .opacity(isFavorite ? 0 : 1)
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.Status.warning)
                }
            }
            .frame(width: 12)
            .onTapGesture { onToggleFavorite() }
            .help(isFavorite ? "Remove from favorites" : "Add to favorites")

            // Port column — dominant typography on top, protocol under. Tightened
            // to 64pt so narrow window widths don't wrap the label vertically;
            // at large font sizes the number scales down instead of clipping
            // (the size slider goes up to 18px, where ":65535" outgrows 64pt).
            VStack(alignment: .leading, spacing: 2) {
                if port.isUnixSocket {
                    Text(verbatim: "PID \(port.pid)")
                        .font(appSettings.appMonoFont(size: appSettings.fontSize, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else {
                    Text(verbatim: ":\(port.port)")
                        .font(appSettings.appMonoFont(size: appSettings.fontSize + 1, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                HStack(spacing: 3) {
                    Image(systemName: typeIcon)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(typeColor)
                    Text(port.protocolName.uppercased())
                        .font(appSettings.appMonoFont(size: 8, weight: .semibold))
                        .foregroundColor(typeColor)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(width: 64, alignment: .leading)

            // Process column — classification badge + command. Flexible.
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(processType.rawValue)
                        .font(appSettings.appFont(size: 9, weight: .semibold))
                        .foregroundColor(processTypeColor(processType))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(processTypeColor(processType).opacity(0.14))
                        )
                    if port.isStopped {
                        Text("PAUSED")
                            .font(appSettings.appMonoFont(size: 8, weight: .bold))
                            .foregroundColor(Theme.Status.warning)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.Status.warning.opacity(0.14))
                            )
                    }
                    if let uptime = processUptime {
                        Text(uptime)
                            .font(appSettings.appMonoFont(size: 9))
                            .foregroundColor(.secondary.opacity(0.7))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                Text(displayName)
                    .font(appSettings.appMonoFont(size: appSettings.fontSize - 1))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Activity sparkline — tight fixed lane.
            Group {
                if history.count >= 2 {
                    Sparkline(
                        values: history,
                        stroke: Theme.Liquid.rowSparkline,
                        fill: Theme.Liquid.rowSparkline.opacity(0.2),
                        lineWidth: 1.0,
                        showDot: true
                    )
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(width: 42, height: 16)

            // CPU chip.
            Group {
                if let cpu = cpuUsage, cpu > 0.1 {
                    Text(String(format: "%.0f%%", cpu))
                        .font(appSettings.appMonoFont(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Capsule().fill(cpuHeatColor(cpu)))
                } else {
                    Text("—")
                        .font(appSettings.appMonoFont(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.45))
                }
            }
            .frame(width: 38, alignment: .trailing)

            // Memory.
            Group {
                if let mem = port.memoryMB {
                    Text(formatMemoryCompact(mem))
                        .font(appSettings.appMonoFont(size: 9, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize()
                } else {
                    Text("—")
                        .font(appSettings.appMonoFont(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.45))
                }
            }
            .frame(width: 42, alignment: .trailing)

            // Actions — info tooltip + pause/resume + kill.
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
                    .help(infoTooltip)
                // Reversible, so it fires on first tap — no arming dance like
                // the kill button. Pausing SIGSTOPs the pid: the port stays
                // bound, the process freezes with its state.
                Button(action: onPauseResume) {
                    Image(systemName: port.isStopped ? "play.circle" : "pause.circle")
                        .font(.system(size: 12))
                        .foregroundColor(port.isStopped ? Theme.Status.connected : Theme.Status.warning)
                }
                .buttonStyle(.plain)
                .help(port.isStopped
                      ? "Resume process (SIGCONT)"
                      : "Pause process (SIGSTOP) — port stays bound, state is kept")
                .accessibilityLabel(port.isStopped
                                    ? "Resume process \(port.command), pid \(port.pid)"
                                    : "Pause process \(port.command), pid \(port.pid)")
                Button(action: {
                    // I arm on the first tap and only fire onKill on the second tap
                    // inside the 3s window — keeps accidental kills from happening.
                    if killArmed {
                        onKill()
                        withAnimation(.easeInOut(duration: 0.15)) { killArmed = false }
                    } else {
                        withAnimation(.easeInOut(duration: 0.15)) { killArmed = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation(.easeInOut(duration: 0.15)) { killArmed = false }
                        }
                    }
                }) {
                    if killArmed {
                        Image(systemName: "bolt.slash.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.Action.kill))
                    } else {
                        Image(systemName: Theme.Icon.kill)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.Action.kill)
                    }
                }
                .buttonStyle(.plain)
                .help(killArmed ? "Tap again to confirm kill" : "Kill process")
                .accessibilityLabel(killArmed ? "Confirm kill" : "Kill process \(port.command), pid \(port.pid)")
            }
            .frame(width: 64, alignment: .trailing)
            .opacity(isHovered || isSelected ? 1 : Theme.Opacity.disabled)
        }
        .padding(.horizontal, Theme.Spacing.contentInset)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? Theme.Surface.selected
                        : (isHovered ? Theme.Surface.hover : Color.clear)
                )
                .padding(.horizontal, 4)
        )
        .overlay(alignment: .leading) {
            // A subtle type-colour rail on the selected row — a deck signature.
            if isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .fill(typeColor)
                    .frame(width: 2)
                    .padding(.vertical, 6)
                    .padding(.leading, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        // Combined for a clean read, but the row still has to be operable:
        // merging the children swallowed the kill button's label entirely, and
        // onTapGesture is invisible to VoiceOver. Custom actions expose
        // select/kill/favorite through the actions rotor instead.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            port.isUnixSocket
                ? "Socket \(port.command), pid \(port.pid)"
                : "Port \(port.port) \(port.protocolName.uppercased()), \(port.command), pid \(port.pid)"
        )
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to select. Actions available via the actions rotor.")
        .accessibilityAction(named: Text("Select")) { onSelect() }
        .accessibilityAction(named: Text(isFavorite ? "Remove from favorites" : "Add to favorites")) { onToggleFavorite() }
        .accessibilityAction(named: Text(killArmed ? "Confirm kill" : "Kill process")) { onKill() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
            // .set() instead of push/pop — an unbalanced push (two overlapping
            // hovers) used to wedge the cursor stack and leave a stuck hand.
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

// MARK: - Row Helpers
private extension PortListRow {
    func processTypeColor(_ type: ProcessType) -> Color {
        switch type {
        case .system: return Theme.Classification.system
        case .userApp: return Theme.Classification.userApp
        case .developerTool: return Theme.Classification.developerTool
        case .other: return Theme.Classification.other
        }
    }

}
