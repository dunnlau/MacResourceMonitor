import SwiftUI
import AppKit

// MARK: - Design Metrics & Spacing

enum InterfaceMetrics {
    static let shellRadius: CGFloat = 14
    static let panelRadius: CGFloat = 12
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 8
    static let compactRadius: CGFloat = 6
    static let shellInset: CGFloat = 12
    static let sidebarWidth: CGFloat = 212
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 14
}

// MARK: - Typography Scale

enum InterfaceTypography {
    static let eyebrow = Font.system(size: 10, weight: .semibold, design: .monospaced)
    static let microMetadata = Font.system(size: 11.5, weight: .regular)
    static let microEmphasized = Font.system(size: 11.5, weight: .medium)
    static let caption = Font.system(size: 12.5, weight: .regular)
    static let captionMedium = Font.system(size: 12.5, weight: .medium)
    static let captionEmphasized = Font.system(size: 12.5, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let bodyEmphasized = Font.system(size: 13, weight: .semibold)
    static let cardTitle = Font.system(size: 14, weight: .semibold)
    static let compactValue = Font.system(size: 12, weight: .semibold, design: .monospaced)
    static let metricValue = Font.system(size: 22, weight: .bold, design: .rounded)
    static let heroValue = Font.system(size: 26, weight: .bold, design: .rounded)
}

// MARK: - Semantic Color System (UI/UX Pro Max Telemetry Palette)

enum InterfacePalette {
    /// Dynamic color that adapts automatically to macOS Light and Dark appearances.
    static func dynamic(
        light: (Double, Double, Double, Double),
        dark: (Double, Double, Double, Double)
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3)
        })
    }

    // Text hierarchy (4.5:1+ contrast on respective surfaces)
    static let textSecondary = dynamic(
        light: (0.14, 0.18, 0.26, 0.76),
        dark: (0.78, 0.84, 0.94, 0.84)
    )
    static let textTertiary = dynamic(
        light: (0.24, 0.29, 0.38, 0.62),
        dark: (0.58, 0.64, 0.74, 0.82)
    )

    // Semantic telemetry hues
    static let accent = dynamic(
        light: (0.11, 0.38, 0.92, 1.0),
        dark: (0.22, 0.74, 0.97, 1.0)
    )
    static let signal = dynamic(
        light: (0.09, 0.64, 0.29, 1.0),
        dark: (0.13, 0.77, 0.37, 1.0)
    )
    static let cpuSeries = accent
    static let memorySeries = dynamic(
        light: (0.49, 0.23, 0.93, 1.0),
        dark: (0.65, 0.55, 0.98, 1.0)
    )
    static let temperature = dynamic(
        light: (0.86, 0.15, 0.15, 1.0),
        dark: (0.97, 0.44, 0.44, 1.0)
    )
    static let download = signal
    static let upload = dynamic(
        light: (0.92, 0.35, 0.05, 1.0),
        dark: (0.98, 0.57, 0.24, 1.0)
    )
    static let storage = dynamic(
        light: (0.03, 0.57, 0.70, 1.0),
        dark: (0.13, 0.83, 0.93, 1.0)
    )
    static let fan = dynamic(
        light: (0.05, 0.58, 0.53, 1.0),
        dark: (0.18, 0.83, 0.75, 1.0)
    )
    static let battery = download
    static let power = dynamic(
        light: (0.85, 0.47, 0.02, 1.0),
        dark: (0.98, 0.75, 0.14, 1.0)
    )

    // Structural strokes and subtle fills
    static let iconSurface = dynamic(
        light: (0.06, 0.09, 0.16, 0.055),
        dark: (0.94, 0.97, 1.00, 0.075)
    )
    static let cardStroke = dynamic(
        light: (0.06, 0.09, 0.16, 0.09),
        dark: (0.58, 0.66, 0.78, 0.18)
    )
    static let subtleSurface = dynamic(
        light: (0.06, 0.09, 0.16, 0.04),
        dark: (0.94, 0.97, 1.00, 0.045)
    )
    static let hoverFill = dynamic(
        light: (0.06, 0.09, 0.16, 0.045),
        dark: (0.94, 0.97, 1.00, 0.055)
    )
    static let separator = dynamic(
        light: (0.06, 0.09, 0.16, 0.08),
        dark: (0.58, 0.66, 0.78, 0.14)
    )
    static let chartGrid = dynamic(
        light: (0.06, 0.09, 0.16, 0.07),
        dark: (0.58, 0.66, 0.78, 0.12)
    )
    static let crosshair = dynamic(
        light: (0.06, 0.09, 0.16, 0.30),
        dark: (0.88, 0.92, 0.98, 0.35)
    )

    // Surface layers
    static func canvas(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.043, green: 0.067, blue: 0.125) // #0B1120
            : Color(red: 0.941, green: 0.953, blue: 0.973) // #F0F3F8
    }

    static func sidebarSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.059, green: 0.086, blue: 0.157) // #0F1628
            : Color(red: 0.973, green: 0.980, blue: 0.992) // #F8FAFD
    }

    static func glassSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.094, green: 0.129, blue: 0.208) // #182135
            : Color.white.opacity(0.96)
    }

    static func stableSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.086, green: 0.122, blue: 0.196) // #161F32
            : Color.white
    }

    static func stableDashboardSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.098, green: 0.137, blue: 0.220) // #192338
            : Color.white
    }

    static func menuSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.055, green: 0.082, blue: 0.145) // #0E1525
            : Color(red: 0.949, green: 0.961, blue: 0.980) // #F2F5FA
    }

    static func menuCardSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.094, green: 0.133, blue: 0.212) // #182236
            : Color.white
    }

    static func cardShadow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.black.opacity(0.28)
            : Color(red: 0.06, green: 0.09, blue: 0.18).opacity(0.065)
    }

    /// Semantic threshold tint for percentage loads (CPU, Disk, Memory).
    static func loadTint(for percent: Double, base: Color) -> Color {
        if percent >= 88 { return temperature }
        if percent >= 72 { return upload }
        return base
    }

    /// Semantic threshold tint for CPU temperature in Celsius.
    static func temperatureTint(for celsius: Double?) -> Color {
        guard let celsius else { return textSecondary }
        if celsius >= 85 { return temperature }
        if celsius >= 70 { return upload }
        return signal
    }
}

