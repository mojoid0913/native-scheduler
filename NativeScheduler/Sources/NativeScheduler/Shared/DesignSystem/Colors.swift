// NativeScheduler/Sources/NativeScheduler/Shared/DesignSystem/Colors.swift
import SwiftUI

extension Color {
    static let nsBackground   = Color(hex: "#000000")
    static let nsSurface      = Color(hex: "#111111")
    static let nsSurfaceElevated = Color(hex: "#161616")
    static let nsBorder       = Color(hex: "#2A2A2A")
    static let nsTextPrimary  = Color(hex: "#EFEFEF")
    static let nsTextSecondary = Color(hex: "#8A8A8A")
    static let nsTextTertiary = Color(hex: "#858585")
    static let nsDefaultSlot  = Color(hex: "#3A3A3A")
    static let nsFutureSlot   = Color(hex: "#252525")  // heatmap cells after current time
    static let nsChevron      = Color(hex: "#CCCCCC")
    static let nsDefaultCategory = Color(hex: "#4DABF7")

    static let daylineElapsedTrack = nsDefaultSlot
    static let daylineFutureTrack = nsFutureSlot
    static let daylineNowMarker = nsChevron
    static let daylineSelected = nsTextPrimary
    static let daylineDefaultCategory = nsDefaultCategory
    static let daylineError = Color(hex: "#FFA94D")

    static func daylineCategory(_ persistedHex: String?) -> Color {
        Color(hex: resolvedCategoryHex(persistedHex))
    }

    static func resolvedCategoryHex(_ hex: String?) -> String {
        guard let hex else { return nsDefaultCategory.hexString }
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let hexDigits = CharacterSet(charactersIn: "0123456789ABCDEFabcdef")
        guard body.count == 6, body.unicodeScalars.allSatisfy(hexDigits.contains) else {
            return nsDefaultCategory.hexString
        }
        return "#\(body.uppercased())"
    }

    init(hex: String, opacity: Double = 1.0) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(
            red:     Double((rgb >> 16) & 0xFF) / 255,
            green:   Double((rgb >>  8) & 0xFF) / 255,
            blue:    Double( rgb        & 0xFF) / 255,
            opacity: opacity
        )
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        // Use .rounded() — not plain Int() — to avoid truncation error.
        // e.g. #808080 → redComponent = 0.50196 → 0.50196 × 255 = 127.999
        //      Int(127.999) = 127  ✗  vs  Int(127.999.rounded()) = 128  ✓
        return String(
            format: "#%02X%02X%02X",
            Int((c.redComponent   * 255).rounded()),
            Int((c.greenComponent * 255).rounded()),
            Int((c.blueComponent  * 255).rounded())
        )
    }
}

// MARK: - Default category palette (12 slots)
enum CategoryPalette {
    static let defaults: [String] = [
        "#FF6B6B", "#FFA94D", "#FFD43B",
        "#69DB7C", "#4DABF7", "#748FFC",
        "#DA77F2", "#F783AC", "#63E6BE",
        "#A9E34B", "#74C0FC", "#E599F7"
    ]

    static let quickAdd: [String] = [
        "#FF6B6B", "#FFA94D", "#FFD43B",
        "#69DB7C", "#4DABF7", "#748FFC"
    ]
}
