import SwiftUI

// MARK: - Timeline Panel

/// The inspector's Timeline tab: port lifecycle events (bound, released,
/// killed, paused, resumed, guard) as a newest-first stream. Renders from
/// the structured `event` field, not message parsing.
struct TimelinePanel: View {
    @ObservedObject var viewModel: PortViewModel
    var selectedPort: PortProcess? = nil

    @State private var filterToSelected = false

    private var events: [LogEntry] {
        let typed = viewModel.logs.filter { $0.event != nil }
        guard filterToSelected, let port = selectedPort else { return typed }
        return typed.filter { $0.portNumber == port.port }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            timelineHeader

            Divider()

            if events.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(events.reversed()) { entry in
                            TimelineEventRow(entry: entry)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Theme.Surface.controlBackground)
    }

    private var timelineHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.Liquid.headerIcon)
            Text("Timeline")
                .font(.system(size: 12, weight: .bold))

            Text("\(events.count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))

            Spacer()

            if selectedPort != nil {
                Toggle("This port", isOn: $filterToSelected)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No lifecycle events yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Text("Ports binding, releasing, or getting acted on will show up here as they happen.")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Timeline Event Row

private struct TimelineEventRow: View {
    let entry: LogEntry
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Time gutter — fixed lane so the dots column stays straight.
            Text(entry.formattedTime)
                .font(appSettings.appMonoFont(size: 9))
                .foregroundColor(.secondary.opacity(0.7))
                .frame(width: 46, alignment: .leading)

            if let event = entry.event {
                Image(systemName: event.symbol)
                    .font(.system(size: 10))
                    .foregroundColor(event.color)
                    .frame(width: 14)
            }

            Text(entry.message)
                .font(appSettings.appMonoFont(size: appSettings.fontSize - 1))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}
