import SwiftUI

// MARK: - Liquid Sidebar

/// The left-hand nav rail: protocol pills and source filters grouped under
/// quiet section labels, topped with a brand mark and footed with a live dot.
///
/// I drive every control off the view model's existing filters so the
/// sidebar and the toolbar stay in lock step — selecting a protocol here
/// updates the same `selectedProtocol` the toolbar reads.
struct LiquidSidebar: View {
    /// The view model I read filter state and counts from, and mutate on taps.
    @ObservedObject var viewModel: PortViewModel
    @ObservedObject private var appSettings = AppSettings.shared
    /// Current top-level section (Ports vs Schedules). Bound so the sidebar
    /// can switch tabs without owning the source of truth.
    @Binding var selectedMainTab: MainTab

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 10)

            // Scrollable body — sections can grow beyond the pane height.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    sectionNav
                    protocolGroup
                    sourcesGroup
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            Divider().opacity(0.4)

            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(width: 176)
        .background(Theme.Surface.chromeTint)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.Surface.groupedStroke)
                .frame(width: 0.5)
        }
    }

    // MARK: Brand

    private var brand: some View {
        HStack(spacing: 8) {
            Image(systemName: Theme.Icon.appLogo)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.Liquid.accentPurple)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.Liquid.accentPurpleMuted)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("PortPilot")
                    .font(appSettings.appFont(size: 13, weight: .bold))
                Text("Liquid Deck")
                    .font(appSettings.appFont(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            Spacer()
        }
        .padding(.bottom, 2)
    }

    // MARK: Main section nav

    private var sectionNav: some View {
        VStack(spacing: 3) {
            navItem(
                label: "Ports",
                icon: Theme.Icon.portsTab,
                count: viewModel.totalCount,
                tint: Theme.Liquid.accentPurple,
                selected: selectedMainTab == .ports,
                action: { selectedMainTab = .ports }
            )
            navItem(
                label: "Schedules",
                icon: "clock.fill",
                count: viewModel.cronjobs.count,
                tint: Theme.Status.warning,
                selected: selectedMainTab == .schedules,
                action: { selectedMainTab = .schedules }
            )
        }
    }

    // MARK: Protocol group

    private var protocolGroup: some View {
        VStack(alignment: .leading, spacing: 4) {
            groupLabel("Protocol")
            filterPill("All", tint: Theme.Liquid.accentPurple, selected: viewModel.selectedProtocol == .all) {
                viewModel.selectedProtocol = .all
            }
            filterPill("TCP", tint: Theme.Action.treeView, selected: viewModel.selectedProtocol == .tcp) {
                viewModel.selectedProtocol = .tcp
            }
            filterPill("UDP", tint: Theme.Section.kubernetes, selected: viewModel.selectedProtocol == .udp) {
                viewModel.selectedProtocol = .udp
            }
        }
    }

    // MARK: Sources group

    private var sourcesGroup: some View {
        VStack(alignment: .leading, spacing: 4) {
            groupLabel("Services")
            ForEach(PortSourceFilter.allCases) { src in
                sourceRow(src)
            }
        }
    }

    private func sourceRow(_ src: PortSourceFilter) -> some View {
        let selected = viewModel.selectedSourceFilter == src
        let count = viewModel.sourceCounts[src] ?? 0
        return Button {
            viewModel.selectedSourceFilter = src
        } label: {
            HStack(spacing: 8) {
                Image(systemName: src.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(selected ? .white : src.color)
                    .frame(width: 14)
                Text(src.rawValue)
                    .font(appSettings.appFont(size: 11, weight: .medium))
                    .foregroundColor(selected ? .white : .primary.opacity(0.85))
                Spacer()
                if count > 0 {
                    Text(verbatim: "\(count)")
                        .font(appSettings.appMonoFont(size: 9, weight: .semibold))
                        .foregroundColor(selected ? .white.opacity(0.85) : .secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(selected ? Color.white.opacity(0.15) : Theme.Surface.headerTint)
                        )
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? src.color : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.Status.connected)
                .frame(width: 6, height: 6)
                .shadow(color: Theme.Status.connected.opacity(0.5), radius: 2)
            Text("Monitoring live")
                .font(appSettings.appFont(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    // MARK: Helpers

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(appSettings.appFont(size: 9, weight: .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundColor(.secondary.opacity(0.75))
            .padding(.top, 4).padding(.leading, 8)
    }

    private func navItem(label: String, icon: String, count: Int, tint: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(selected ? .white : tint)
                    .frame(width: 16)
                Text(label)
                    .font(appSettings.appFont(size: 12, weight: .semibold))
                    .foregroundColor(selected ? .white : .primary)
                Spacer()
                Text(verbatim: "\(count)")
                    .font(appSettings.appMonoFont(size: 9, weight: .semibold))
                    .foregroundColor(selected ? .white.opacity(0.85) : .secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(selected ? Color.white.opacity(0.15) : Theme.Surface.headerTint)
                    )
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? tint : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func filterPill(_ label: String, tint: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                    .opacity(selected ? 0 : 1)
                Text(label)
                    .font(appSettings.appFont(size: 11, weight: .medium))
                    .foregroundColor(selected ? .white : .primary.opacity(0.85))
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? tint : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
