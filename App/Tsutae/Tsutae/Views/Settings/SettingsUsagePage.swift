import Combine
import SwiftUI
import TsutaeCore

struct UsageSettingsPage: View {
    @StateObject private var store = UsageInsightsStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            UsageHeader {
                store.refresh()
            }

            UsageTodaySummary(summary: store.summary)

            UsageDivider()

            HStack(alignment: .top, spacing: 26) {
                UsageTargetAppsSection(summary: store.summary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                UsageVerticalDivider()

                UsageSpeedSection(metric: store.summary.e2eSpeed)
                    .frame(width: 258, alignment: .top)
            }
            .frame(height: 198)

            UsageDivider()

            UsageCleanupSection(summary: store.summary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, minHeight: 584, alignment: .topLeading)
        .background(UsageCanvasBackground())
        .padding(.top, 4)
        .onAppear {
            store.refresh()
        }
    }
}

private struct UsageCanvasBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(fillColor)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .shadow(color: shadowColor, radius: 18, x: 0, y: 10)
    }

    private var fillColor: Color {
        colorScheme == .dark
            ? DS.color.surface2Dark.opacity(0.22)
            : DS.color.settingsCardLight.opacity(0.42)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.055)
            : DS.color.borderSoft.opacity(0.22)
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.0)
            : DS.shadow.soft.opacity(0.18)
    }
}

private struct UsageHeader: View {
    let onRefresh: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.Settings.tabUsage)
                    .font(DS.font.mono(size: 20, weight: .semibold))
                    .foregroundStyle(primaryText)
                Text(L10n.Settings.subtitleUsage)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onRefresh()
            } label: {
                Label(L10n.Settings.usageRefreshButton, systemImage: "arrow.clockwise")
            }
            .buttonStyle(SettingsGhostButtonStyle())
        }
    }

    private var primaryText: Color {
        colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground
    }

    private var secondaryText: Color {
        colorScheme == .dark ? DS.color.mutedDark : DS.color.muted
    }
}

