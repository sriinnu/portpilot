import SwiftUI

private let toolbarSelectionSpring = Animation.spring(response: 0.28, dampingFraction: 0.82, blendDuration: 0.12)

// MARK: - Main Window Toolbar
struct MainWindowToolbar: View {
    @Binding var searchText: String
    @ObservedObject var viewModel: PortViewModel
    let onRefresh: () -> Void
    let onSettings: () -> Void
    let isLoading: Bool
    let portCount: Int
    let totalCount: Int
    @Binding var selectedMainTab: MainTab

    var body: some View {
        VStack(spacing: 0) {
            // Top row: refresh, count, search, settings
            HStack(spacing: 10) {
                Button(action: onRefresh) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: Theme.Icon.refresh)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.Action.refresh)
                    }
                }
                .buttonStyle(.borderless)
                .help("Refresh (\u{2318}R)")

                if selectedMainTab == .ports {
                    ToolbarPortSummary(portCount: portCount, totalCount: totalCount)
                } else {
                    Text("Schedules")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Spacer()

                // Search field
                HStack(spacing: 6) {
                    Image(systemName: Theme.Icon.search)
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField(selectedMainTab == .ports ? "Search ports, processes..." : "Search cronjobs...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: Theme.Icon.clearSearch)
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
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
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .help("Settings (\u{2318},)")
            }
            .padding(.horizontal, Theme.Spacing.sectionInset)
            .padding(.vertical, Theme.Spacing.sm)

            // Main tabs row (Ports / Schedules)
            HStack(spacing: 8) {
                MainTabPill(
                    label: "Ports",
                    icon: "network",
                    isSelected: selectedMainTab == .ports
                ) {
                    withAnimation(toolbarSelectionSpring) {
                        selectedMainTab = .ports
                    }
                }

                MainTabPill(
                    label: "Schedules",
                    icon: "clock",
                    isSelected: selectedMainTab == .schedules
                ) {
                    withAnimation(toolbarSelectionSpring) {
                        selectedMainTab = .schedules
                    }
                }

                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.sectionInset)
            .padding(.bottom, Theme.Spacing.xs)

            // Source tabs row (only visible for Ports tab)
            if selectedMainTab == .ports {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PortSourceFilter.allCases) { source in
                            SourceTabPill(
                                source: source,
                                count: viewModel.sourceCounts[source] ?? 0,
                                isSelected: viewModel.selectedSourceFilter == source
                            ) {
                                withAnimation(toolbarSelectionSpring) {
                                    viewModel.selectedSourceFilter = viewModel.selectedSourceFilter == source ? .all : source
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Theme.Surface.headerTint)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }
                .padding(.horizontal, Theme.Spacing.sectionInset)
                .padding(.bottom, Theme.Spacing.xs)

                // Filter pills row
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        // Protocol filters
                        ProtocolPill(label: "TCP", isSelected: viewModel.selectedProtocol == .tcp) {
                            withAnimation(toolbarSelectionSpring) {
                                viewModel.selectedProtocol = viewModel.selectedProtocol == .tcp ? .all : .tcp
                            }
                        }
                        ProtocolPill(label: "UDP", isSelected: viewModel.selectedProtocol == .udp) {
                            withAnimation(toolbarSelectionSpring) {
                                viewModel.selectedProtocol = viewModel.selectedProtocol == .udp ? .all : .udp
                            }
                        }

                        DividerPill()

                        // Category filters
                        ForEach(FilterCategory.allCases) { cat in
                            CategoryPill(
                                category: cat,
                                count: viewModel.categoryCounts[cat] ?? 0,
                                isSelected: viewModel.selectedCategory == cat
                            ) {
                                withAnimation(toolbarSelectionSpring) {
                                    viewModel.selectedCategory = viewModel.selectedCategory == cat ? .all : cat
                                }
                            }
                        }

                        DividerPill()

                        // Hide system toggle
                        TogglePill(
                            label: "Hide System",
                            icon: viewModel.hideSystemProcesses ? "eye.slash" : "eye",
                            isActive: viewModel.hideSystemProcesses
                        ) {
                            withAnimation(toolbarSelectionSpring) {
                                viewModel.hideSystemProcesses.toggle()
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, Theme.Spacing.sectionInset)
                    .padding(.vertical, Theme.Spacing.sm)
                }
            }
        }
        .background(Theme.Surface.windowBackground)
    }
}

// MARK: - Main Tab Pill
struct MainTabPill: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? Theme.Badge.accentBackground
                    : Theme.Surface.chromeTint
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Size.cornerRadiusLarge, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.white.opacity(0.16) : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Size.cornerRadiusLarge, style: .continuous))
            .animation(toolbarSelectionSpring, value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct ToolbarPortSummary: View {
    let portCount: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: Theme.Icon.portsTab)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            Text("\(portCount)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)

            Text(portCount == totalCount ? "active" : "shown")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            if portCount != totalCount {
                Text("of \(totalCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary.opacity(Theme.Opacity.subtle))
            }
        }
    }
}

struct SourceTabPill: View {
    let source: PortSourceFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: source.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(source.shortLabel)
                    .font(.system(size: 12, weight: .semibold))
                if isSelected || source == .all {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(isSelected ? .white.opacity(Theme.Opacity.subtle) : .secondary.opacity(Theme.Opacity.secondary))
                }
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? source.color
                    : Theme.Surface.chromeTint
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.white.opacity(0.16) : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .cornerRadius(13)
            .animation(toolbarSelectionSpring, value: isSelected)
        }
        .buttonStyle(.plain)
        .help(source.rawValue)
    }
}

struct ProtocolPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    isSelected
                        ? Theme.Badge.accentBackground
                        : Theme.Surface.chromeTint
                )
                .cornerRadius(11)
        }
        .buttonStyle(.plain)
    }
}

struct CategoryPill: View {
    let category: FilterCategory
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    private var pillColor: Color {
        switch category {
        case .all: return Theme.Badge.accentBackground
        case .web: return Theme.Section.local
        case .database: return Theme.Section.database
        case .dev: return Theme.Section.kubernetes
        case .system: return Theme.Classification.system
        case .favorites: return Color.yellow
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: category.icon)
                    .font(.system(size: 10))
                Text(category.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                if count > 0 && category != .all && isSelected {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(isSelected ? .white.opacity(Theme.Opacity.subtle) : .secondary.opacity(Theme.Opacity.secondary))
                }
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isSelected
                    ? pillColor
                    : Theme.Surface.chromeTint
            )
            .cornerRadius(11)
        }
        .buttonStyle(.plain)
    }
}

struct TogglePill: View {
    let label: String
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(isActive ? .white : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isActive
                    ? Theme.Section.ssh
                    : Theme.Surface.chromeTint
            )
            .cornerRadius(11)
        }
        .buttonStyle(.plain)
    }
}

struct DividerPill: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(Theme.Opacity.disabled))
            .frame(width: 1, height: 18)
    }
}
