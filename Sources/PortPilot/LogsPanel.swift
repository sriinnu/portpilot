import SwiftUI

// MARK: - Logs Panel
struct LogsPanel: View {
    @ObservedObject var viewModel: PortViewModel
    @ObservedObject private var appSettings = AppSettings.shared
    var selectedPort: PortProcess? = nil

    @State private var isExpanded = true
    @State private var filterByPort = false

    private var displayedLogs: [LogEntry] {
        if filterByPort, let port = selectedPort {
            return viewModel.logsForPort(port.port)
        }
        return viewModel.logs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            logsHeader

            if isExpanded {
                Divider()

                if displayedLogs.isEmpty {
                    emptyLogsView
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(displayedLogs) { entry in
                                    LogEntryRow(entry: entry)
                                        .id(entry.id)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .onChange(of: viewModel.logs.count) { _ in
                            if let lastLog = displayedLogs.last {
                                withAnimation {
                                    proxy.scrollTo(lastLog.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(minHeight: isExpanded ? 120 : 30)
        .background(Theme.Surface.controlBackground)
    }

    // MARK: - Header

    private var logsHeader: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? Theme.Icon.chevronDown : Theme.Icon.chevronRight)
                    .font(appSettings.appFont(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 12)

                Text("Logs")
                    .font(appSettings.appFont(size: 13, weight: .semibold))

                if !viewModel.logs.isEmpty {
                    Text("\(viewModel.logs.count)")
                        .font(appSettings.appMonoFont(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.Surface.chromeTint)
                        .cornerRadius(Theme.Size.cornerRadiusSmall)
                }

                Spacer()

                if isExpanded && !viewModel.logs.isEmpty {
                    // Filter by port toggle
                    if selectedPort != nil {
                        Button(action: { filterByPort.toggle() }) {
                            Image(systemName: filterByPort ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .font(appSettings.appFont(size: 11))
                                .foregroundColor(filterByPort ? Theme.Action.treeView : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(filterByPort ? "Show all logs" : "Filter by selected port")
                            .accessibilityLabel(filterByPort ? "Show all logs" : "Filter by selected port")
                    }

                    // Blue copy icon
                    Button(action: { viewModel.copyLogs() }) {
                        Image(systemName: Theme.Icon.copy)
                            .font(appSettings.appFont(size: 11))
                            .foregroundColor(Theme.Action.treeView)
                    }
                    .buttonStyle(.plain)
                    .help("Copy logs")
                        .accessibilityLabel("Copy logs")

                    // Red clear/trash icon
                    Button(action: { viewModel.clearLogs() }) {
                        Image(systemName: Theme.Icon.trash)
                            .font(appSettings.appFont(size: 11))
                            .foregroundColor(Theme.Action.kill)
                    }
                    .buttonStyle(.plain)
                    .help("Clear logs")
                        .accessibilityLabel("Clear logs")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.Surface.headerTint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyLogsView: some View {
        HStack {
            Spacer()
            Text("No log entries")
                .font(appSettings.appFont(size: 12))
                .foregroundColor(.secondary.opacity(0.6))
            Spacer()
        }
        .padding(.vertical, 16)
    }
}

// MARK: - Log Entry Row
struct LogEntryRow: View {
    @ObservedObject private var appSettings = AppSettings.shared

    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.formattedTime)
                .font(appSettings.appMonoFont(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            // Source as colored chip/pill
            Text(entry.source)
                .font(appSettings.appMonoFont(size: 10, weight: .medium))
                .foregroundColor(Theme.LogSource.color(for: entry.source))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.LogSource.backgroundColor(for: entry.source))
                .cornerRadius(Theme.Size.cornerRadiusSmall)
                .frame(width: 80, alignment: .leading)

            Text(entry.message)
                .font(appSettings.appMonoFont(size: 11))
                .foregroundColor(entry.level.color.opacity(0.9))
                .lineLimit(3)
        }
        .padding(.vertical, 2)
    }
}
