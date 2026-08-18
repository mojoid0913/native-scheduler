import AppKit
import SwiftUI

enum NotchGeometry {
    static let shadowPadding: CGFloat = 20
    static let ringAreaWidth: CGFloat = 44
    static let expandedContentTopSpacing: CGFloat = 10
    static let expandedContentBottomSpacing: CGFloat = 16
    static let shellMenuButtonSize: CGFloat = 24
    private static let widthPadding: CGFloat = 12

    static let expandedPanelWidth: CGFloat = 816
    static let expandedPanelHeight: CGFloat = 384

    static let cornerRadiusClosed = (top: CGFloat(6), bottom: CGFloat(14))
    static let cornerRadiusOpen = (top: CGFloat(19), bottom: CGFloat(24))

    static func preferredScreen() -> NSScreen? {
        notchScreen ?? NSScreen.main ?? NSScreen.screens.first
    }

    static var notchScreen: NSScreen? {
        NSScreen.screens.first {
            $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil
        }
    }

    static func detectedNotchSize(for screen: NSScreen) -> CGSize {
        if let leftAux = screen.auxiliaryTopLeftArea,
           let rightAux = screen.auxiliaryTopRightArea {
            let width = rightAux.minX - leftAux.maxX
            let height = leftAux.height
            if width > 50, height > 0 {
                return CGSize(width: width, height: height)
            }
        }

        let safeAreaHeight = screen.safeAreaInsets.top
        guard safeAreaHeight > 0 else { return .zero }
        return CGSize(width: 184, height: safeAreaHeight)
    }

    static func notchWidth(for screen: NSScreen) -> CGFloat {
        let size = detectedNotchSize(for: screen)
        return (size.width > 0 ? size.width : 184) + widthPadding
    }

    static func notchHeight(for screen: NSScreen) -> CGFloat {
        let size = detectedNotchSize(for: screen)
        return size.height > 0 ? size.height : 37
    }

    static func idleShellWidth(notchWidth: CGFloat, showsProgress: Bool) -> CGFloat {
        notchWidth + (showsProgress ? ringAreaWidth : 0)
    }

    static func idleShellMinX(boundsWidth: CGFloat, notchWidth: CGFloat) -> CGFloat {
        (boundsWidth - notchWidth) / 2
    }

    static func idleShellHeight(notchHeight: CGFloat) -> CGFloat {
        notchHeight + 1
    }

    static func shellMenuTopOffset(notchHeight: CGFloat) -> CGFloat {
        let expandedContentTop = notchHeight + expandedContentTopSpacing
        let mainPanelHeight = expandedPanelHeight - expandedContentTop - expandedContentBottomSpacing
        let mainPanelHeaderHeight = max(28, min(36, mainPanelHeight * 0.09))
        return expandedContentTop + (mainPanelHeaderHeight - shellMenuButtonSize) / 2
    }

    static func anchorMidX(
        leftAuxMaxX: CGFloat?,
        rightAuxMinX: CGFloat?,
        safeAreaMidX: CGFloat?,
        screenMidX: CGFloat
    ) -> CGFloat {
        if let leftAuxMaxX,
           let rightAuxMinX,
           rightAuxMinX > leftAuxMaxX {
            return (leftAuxMaxX + rightAuxMinX) / 2
        }

        return safeAreaMidX ?? screenMidX
    }

    static func anchorMidX(for screen: NSScreen) -> CGFloat {
        let safeArea = NSRect(
            x: screen.frame.minX + screen.safeAreaInsets.left,
            y: screen.frame.minY,
            width: screen.frame.width - screen.safeAreaInsets.left - screen.safeAreaInsets.right,
            height: screen.frame.height
        )

        return anchorMidX(
            leftAuxMaxX: screen.auxiliaryTopLeftArea?.maxX,
            rightAuxMinX: screen.auxiliaryTopRightArea?.minX,
            safeAreaMidX: safeArea.width > 0 ? safeArea.midX : nil,
            screenMidX: screen.frame.midX
        )
    }

    static func windowFrame(screenFrame: CGRect, anchorMidX: CGFloat) -> CGRect {
        CGRect(
            x: anchorMidX - (expandedPanelWidth / 2),
            y: screenFrame.maxY - (expandedPanelHeight + shadowPadding),
            width: expandedPanelWidth,
            height: expandedPanelHeight + shadowPadding
        )
    }

    static func windowFrame(for screen: NSScreen) -> CGRect {
        windowFrame(screenFrame: screen.frame, anchorMidX: screen.frame.midX)
    }

    static func hitRect(
        bounds: CGRect,
        isExpanded: Bool,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        showsProgress: Bool
    ) -> CGRect {
        if isExpanded {
            return CGRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: expandedPanelHeight + shadowPadding
            )
        }

        let idleWidth = idleShellWidth(notchWidth: notchWidth, showsProgress: showsProgress)
        let idleHeight = idleShellHeight(notchHeight: notchHeight)
        return CGRect(
            x: idleShellMinX(boundsWidth: bounds.width, notchWidth: notchWidth),
            y: 0,
            width: idleWidth,
            height: idleHeight
        )
    }

    static func containsLocalPoint(
        _ point: CGPoint,
        localRect: CGRect,
        isExpanded: Bool = false
    ) -> Bool {
        guard !isExpanded else { return localRect.contains(point) }
        return NotchShape(
            topCornerRadius: cornerRadiusClosed.top,
            bottomCornerRadius: cornerRadiusClosed.bottom
        )
        .path(in: localRect)
        .contains(point)
    }

    static func containsScreenPoint(
        _ point: CGPoint,
        windowFrame: CGRect,
        localRect: CGRect,
        isExpanded: Bool = false
    ) -> Bool {
        containsLocalPoint(
            CGPoint(
                x: point.x - windowFrame.minX,
                y: windowFrame.maxY - point.y
            ),
            localRect: localRect,
            isExpanded: isExpanded
        )
    }

}
