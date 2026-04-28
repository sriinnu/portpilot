import SwiftUI

// MARK: - Protocol Donut

/// Compact ring chart showing the ratio of TCP / UDP / Unix sockets.
///
/// I keep the math explicit and draw the slices inline so the Liquid surface
/// doesn't drag in a chart framework. The legend is tappable and mirrors the
/// ring's tap targets, so trackpad users get a bigger hit area than the
/// skinny arc.
struct ProtocolDonut: View {
    /// Number of TCP ports represented by the first slice.
    let tcp: Int
    /// Number of UDP ports represented by the second slice.
    let udp: Int
    /// Number of Unix socket ports represented by the third slice.
    let unix: Int

    // Tap callbacks — I keep these optional so the donut still works as a
    // read-only chart when filtering isn't wired up. The caller is expected
    // to toggle: if the caller's state already matches this slice, tapping
    // should clear back to "all". That toggle logic lives at the call site,
    // not here — this view just fires the closure.

    /// Fired when the TCP slice or legend row is tapped.
    var onSelectTCP: (() -> Void)? = nil
    /// Fired when the UDP slice or legend row is tapped.
    var onSelectUDP: (() -> Void)? = nil
    /// Fired when the Unix slice or legend row is tapped.
    var onSelectUnix: (() -> Void)? = nil
    /// Active protocol filter: `"tcp"`, `"udp"`, `"unix"`, or `nil` for "all".
    /// I use a string rather than an enum so this Liquid component doesn't
    /// have to know about `PortViewModel`.
    var selectedProtocol: String? = nil

    @ObservedObject private var appSettings = AppSettings.shared

    private var total: Int { tcp + udp + unix }

    var body: some View {
        HStack(spacing: 12) {
            ring
                .frame(width: 56, height: 56)
            legend
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: Theme.Liquid.cardCornerRadius, style: .continuous)
                .fill(Theme.Surface.controlBackground.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Liquid.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.Surface.groupedStroke, lineWidth: Theme.Liquid.cardStrokeWidth)
        )
    }

    // MARK: Ring

    private var ring: some View {
        ZStack {
            if total == 0 {
                Circle()
                    .stroke(Theme.Surface.groupedStroke, lineWidth: 6)
            } else {
                slice(
                    start: 0,
                    fraction: Double(tcp) / Double(total),
                    color: Theme.Action.treeView,
                    proto: "tcp",
                    action: onSelectTCP
                )
                slice(
                    start: Double(tcp) / Double(total),
                    fraction: Double(udp) / Double(total),
                    color: Theme.Section.kubernetes,
                    proto: "udp",
                    action: onSelectUDP
                )
                slice(
                    start: Double(tcp + udp) / Double(total),
                    fraction: Double(unix) / Double(total),
                    color: Theme.Section.ssh,
                    proto: "unix",
                    action: onSelectUnix
                )
            }
            VStack(spacing: 0) {
                Text(verbatim: "\(total)")
                    .font(appSettings.appMonoFont(size: 14, weight: .bold))
                Text("total")
                    .font(appSettings.appFont(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .allowsHitTesting(false) // I don't want the center label stealing taps from slices.
        }
    }

    /// I draw a donut slice as a stroked arc — thickness is the "donut" width.
    /// When `proto` matches the selected protocol, I thicken the stroke and
    /// bump opacity so the user can see which filter is live.
    private func slice(
        start: Double,
        fraction: Double,
        color: Color,
        proto: String,
        action: (() -> Void)?
    ) -> some View {
        let isActive = (selectedProtocol == proto)
        let isDimmed = (selectedProtocol != nil && !isActive)
        let lineWidth: CGFloat = isActive ? 8 : 6
        // I dim unselected slices to 60% so the active one pops. If nothing
        // is selected, every slice renders at full opacity.
        let opacity: Double = isDimmed ? 0.6 : 1.0

        return Circle()
            .trim(from: start, to: start + fraction)
            .stroke(color.opacity(opacity), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            .rotationEffect(.degrees(-90))
            .contentShape(Circle().stroke(lineWidth: max(lineWidth, 14)))
            .onTapGesture { action?() }
    }

    // MARK: Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Protocol Mix")
                    .font(appSettings.appFont(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundColor(.secondary)
            }
            legendRow("TCP", value: tcp, tint: Theme.Action.treeView, proto: "tcp", action: onSelectTCP)
            legendRow("UDP", value: udp, tint: Theme.Section.kubernetes, proto: "udp", action: onSelectUDP)
            legendRow("Unix", value: unix, tint: Theme.Section.ssh, proto: "unix", action: onSelectUnix)
        }
        .frame(minWidth: 100, alignment: .leading)
    }

    /// Legend row — tappable, so trackpad users get a bigger target than
    /// the skinny ring arc. Fires the same closure as the matching slice.
    private func legendRow(
        _ label: String,
        value: Int,
        tint: Color,
        proto: String,
        action: (() -> Void)?
    ) -> some View {
        let isActive = (selectedProtocol == proto)
        return Button(action: { action?() }) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(appSettings.appFont(size: 10, weight: isActive ? .bold : .medium))
                    .foregroundColor(isActive ? .primary : .primary.opacity(0.85))
                Spacer()
                Text(verbatim: "\(value)")
                    .font(appSettings.appMonoFont(size: 10, weight: .bold))
                    .foregroundColor(isActive ? .primary : .secondary)
            }
            .contentShape(Rectangle()) // I widen the hit area to the whole row.
        }
        .buttonStyle(.plain)
    }
}