private struct UsageTodaySummary: View {
    let summary: UsageSummary
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 34) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.Settings.usageHeroTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryText)
                Text(summary.primaryValue)
                    .font(DS.font.mono(size: 42, weight: .semibold))
                    .foregroundStyle(primaryText)
                    .monospacedDigit()
                Text(summary.primaryCaption)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(secondaryText)
            }
            .frame(width: 170, alignment: .leading)

            if summary.todayCount == 0 {
                SettingsInlineStatusMessage(text: L10n.Settings.usageNoActivity, tone: .neutral)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    UsageTopMetric(title: L10n.Settings.usageDictations, value: "\(summary.todayCount)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    UsageMetricSeparator(height: 44)
                    UsageTopMetric(title: L10n.Settings.usageTargetApps, value: "\(summary.appCount)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    UsageMetricSeparator(height: 44)
                    UsageTopMetric(title: L10n.Settings.usageAvgE2E, value: summary.averageE2E)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    UsageMetricSeparator(height: 44)
                    UsageTopMetric(title: L10n.Settings.usageLastActivity, value: summary.lastActivityTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    private var primaryText: Color {
        colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground
    }

    private var secondaryText: Color {
        colorScheme == .dark ? DS.color.mutedDark : DS.color.muted
    }
}

private struct UsageTargetAppsSection: View {
    let summary: UsageSummary
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        UsageSection(title: L10n.Settings.usageTopAppsTitle) {
            if summary.apps.isEmpty {
                SettingsInlineStatusMessage(text: L10n.Settings.usageNoSamples, tone: .neutral)
            } else {
                VStack(spacing: 13) {
                    UsageAppTableHeader()
                    ForEach(summary.apps) { app in
                        UsageAppRow(app: app, maxCount: summary.maxAppCount)
                    }
                }
            }
        }
    }
}

private struct UsageSpeedSection: View {
    let metric: UsageSummary.SpeedMetric

    var body: some View {
        UsageSection(title: L10n.Settings.usageTimingTitle) {
            VStack(alignment: .center, spacing: 12) {
                UsageGaugeView()
                    .frame(width: 174, height: 82)

                HStack(spacing: 20) {
                    UsageInlineMetric(title: L10n.Settings.usageTypical, value: metric.usual, valueSize: 21)
                    UsageMetricSeparator(height: 38)
                    UsageInlineMetric(title: L10n.Settings.usageSlow, value: metric.slower, valueSize: 21)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct UsageCleanupSection: View {
    let summary: UsageSummary

    var body: some View {
        UsageSection(title: L10n.Settings.usageCleanupTitle) {
            HStack(spacing: 18) {
                UsageInlineMetric(title: L10n.Settings.usageLocalCleanup, value: "\(summary.localCleanupCount)", alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                UsageMetricSeparator()
                UsageInlineMetric(title: L10n.Settings.usageRemoteCleanup, value: "\(summary.remoteCleanupCount)", alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                UsageMetricSeparator()
                UsageInlineMetric(title: L10n.Settings.usageDictionaryHits, value: "\(summary.dictionaryHitCount)", alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                UsageMetricSeparator()
                UsageInlineMetric(title: L10n.Settings.usageClipboardFallback, value: "\(summary.clipboardFallbackCount)", alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

private struct UsageSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title)
                .font(DS.font.mono(size: 13, weight: .medium))
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct UsageTopMetric: View {
    let title: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(DS.font.mono(size: 19, weight: .medium))
                .foregroundStyle(colorScheme == .dark ? DS.color.accentDark : DS.color.accent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minWidth: 82, alignment: .leading)
    }
}

private struct UsageInlineMetric: View {
    enum MetricAlignment {
        case leading
        case center
    }

    let title: String
    let value: String
    var valueSize: CGFloat = 17
    var alignment: MetricAlignment = .leading
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: stackAlignment, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(textAlignment)
            Text(value)
                .font(DS.font.mono(size: valueSize, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? DS.color.accentDark : DS.color.accent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(textAlignment)
        }
        .frame(minWidth: 76, alignment: frameAlignment)
    }

    private var stackAlignment: HorizontalAlignment {
        alignment == .center ? .center : .leading
    }

    private var frameAlignment: Alignment {
        alignment == .center ? .center : .leading
    }

    private var textAlignment: TextAlignment {
        alignment == .center ? .center : .leading
    }
}

private struct UsageMetricSeparator: View {
    var height: CGFloat = 36
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07))
            .frame(width: 1, height: height)
    }
}

private struct UsageAppRow: View {
    let app: UsageSummary.AppMetric
    let maxCount: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(app.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground)
                    .lineLimit(1)

                UsageProgressBar(progress: progress)
                    .frame(height: 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(app.count)")
                .font(DS.font.mono(size: 12, weight: .semibold))
                .foregroundStyle(countColor)
                .monospacedDigit()
                .frame(width: UsageAppTableHeader.countColumnWidth, alignment: .trailing)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(app.chars)")
                    .font(DS.font.mono(size: 12, weight: .semibold))
                    .foregroundStyle(charsNumberColor)
                    .monospacedDigit()
                Text(L10n.Settings.usageCharsUnit)
                    .font(DS.font.mono(size: 12, weight: .medium))
                    .foregroundStyle(charsUnitColor)
            }
                .frame(width: UsageAppTableHeader.charsColumnWidth, alignment: .trailing)
        }
    }

    private var progress: CGFloat {
        guard maxCount > 0 else { return 0 }
        return min(max(CGFloat(app.count) / CGFloat(maxCount), 0), 1)
    }

    private var countColor: Color {
        colorScheme == .dark ? DS.color.mutedDark.opacity(0.9) : DS.color.soft.opacity(0.86)
    }

    private var charsNumberColor: Color {
        colorScheme == .dark ? DS.color.mutedDark.opacity(0.84) : DS.color.soft.opacity(0.78)
    }

    private var charsUnitColor: Color {
        colorScheme == .dark ? DS.color.mutedDark.opacity(0.62) : DS.color.muted.opacity(0.7)
    }

}

private struct UsageAppTableHeader: View {
    static let countColumnWidth: CGFloat = 72
    static let charsColumnWidth: CGFloat = 96

    var body: some View {
        HStack(spacing: 18) {
            Text(L10n.Settings.usageAppColumn)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.Settings.usageDictations)
                .frame(width: Self.countColumnWidth, alignment: .trailing)
            Text(L10n.Settings.usageCharactersColumn)
                .frame(width: Self.charsColumnWidth, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
    }
}

private struct UsageProgressBar: View {
    let progress: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(barTrackColor)
                Capsule()
                    .fill(barFillColor)
                    .frame(width: max(proxy.size.width * progress, progress > 0 ? 10 : 0))
            }
        }
    }

    private var barFillColor: Color {
        colorScheme == .dark ? DS.color.accentDarkSoft.opacity(0.76) : DS.color.accent.opacity(0.78)
    }

    private var barTrackColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : DS.color.accent.opacity(0.07)
    }
}

private struct UsageGaugeView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height - 4)

            ZStack {
                UsageGaugeArc()
                    .stroke(gaugeTrackColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                UsageGaugeArc(endAngle: .degrees(220))
                    .stroke(gaugeFillColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                UsageGaugeNeedle()
                    .stroke(needleColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                Circle()
                    .stroke(needleColor, lineWidth: 2)
                    .frame(width: 11, height: 11)
                    .position(center)
            }
        }
    }

    private var gaugeTrackColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : DS.color.accent.opacity(0.09)
    }

    private var gaugeFillColor: Color {
        colorScheme == .dark ? DS.color.accentDarkSoft.opacity(0.72) : DS.color.accent.opacity(0.64)
    }

    private var needleColor: Color {
        colorScheme == .dark ? DS.color.foregroundDark.opacity(0.7) : DS.color.foreground.opacity(0.68)
    }
}

private struct UsageGaugeArc: Shape {
    var startAngle: Angle = .degrees(180)
    var endAngle: Angle = .degrees(360)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width / 2, rect.height * 0.95)
        let center = CGPoint(x: rect.midX, y: rect.maxY - 4)
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}

private struct UsageGaugeNeedle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY - 4)
        let angle = CGFloat(Angle.degrees(226).radians)
        let ringRadius: CGFloat = 6.4
        let end = CGPoint(x: rect.midX - rect.width * 0.18, y: rect.midY + 2)
        let ringEdge = CGPoint(
            x: center.x + cos(angle) * ringRadius,
            y: center.y + sin(angle) * ringRadius
        )
        path.move(to: ringEdge)
        path.addLine(to: end)
        return path
    }
}

