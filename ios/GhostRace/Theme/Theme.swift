import SwiftUI

// MARK: - Palette
//
// The GhostRace identity: you are blaze orange (hi-vis, the color runners
// actually wear); the opponent is spectral ice (an outline, never solid);
// everything sits on asphalt. Ahead/behind are full-screen race fields.
// Semantic green/orange is reserved for status (GPS, wins) and never used
// as an accent.

extension Color {
    static let grAsphalt   = Color(red: 0.039, green: 0.055, blue: 0.082) // #0A0E15 ground
    static let grPanel     = Color(red: 0.067, green: 0.090, blue: 0.141) // #111724 surfaces
    static let grPanelDeep = Color(red: 0.051, green: 0.067, blue: 0.098) // #0D1119 deep surfaces
    static let grLine      = Color(red: 0.129, green: 0.169, blue: 0.239) // #212B3D hairlines

    static let grChalk     = Color(red: 0.929, green: 0.945, blue: 0.969) // #EDF1F7 text / start line
    static let grMuted     = Color(red: 0.549, green: 0.588, blue: 0.659) // #8C96A8 secondary text

    static let grBlaze     = Color(red: 1.000, green: 0.353, blue: 0.122) // #FF5A1F you / primary
    static let grBlazeHot  = Color(red: 1.000, green: 0.478, blue: 0.271) // #FF7A45 you (highlight)
    static let grInk       = Color(red: 0.102, green: 0.043, blue: 0.016) // #1A0B04 text on blaze

    static let grIce       = Color(red: 0.659, green: 0.882, blue: 0.937) // #A8E1EF the ghost
    static let grIceDim    = Color(red: 0.424, green: 0.576, blue: 0.631) // #6C93A1 ghost, dimmed

    static let grAheadA    = Color(red: 0.047, green: 0.298, blue: 0.149) // #0C4C26 ahead field
    static let grAheadB    = Color(red: 0.016, green: 0.125, blue: 0.059) // #04200F ahead field
    static let grBehindA   = Color(red: 0.361, green: 0.098, blue: 0.075) // #5C1913 behind field
    static let grBehindB   = Color(red: 0.137, green: 0.039, blue: 0.031) // #230A08 behind field

    static let grOK        = Color(red: 0.255, green: 0.851, blue: 0.553) // #41D98D GPS good, wins
    static let grWarn      = Color(red: 0.961, green: 0.647, blue: 0.141) // #F5A524 GPS poor
    static let grStop      = Color(red: 0.898, green: 0.220, blue: 0.165) // #E5382A finish / stop
    static let grLoss      = Color(red: 1.000, green: 0.420, blue: 0.357) // #FF6B5B losing record
}

/// Full-screen race field backgrounds. Ahead = deep green, behind = oxblood
/// (urgent, not alarm-red — it has to stay legible under direct sun).
enum RaceField {
    static let ahead = RadialGradient(
        gradient: Gradient(colors: [.grAheadA, .grAheadB]),
        center: .top, startRadius: 0, endRadius: 720
    )
    static let behind = RadialGradient(
        gradient: Gradient(colors: [.grBehindA, .grBehindB]),
        center: .top, startRadius: 0, endRadius: 720
    )
    static let victory = RadialGradient(
        gradient: Gradient(colors: [Color(red: 0.043, green: 0.239, blue: 0.125), .grAsphalt]),
        center: .top, startRadius: 0, endRadius: 640
    )
    static let defeat = RadialGradient(
        gradient: Gradient(colors: [Color(red: 0.278, green: 0.078, blue: 0.063), .grAsphalt]),
        center: .top, startRadius: 0, endRadius: 640
    )
}

// MARK: - Typography
//
// Two hero roles: DISPLAY is SF Pro Black Italic in caps (headlines, states,
// moments); INSTRUMENT is SF Mono, tabular, for every number in the app so the
// whole thing reads like a stopwatch.

enum GRFont {
    /// Heavy oblique display face — headlines and the big race moments.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default).italic()
    }
    /// Monospaced instrument face for numbers; always paired with tabular digits.
    static func instrument(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .monospaced).monospacedDigit()
    }
    /// Small monospaced caps for eyebrows, stat keys, and chips.
    static func label(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }
}

/// Uppercase monospaced label with wide tracking — the app's connective tissue.
private struct GRLabelModifier: ViewModifier {
    var size: CGFloat
    var tracking: CGFloat
    var color: Color
    func body(content: Content) -> some View {
        content
            .font(GRFont.label(size))
            .tracking(tracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

extension View {
    func grLabel(size: CGFloat = 11, tracking: CGFloat = 2, color: Color = .grMuted) -> some View {
        modifier(GRLabelModifier(size: size, tracking: tracking, color: color))
    }
}

// MARK: - Wordmark

/// "Ghost" solid, "Race" in spectral ice — the ghost of the word itself.
struct GhostWordmark: View {
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: 0) {
            Text("Ghost").foregroundStyle(Color.grChalk)
            Text("Race").foregroundStyle(Color.grIce)
        }
        .font(GRFont.display(size))
        .textCase(.uppercase)
        .tracking(-0.5)
    }
}
