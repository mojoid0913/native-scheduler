import SwiftUI

enum NotchAnimation {
    static let expand: Animation = .spring(response: 0.34, dampingFraction: 0.76)
    static let collapse: Animation = .spring(response: 0.24, dampingFraction: 0.90)
    static let hover: Animation = .interactiveSpring(response: 0.20, dampingFraction: 0.86)
}
