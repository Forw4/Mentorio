//
//  DiagnosticsView.swift
//  Mentorio
//

import SwiftUI
import UserNotifications
import UIKit

struct DiagnosticsView: View {
    private struct SeedScenario: Identifiable {
        let id = UUID()
        let title: String
        let prompt: String
    }

    private enum EventLogFilter: String, CaseIterable, Identifiable {
        case all
        case product
        case debug

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return "All"
            case .product:
                return "Product"
            case .debug:
                return "Debug"
            }
        }

        var analyticsChannel: String? {
            switch self {
            case .all:
                return nil
            case .product:
                return "product"
            case .debug:
                return "debug"
            }
        }
    }

    private struct CoreLoopMetrics {
        let generatedCount: Int
        let startedCount: Int
        let completedCount: Int
        let completionRate: Double?
        let realityCaptureRate: Double?
        let avgTimeToFirstAction: TimeInterval?
        let avgTimeToFirstCompletion: TimeInterval?

        static let empty = CoreLoopMetrics(
            generatedCount: 0,
            startedCount: 0,
            completedCount: 0,
            completionRate: nil,
            realityCaptureRate: nil,
            avgTimeToFirstAction: nil,
            avgTimeToFirstCompletion: nil
        )
    }

    @EnvironmentObject var viewModel: MentorioViewModel

    @State private var analyticsEvents: [AnalyticsEventSnapshot] = []
    @State private var notifications: [NotificationDebugItem] = []
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var testStatus: String? = nil
    @State private var seedStatus: String? = nil
    @State private var isSpawningScenarios = false
    @State private var isClearingScenarios = false
    @State private var coreMetrics: CoreLoopMetrics = .empty
    @State private var eventFilter: EventLogFilter = .all
    @State private var isRunningAnchoringSuite = false
    @State private var anchoringSuiteReport: [String] = []
    @State private var anchoringSuiteRunAt: Date? = nil
    @State private var copyStatus: String? = nil

    private let seedScenarios: [SeedScenario] = [
        SeedScenario(
            title: "Карьерный выбор (High-Stakes)",
            prompt: "Мне 26, я backend-разработчик. Есть оффер в Берлине с зарплатой выше на 40%, но это переезд, разлука с семьей и смена команды. Если остаюсь, стабильность и друзья рядом, но рост медленнее. Уже месяц сравниваю и не могу выбрать."
        ),
        SeedScenario(
            title: "Ресурс или отмазка (Preconditions)",
            prompt: "Хочу начать брать заказы по моушен-дизайну, но постоянно говорю, что без нового ноутбука старт бессмысленен. Денег впритык. Не понимаю, это реальный блокер или я просто избегаю первого клиента."
        ),
        SeedScenario(
            title: "Сложный разговор (Личные отношения)",
            prompt: "Тяну разговор с партнером о деньгах и бытовых обязанностях уже 3 недели. Накопилось раздражение, но каждый вечер откладываю и делаю вид, что все нормально."
        ),
        SeedScenario(
            title: "Туман и перегруз (Vague Overwhelm)",
            prompt: "Последние два месяца я как в тумане: сплю плохо, срываю дедлайны, скроллю до ночи и злюсь на себя. Хочу собраться, но не понимаю, за что хвататься первым."
        ),
        SeedScenario(
            title: "Многотемный хаос (Topics)",
            prompt: "У меня одновременно горит диплом, долг по кредитке, поиск новой квартиры и конфликт с другом из-за совместного проекта. В голове каша, ничего не двигается."
        )
    ]

    var body: some View {
        List {
            Section("Уведомления") {
                Text("Доступ: \(authorizationLabel(authStatus))")
                    .font(.subheadline)

                Button("Отправить тестовое уведомление (10с)") {
                    NotificationManager.shared.scheduleTestNotification()
                    testStatus = "Тестовое уведомление запланировано через 10 секунд"
                    Task {
                        await refreshData()
                    }
                }
                .disabled(authStatus == .denied || authStatus == .notDetermined)

                if let testStatus {
                    Text(testStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if notifications.isEmpty {
                    Text("Нет ожидающих уведомлений")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(notifications) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                            Text(item.body)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("Триггер: \(item.nextTriggerDescription)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Идентификатор: \(item.id)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Аналитика (последние 20)") {
                Picker("Канал", selection: $eventFilter) {
                    ForEach(EventLogFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                if analyticsEvents.isEmpty {
                    Text("События еще не зафиксированы")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(analyticsEvents) { event in
                        let channel = event.properties["channel"] ?? "product"
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(event.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(channel.uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(channel == "debug" ? .orange : .green)
                            }
                            if !event.properties.isEmpty {
                                Text(serializedProperties(event.properties))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Core Loop Metrics") {
                metricRow(
                    title: "Completion Rate",
                    value: percentString(coreMetrics.completionRate),
                    subtitle: "\(coreMetrics.completedCount) из \(coreMetrics.generatedCount) generated"
                )

                metricRow(
                    title: "Reality Check Capture",
                    value: percentString(coreMetrics.realityCaptureRate),
                    subtitle: "selected vs selected+skipped"
                )

                metricRow(
                    title: "Time to First Action",
                    value: durationString(coreMetrics.avgTimeToFirstAction),
                    subtitle: "среднее: braindump_started -> one_action_started"
                )

                metricRow(
                    title: "Time to First Completion",
                    value: durationString(coreMetrics.avgTimeToFirstCompletion),
                    subtitle: "среднее: braindump_started -> one_action_completed"
                )

                metricRow(
                    title: "Notes Started",
                    value: "\(coreMetrics.startedCount)",
                    subtitle: "уникальные note_id с one_action_started"
                )
            }

            Section("Context Anchoring Suite") {
                Button(isRunningAnchoringSuite ? "Проверка в процессе..." : "Запустить regression suite") {
                    runContextAnchoringSuite()
                }
                .disabled(isRunningAnchoringSuite)

                if let anchoringSuiteRunAt {
                    Text("Последний запуск: \(anchoringSuiteRunAt.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if anchoringSuiteReport.isEmpty {
                    Text("Suite еще не запускался")
                        .foregroundStyle(.secondary)
                } else {
                    let passCount = anchoringSuiteReport.filter { $0.hasPrefix("PASS") }.count
                    let failCount = anchoringSuiteReport.filter { $0.hasPrefix("FAIL") }.count

                    Text("PASS: \(passCount), FAIL: \(failCount)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(failCount == 0 ? .green : .orange)

                    Button("Скопировать отчет") {
                        copyAnchoringSuiteReport()
                    }

                    if let copyStatus {
                        Text(copyStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(Array(anchoringSuiteReport.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(line.hasPrefix("PASS") ? .green : .orange)
                    }
                }
            }

            Section("Тестовые сценарии") {
                Button(isSpawningScenarios ? "Добавление в процессе..." : "Добавить 5 сценариев на главный экран") {
                    spawnSeedScenarios()
                }
                .disabled(isSpawningScenarios || isClearingScenarios)

                Button(isClearingScenarios ? "Очистка в процессе..." : "Очистить тестовые сценарии") {
                    clearSeedScenarios()
                }
                .disabled(isSpawningScenarios || isClearingScenarios)

                if let seedStatus {
                    Text(seedStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(seedScenarios) { scenario in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scenario.title)
                            .font(.subheadline.weight(.semibold))
                        Text(scenario.prompt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Диагностика")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.051, green: 0.051, blue: 0.051))
        .task {
            await refreshData()
        }
        .refreshable {
            await refreshData()
        }
        .onChange(of: eventFilter) { _, _ in
            refreshAnalyticsData()
        }
    }

    private func refreshData() async {
        authStatus = await NotificationManager.shared.fetchAuthorizationStatus()
        notifications = await NotificationManager.shared.fetchPendingNotifications()
        refreshAnalyticsData()
    }

    private func refreshAnalyticsData() {
        analyticsEvents = AnalyticsManager.shared.recentEvents(
            limit: 20,
            channel: eventFilter.analyticsChannel
        )
        let productEvents = AnalyticsManager.shared.recentEvents(limit: 500, channel: "product")
        coreMetrics = computeCoreMetrics(from: productEvents)
    }

    private func computeCoreMetrics(from events: [AnalyticsEventSnapshot]) -> CoreLoopMetrics {
        var generatedIDs = Set<String>()
        var startedIDs = Set<String>()
        var completedIDs = Set<String>()
        var realitySelectedIDs = Set<String>()
        var realitySkippedIDs = Set<String>()

        var braindumpByNote: [String: Date] = [:]
        var actionStartedByNote: [String: Date] = [:]
        var completedByNote: [String: Date] = [:]

        for event in events {
            guard let noteID = event.properties["note_id"], !noteID.isEmpty else { continue }

            switch event.name {
            case "braindump_started":
                if braindumpByNote[noteID] == nil {
                    braindumpByNote[noteID] = event.timestamp
                }
            case "one_action_generated":
                generatedIDs.insert(noteID)
            case "one_action_started":
                startedIDs.insert(noteID)
                if actionStartedByNote[noteID] == nil {
                    actionStartedByNote[noteID] = event.timestamp
                }
            case "one_action_completed":
                completedIDs.insert(noteID)
                if completedByNote[noteID] == nil {
                    completedByNote[noteID] = event.timestamp
                }
            case "reality_check_selected":
                realitySelectedIDs.insert(noteID)
            case "reality_check_skipped":
                realitySkippedIDs.insert(noteID)
            default:
                continue
            }
        }

        let completionRate: Double?
        if generatedIDs.isEmpty {
            completionRate = nil
        } else {
            completionRate = Double(completedIDs.count) / Double(generatedIDs.count)
        }

        let realityDenominator = realitySelectedIDs.union(realitySkippedIDs).count
        let realityCaptureRate: Double?
        if realityDenominator == 0 {
            realityCaptureRate = nil
        } else {
            realityCaptureRate = Double(realitySelectedIDs.count) / Double(realityDenominator)
        }

        var tfaIntervals: [TimeInterval] = []
        var tfcIntervals: [TimeInterval] = []

        for (noteID, startDate) in braindumpByNote {
            if let firstActionDate = actionStartedByNote[noteID], firstActionDate >= startDate {
                tfaIntervals.append(firstActionDate.timeIntervalSince(startDate))
            }
            if let firstCompletionDate = completedByNote[noteID], firstCompletionDate >= startDate {
                tfcIntervals.append(firstCompletionDate.timeIntervalSince(startDate))
            }
        }

        let avgTFA = tfaIntervals.isEmpty ? nil : tfaIntervals.reduce(0, +) / Double(tfaIntervals.count)
        let avgTFC = tfcIntervals.isEmpty ? nil : tfcIntervals.reduce(0, +) / Double(tfcIntervals.count)

        return CoreLoopMetrics(
            generatedCount: generatedIDs.count,
            startedCount: startedIDs.count,
            completedCount: completedIDs.count,
            completionRate: completionRate,
            realityCaptureRate: realityCaptureRate,
            avgTimeToFirstAction: avgTFA,
            avgTimeToFirstCompletion: avgTFC
        )
    }

    private func authorizationLabel(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "не определен"
        case .denied:
            return "запрещен"
        case .authorized:
            return "разрешен"
        case .provisional:
            return "временный"
        case .ephemeral:
            return "эфемерный"
        @unknown default:
            return "неизвестно"
        }
    }

    private func serializedProperties(_ properties: [String: String]) -> String {
        properties
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ", ")
    }

    private func metricRow(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func percentString(_ value: Double?) -> String {
        guard let value else { return "-" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func durationString(_ interval: TimeInterval?) -> String {
        guard let interval else { return "-" }
        let totalSeconds = Int(interval.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes == 0 {
            return "\(seconds)с"
        }
        return "\(minutes)м \(seconds)с"
    }

    @MainActor
    private func spawnSeedScenarios() {
        isSpawningScenarios = true

        var existing = Set(
            (viewModel.notes + viewModel.archivedNotes + viewModel.deletedNotes)
                .map { normalizedText($0.text) }
        )

        var added = 0
        var skipped = 0

        for scenario in seedScenarios {
            let normalizedPrompt = normalizedText(scenario.prompt)
            if existing.contains(normalizedPrompt) {
                skipped += 1
                continue
            }

            let note = viewModel.addNote(scenario.prompt, source: "diagnostics_seed")
            if let data = viewModel.encodeChatHistory([(isAI: false, text: scenario.prompt)]) {
                note.chatHistoryData = data
            }
            existing.insert(normalizedPrompt)
            added += 1
        }

        seedStatus = "Добавлено: \(added), пропущено (уже были): \(skipped). Проверь основной экран заметок."
        AnalyticsManager.shared.track("diagnostics_seed_scenarios_spawned", properties: [
            "channel": "debug",
            "added": "\(added)",
            "skipped": "\(skipped)",
            "total": "\(seedScenarios.count)"
        ])

        isSpawningScenarios = false
    }

    @MainActor
    private func clearSeedScenarios() {
        isClearingScenarios = true

        let removed = viewModel.purgeNotes(matchingTexts: seedScenarios.map(\.prompt))
        if removed > 0 {
            seedStatus = "Очищено тестовых сценариев: \(removed)."
        } else {
            seedStatus = "Тестовые сценарии для очистки не найдены."
        }

        AnalyticsManager.shared.track("diagnostics_seed_scenarios_cleared", properties: [
            "channel": "debug",
            "removed": "\(removed)",
            "total": "\(seedScenarios.count)"
        ])

        isClearingScenarios = false
    }

    private func normalizedText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    @MainActor
    private func runContextAnchoringSuite() {
        isRunningAnchoringSuite = true
        copyStatus = nil

        #if DEBUG
        let report = MentorioAIService.runContextAnchoringRegressionSuite()
        anchoringSuiteReport = report
        anchoringSuiteRunAt = Date()

        let failCount = report.filter { $0.hasPrefix("FAIL") }.count
        AnalyticsManager.shared.track("diagnostics_context_anchoring_suite_run", properties: [
            "channel": "debug",
            "cases": "\(report.count)",
            "fails": "\(failCount)"
        ])
        #else
        anchoringSuiteReport = ["FAIL: suite_available_only_in_debug_build"]
        anchoringSuiteRunAt = Date()
        #endif

        isRunningAnchoringSuite = false
    }

    @MainActor
    private func copyAnchoringSuiteReport() {
        guard !anchoringSuiteReport.isEmpty else {
            copyStatus = "Нечего копировать"
            return
        }

        let reportText = anchoringSuiteReport.joined(separator: "\n")
        UIPasteboard.general.string = reportText
        copyStatus = "Отчет скопирован"
    }
}

#Preview {
    NavigationStack {
        DiagnosticsView()
    }
    .environmentObject(makePreviewViewModel())
}
