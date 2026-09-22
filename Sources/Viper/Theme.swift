import AppKit
import SwiftUI
import ViperCore

/// Viper's palette. Colour lives in the light behind the glass; surfaces and type stay quiet and neutral.
enum Palette {
    static let paper = Color(hex: 0x07070B)
    static let surface = Color(hex: 0x121219)
    static let elevated = Color(hex: 0x1B1B24)
    static let ink = Color(hex: 0xF4F4F7)
    static let muted = Color(hex: 0x9A9AAB)
    static let faint = Color(hex: 0x62626F)
    static let line = Color.white.opacity(0.08)
    static let onAccent = Color(hex: 0x0B0B12)

    // Accents, used for small signals (dots, arcs, tints) rather than fills.
    static let mint = Color(hex: 0x6EE7B7)
    static let lavender = Color(hex: 0x9B8CFF)
    static let yellow = Color(hex: 0xFFB547)
    static let peach = Color(hex: 0xFF7A6B)
    static let blue = Color(hex: 0x6CB8FF)
    static let pink = Color(hex: 0xF58BD0)
    static let lime = Color(hex: 0xB9DF74)
    static let slate = Color(hex: 0x9097AA)
    static let orange = Color(hex: 0xFF8F3F)
    static let teal = Color(hex: 0x5ED6CB)

    // Deep, saturated light sources for the aurora behind the glass.
    static let violet = Color(hex: 0x6A4DFF)
    static let indigo = Color(hex: 0x2B2FB8)
    static let ember = Color(hex: 0xFF8A2B)
    static let rose = Color(hex: 0xFF4F7A)
    static let ocean = Color(hex: 0x2F7BFF)
    static let lagoon = Color(hex: 0x19B5A6)

