import SwiftUI

// MARK: - Sparkline

/// A minimal, dependency-free line + fill chart for small inline use.
///
/// I keep this pure — no state, no timer — so it composes freely with the
/// sampler (`LiveMetricsHistory`) that feeds it. Every tile, row, and
/// inspector card reuses the same renderer at different sizes, strokes, and
/// fills rather than each rolling its own path math.
struct Sparkline: View {
    /// The data to plot. Two or more values render a line; fewer fall back
    /// to a flat baseline rule so layouts don't shift when data is quiet.
    let values: [Double]
    /// Stroke colour for the line and the trailing dot.
    var stroke: Color = Theme.Liquid.sparklineStroke
    /// Fill colour underneath the line. Typically a translucent version of `stroke`.
    var fill: Color = Theme.Liquid.sparklineFill
    /// Line thickness. I bump this slightly on big inspector cards.
    var lineWidth: CGFloat = 1.2
    /// When `true`, the most recent sample is marked with a small glowing dot.
    var showDot: Bool = true

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if pts.count >= 2 {
                    fillPath(pts, size: geo.size).fill(fill)
                    linePath(pts).stroke(stroke, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    if showDot, let last = pts.last {
                        Circle()
                            .fill(stroke)
                            .frame(width: 4, height: 4)
                            .shadow(color: stroke.opacity(0.6), radius: 2)
                            .position(last)
                    }
                } else {
                    // Flat baseline for quiet metrics — keeps layouts steady.
                    Rectangle()
                        .fill(stroke.opacity(0.3))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = max(maxV - minV, 0.0001)
        let stepX = values.count > 1 ? size.width / CGFloat(values.count - 1) : 0
        return values.enumerated().map { idx, v in
            let x = CGFloat(idx) * stepX
            let y = size.height - (CGFloat((v - minV) / span) * size.height)
            return CGPoint(x: x, y: y)
        }
    }

    private func linePath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: pts[0])
        for p in pts.dropFirst() { path.addLine(to: p) }
        return path
    }

    private func fillPath(_ pts: [CGPoint], size: CGSize) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: pts[0].x, y: size.height))
        for p in pts { path.addLine(to: p) }
        path.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: size.height))
        path.closeSubpath()
        return path
    }
}
