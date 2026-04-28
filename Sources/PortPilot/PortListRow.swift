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
            lines.append("Memory: \(formatMemory(mem))")
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
                        .foregroundColor(.yellow)
                }
            }
            .frame(width: 12)
            .onTapGesture { onToggleFavorite() }
            .help(isFavorite ? "Remove from favorites" : "Add to favorites")

            // Port column — dominant typography on top, protocol under. Tightened
            // to 64pt so narrow window widths don't wrap the label vertically.
            VStack(alignment: .leading, spacing: 2) {
                if port.isUnixSocket {
                    Text(verbatim: "PID \(port.pid)")
                        .font(appSettings.appMonoFont(size: appSettings.fontSize, weight: .bold))
                        .fixedSize(horizontal: true, vertical: false)
                        .lineLimit(1)
                } else {
                    Text(verbatim: ":\(port.port)")
                        .font(appSettings.appMonoFont(size: appSettings.fontSize + 1, weight: .bold))
                        .fixedSize(horizontal: true, vertical: false)
                        .lineLimit(1)
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
                    Text(formatMemory(mem))
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

            // Actions — info tooltip + kill button.
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
                    .help(infoTooltip)
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
            }
            .frame(width: 46, alignment: .trailing)
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
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
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

    func formatMemory(_ mb: Double) -> String {
        if mb >= 1024 { return String(format: "%.1fG", mb / 1024.0) }
        if mb >= 10 { return String(format: "%.0fM", mb) }
        return String(format: "%.1fM", mb)
    }

    /// Smooth heat-map: 0% teal → 25% blue → 50% amber → 75% orange → 100% red
    func cpuHeatColor(_ usage: Double) -> Color {
        let t = min(max(usage / 100.0, 0), 1)
        let r: Double, g: Double, b: Double
        if t < 0.25 {
            let p = t / 0.25
            r = 0.18 + p * 0.12;  g = 0.62 - p * 0.14;  b = 0.70 - p * 0.02
        } else if t < 0.50 {
            let p = (t - 0.25) / 0.25
            r = 0.30 + p * 0.58;  g = 0.48 + p * 0.14;  b = 0.68 - p * 0.52
        } else if t < 0.75 {
            let p = (t - 0.50) / 0.25
            r = 0.88 + p * 0.07;  g = 0.62 - p * 0.22;  b = 0.16 - p * 0.04
        } else {
            let p = (t - 0.75) / 0.25
            r = 0.95 - p * 0.05;  g = 0.40 - p * 0.18;  b = 0.12 + p * 0.08
        }
        return Color(red: r, green: g, blue: b)
    }
}