    /// Kept deliberately subtle: a white that cools slightly toward lavender, never a rainbow.
    static let brand = LinearGradient(colors: [Color.white, Color(hex: 0xD6D0FF)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let brandHorizontal = LinearGradient(colors: [Color.white, Color(hex: 0xD6D0FF)], startPoint: .leading, endPoint: .trailing)
    static let titleGradient = LinearGradient(colors: [Color.white, Color.white.opacity(0.84)], startPoint: .top, endPoint: .bottom)
    /// Warm-to-violet light used for arcs and meters, like light passing through tinted glass.
    static let spectrum: [Color] = [Color(hex: 0xFFC46B), Color(hex: 0xFF7A6B), Color(hex: 0x9B8CFF)]

    static func category(_ value: StorageCategory) -> Color {
        switch value {
        case .applications: return lavender
        case .documents: return mint
        case .images: return peach
        case .video: return blue
        case .audio: return yellow
        case .archives: return pink
        case .development: return lime
        case .other: return slate
        }
    }

    static func catalog(_ value: CatalogCategory) -> Color {
        switch value {
        case .developer: return lime
        case .ai: return lavender
        case .audio: return yellow
        case .video: return blue
        case .gaming: return peach
        case .browsers: return mint
        case .design: return pink
        case .utilities: return slate
        case .productivity: return orange
        case .communication: return teal
        }
    }
}

extension Page {
    /// Three light sources the aurora morphs to when this page opens.
    var aura: [Color] {
        switch self {
        case .overview: return [Palette.violet, Palette.ember, Palette.indigo]
        case .storage: return [Palette.ocean, Palette.violet, Palette.lagoon]
        case .uninstaller: return [Palette.violet, Palette.rose, Palette.indigo]
        case .leftovers: return [Palette.ember, Palette.rose, Palette.violet]
        case .updates: return [Palette.lagoon, Palette.ocean, Palette.violet]
        case .privacy: return [Palette.rose, Palette.violet, Palette.ember]
        case .discover: return [Palette.violet, Palette.ocean, Color(hex: 0xE0529C)]
        case .settings: return [Color(hex: 0x4A4F6B), Palette.violet, Palette.indigo]
        }
    }
    var glow: (Color, Color) { (aura[0], aura[1]) }
    fileprivate var auraLayout: [(x: CGFloat, y: CGFloat, scale: CGFloat)] {
        switch self {
        case .overview, .discover: return [(0.86, 0.02, 1.0), (0.18, 0.92, 0.85), (0.42, 0.30, 0.6)]
        case .storage, .updates: return [(0.12, 0.05, 0.95), (0.92, 0.70, 0.9), (0.60, 0.20, 0.55)]
        case .uninstaller, .privacy: return [(0.80, 0.10, 1.0), (0.05, 0.60, 0.8), (0.55, 0.95, 0.6)]
        case .leftovers, .settings: return [(0.95, 0.35, 0.95), (0.20, 0.05, 0.8), (0.45, 0.90, 0.6)]
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

enum Motion {
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.8)
    static let smooth = Animation.spring(response: 0.55, dampingFraction: 0.88)
    static let hover = Animation.easeOut(duration: 0.2)
}

// MARK: - Grain

/// A tiny tileable noise texture, generated once, that gives glass its frosted tooth.
enum Grain {
    static let image: NSImage = {
        let side = 160
        var state: UInt32 = 0x9E3779B9
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for index in 0..<(side * side) {
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            let value = UInt8(truncatingIfNeeded: state >> 24)
            pixels[index * 4] = value
            pixels[index * 4 + 1] = value
            pixels[index * 4 + 2] = value
            pixels[index * 4 + 3] = 255
        }
        // The image owns a copy of the bytes, so no pointer outlives this closure.
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return NSImage() }
        // Half-size in points so each grain is a single Retina pixel.
        return NSImage(cgImage: cgImage, size: NSSize(width: side / 2, height: side / 2))
    }()
}

struct GrainLayer: View {
    var opacity: Double = 0.05
    var body: some View {
        Image(nsImage: Grain.image).resizable(resizingMode: .tile)
            .opacity(opacity)
            .blendMode(.overlay)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Glass

/// Frosted, grainy glass. Every layer is sized to the surface, so it never changes layout or spills over neighbours.
struct GlassBackground: View {
    var tint: Color?
    var radius: CGFloat = 20
    var selected = false
    var bordered = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape.fill(Color(hex: 0x14141C).opacity(0.46))
            .overlay {
                // Milky frost that catches more light at the top.
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.075), Color.white.opacity(0.02), Color.white.opacity(0.035)],
                                          startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                if let tint {
                    shape.fill(RadialGradient(colors: [tint.opacity(selected ? 0.30 : 0.16), tint.opacity(0.04), .clear],
                                              center: .topLeading, startRadius: 0, endRadius: 520))
                }
            }
            .overlay { GrainLayer(opacity: 0.09).clipShape(shape) }
            .overlay(alignment: .top) {
                // A thin specular line where light catches the top edge of the pane.
                if bordered {
                    LinearGradient(colors: [.clear, Color.white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(height: 1).padding(.horizontal, radius)
                }
            }
            .overlay {
                if bordered {
                    shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(selected ? 0.34 : 0.20), Color.white.opacity(0.05),
                                                               Color.white.opacity(0.02), (tint ?? .white).opacity(tint == nil ? 0.06 : 0.22)],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                }
            }
            // Flattened into one texture: scrolling moves a cached image instead of re-blending grain and gradients every frame.
            .drawingGroup()
            // A hairline ledge below the pane gives depth without a blurred shadow (and without darkening the light behind the glass).
            .background { if bordered { shape.stroke(Color.black.opacity(0.45), lineWidth: 1).offset(y: 1.5) } }
    }
}

extension View {
    /// Coloured light placed behind a glass surface. It glows through the frost and spills softly past the edges.
    /// Rendered in a background, so it never affects layout.
    func glassAura(_ primary: Color, _ secondary: Color, intensity: Double = 1) -> some View {
        background {
            GeometryReader { geometry in
                let size = geometry.size
                let span = max(size.height, min(size.width, 520))
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [primary.opacity(0.9 * intensity), primary.opacity(0.32 * intensity), .clear],
                                             center: .center, startRadius: 0, endRadius: span * 0.6))
                        .frame(width: span * 1.2, height: span * 1.2)
                        .position(x: size.width * 0.86, y: size.height * 0.08)
                    Circle()
                        .fill(RadialGradient(colors: [secondary.opacity(0.8 * intensity), secondary.opacity(0.24 * intensity), .clear],
                                             center: .center, startRadius: 0, endRadius: span * 0.48))
                        .frame(width: span * 0.96, height: span * 0.96)
                        .position(x: size.width * 0.12, y: size.height * 0.96)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Buttons

enum ButtonTone {
    case primary, secondary, accent, danger, warning

    var tint: Color? {
        switch self {
        case .primary, .secondary: return nil
        case .accent: return Palette.lavender
        case .danger: return Palette.peach
        case .warning: return Palette.yellow
        }
    }
    var foreground: Color {
        switch self {
        case .primary: return Palette.onAccent
        case .secondary: return Palette.ink
        case .accent: return Color(hex: 0xD9D2FF)
        case .danger: return Color(hex: 0xFFB2A8)
        case .warning: return Color(hex: 0xFFD89A)
        }
    }
}

struct GlowButtonStyle: ButtonStyle {
    var tone: ButtonTone = .primary
    var compact = false

    init(_ tone: ButtonTone = .primary, compact: Bool = false) {
        self.tone = tone
        self.compact = compact
    }

    func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration, tone: tone, compact: compact)
    }

    private struct GlassButtonBody: View {
        let configuration: ButtonStyle.Configuration
        let tone: ButtonTone
        let compact: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            let shape = Capsule(style: .continuous)
            let lit = hovering && enabled
            configuration.label
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .labelStyle(TightLabelStyle())
                .padding(.horizontal, compact ? 13 : 18).padding(.vertical, compact ? 7 : 10)
                .foregroundStyle(tone.foreground)
                .background { surface(shape, lit: lit) }
                .shadow(color: .black.opacity(tone == .primary ? 0.3 : 0), radius: tone == .primary ? 6 : 0, y: tone == .primary ? 3 : 0)
                .scaleEffect(configuration.isPressed && enabled ? 0.97 : 1)
                .offset(y: lit && !reduceMotion ? -1 : 0)
                .opacity(enabled ? 1 : 0.4)
                .animation(reduceMotion ? nil : Motion.snappy, value: configuration.isPressed)
                .animation(reduceMotion ? nil : Motion.hover, value: hovering)
                .contentShape(shape)
                .onHover { hovering = $0 }
                .modifier(FocusHalo(kind: .capsule))
        }

        @ViewBuilder private func surface(_ shape: Capsule, lit: Bool) -> some View {
            switch tone {
            case .primary:
                // Porcelain: bright frosted white, like a lit pane of glass.
                shape.fill(LinearGradient(colors: [Color.white, Color(hex: lit ? 0xEFEDF6 : 0xE3E1EC)], startPoint: .top, endPoint: .bottom))
                    .overlay { shape.strokeBorder(Color.white.opacity(0.9), lineWidth: 0.5) }
            case .secondary:
                shape.fill(Color.white.opacity(lit ? 0.12 : 0.07))
                    .overlay {
                        shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(lit ? 0.32 : 0.2), Color.white.opacity(0.04)],
                                                          startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
            case .accent, .danger, .warning:
                let tint = tone.tint ?? .white
                shape.fill(LinearGradient(colors: [tint.opacity(lit ? 0.3 : 0.2), tint.opacity(lit ? 0.16 : 0.1)], startPoint: .top, endPoint: .bottom))
                    .overlay {
                        shape.strokeBorder(LinearGradient(colors: [tint.opacity(lit ? 0.7 : 0.5), tint.opacity(0.12)],
                                                          startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
            }
        }
    }
}

private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 11, weight: .semibold))
            configuration.title
        }
    }
}

