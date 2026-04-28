import SwiftUI

// MARK: - Footer
struct PortListFooter: View {
    let onAdd: () -> Void
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onAdd) {
                HStack(spacing: 4) {
                    // Green filled circle with white "+"
                    ZStack {
                        Circle()
                            .fill(Theme.Action.add)
                            .frame(width: 16, height: 16)
                        Image(systemName: Theme.Icon.add)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("Add")
                        .font(appSettings.appFont(size: appSettings.fontSize))
                        .foregroundColor(Theme.Action.add)
                }
            }
            .buttonStyle(.plain)
            .help("Add port forward")

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.contentInset)
        .padding(.vertical, Theme.Spacing.sm)
    }
}
