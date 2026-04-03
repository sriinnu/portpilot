import SwiftUI

// MARK: - Cronjob List Panel (for Main Window)
struct CronjobListPanel: View {
    @ObservedObject var viewModel: PortViewModel
    @Binding var selectedCronjob: CronjobEntry?

    @State private var hoveredCronjobId: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Schedules")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Text("\(viewModel.cronjobs.count) cronjobs")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Button(action: { viewModel.refreshCronjobs() }) {
                    Image(systemName: Theme.Icon.refresh)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Action.refresh)
                }
                .buttonStyle(.borderless)
                .help("Refresh cronjobs")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.Surface.headerTint)

            Divider()

            // Cronjob list
            if viewModel.isLoadingCronjobs {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Scanning cronjobs...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else if viewModel.cronjobs.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No Cronjobs Found")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Text("User and system cronjobs appear here")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.cronjobs) { job in
                            CronjobRowView(
                                cronjob: job,
                                isSelected: selectedCronjob?.id == job.id,
                                isHovered: hoveredCronjobId == job.id
                            )
                            .onTapGesture {
                                selectedCronjob = job
                            }
                            .onHover { hovering in
                                hoveredCronjobId = hovering ? job.id : nil
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Theme.Surface.chromeTint)
    }
}

// MARK: - Cronjob Row View
struct CronjobRowView: View {
    let cronjob: CronjobEntry
    let isSelected: Bool
    let isHovered: Bool

    private var sourceColor: Color {
        cronjob.source == "user" ? Theme.Classification.userApp : Theme.Classification.system
    }

    var body: some View {
        HStack(spacing: 8) {
            // Source indicator
            Circle()
                .fill(sourceColor)
                .frame(width: 6, height: 6)

            // Job info
            VStack(alignment: .leading, spacing: 2) {
                Text(cronjob.scheduleHuman ?? cronjob.schedule)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.yellow)
                    .lineLimit(1)

                Text(cronjob.command)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }

            Spacer()

            // User badge
            if let user = cronjob.user {
                Text(user)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            isSelected
                ? Theme.Badge.accentBackground.opacity(0.2)
                : isHovered
                    ? Theme.Surface.hover
                    : Color.clear
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    isSelected ? Theme.Badge.accentBackground : Color.clear,
                    lineWidth: 1
                )
        )
        .cornerRadius(4)
        .contentShape(Rectangle())
    }
}

// MARK: - Cronjob Configuration Panel
struct CronjobConfigurationPanel: View {
    let cronjob: CronjobEntry?
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let job = cronjob {
                // Header
                HStack {
                    Text("Cronjob Details")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.Surface.headerTint)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Schedule
                        DetailRow(label: "Schedule", value: job.schedule)

                        if let human = job.scheduleHuman {
                            DetailRow(label: "Human", value: human)
                        }

                        if let user = job.user {
                            DetailRow(label: "User", value: user)
                        }

                        DetailRow(label: "Source", value: job.source)

                        if let nextRun = job.nextRun {
                            DetailRow(label: "Next Run", value: Self.dateFormatter.string(from: nextRun))
                        }

                        Divider()
                            .padding(.vertical, 4)

                        // Command
                        Text("Command")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        Text(job.command)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.Surface.chromeTint)
                            .cornerRadius(6)
                    }
                    .padding(12)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Select a cronjob")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.Surface.chromeTint)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
}

// MARK: - Detail Row
struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Cronjob Logs Panel
struct CronjobLogsPanel: View {
    @ObservedObject var viewModel: PortViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Activity")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Button(action: { viewModel.clearLogs() }) {
                    Text("Clear")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)

                Button(action: { viewModel.copyLogs() }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Copy logs")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.Surface.headerTint)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if viewModel.logs.isEmpty {
                        Text("No activity yet")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 20)
                    } else {
                        ForEach(viewModel.logs.reversed()) { entry in
                            LogEntryRow(entry: entry)
                        }
                    }
                }
                .padding(8)
            }
        }
        .background(Theme.Surface.chromeTint)
    }
}