// MARK: - Surface Modifiers

struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(InterfacePalette.glassSurface(for: colorScheme), in: shape)
            .overlay(shape.stroke(InterfacePalette.cardStroke, lineWidth: 0.8))
            .clipShape(shape)
            .shadow(color: InterfacePalette.cardShadow(for: colorScheme), radius: 10, y: 3)
    }
}

struct LiquidGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isDense: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(
                isDense
                    ? InterfacePalette.sidebarSurface(for: colorScheme)
                    : InterfacePalette.stableDashboardSurface(for: colorScheme),
                in: shape
            )
            .overlay(shape.stroke(InterfacePalette.cardStroke, lineWidth: 0.7))
            .clipShape(shape)
    }
}

struct StableListCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(InterfacePalette.stableSurface(for: colorScheme), in: shape)
            .overlay(shape.stroke(InterfacePalette.cardStroke, lineWidth: 0.7))
            .clipShape(shape)
    }
}

struct StableDashboardCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color(red: 0.110, green: 0.153, blue: 0.243),
                            Color(red: 0.086, green: 0.122, blue: 0.196)
                        ]
                        : [
                            Color.white,
                            Color(red: 0.990, green: 0.994, blue: 1.000)
                        ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: shape
            )
            .overlay(
                shape.stroke(
                    colorScheme == .dark
                        ? LinearGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        : LinearGradient(
                            colors: [
                                Color(red: 0.06, green: 0.09, blue: 0.18).opacity(0.08),
                                Color(red: 0.06, green: 0.09, blue: 0.18).opacity(0.06)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                    lineWidth: 0.9
                )
            )
            .clipShape(shape)
            .shadow(color: InterfacePalette.cardShadow(for: colorScheme), radius: 10, y: 3)
    }
}

