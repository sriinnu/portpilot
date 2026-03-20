import SwiftUI

// MARK: - Port History View
struct PortHistoryView: View {
    @StateObject private var historyManager = HistoryManager()
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("History Type", selection: $selectedTab) {
                Text("Timeline").tag(0)
                Text("Statistics").tag(1)
                Text("Port Details").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Content based on selected tab
            switch selectedTab {
            case 0:
                TimelineView(historyManager: historyManager)
            case 1:
                StatisticsView(historyManager: historyManager)
            case 2:
                PortDetailsView(historyManager: historyManager)
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Timeline View
struct TimelineView: View {
    @ObservedObject var historyManager: HistoryManager

    var body: some View {
        if historyManager.getAllHistory().isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No history yet")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                Text("Port kill history will appear here")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(historyManager.getRecentHistory(limit: 100)) { entry in
                        TimelineEntryRow(entry: entry)
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }
}

// MARK: - Timeline Entry Row
struct TimelineEntryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            // Timeline indicator
            VStack(spacing: 0) {
                Circle()
                    .fill(entry.wasForceKilled ? Theme.Status.error : Theme.Status.connected)
                    .frame(width: 10, height: 10)
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 2)
            }
            .frame(width: 20)

            // Entry details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Port \(entry.port)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text(entry.protocolName.uppercased())
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                        .cornerRadius(3)

                    if entry.wasForceKilled {
                        Text("FORCED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Theme.Status.error)
                            .cornerRadius(3)
                    }
                }

                Text(entry.command)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)

                if let duration = entry.duration {
                    Text("Duration: \(formatDuration(duration))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }

            Spacer()

            // Time
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.relativeTime)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Text(entry.formattedDate)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration))s"
        } else if duration < 3600 {
            return "\(Int(duration / 60))m \(Int(duration.truncatingRemainder(dividingBy: 60)))s"
        } else {
            return "\(Int(duration / 3600))h \(Int(duration.truncatingRemainder(dividingBy: 3600) / 60))m"
        }
    }
}

// MARK: - Statistics View
struct StatisticsView: View {
    @ObservedObject var historyManager: HistoryManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary cards
                let stats = historyManager.getHistoryStats()
                HStack(spacing: 16) {
                    StatCard(title: "Total Kills", value: "\(stats.totalKills)", icon: "xmark.circle.fill", color: Theme.Status.error)
                    StatCard(title: "Ports Killed", value: "\(stats.uniquePortsKilled)", icon: "network", color: Theme.Section.local)
                    StatCard(title: "Kills Today", value: "\(stats.killsToday)", icon: "calendar", color: Theme.Action.add)
                }
                .padding(.horizontal)

                Divider()

                // Most killed ports
                VStack(alignment: .leading, spacing: 12) {
                    Text("Most Killed Ports")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal)

                    let mostKilled = historyManager.getMostKilledPorts(limit: 5)
                    if mostKilled.isEmpty {
                        Text("No data available")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    } else {
                        ForEach(mostKilled, id: \.port) { item in
                            HStack {
                                Text("Port \(item.port)")
                                    .font(.system(size: 12, design: .monospaced))
                                Spacer()
                                Text("\(item.count) kills")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                Divider()

                // Most killed commands
                VStack(alignment: .leading, spacing: 12) {
                    Text("Most Killed Commands")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal)

                    let mostKilledCommands = historyManager.getMostKilledCommands(limit: 5)
                    if mostKilledCommands.isEmpty {
                        Text("No data available")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    } else {
                        ForEach(mostKilledCommands, id: \.command) { item in
                            HStack {
                                Text(item.command)
                                    .font(.system(size: 12, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(item.count) kills")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                Divider()

                // Frequently restarted ports (from port usage)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Frequently Restarted Ports")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal)

                    let portStats = historyManager.getPortStats()
                    if portStats.frequentlyRestartedPorts.isEmpty {
                        Text("No frequently restarted ports detected")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    } else {
                        ForEach(portStats.frequentlyRestartedPorts, id: \.port) { item in
                            HStack {
                                Text("Port \(item.port)")
                                    .font(.system(size: 12, design: .monospaced))
                                Spacer()
                                Text("\(item.restartCount) restarts")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 24, weight: .bold))

            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.Surface.controlBackground)
        .cornerRadius(12)
    }
}

// MARK: - Port Details View
struct PortDetailsView: View {
    @ObservedObject var historyManager: HistoryManager
    @State private var selectedPort: Int?

    private var portUsage: [PortUsageEntry] {
        historyManager.getAllPortUsage()
    }

    private var uniquePorts: [Int] {
        Array(Set(portUsage.map { $0.port })).sorted()
    }

    var body: some View {
        if portUsage.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No port usage data")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                Text("Port usage history will appear here")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                // Port list
                List(uniquePorts, id: \.self, selection: $selectedPort) { port in
                    PortUsageRow(
                        port: port,
                        entries: portUsage.filter { $0.port == port },
                        isSelected: selectedPort == port
                    )
                }
                .listStyle(.sidebar)
                .frame(minWidth: 180)

                // Port details
                if let port = selectedPort, let entry = portUsage.first(where: { $0.port == port }) {
                    PortDetailPanel(port: port, entries: portUsage.filter { $0.port == port })
                } else {
                    VStack {
                        Image(systemName: "arrow.left.circle")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("Select a port to view details")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

// MARK: - Port Usage Row
struct PortUsageRow: View {
    let port: Int
    let entries: [PortUsageEntry]
    let isSelected: Bool

    private var lastEntry: PortUsageEntry? {
        entries.max(by: { $0.lastSeen < $1.lastSeen })
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Port \(port)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                if let entry = lastEntry {
                    Text(entry.relativeLastSeen)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text("\(entries.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(4)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
}

// MARK: - Port Detail Panel
struct PortDetailPanel: View {
    let port: Int
    let entries: [PortUsageEntry]

    private var firstEntry: PortUsageEntry? {
        entries.min(by: { $0.firstSeen < $1.firstSeen })
    }

    private var lastEntry: PortUsageEntry? {
        entries.max(by: { $0.lastSeen < $1.lastSeen })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Port \(port)")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                    Text("TCP")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Divider()

                // Stats
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("First Seen")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(firstEntry?.formattedFirstSeen ?? "Unknown")
                            .font(.system(size: 13, weight: .medium))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last Seen")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(lastEntry?.formattedLastSeen ?? "Unknown")
                            .font(.system(size: 13, weight: .medium))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Occurrences")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("\(entries.count)")
                            .font(.system(size: 13, weight: .medium))
                    }
                }

                Divider()

                // History timeline
                VStack(alignment: .leading, spacing: 12) {
                    Text("Activity Timeline")
                        .font(.system(size: 14, weight: .semibold))

                    ForEach(entries.sorted(by: { $0.lastSeen > $1.lastSeen })) { entry in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Theme.Status.connected)
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.command)
                                    .font(.system(size: 12, design: .monospaced))
                                Text("PID: \(entry.pid) | User: \(entry.user)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text(entry.relativeLastSeen)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Preview
#Preview {
    PortHistoryView()
        .frame(width: 600, height: 400)
}
