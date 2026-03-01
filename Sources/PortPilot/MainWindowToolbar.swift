import SwiftUI

// MARK: - Main Window Toolbar
struct MainWindowToolbar: View {
    @Binding var searchText: String
    let onRefresh: () -> Void
    let onSettings: () -> Void
    let isLoading: Bool
    let portCount: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 12) {
            // Green refresh button
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

            // Vibrant blue port count badge
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

            // Settings button
            Button(action: onSettings) {
                Image(systemName: Theme.Icon.settings)
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help("Settings (\u{2318},)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.Surface.windowBackground)
    }
}
