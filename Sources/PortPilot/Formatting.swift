import SwiftUI

// MARK: - Shared Row Formatting
// Single source for heat-map colors and memory formatting. The dropdown and
// the main port list used to carry two drifting copies of each.

/// Smooth heat-map: 0% teal → 25% blue → 50% amber → 75% orange → 100% red
func cpuHeatColor(_ usage: Double) -> Color {
    let t = min(max(usage / 100.0, 0), 1)
    let r: Double, g: Double, b: Double
    if t < 0.25 {
        let p = t / 0.25
        r = 0.18 + p * 0.12;  g = 0.62 - p * 0.14;  b = 0.70 - p * 0.02
    } else if t < 0.50 {
        let p = (t - 0.25) / 0.25
        r = 0.30 + p * 0.58;  g = 0.48 + p * 0.14;  b = 0.68 - p * 0.52
    } else if t < 0.75 {
        let p = (t - 0.50) / 0.25
        r = 0.88 + p * 0.07;  g = 0.62 - p * 0.22;  b = 0.16 - p * 0.04
    } else {
        let p = (t - 0.75) / 0.25
        r = 0.95 - p * 0.05;  g = 0.40 - p * 0.18;  b = 0.12 + p * 0.08
    }
    return Color(red: r, green: g, blue: b)
}

/// Compact memory for table rows and chips: "412M", "1.2G"
func formatMemoryCompact(_ mb: Double) -> String {
    if mb >= 1024 { return String(format: "%.1fG", mb / 1024.0) }
    if mb >= 10 { return String(format: "%.0fM", mb) }
    return String(format: "%.1fM", mb)
}

/// Spacious memory for cards and detail panes: "412 MB", "1.2 GB"
func formatMemorySpacious(_ mb: Double) -> String {
    if mb >= 1024 { return String(format: "%.1f GB", mb / 1024.0) }
    if mb >= 10 { return String(format: "%.0f MB", mb) }
    return String(format: "%.1f MB", mb)
}
