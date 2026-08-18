import SwiftUI

struct TodayUsageEntry: Identifiable, Equatable {
    let categoryID: UUID?
    let name: String
    let colorHex: String
    let seconds: TimeInterval
    let fraction: Double
    let isEtc: Bool

    var id: String { categoryID?.uuidString.lowercased() ?? (isEtc ? "etc" : "default") }
}

enum TodayUsageSummaryProjection {
    static func entries(for snapshot: DayActivitySnapshot) -> [TodayUsageEntry] {
        let totalSeconds = snapshot.totalTrackedSeconds
        guard totalSeconds > 0 else { return [] }
        let locale = Locale(identifier: snapshot.localeIdentifier)

        return snapshot.categoryTotals
            .filter { $0.seconds > 0 }
            .map { total in
                TodayUsageEntry(
                    categoryID: total.categoryID,
                    name: total.categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Default" : total.categoryName,
                    colorHex: Color.resolvedCategoryHex(total.categoryHex),
                    seconds: total.seconds,
                    fraction: total.seconds / totalSeconds,
                    isEtc: false
                )
            }
            .sorted { left, right in
                if left.seconds != right.seconds { return left.seconds > right.seconds }
                let nameOrder = left.name.compare(right.name, options: .caseInsensitive, range: nil, locale: locale)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return left.id < right.id
            }
    }

    static func visibleEntries(for snapshot: DayActivitySnapshot) -> [TodayUsageEntry] {
        let entries = entries(for: snapshot)
        guard entries.count > 5 else { return entries }
        let leading = Array(entries.prefix(5))
        let remaining = entries.dropFirst(5)
        let seconds = remaining.reduce(0) { $0 + $1.seconds }
        return leading + [
            TodayUsageEntry(
                categoryID: nil,
                name: "Etc",
                colorHex: Color.nsTextSecondary.hexString,
                seconds: seconds,
                fraction: snapshot.totalTrackedSeconds > 0 ? seconds / snapshot.totalTrackedSeconds : 0,
                isEtc: true
            )
        ]
    }

    static func compactEntries(for snapshot: DayActivitySnapshot) -> [TodayUsageEntry] {
        let entries = entries(for: snapshot)
        guard entries.count > 3 else { return entries }
        let leading = Array(entries.prefix(3))
        let remaining = entries.dropFirst(3)
        let seconds = remaining.reduce(0) { $0 + $1.seconds }
        return leading + [
            TodayUsageEntry(
                categoryID: nil,
                name: "Etc",
                colorHex: Color.nsTextSecondary.hexString,
                seconds: seconds,
                fraction: snapshot.totalTrackedSeconds > 0 ? seconds / snapshot.totalTrackedSeconds : 0,
                isEtc: true
            )
        ]
    }

    static func percentageText(_ entry: TodayUsageEntry) -> String {
        "\(Int((entry.fraction * 100).rounded()))%"
    }

    static func durationText(_ seconds: TimeInterval, localeIdentifier: String) -> String {
        DaylineContract.durationText(seconds, localeIdentifier: localeIdentifier)
    }

    static func totalText(_ seconds: TimeInterval, localeIdentifier: String) -> String {
        "Today · \(DaylineContract.compactDurationText(seconds, localeIdentifier: localeIdentifier))"
    }
}

enum TodayUsageSummaryLayout {
    static let horizontalPadding: CGFloat = 8
    static let ringWidth: CGFloat = 44
    static let ringSpacing: CGFloat = 14
    static let contentMaxWidth: CGFloat = 184
    static let meaningfulTextSize: CGFloat = 11

    static func textColumnWidth(summaryWidth: CGFloat) -> CGFloat {
        max(0, summaryWidth - horizontalPadding * 2 - ringWidth - ringSpacing)
    }
}

struct TodayUsageSummaryView: View {
    let snapshot: DayActivitySnapshot

    init(snapshot: DayActivitySnapshot) {
        self.snapshot = snapshot
    }

    private var entries: [TodayUsageEntry] {
        TodayUsageSummaryProjection.compactEntries(for: snapshot)
    }

    var body: some View {
        HStack(alignment: .center, spacing: TodayUsageSummaryLayout.ringSpacing) {
            UsageCategoryRing(entries: entries)
                .frame(width: TodayUsageSummaryLayout.ringWidth, height: TodayUsageSummaryLayout.ringWidth)

            VStack(alignment: .leading, spacing: 5) {
                Text(TodayUsageSummaryProjection.totalText(
                    snapshot.totalTrackedSeconds,
                    localeIdentifier: snapshot.localeIdentifier
                ))
                    .font(.system(
                        size: TodayUsageSummaryLayout.meaningfulTextSize,
                        weight: .semibold,
                        design: .monospaced
                    ))
                    .foregroundColor(.nsTextPrimary)
                    .lineLimit(1)

                if entries.isEmpty {
                    Text("No tracked time")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.nsTextTertiary)
                } else {
                    ForEach(entries) { entry in
                        usageRow(entry)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: TodayUsageSummaryLayout.contentMaxWidth, alignment: .center)
        .padding(TodayUsageSummaryLayout.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .schedulerCardSurface()
    }

    private func usageRow(_ entry: TodayUsageEntry) -> some View {
        HStack(spacing: 6) {
            SummaryPatternSwatch(entry: entry)
            Text(entry.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.nsTextPrimary)
                .lineLimit(1)
                .help(entry.name)
            Spacer(minLength: 4)
            Text(DaylineContract.compactDurationText(entry.seconds, localeIdentifier: snapshot.localeIdentifier))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.nsTextTertiary)
                .frame(width: 42, alignment: .trailing)
        }
        .frame(height: 13)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([
            entry.name,
            TodayUsageSummaryProjection.percentageText(entry),
            TodayUsageSummaryProjection.durationText(entry.seconds, localeIdentifier: snapshot.localeIdentifier)
        ].joined(separator: ", "))
    }
}

private struct SummaryPatternSwatch: View {
    let entry: TodayUsageEntry

    var body: some View {
        Capsule()
            .stroke(
                Color(hex: entry.colorHex),
                style: StrokeStyle(
                    lineWidth: 2,
                    lineCap: .round,
                    dash: DaylineContract.pattern(for: entry.categoryID).dash.map { CGFloat($0) }
                )
            )
            .frame(width: 14, height: 7)
            .accessibilityHidden(true)
    }
}

private struct UsageCategoryRing: View {
    let entries: [TodayUsageEntry]

    var body: some View {
        ZStack {
            Circle().stroke(Color.nsBorder.opacity(0.75), lineWidth: 8)
            ForEach(Array(ringSegments.enumerated()), id: \.offset) { _, segment in
                Circle()
                    .trim(from: segment.start, to: segment.end)
                    .stroke(Color(hex: segment.colorHex), style: StrokeStyle(lineWidth: 8, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .accessibilityHidden(true)
    }

    private var ringSegments: [(start: Double, end: Double, colorHex: String)] {
        var cursor = 0.0
        let gap = entries.count > 1 ? 0.008 : 0
        return entries.compactMap { entry in
            let start = cursor
            let end = min(1, cursor + max(0, entry.fraction) - gap)
            cursor = min(1, cursor + max(0, entry.fraction))
            return end > start ? (start, end, entry.colorHex) : nil
        }
    }
}