/// Visible keyboard focus for custom controls. The system ring is not drawn for these button styles.
struct FocusHalo: ViewModifier {
    enum Kind { case capsule, circle, rounded(CGFloat) }
    var kind: Kind
    @Environment(\.isFocused) private var focused

    func body(content: Content) -> some View {
        content.overlay {
            if focused {
                ring.padding(-3).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private var ring: some View {
        switch kind {
        case .capsule:
            Capsule(style: .continuous).strokeBorder(Color.white, lineWidth: 2)
        case .circle:
            Circle().strokeBorder(Color.white, lineWidth: 2)
        case .rounded(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white, lineWidth: 2)
        }
    }
}

/// Compatibility for call sites written against the previous design.
struct BlockButtonStyle: ButtonStyle {
    var color: Color = Palette.mint
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        GlowButtonStyle(tone, compact: compact).makeBody(configuration: configuration)
    }
    private var tone: ButtonTone {
        switch color {
        case Palette.paper, Palette.surface, Palette.elevated: return .secondary
        case Palette.peach: return .danger
        case Palette.lavender: return .accent
        case Palette.yellow: return .warning
        default: return .primary
        }
    }
}

/// Small borderless icon button that lights up on hover.
struct IconButtonStyle: ButtonStyle {
    var tint: Color = .white
    func makeBody(configuration: Configuration) -> some View { IconButtonBody(configuration: configuration, tint: tint) }
    private struct IconButtonBody: View {
        let configuration: ButtonStyle.Configuration
        let tint: Color
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .foregroundStyle(hovering && enabled ? tint : Palette.muted)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(hovering && enabled ? 0.09 : 0)))
                .overlay(Circle().strokeBorder(Color.white.opacity(hovering && enabled ? 0.12 : 0), lineWidth: 1))
                .scaleEffect(configuration.isPressed ? 0.88 : 1)
                .opacity(enabled ? 1 : 0.35)
                .contentShape(Circle())
                .onHover { hovering = $0 }
                .animation(Motion.snappy, value: configuration.isPressed)
                .animation(Motion.hover, value: hovering)
                .modifier(FocusHalo(kind: .circle))
        }
    }
}

