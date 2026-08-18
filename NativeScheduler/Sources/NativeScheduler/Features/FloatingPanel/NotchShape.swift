import SwiftUI

struct NotchShape: InsettableShape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat
    private var insetAmount: CGFloat = 0

    init(topCornerRadius: CGFloat, bottomCornerRadius: CGFloat) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { .init(.init(topCornerRadius, bottomCornerRadius), insetAmount) }
        set {
            topCornerRadius = newValue.first.first
            bottomCornerRadius = newValue.first.second
            insetAmount = newValue.second
        }
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard insetRect.width > 0, insetRect.height > 0 else { return Path() }
        let topCornerRadius = max(0, topCornerRadius - insetAmount)
        let bottomCornerRadius = max(0, bottomCornerRadius - insetAmount)
        var path = Path()

        path.move(to: CGPoint(x: insetRect.minX, y: insetRect.minY))
        path.addQuadCurve(
            to: CGPoint(x: insetRect.minX + topCornerRadius, y: insetRect.minY + topCornerRadius),
            control: CGPoint(x: insetRect.minX + topCornerRadius, y: insetRect.minY)
        )
        path.addLine(to: CGPoint(x: insetRect.minX + topCornerRadius, y: insetRect.maxY - bottomCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: insetRect.minX + topCornerRadius + bottomCornerRadius, y: insetRect.maxY),
            control: CGPoint(x: insetRect.minX + topCornerRadius, y: insetRect.maxY)
        )
        path.addLine(to: CGPoint(x: insetRect.maxX - topCornerRadius - bottomCornerRadius, y: insetRect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: insetRect.maxX - topCornerRadius, y: insetRect.maxY - bottomCornerRadius),
            control: CGPoint(x: insetRect.maxX - topCornerRadius, y: insetRect.maxY)
        )
        path.addLine(to: CGPoint(x: insetRect.maxX - topCornerRadius, y: insetRect.minY + topCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: insetRect.maxX, y: insetRect.minY),
            control: CGPoint(x: insetRect.maxX - topCornerRadius, y: insetRect.minY)
        )
        path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.minY))

        return path
    }
}
