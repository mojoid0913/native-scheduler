import SwiftUI

enum SchedulerSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let compact: CGFloat = 10
    static let cardInset: CGFloat = 12
    static let lg: CGFloat = 16
}

enum SchedulerRadius {
    static let row: CGFloat = 6
    static let control: CGFloat = 8
    static let card: CGFloat = 10
    static let sheet: CGFloat = 12
}

enum SchedulerType {
    static let cardTitle = Font.system(size: 12, weight: .semibold)
    static let body = Font.system(size: 11)
    static let bodyMedium = Font.system(size: 11, weight: .medium)
    static let metadata = Font.system(size: 10, weight: .medium)
    static let monospacedMetadata = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let monospacedContext = Font.system(size: 11, weight: .medium, design: .monospaced)
}

enum SchedulerControl {
    static let minimumTarget: CGFloat = 24
}

private struct SchedulerCardSurface: ViewModifier {
    let radius: CGFloat
    let elevated: Bool

    func body(content: Content) -> some View {
        content
            .background(elevated ? Color.nsSurfaceElevated : Color.nsSurface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.nsBorder.opacity(0.52), lineWidth: 0.5)
            }
    }
}

extension View {
    func schedulerCardSurface(
        radius: CGFloat = SchedulerRadius.card,
        elevated: Bool = false
    ) -> some View {
        modifier(SchedulerCardSurface(radius: radius, elevated: elevated))
    }
}
