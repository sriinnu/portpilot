import SwiftUI

// MARK: - Column Headers
// The deck-style header — narrow fixed columns on the right mirror the row
// layout so the eye can scan Port → Process → Activity → Stats → Actions.
// I pin every label with .fixedSize so a tight pane width never lets a header
// wrap letter-by-letter.
struct PortListHeader: View {
    @ObservedObject private var appSettings = AppSettings.shared

    private func label(_ text: String) -> some View {
        Text(text)
            .font(appSettings.appFont(size: 9, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: true, vertical: false)
            .lineLimit(1)
    }

    var body: some View {
        HStack(spacing: 6) {
            label("PORT").frame(width: 64, alignment: .leading)
            label("PROCESS").frame(maxWidth: .infinity, alignment: .leading)
            label("ACT").frame(width: 42, alignment: .trailing)
            label("CPU").frame(width: 38, alignment: .trailing)
            label("MEM").frame(width: 42, alignment: .trailing)
            Spacer().frame(width: 46)
        }
        .padding(.horizontal, Theme.Spacing.contentInset)
        .padding(.vertical, 8)
        .background(Theme.Surface.headerTint)
    }
}