private struct UsageDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
            .frame(height: 1)
    }
}

private struct UsageVerticalDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
            .frame(width: 1)
    }
}

@MainActor
private final class UsageInsightsStore: ObservableObject {
    @Published private(set) var summary = UsageSummary.empty

    func refresh() {
        let records = Self.loadRecords()
        summary = UsageSummary(records: records.sorted { $0.date > $1.date })
    }

    private static func loadRecords(limit: Int = 500) -> [UsageRecord] {
        guard let text = try? String(contentsOf: ASRSampleLog.fileURL, encoding: .utf8) else {
            return []
        }
        let decoder = JSONDecoder()
        return text
            .split(separator: "\n")
            .suffix(limit)
            .compactMap { line -> UsageRecord? in
                guard let data = String(line).data(using: .utf8),
                      let record = try? decoder.decode(ASRSampleLog.Record.self, from: data) else {
                    return nil
                }
                return UsageRecord(record: record)
            }
    }
}

private struct UsageRecord {
    let record: ASRSampleLog.Record
    let date: Date

    init?(record: ASRSampleLog.Record) {
        guard let date = Self.parseDate(record.timestamp) else {
            return nil
        }
        self.record = record
        self.date = date
    }

    var targetAppTitle: String {
        record.targetApplication?.localizedName?.usageNilIfBlank
            ?? record.targetApplication?.bundleIdentifier?.usageNilIfBlank
            ?? L10n.Settings.usageUnknownApp
    }