/// Text-only action (Select all, Clear, Manage sources).
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { LinkButtonBody(configuration: configuration) }
    private struct LinkButtonBody: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.ink.opacity(enabled ? (hovering ? 1 : 0.68) : 0.3))
                .underline(hovering && enabled, color: Palette.ink.opacity(0.4))
                .opacity(configuration.isPressed ? 0.6 : 1)
                .onHover { hovering = $0 }
                .animation(Motion.hover, value: hovering)
                .modifier(FocusHalo(kind: .rounded(6)))
        }
    }
}

// MARK: - Surfaces

/// Tracks the pointer separately so only the light layer re-renders while the mouse moves.
private final class PointerTracker: ObservableObject {
    @Published var location: CGPoint?
}

/// A soft sheen that follows the pointer across glass, and brightens the rim nearest to it.
private struct SheenLayer: View {
    @ObservedObject var tracker: PointerTracker
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if let point = tracker.location {
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.07), .clear], center: .center, startRadius: 0, endRadius: 240))
                    .frame(width: 480, height: 480).position(point)
                shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                    .mask(Circle().fill(RadialGradient(colors: [.white, .clear], center: .center, startRadius: 0, endRadius: 160))
                        .frame(width: 320, height: 320).position(point))
            }
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}

/// Entrance for surfaces: a short rise and fade the first time a view appears.
struct RiseIn: ViewModifier {
    var delay: Double = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .onAppear {
                guard !shown else { return }
                if reduceMotion { shown = true } else { withAnimation(Motion.smooth.delay(delay)) { shown = true } }
            }
    }
}

extension View {
    func riseIn(delay: Double = 0) -> some View { modifier(RiseIn(delay: delay)) }

