import SwiftUI

private let toolbarSelectionSpring = Animation.spring(response: 0.28, dampingFraction: 0.82, blendDuration: 0.12)

// MARK: - Main Window Toolbar
struct MainWindowToolbar: View {
    @ObservedObject private var appSettings = AppSettings.shared

    @Binding var searchText: String
    @ObservedObject var viewModel: PortViewModel
    let onRefresh: () -> Void
    let onSettings: () -> Void
    let isLoading: Bool
    let portCount: Int
    let totalCount: Int
    @Binding var selectedMainTab: MainTab

    var body: some View {
        // The sidebar owns section nav, protocol filters, and services. The
        // toolbar stays focused on refresh, count, Hide System, search (with
        // a ⌘K chip for the palette), and settings. No duplicate nav.
        HStack(spacing: 10) {
            Button(action: onRefresh) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: Theme.Icon.refresh)
                        .font(appSettings.appFont(size: 13))
                        .foregroundColor(Theme.Action.refresh)
                }
            }
            .buttonStyle(.borderless)
            .help("Refresh ports")

            if selectedMainTab == .ports {
                ToolbarPortSummary(portCount: portCount, totalCount: totalCount)
            } else {
                Text("Schedules")
                    .font(appSettings.appFont(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
            }

            // Hide system processes — the one filter that isn't in the sidebar.
            Button {
                withAnimation(toolbarSelectionSpring) {
                    viewModel.hideSystemProcesses.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.hideSystemProcesses ? "eye.slash" : "eye")
                        .font(appSettings.appFont(size: 11, weight: .medium))
                    Text(viewModel.hideSystemProcesses ? "System hidden" : "Showing all")
                        .font(appSettings.appFont(size: 11, weight: .medium))
                }
                .foregroundColor(viewModel.hideSystemProcesses ? Theme.Status.warning : .secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(viewModel.hideSystemProcesses ? Theme.Status.warning.opacity(0.15) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .help("Toggle system-process visibility")

            Spacer()

            // Search with a persistent ⌘K hint — command palette is the fast path.
            HStack(spacing: 6) {
                Image(systemName: Theme.Icon.search)
                    .foregroundColor(.secondary)
                    .font(appSettings.appFont(size: 12))
                TextField(selectedMainTab == .ports ? "Search ports, processes..." : "Search cronjobs...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(appSettings.appFont(size: 13))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: Theme.Icon.clearSearch)
                            .foregroundColor(.secondary)
                            .font(appSettings.appFont(size: 11))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                } else {
                    Text("\u{2318}K")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.Surface.headerTint)
                        )
                        .help("Open Command Palette")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Theme.Surface.chromeTint)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Size.cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Size.cornerRadius, style: .continuous))
            .frame(maxWidth: 280)

            Button(action: onSettings) {
                Image(systemName: Theme.Icon.settings)
                    .font(appSettings.appFont(size: 13))
            }
            .buttonStyle(.borderless)
            .help("Open settings")
        }
        .padding(.horizontal, Theme.Spacing.sectionInset)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Surface.windowBackground)
    }
}

// MARK: - Port Summary

struct ToolbarPortSummary: View {
    @ObservedObject private var appSettings = AppSettings.shared

    let portCount: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: Theme.Icon.portsTab)
                .font(appSettings.appFont(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            Text("\(portCount)")
                .font(appSettings.appMonoFont(size: 12, weight: .semibold))
                .foregroundColor(.primary)

            Text(portCount == totalCount ? "active" : "shown")
                .font(appSettings.appFont(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            if portCount != totalCount {
                Text("of \(totalCount)")
                    .font(appSettings.appMonoFont(size: 11))
                    .foregroundColor(.secondary.opacity(Theme.Opacity.subtle))
            }
        }
    }
}

