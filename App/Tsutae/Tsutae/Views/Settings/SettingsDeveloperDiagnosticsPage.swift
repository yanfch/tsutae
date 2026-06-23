import AppKit
import Combine
import SwiftUI
import TsutaeCore

struct DeveloperDiagnosticsPage: View {
    let onBack: () -> Void
    @StateObject private var store = DeveloperDiagnosticsStore()

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.Spacing.card) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Label(L10n.Settings.developerDiagnosticsBackButton, systemImage: "chevron.left")
                }
                .buttonStyle(SettingsGhostButtonStyle())

                Spacer()

                Button(L10n.Settings.developerDiagnosticsRevealLogButton) {
                    store.revealLog()
                }
                .buttonStyle(.bordered)

                Button(L10n.Settings.sttRefreshButton) {
                    store.refresh()
                }
                .buttonStyle(SettingsAccentButtonStyle())
            }

            SettingsDashboardCard(
                title: L10n.Settings.developerDiagnosticsSummaryTitle,
                subtitle: store.summarySubtitle
            ) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 180), spacing: 10),
                        GridItem(.flexible(minimum: 180), spacing: 10),
                        GridItem(.flexible(minimum: 180), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    DeveloperDiagnosticsMetricCell(title: L10n.Settings.developerDiagnosticsTodayCount, value: "\(store.summary.todayCount)")
                    DeveloperDiagnosticsMetricCell(title: L10n.Settings.developerDiagnosticsOutputChars, value: "\(store.summary.outputChars)")
                    DeveloperDiagnosticsMetricCell(title: L10n.Settings.developerDiagnosticsTotalSamples, value: "\(store.summary.totalCount)")
                    DeveloperDiagnosticsMetricCell(title: L10n.Settings.developerDiagnosticsLocalCleanup, value: "\(store.summary.localCleanupCount)")
                    DeveloperDiagnosticsMetricCell(title: L10n.Settings.developerDiagnosticsRemoteCleanup, value: "\(store.summary.remoteCleanupCount)")
                    DeveloperDiagnosticsMetricCell(title: L10n.Settings.developerDiagnosticsClipboardFallback, value: "\(store.summary.clipboardFallbackCount)")
                }
            }

            SettingsDashboardCard(title: L10n.Settings.developerDiagnosticsTimingTitle, subtitle: L10n.Settings.developerDiagnosticsTimingSubtitle) {
                SettingsKeyValueList(rows: [
                    (L10n.Settings.developerDiagnosticsE2E, store.summary.e2eSummary),
                    (L10n.Settings.developerDiagnosticsASR, store.summary.asrSummary),
                    (L10n.Settings.developerDiagnosticsCleanup, store.summary.cleanupSummary),
                    (L10n.Settings.developerDiagnosticsInsertion, store.summary.insertionSummary)
                ])
            }

            SettingsDashboardCard(title: L10n.Settings.developerDiagnosticsAppsTitle, subtitle: L10n.Settings.developerDiagnosticsAppsSubtitle) {
                if store.summary.apps.isEmpty {
                    SettingsInlineStatusMessage(text: L10n.Settings.developerDiagnosticsNoSamples, tone: .neutral)
                } else {
                    VStack(spacing: 10) {
                        ForEach(store.summary.apps) { app in
                            DeveloperDiagnosticsAppRow(app: app)
                        }
                    }
                }
            }

            SettingsDashboardCard(title: L10n.Settings.developerDiagnosticsTermsTitle, subtitle: L10n.Settings.developerDiagnosticsTermsSubtitle) {
                if store.summary.terms.isEmpty {
                    SettingsInlineStatusMessage(text: L10n.Settings.developerDiagnosticsNoTerms, tone: .neutral)
                } else {
                    HStack(spacing: 8) {
                        ForEach(store.summary.terms) { term in
                            ServerStatusCapsule(title: "\(term.term) · \(term.count)", tone: .soft)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            SettingsDashboardCard(title: L10n.Settings.developerDiagnosticsRecentTitle, subtitle: L10n.Settings.developerDiagnosticsRecentSubtitle) {
                if store.recentRecords.isEmpty {
                    SettingsInlineStatusMessage(text: L10n.Settings.developerDiagnosticsNoSamples, tone: .neutral)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(store.recentRecords) { record in
                            DeveloperDiagnosticsSampleRow(record: record)
                        }
                    }
                }
            }
        }
        .onAppear {
            store.refresh()
        }
    }
}

@MainActor
private final class DeveloperDiagnosticsStore: ObservableObject {
    @Published private(set) var records: [DeveloperDiagnosticsRecord] = []
    @Published private(set) var summary = DeveloperDiagnosticsSummary.empty

    var recentRecords: [DeveloperDiagnosticsRecord] {
        Array(records.prefix(8))
    }

    var summarySubtitle: String {
        L10n.Settings.developerDiagnosticsSummarySubtitle(summary.totalCount)
    }

    func refresh() {
        let decoded = Self.loadRecords()
        records = decoded.sorted { $0.date > $1.date }
        summary = DeveloperDiagnosticsSummary(records: records)
    }

    func revealLog() {
        let fileURL = ASRSampleLog.fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            NSWorkspace.shared.open(fileURL.deletingLastPathComponent())
        }
    }

    private static func loadRecords(limit: Int = 500) -> [DeveloperDiagnosticsRecord] {
        guard let text = try? String(contentsOf: ASRSampleLog.fileURL, encoding: .utf8) else {
            return []
        }
        let decoder = JSONDecoder()
        return text
            .split(separator: "\n")
            .suffix(limit)
            .compactMap { line -> DeveloperDiagnosticsRecord? in
                guard let data = String(line).data(using: .utf8),
                      let record = try? decoder.decode(ASRSampleLog.Record.self, from: data) else {
                    return nil
                }
                return DeveloperDiagnosticsRecord(record: record)
            }
    }
}