    /// A small frosted tile behind an icon, lit from below by its colour.
    func glowTile(_ color: Color, radius: CGFloat = 10, glow: Bool = true) -> some View {
        self.foregroundStyle(Color.white.opacity(0.94))
            .background {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                shape.fill(Color.white.opacity(0.06))
                    .overlay {
                        shape.fill(RadialGradient(colors: [color.opacity(glow ? 0.55 : 0.38), color.opacity(0.08), .clear],
                                                  center: .bottom, startRadius: 0, endRadius: radius * 5))
                    }
                    .overlay {
                        shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.24), Color.white.opacity(0.04), color.opacity(0.35)],
                                                          startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
            }
            .shadow(color: color.opacity(glow ? 0.22 : 0), radius: glow ? 14 : 0, y: glow ? 4 : 0)
    }

    /// A frosted notice with a hint of colour.
    func noticeBackground(_ color: Color, radius: CGFloat = 14) -> some View {
        self.background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            shape.fill(Color.white.opacity(0.04))
                .overlay { shape.fill(RadialGradient(colors: [color.opacity(0.16), .clear], center: .leading, startRadius: 0, endRadius: 420)) }
                .overlay { shape.strokeBorder(LinearGradient(colors: [color.opacity(0.35), Color.white.opacity(0.06)], startPoint: .leading, endPoint: .trailing), lineWidth: 1) }
        }
    }

    /// Recessed glass well for lists inside a card.
    func glassPanel(radius: CGFloat = 16) -> some View {
        self.background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            shape.fill(Color.black.opacity(0.18))
                .overlay { shape.strokeBorder(LinearGradient(colors: [Color.black.opacity(0.25), Color.white.opacity(0.07)], startPoint: .top, endPoint: .bottom), lineWidth: 1) }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Hover and selection wash for list rows.
    func rowHighlight(hovering: Bool, selected: Bool = false, tint: Color = .white) -> some View {
        self.background {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            shape.fill(Color.white.opacity(selected ? 0.07 : (hovering ? 0.045 : 0)))
                .overlay { shape.strokeBorder(Color.white.opacity(selected ? 0.14 : (hovering ? 0.07 : 0)), lineWidth: 1) }
                .animation(Motion.hover, value: hovering)
                .animation(Motion.snappy, value: selected)
        }
    }
}

struct Card<Content: View>: View {
    var color: Color?
    var interactive = true
    @ViewBuilder var content: Content
    @StateObject private var tracker = PointerTracker()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(color: Color? = nil, interactive: Bool = true, @ViewBuilder content: () -> Content) {
        self.color = color
        self.interactive = interactive
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GlassBackground(tint: color))
            .overlay(SheenLayer(tracker: tracker, radius: 20))
            .onContinuousHover { phase in
                guard interactive, !reduceMotion else { return }
                switch phase {
                case .active(let point): tracker.location = point
                case .ended: withAnimation(Motion.hover) { tracker.location = nil }
                }
            }
            .riseIn()
    }
}

struct Tag: View {
    let text: String
    var color: Color = Palette.slate
    var pulse = false
    @State private var lit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            if color != Palette.slate || pulse {
                Circle().fill(color).frame(width: 5, height: 5)
                    .shadow(color: color.opacity(0.9), radius: lit ? 5 : 2)
                    .opacity(pulse ? (lit ? 1 : 0.35) : 1)
                    .onAppear {
                        guard pulse, !reduceMotion else { lit = true; return }
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { lit = true }
                    }
            }
            Text(text).font(.system(size: 9.5, weight: .semibold)).tracking(0.9)
        }
        .foregroundStyle(Palette.ink.opacity(0.82))
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .fixedSize()
    }
}

struct PageHeading<Actions: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var actions: Actions

    init(_ title: String, subtitle: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 14) {
                Text(title).font(.system(size: 28, weight: .medium)).tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                actions
            }
            if let subtitle {
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(2)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .riseIn()
    }
}

extension PageHeading where Actions == EmptyView {
    init(_ title: String, subtitle: String? = nil) { self.init(title, subtitle: subtitle) { EmptyView() } }
}

struct InfoLine: View {
    let text: String
    var icon = "info.circle"
    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon).foregroundStyle(Palette.ink.opacity(0.45))
        }
        .font(.system(size: 12)).foregroundStyle(Palette.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct EmptyPanel: View {
    var framed = true
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 26, weight: .light))
                .foregroundStyle(Palette.ink.opacity(0.9))
                .frame(width: 76, height: 76)
                .background {
                    Circle().fill(Color.white.opacity(0.06))
                        .overlay { GrainLayer(opacity: 0.1).clipShape(Circle()) }
                        .overlay { Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1) }
                }
                .background {
                    // A soft two-tone halo behind the frosted disc.
                    ZStack {
                        Circle().fill(RadialGradient(colors: [Palette.violet.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 110))
                            .frame(width: 220, height: 220).offset(x: 22, y: -14)
                        Circle().fill(RadialGradient(colors: [Palette.ember.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: 90))
                            .frame(width: 180, height: 180).offset(x: -26, y: 20)
                    }
                    .allowsHitTesting(false)
                }
                .padding(.vertical, 10)
            Text(title).font(.system(size: 19, weight: .medium)).foregroundStyle(Palette.ink)
            Text(detail).font(.system(size: 13)).foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 430)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
        .background { if framed { GlassBackground(radius: 20) } }
        .riseIn()
    }
}

