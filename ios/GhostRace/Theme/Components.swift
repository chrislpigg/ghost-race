import SwiftUI
import GhostRaceKit

// MARK: - Ghost mark
//
// A ghost with a rounded dome and a scalloped hem — the finish-flag checker
// lives in that hem. Used as the app mark and as the opponent's glyph.

/// The ghost silhouette: a semicircular dome over vertical sides and a
/// scalloped bottom edge. Drawn in a rect; keep the rect's aspect near 16:19.
struct GhostShape: Shape {
    var scallops: Int = 5

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let radius = rect.width / 2
        let shoulderY = rect.minY + radius

        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: shoulderY))
        p.addArc(
            center: CGPoint(x: rect.midX, y: shoulderY),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(360),
            clockwise: false
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))

        // Scalloped hem, right edge back to the left.
        let step = rect.width / CGFloat(scallops)
        let amp = rect.height * 0.055
        for i in 0..<scallops {
            let x = rect.maxX - CGFloat(i) * step
            let nextX = x - step
            p.addQuadCurve(
                to: CGPoint(x: nextX, y: rect.maxY),
                control: CGPoint(x: (x + nextX) / 2, y: rect.maxY - amp * 2)
            )
        }
        p.closeSubpath()
        return p
    }
}

/// The ghost mark: outline in ice with eyes. `smug` gives it the defeat-screen
/// look (the ghost that just beat you).
struct GhostMark: View {
    var size: CGFloat = 120
    var stroke: Color = .grIce
    var lineWidth: CGFloat = 1.6
    var checkerHem: Bool = false
    var smug: Bool = false

    private var height: CGFloat { size * 19.0 / 16.0 }

    var body: some View {
        ZStack {
            if checkerHem {
                GhostShape()
                    .fill(Color.grIce.opacity(0.10))
                CheckerStrip(square: max(4, size / 14))
                    .frame(height: height * 0.34)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .mask { GhostShape() }
                    .opacity(0.7)
            }
            GhostShape()
                .stroke(stroke, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
            eyes
        }
        .frame(width: size, height: height)
    }

    private var eyes: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let r = w * 0.09
            let y = h * 0.42
            Group {
                if smug {
                    // Half-closed, self-satisfied eyes.
                    Capsule().fill(stroke)
                        .frame(width: r * 2, height: r * 0.7)
                        .position(x: w * 0.325, y: y)
                    Capsule().fill(stroke)
                        .frame(width: r * 2, height: r * 0.7)
                        .position(x: w * 0.675, y: y)
                } else {
                    Circle().fill(stroke).frame(width: r * 2, height: r * 2)
                        .position(x: w * 0.325, y: y)
                    Circle().fill(stroke).frame(width: r * 2, height: r * 2)
                        .position(x: w * 0.675, y: y)
                }
            }
        }
    }
}

// MARK: - Checker + stripe

/// Two-row checkered strip (the finish line). Fills its frame.
struct CheckerStrip: View {
    var square: CGFloat = 12
    var color: Color = .grChalk

    var body: some View {
        Canvas { ctx, size in
            let rows = max(1, Int((size.height / square).rounded()))
            let s = size.height / CGFloat(rows)
            let cols = Int(ceil(size.width / s)) + 1
            for r in 0..<rows {
                for c in 0..<cols where (r + c) % 2 == 0 {
                    let rect = CGRect(x: CGFloat(c) * s, y: CGFloat(r) * s, width: s, height: s)
                    ctx.fill(Path(rect), with: .color(color))
                }
            }
        }
        .drawingGroup()
    }
}

/// The blaze/ice racing stripe used as a section rule.
struct StripeRule: View {
    var flipped: Bool = false
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                Rectangle().fill(flipped ? Color.grIce : Color.grBlaze).frame(width: w * 0.42)
                Rectangle().fill(flipped ? Color.grBlaze : Color.grIce).frame(width: w * 0.04)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 3)
    }
}

// MARK: - Route silhouette
//
// Draws a segment's polyline as a single stroke, normalized to fit. Makes a
// segment feel like a named circuit instead of a database row — no map tiles.

struct RouteSilhouette: View {
    let polyline: [Coordinate]
    var stroke: Color = .grIce
    var lineWidth: CGFloat = 3
    var showGates: Bool = false

    var body: some View {
        GeometryReader { geo in
            let pts = Self.normalized(polyline, in: geo.size, padding: lineWidth + 6)
            ZStack {
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(stroke, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

                if showGates, let start = pts.first, let finish = pts.last {
                    Circle().fill(Color.grChalk)
                        .frame(width: lineWidth * 2.6, height: lineWidth * 2.6)
                        .position(start)
                    Rectangle().stroke(Color.grChalk, lineWidth: 1.5)
                        .frame(width: lineWidth * 3, height: lineWidth * 3)
                        .position(finish)
                }
            }
        }
    }

    /// Equirectangular projection (lon scaled by cos(meanLat)), normalized to
    /// fit the frame with north pointing up. Handles degenerate spans.
    static func normalized(_ coords: [Coordinate], in size: CGSize, padding: CGFloat) -> [CGPoint] {
        guard coords.count >= 2 else { return [] }
        let meanLat = (coords.reduce(0.0) { $0 + $1.lat } / Double(coords.count)) * .pi / 180
        let xs = coords.map { $0.lon * cos(meanLat) }
        let ys = coords.map { $0.lat }
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 0
        let spanX = max(maxX - minX, 1e-9)
        let spanY = max(maxY - minY, 1e-9)
        let w = max(size.width - padding * 2, 1)
        let h = max(size.height - padding * 2, 1)
        let scale = min(w / spanX, h / spanY)
        let offX = padding + (w - spanX * scale) / 2
        let offY = padding + (h - spanY * scale) / 2
        return zip(xs, ys).map { x, y in
            CGPoint(x: offX + (x - minX) * scale, y: offY + (maxY - y) * scale)
        }
    }
}

// MARK: - Racer glyphs

/// You: a blaze chevron — a direction, a vehicle. Distinct from the ghost by
/// shape, so the two racers read apart even in grayscale.
struct RacerChevron: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Buttons

struct BlazeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .heavy))
            .foregroundStyle(Color.grInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.grBlaze, in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct IceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .heavy))
            .foregroundStyle(Color.grIce)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.grIce.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.grIce.opacity(0.35), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct GhostlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.grChalk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.grPanel.opacity(configuration.isPressed ? 0.9 : 0.5), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.grLine, lineWidth: 1))
    }
}

struct StopButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .heavy))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.grStop, in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Small building blocks

/// A labelled instrument stat: mono value over a tracked caps key.
struct StatBlock: View {
    var key: String
    var value: String
    var alignment: HorizontalAlignment = .leading
    var valueColor: Color = .grChalk

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(key).grLabel(size: 9, tracking: 2, color: .grMuted.opacity(0.8))
            Text(value)
                .font(GRFont.instrument(17, weight: .bold))
                .foregroundStyle(valueColor)
        }
    }
}

/// Standard panel surface — asphalt card with a hairline border.
struct PanelCard<Content: View>: View {
    var accent: Color?
    var content: Content

    init(accent: Color? = nil, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.grPanel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .leading) {
                if let accent {
                    Rectangle().fill(accent)
                        .frame(width: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.grLine, lineWidth: 1))
    }
}
