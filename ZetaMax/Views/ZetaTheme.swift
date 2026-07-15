import SwiftUI

private struct ZetaReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var zetaReduceMotionOverride: Bool {
        get { self[ZetaReduceMotionOverrideKey.self] }
        set { self[ZetaReduceMotionOverrideKey.self] = newValue }
    }
}

enum ZetaTheme {
    static let screenWidth: CGFloat = 1_520
    static let cornerRadius: CGFloat = 16
    static let compactRadius: CGFloat = 12
    static let pagePadding: CGFloat = 22
    static let sectionSpacing: CGFloat = 18

    static let brand = Color(red: 0.31, green: 0.35, blue: 0.96)
    static let cyan = Color(red: 0.10, green: 0.68, blue: 0.88)
    static let positive = Color(red: 0.10, green: 0.64, blue: 0.48)
    static let caution = Color(red: 0.93, green: 0.55, blue: 0.14)
    static let negative = Color(red: 0.88, green: 0.28, blue: 0.35)
    static let selectionGradient = LinearGradient(
        colors: [brand.opacity(0.18), cyan.opacity(0.09)],
        startPoint: .leading,
        endPoint: .trailing
    )

    static func color(for operation: ArithmeticOperation) -> Color {
        switch operation {
        case .addition: cyan
        case .subtraction: Color(red: 0.62, green: 0.34, blue: 0.92)
        case .multiplication: Color(red: 0.94, green: 0.48, blue: 0.14)
        case .division: Color(red: 0.05, green: 0.64, blue: 0.58)
        case .power: Color(red: 0.35, green: 0.42, blue: 0.90)
        case .percentage: Color(red: 0.88, green: 0.32, blue: 0.55)
        }
    }

    static func systemImage(for operation: ArithmeticOperation) -> String {
        switch operation {
        case .addition: "plus"
        case .subtraction: "minus"
        case .multiplication: "multiply"
        case .division: "divide"
        case .power: "textformat.superscript"
        case .percentage: "percent"
        }
    }
}

struct ZetaBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var increaseContrast: Bool { colorSchemeContrast == .increased }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if !reduceTransparency {
                LinearGradient(
                    colors: [ZetaTheme.brand.opacity(increaseContrast ? 0.03 : 0.075), .clear, ZetaTheme.cyan.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}

struct ZetaScreen<Content: View>: View {
    let maxWidth: CGFloat
    @ViewBuilder let content: Content

    init(maxWidth: CGFloat = ZetaTheme.screenWidth, @ViewBuilder content: () -> Content) {
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .padding(ZetaTheme.pagePadding)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .background(ZetaBackground())
    }
}

struct ZetaPageHeader: View {
    let title: String
    var subtitle: String? = nil
    var systemImage = "sparkles"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.largeTitle.weight(.bold))
                .symbolRenderingMode(.hierarchical)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ZetaSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct ZetaCard<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.zetaReduceMotionOverride) private var reduceMotionOverride
    @State private var isHovered = false
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zetaLayeredSurface(cornerRadius: ZetaTheme.cornerRadius)
            .scaleEffect(isHovered ? 1.002 : 1)
            .animation(reduceMotion || reduceMotionOverride ? nil : .easeOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

private struct ZetaLayeredSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(
                reduceTransparency
                    ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                    : AnyShapeStyle(.regularMaterial),
                in: shape
            )
            .overlay {
                shape.strokeBorder(.primary.opacity(colorSchemeContrast == .increased ? 0.26 : 0.10), lineWidth: 1)
            }
            .overlay {
                shape.inset(by: 1).strokeBorder(.white.opacity(colorScheme == .dark ? 0.06 : 0.34), lineWidth: 1)
            }
            .clipShape(shape)
            .shadow(
                color: colorSchemeContrast == .increased ? .clear : .black.opacity(colorScheme == .dark ? 0.22 : 0.07),
                radius: colorScheme == .dark ? 18 : 14,
                y: 6
            )
    }
}

extension View {
    func zetaLayeredSurface(cornerRadius: CGFloat = ZetaTheme.cornerRadius) -> some View {
        modifier(ZetaLayeredSurfaceModifier(cornerRadius: cornerRadius))
    }
}

struct ZetaChartCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ZetaCard {
            VStack(alignment: .leading, spacing: 15) {
                ZetaSectionHeader(title: title, subtitle: subtitle)
                content
            }
        }
    }
}

struct ZetaMetricTile: View {
    let title: String
    let value: String
    var detail: String? = nil
    var change: Double? = nil
    var tint: Color = ZetaTheme.brand

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.45)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if let change {
                    Label(String(format: "%+.0f%%", change), systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(change >= 0 ? ZetaTheme.positive : ZetaTheme.caution)
                }
            }
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: detail == nil ? 78 : 96, alignment: .leading)
        .background(tint.opacity(0.075), in: RoundedRectangle(cornerRadius: ZetaTheme.compactRadius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: ZetaTheme.compactRadius, style: .continuous).strokeBorder(tint.opacity(0.16)) }
        .accessibilityElement(children: .combine)
    }
}

struct ZetaStatusChip: View {
    let title: String
    let color: Color
    var systemImage: String? = nil

    var body: some View {
        Group {
            if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.11), in: Capsule())
        .overlay { Capsule().strokeBorder(color.opacity(0.18)) }
    }
}

struct ZetaResponsivePair<First: View, Second: View>: View {
    private let first: () -> First
    private let second: () -> Second

    init(@ViewBuilder first: @escaping () -> First, @ViewBuilder second: @escaping () -> Second) {
        self.first = first
        self.second = second
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: ZetaTheme.sectionSpacing) {
                first().frame(maxWidth: .infinity)
                second().frame(maxWidth: .infinity)
            }
            VStack(spacing: ZetaTheme.sectionSpacing) { first(); second() }
        }
    }
}

struct ZetaGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        ZetaCard {
            VStack(alignment: .leading, spacing: 14) {
                configuration.label.font(.headline)
                configuration.content
            }
        }
    }
}