struct StableMenuCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(InterfacePalette.menuCardSurface(for: colorScheme), in: shape)
            .overlay(
                shape.stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(0.09)
                        : Color(red: 0.06, green: 0.09, blue: 0.18).opacity(0.08),
                    lineWidth: 0.75
                )
            )
            .clipShape(shape)
            .shadow(
                color: colorScheme == .dark
                    ? .clear
                    : Color(red: 0.06, green: 0.09, blue: 0.18).opacity(0.045),
                radius: 4,
                y: 1
            )
    }
}

struct HoverRowModifier: ViewModifier {
    @State private var isHovering = false
    var cornerRadius: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHovering ? InterfacePalette.hoverFill : .clear)
            )
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = InterfaceMetrics.cardRadius) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    func liquidGlassPanel(
        cornerRadius: CGFloat = InterfaceMetrics.panelRadius,
        isDense: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassPanelModifier(
                cornerRadius: cornerRadius,
                isDense: isDense
            )
        )
    }

    func stableListCard(
        cornerRadius: CGFloat = InterfaceMetrics.cardRadius
    ) -> some View {
        modifier(StableListCardModifier(cornerRadius: cornerRadius))
    }

    func stableDashboardCard(
        cornerRadius: CGFloat = InterfaceMetrics.cardRadius
    ) -> some View {
        modifier(StableDashboardCardModifier(cornerRadius: cornerRadius))
    }

    func stableMenuCard(
        cornerRadius: CGFloat = InterfaceMetrics.cardRadius
    ) -> some View {
        modifier(StableMenuCardModifier(cornerRadius: cornerRadius))
    }

    func hoverRowHighlight(cornerRadius: CGFloat = 0) -> some View {
        modifier(HoverRowModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Reusable Telemetry Components

struct IconBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 26
    var iconSize: CGFloat = 12
    var cornerRadius: CGFloat = 7

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                tint.opacity(0.14),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 0.6)
            )
            .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let text: String
    let tint: Color
    var showDot: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if showDot {
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
            }
            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(tint.opacity(0.13), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.20), lineWidth: 0.6))
    }
}

struct SectionCardHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var tint: Color = InterfacePalette.accent
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let symbol {
                IconBadge(symbol: symbol, tint: tint, size: 28, iconSize: 12.5, cornerRadius: 7)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(InterfaceTypography.cardTitle)
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(InterfaceTypography.microMetadata)
                        .foregroundStyle(InterfacePalette.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension SectionCardHeader where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        symbol: String? = nil,
        tint: Color = InterfacePalette.accent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.trailing = { EmptyView() }
    }
}

struct TelemetryProgressBar: View {
    let progress: Double // 0...100
    let tint: Color
    var height: CGFloat = 5

