import SwiftUI

// MARK: - Main Window Toolbar
struct MainWindowToolbar: View {
    @Binding var searchText: String
    @ObservedObject var viewModel: PortViewModel
    let onRefresh: () -> Void
    let onSettings: () -> Void
    let isLoading: Bool
    let portCount: Int
    let totalCount: Int

    var body: some View {
        VStack(spacing: 0) {
            // Top row: refresh, count, search, settings
            HStack(spacing: 12) {
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
                .help("Refresh ports (\u{2318}R)")

                HStack(spacing: 4) {
                    Text("\(portCount)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.Badge.accentText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.Badge.accentBackground)
                        .cornerRadius(Theme.Size.cornerRadiusSmall)
                    if portCount != totalCount {
                        Text("/ \(totalCount)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Text("ports")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Search field
                HStack(spacing: 6) {
                    Image(systemName: Theme.Icon.search)
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField("Search ports, processes...", text: $searchText)
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
                .padding(.vertical, 5)
                .background(Theme.Surface.controlBackground)
                .cornerRadius(Theme.Size.cornerRadius)
                .frame(maxWidth: 250)

                Button(action: onSettings) {
                    Image(systemName: Theme.Icon.settings)
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .help("Settings (\u{2318},)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Filter pills row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Protocol filters
                    ProtocolPill(label: "TCP", isSelected: viewModel.selectedProtocol == .tcp) {
                        viewModel.selectedProtocol = viewModel.selectedProtocol == .tcp ? .all : .tcp
                    }
                    ProtocolPill(label: "UDP", isSelected: viewModel.selectedProtocol == .udp) {
                        viewModel.selectedProtocol = viewModel.selectedProtocol == .udp ? .all : .udp
                    }

                    DividerPill()

                    // Category filters
                    ForEach(FilterCategory.allCases) { cat in
                        CategoryPill(
                            category: cat,
                            count: viewModel.categoryCounts[cat] ?? 0,
                            isSelected: viewModel.selectedCategory == cat
                        ) {
                            viewModel.selectedCategory = viewModel.selectedCategory == cat ? .all : cat
                        }
                    }

                    DividerPill()

                    // Hide system toggle
                    TogglePill(
                        label: "Hide System",
                        icon: viewModel.hideSystemProcesses ? "eye.slash" : "eye",
                        isActive: viewModel.hideSystemProcesses
                    ) {
                        viewModel.hideSystemProcesses.toggle()
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .background(Theme.Surface.windowBackground)
    }
}

// MARK: - Filter Pill Components

struct ProtocolPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    isSelected
                        ? Theme.Badge.accentBackground
                        : Color(nsColor: .quaternaryLabelColor).opacity(0.5)
                )
                .cornerRadius(10)
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
            HStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.system(size: 9))
                Text(category.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                if count > 0 && category != .all {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary.opacity(0.7))
                }
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isSelected
                    ? pillColor
                    : Color(nsColor: .quaternaryLabelColor).opacity(0.5)
            )
            .cornerRadius(10)
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
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(isActive ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isActive
                    ? Theme.Section.ssh
                    : Color(nsColor: .quaternaryLabelColor).opacity(0.5)
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

struct DividerPill: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 1, height: 16)
    }
}