    private static func parseDate(_ value: String) -> Date? {
        fractionalFormatter.date(from: value) ?? plainFormatter.date(from: value)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct UsageSummary {
    struct SpeedMetric: Equatable {
        let usual: String
        let slower: String

        static let empty = SpeedMetric(usual: "—", slower: "—")
    }

    struct AppMetric: Identifiable {
        let id: String
        let title: String
        let count: Int
        let chars: Int
    }

    let todayCount: Int
    let outputChars: Int
    let appCount: Int
    let localCleanupCount: Int
    let remoteCleanupCount: Int
    let dictionaryHitCount: Int
    let clipboardFallbackCount: Int
    let e2eSpeed: SpeedMetric
    let asrSpeed: SpeedMetric
    let cleanupSpeed: SpeedMetric
    let insertionSpeed: SpeedMetric
    let averageE2E: String
    let lastActivityTitle: String
    let apps: [AppMetric]
    let maxAppCount: Int

    static let empty = UsageSummary(records: [])

    init(records: [UsageRecord]) {
        let calendar = Calendar.current
        let today = records.filter { calendar.isDateInToday($0.date) }
        todayCount = today.count
        outputChars = today.reduce(0) { $0 + $1.record.finalChars }
        localCleanupCount = today.filter { $0.record.postProcessing?.provider.contains("rules") == true }.count
        remoteCleanupCount = today.filter { $0.record.postProcessing?.provider.contains("openai_compatible") == true }.count
        dictionaryHitCount = today.reduce(0) { $0 + ($1.record.postProcessing?.dictionaryMatches.count ?? 0) }
        clipboardFallbackCount = today.filter { $0.record.insertion?.method == "clipboard_fallback" }.count
        e2eSpeed = Self.speedMetric(today.compactMap(\.record.endToEndElapsedMs))
        asrSpeed = Self.speedMetric(today.map(\.record.transcriptionElapsedMs))
        cleanupSpeed = Self.speedMetric(today.compactMap(\.record.postProcessing?.elapsedMs))
        insertionSpeed = Self.speedMetric(today.compactMap(\.record.insertion?.elapsedMs))
        averageE2E = Self.averageSummary(today.compactMap(\.record.endToEndElapsedMs))
        lastActivityTitle = today.first.map { Self.timeFormatter.string(from: $0.date) } ?? "—"

        let grouped = Dictionary(grouping: today) { $0.targetAppTitle }
        let appMetrics = grouped
            .map { title, records in
                AppMetric(
                    id: title,
                    title: title,
                    count: records.count,
                    chars: records.reduce(0) { $0 + $1.record.finalChars }
                )
            }
            .sorted {
                if $0.count == $1.count { return $0.title < $1.title }
                return $0.count > $1.count
            }
        appCount = appMetrics.count
        apps = Array(appMetrics.prefix(3))
        maxAppCount = apps.map(\.count).max() ?? 0
    }

    var primaryValue: String {
        outputChars > 0 ? "\(outputChars)" : "0"
    }

    var primaryCaption: String {
        outputChars > 0 ? L10n.Settings.usageOutputChars : L10n.Settings.usageHeroSubtitle
    }

    private static func speedMetric(_ values: [Double]) -> SpeedMetric {
        guard let usual = percentile(values, fraction: 0.5),
              let slower = percentile(values, fraction: 0.95) else {
            return .empty
        }
        return SpeedMetric(usual: formatMs(usual), slower: formatMs(slower))
    }

    private static func averageSummary(_ values: [Double]) -> String {
        guard values.isEmpty == false else { return "—" }
        let average = values.reduce(0, +) / Double(values.count)
        return formatMs(average)
    }

    private static func percentile(_ values: [Double], fraction: Double) -> Double? {
        guard values.isEmpty == false else { return nil }
        let sorted = values.sorted()
        let index = min(max(Int(ceil(Double(sorted.count) * fraction)) - 1, 0), sorted.count - 1)
        return sorted[index]
    }

    private static func formatMs(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.2fs", value / 1000)
        }
        return String(format: "%.0fms", value)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private extension String {
    var usageNilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