/// A slim meter: a recessed track with a softly lit, warm-to-violet fill that grows in when it appears.
struct GlowMeter: View {
    let fraction: Double
    var colors: [Color] = Palette.spectrum
    var height: CGFloat = 10
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let width = max(height, geometry.size.width * min(1, max(0, fraction)) * (shown ? 1 : 0))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.3))
                    .overlay(Capsule().strokeBorder(LinearGradient(colors: [Color.black.opacity(0.3), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)))
                    .frame(width: width)
                    .shadow(color: (colors.last ?? .white).opacity(0.35), radius: 8)
                    .opacity(shown ? 1 : 0)
            }
        }
        .frame(height: height)
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(.spring(response: 1.1, dampingFraction: 0.86).delay(0.15)) { shown = true } }
        }
    }
}

/// A circular gauge: frosted dial with a lit arc, inspired by instrument faces.
struct RingGauge<Center: View>: View {
    let fraction: Double
    var size: CGFloat = 168
    var lineWidth: CGFloat = 9
    var colors: [Color] = Palette.spectrum
    @ViewBuilder var center: Center
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let value = min(1, max(0, fraction)) * (shown ? 1 : 0)
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.1), Color(hex: 0x101017).opacity(0.85)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: size * 0.6))
                .overlay { GrainLayer(opacity: 0.1).clipShape(Circle()) }
                .overlay { Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1) }
                .padding(lineWidth + 6)
            Circle().stroke(Color.white.opacity(0.06), lineWidth: lineWidth)
            Circle().trim(from: 0, to: value)
                .stroke(AngularGradient(colors: colors + [colors.first ?? .white], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: (colors.first ?? .white).opacity(0.45), radius: 10)
            center
        }
        .frame(width: size, height: size)
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(.spring(response: 1.3, dampingFraction: 0.85).delay(0.2)) { shown = true } }
        }
    }
}

// MARK: - Backdrops

/// Aurora of deep light behind everything. It morphs only when the page changes, so an idle Viper stays idle.
struct AmbientBackground: View {
    let page: Page
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let base = max(size.width, size.height)
            ZStack {
                Palette.paper
                ForEach(0..<3, id: \.self) { index in
                    let color = page.aura[index]
                    let spot = page.auraLayout[index]
                    let diameter = base * 0.95 * spot.scale
                    Circle()
                        .fill(RadialGradient(colors: [color.opacity(index == 2 ? 0.34 : 0.5), color.opacity(0.14), .clear],
                                             center: .center, startRadius: 0, endRadius: diameter / 2))
                        .frame(width: diameter, height: diameter)
                        .position(x: size.width * spot.x, y: size.height * spot.y)
                }
                // Soft vignette keeps edges deep and text legible.
                RadialGradient(colors: [.clear, Color.black.opacity(0.55)], center: .center, startRadius: base * 0.2, endRadius: base * 0.8)
                GrainLayer(opacity: 0.07)
            }
        }
        .drawingGroup()
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Background for sheets: deep canvas with two soft light sources.
struct SheetBackground: View {
    var tint: Color = Palette.violet
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Palette.paper
                Circle().fill(RadialGradient(colors: [tint.opacity(0.42), tint.opacity(0.1), .clear], center: .center, startRadius: 0, endRadius: 320))
                    .frame(width: 640, height: 640).position(x: size.width * 0.9, y: 0)
                Circle().fill(RadialGradient(colors: [Palette.indigo.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 280))
                    .frame(width: 560, height: 560).position(x: 0, y: size.height)
                GrainLayer(opacity: 0.07)
            }
        }
        .drawingGroup()
        .ignoresSafeArea()
    }
}

struct GlowDivider: View {
    var vertical = false
    var body: some View {
        let gradient = LinearGradient(colors: [.clear, Color.white.opacity(0.1), .clear],
                                      startPoint: vertical ? .top : .leading, endPoint: vertical ? .bottom : .trailing)
        if vertical { Rectangle().fill(gradient).frame(width: 1) } else { Rectangle().fill(gradient).frame(height: 1) }
    }
}

/// Small section label.
struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Palette.muted)
    }
}