    var body: some View {
        let clamped = min(1, max(0, progress / 100.0))
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.14))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.72), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: clamped > 0 ? max(height, geometry.size.width * clamped) : 0)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct RadialGaugeRing: View {
    let progress: Double // 0...100
    let tint: Color
    let valueText: String
    var caption: String? = nil
    var size: CGFloat = 68
    var lineWidth: CGFloat = 6.5

    var body: some View {
        let clamped = min(1, max(0, progress / 100.0))
        let arcSpan: Double = 0.78 // 280-degree open gauge

        ZStack {
            Circle()
                .trim(from: 0, to: arcSpan)
                .stroke(
                    tint.opacity(0.14),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(129.6))

            Circle()
                .trim(from: 0, to: max(0.015, clamped * arcSpan))
                .stroke(
                    LinearGradient(
                        colors: [tint.opacity(0.70), tint],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(129.6))

            VStack(spacing: 1) {
                Text(valueText)
                    .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let caption {
                    Text(caption)
                        .font(.system(size: max(8.5, size * 0.13), weight: .semibold, design: .monospaced))
                        .foregroundStyle(InterfacePalette.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, lineWidth + 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct MetricSummaryCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
    var badgeText: String? = nil
    var badgeTint: Color? = nil
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                IconBadge(symbol: symbol, tint: tint, size: 24, iconSize: 11.5, cornerRadius: 6)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(InterfacePalette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let badgeText {
                    StatusBadge(text: badgeText, tint: badgeTint ?? tint)
                }
            }

            Text(value)
                .font(InterfaceTypography.metricValue)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let progress {
                TelemetryProgressBar(progress: progress, tint: tint, height: 4)
            }

            Text(detail)
                .font(InterfaceTypography.microMetadata)
                .foregroundStyle(InterfacePalette.textTertiary)
                .lineLimit(1)
        }
        .padding(InterfaceMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stableDashboardCard()
        .accessibilityElement(children: .combine)
    }
}

struct TelemetrySparkline: View {
    let values: [Double]
    let tint: Color
    var maxValue: Double = 100

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                areaPath(in: size)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.28), tint.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                linePath(in: size)
                    .stroke(
                        tint,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private func linePath(in size: CGSize) -> Path {
        var path = Path()
        let samples = Array(values.suffix(24))
        guard samples.count > 1, maxValue > 0 else { return path }
        for (index, raw) in samples.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(samples.count - 1)
            let normalized = min(1, max(0, raw / maxValue))
            let y = size.height * (1 - CGFloat(normalized))
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    private func areaPath(in size: CGSize) -> Path {
        var path = linePath(in: size)
        let samples = Array(values.suffix(24))
        guard samples.count > 1 else { return path }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }
}

struct SearchToolbarField: View {
    let placeholder: String
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(InterfacePalette.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(InterfacePalette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: InterfaceMetrics.controlRadius, style: .continuous)
                .fill(
                    colorScheme == .dark
                        ? Color.white.opacity(0.055)
                        : Color.white.opacity(0.92)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: InterfaceMetrics.controlRadius, style: .continuous)
                .stroke(InterfacePalette.cardStroke, lineWidth: 0.75)
        )
    }
}

struct ToolbarToggleChip: View {
    let title: String
    let activeSymbol: String
    let inactiveSymbol: String
    let isActive: Bool
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isActive ? activeSymbol : inactiveSymbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isActive ? InterfacePalette.accent : InterfacePalette.textSecondary)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? Color.primary : InterfacePalette.textSecondary)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: InterfaceMetrics.controlRadius, style: .continuous)
                    .fill(
                        isActive
                            ? InterfacePalette.accent.opacity(colorScheme == .dark ? 0.16 : 0.11)
                            : (isHovering ? InterfacePalette.hoverFill : InterfacePalette.subtleSurface)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: InterfaceMetrics.controlRadius, style: .continuous)
                    .stroke(
                        isActive ? InterfacePalette.accent.opacity(0.38) : InterfacePalette.cardStroke,
                        lineWidth: 0.75
                    )
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .onHover { isHovering = $0 }
    }
}

struct ActionPillButton: View {
    let title: String
    let symbol: String
    var isPrimary: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(
                isPrimary
                    ? (colorScheme == .dark ? Color(red: 0.04, green: 0.07, blue: 0.13) : Color.white)
                    : Color.primary
            )
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        isPrimary ? Color.clear : InterfacePalette.cardStroke,
                        lineWidth: 0.75
                    )
            )
            .opacity(isDisabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        if isPrimary {
            return InterfacePalette.accent.opacity(isHovering ? 0.90 : 1.0)
        }
        return isHovering
            ? InterfacePalette.hoverFill
            : (colorScheme == .dark ? Color.white.opacity(0.065) : Color.white.opacity(0.92))
    }
}

struct ChartLegendPill: View {
    let label: String
    var value: String? = nil
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(color)
                .frame(width: 10, height: 3)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(InterfacePalette.textSecondary)
            if let value {
                Text(value)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(InterfacePalette.subtleSurface, in: Capsule())
    }
}
