import SwiftUI

// MARK: - Empty State
struct PortListEmptyState: View {
    let hasFilters: Bool
    let onClearFilters: () -> Void
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: hasFilters ? "line.3.horizontal.decrease.circle" : "network.slash")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.5))
            Text(hasFilters ? "No matching ports" : "No ports found")
                .font(appSettings.appFont(size: appSettings.fontSize + 1, weight: .medium))
                .foregroundColor(.secondary)
            if hasFilters {
                Button("Clear Filters") { onClearFilters() }
                    .buttonStyle(.plain)
                    .font(appSettings.appFont(size: appSettings.fontSize))
                    .foregroundColor(.accentColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