private struct DeveloperDiagnosticsRecord: Identifiable {
    let record: ASRSampleLog.Record
    let date: Date

    var id: String { record.id }

    init?(record: ASRSampleLog.Record) {
        guard let date = Self.isoFormatter.date(from: record.timestamp) else {
            return nil
        }
        self.record = record
        self.date = date
    }

    var targetAppTitle: String {
        record.targetApplication?.localizedName?.diagnosticsNilIfBlank
            ?? record.targetApplication?.bundleIdentifier?.diagnosticsNilIfBlank
            ?? L10n.Settings.developerDiagnosticsUnknownApp
    }

    var providerTitle: String {
        record.postProcessing?.provider ?? L10n.Settings.developerDiagnosticsNoProvider
    }

    var timeTitle: String {
        Self.timeFormatter.string(from: date)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct DeveloperDiagnosticsSummary {
    struct AppMetric: Identifiable {
        let id: String
        let title: String
        let count: Int
        let chars: Int
    }

    struct TermMetric: Identifiable {
        let id: String
        let term: String
        let count: Int
    }

    let totalCount: Int
    let todayCount: Int
    let outputChars: Int
    let localCleanupCount: Int
    let remoteCleanupCount: Int
    let clipboardFallbackCount: Int
    let e2eSummary: String
    let asrSummary: String
    let cleanupSummary: String
    let insertionSummary: String
    let apps: [AppMetric]
    let terms: [TermMetric]

    static let empty = DeveloperDiagnosticsSummary(records: [])

    init(records: [DeveloperDiagnosticsRecord]) {
        let calendar = Calendar.current
        let today = records.filter { calendar.isDateInToday($0.date) }
        totalCount = records.count
        todayCount = today.count
        outputChars = today.reduce(0) { $0 + $1.record.finalChars }
        localCleanupCount = today.filter { $0.record.postProcessing?.provider.contains("rules") == true }.count
        remoteCleanupCount = today.filter { $0.record.postProcessing?.provider.contains("openai_compatible") == true }.count
        clipboardFallbackCount = today.filter { $0.record.insertion?.method == "clipboard_fallback" }.count
        e2eSummary = Self.percentileSummary(today.compactMap(\.record.endToEndElapsedMs))
        asrSummary = Self.percentileSummary(today.map(\.record.transcriptionElapsedMs))
        cleanupSummary = Self.percentileSummary(today.compactMap(\.record.postProcessing?.elapsedMs))
        insertionSummary = Self.percentileSummary(today.compactMap(\.record.insertion?.elapsedMs))
        apps = Self.appMetrics(for: today)
        terms = Self.termMetrics(for: today)
    }

    private static func appMetrics(for records: [DeveloperDiagnosticsRecord]) -> [AppMetric] {
        let grouped = Dictionary(grouping: records) { record in
            record.targetAppTitle
        }
        return grouped
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
            .prefix(6)
            .map { $0 }
    }

    private static func termMetrics(for records: [DeveloperDiagnosticsRecord]) -> [TermMetric] {
        let terms = records.flatMap { $0.record.postProcessing?.dictionaryMatches ?? [] }
        let grouped = Dictionary(grouping: terms, by: { $0 })
        return grouped
            .map { term, values in TermMetric(id: term, term: term, count: values.count) }
            .sorted {
                if $0.count == $1.count { return $0.term < $1.term }
                return $0.count > $1.count
            }
            .prefix(8)
            .map { $0 }
    }

    private static func percentileSummary(_ values: [Double]) -> String {
        guard let p50 = percentile(values, fraction: 0.5),
              let p95 = percentile(values, fraction: 0.95) else {
            return "—"
        }
        return "p50 \(formatMs(p50)) · p95 \(formatMs(p95))"
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
}

private struct DeveloperDiagnosticsMetricCell: View {
    let title: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(DS.font.mono(size: 18, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? DS.color.foregroundDark : DS.color.foreground)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
                )
        )
    }
}

private struct DeveloperDiagnosticsAppRow: View {
    let app: DeveloperDiagnosticsSummary.AppMetric

    var body: some View {
        HStack(spacing: 10) {
            Text(app.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer()
            ServerStatusCapsule(title: "\(app.count)", tone: .soft)
            ServerStatusCapsule(title: L10n.Settings.developerDiagnosticsChars(app.chars), tone: .soft)
        }
    }
}

private struct DeveloperDiagnosticsSampleRow: View {
    let record: DeveloperDiagnosticsRecord
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ServerStatusCapsule(title: record.timeTitle, tone: .soft)
                ServerStatusCapsule(title: record.targetAppTitle, tone: .active)
                ServerStatusCapsule(title: record.providerTitle, tone: .soft)
                Spacer(minLength: 0)
                Text(L10n.Settings.developerDiagnosticsE2ERow(record.record.endToEndElapsedMs.map(DeveloperDiagnosticsSummary.formatMsForRow) ?? "—"))
                    .font(DS.font.mono(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.Settings.developerDiagnosticsFinalLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(record.record.finalText)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(2)
                    .textSelection(.enabled)
                if record.record.rawText != record.record.finalText {
                    Text(L10n.Settings.developerDiagnosticsRawLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(record.record.rawText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
                )
        )
    }
}

private extension DeveloperDiagnosticsSummary {
    static func formatMsForRow(_ value: Double) -> String {
        formatMs(value)
    }
}

private extension String {
    var diagnosticsNilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
