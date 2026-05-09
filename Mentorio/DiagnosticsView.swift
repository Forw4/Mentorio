//
//  DiagnosticsView.swift
//  Mentorio
//

import SwiftUI
import UserNotifications
import UIKit

struct DiagnosticsView: View {

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
        let braindumpCount: Int
        let generatedCount: Int
        let startedCount: Int
        let completedCount: Int
        let completionRate: Double?
        let engagementRate: Double?
        let realityCaptureRate: Double?
        let avgTimeToFirstAction: TimeInterval?
        let avgTimeToFirstCompletion: TimeInterval?

        static let empty = CoreLoopMetrics(
            braindumpCount: 0,
            generatedCount: 0,
            startedCount: 0,
            completedCount: 0,
            completionRate: nil,
            engagementRate: nil,
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
    @State private var isWipingData = false
    @State private var coreMetrics: CoreLoopMetrics = .empty
    @State private var eventFilter: EventLogFilter = .all
    @State private var isRunningAnchoringSuite = false
    @State private var anchoringSuiteReport: [String] = []
    @State private var anchoringSuiteRunAt: Date? = nil
    @State private var copyStatus: String? = nil

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

            Section("Воронка конверсии (Core Funnel)") {
                metricRow(
                    title: "1. Выгрузка (Braindump)",
                    value: "\(coreMetrics.braindumpCount)",
                    subtitle: "Попытки выговориться"
                )

                metricRow(
                    title: "2. Сгенерирован шаг",
                    value: "\(coreMetrics.generatedCount)",
                    subtitle: "Нейросеть дала ответ"
                )

                metricRow(
                    title: "3. Шаг взят в работу",
                    value: "\(coreMetrics.startedCount)",
                    subtitle: "Конверсия из старта: \(percentString(coreMetrics.engagementRate))"
                )

                metricRow(
                    title: "4. Шаг выполнен",
                    value: "\(coreMetrics.completedCount)",
                    subtitle: "Конверсия из взятого: \(percentString(coreMetrics.completionRate))"
                )

                Divider()

                metricRow(
                    title: "Reality Check Capture",
                    value: percentString(coreMetrics.realityCaptureRate),
                    subtitle: "selected vs selected+skipped"
                )

                metricRow(
                    title: "Time to First Action",
                    value: durationString(coreMetrics.avgTimeToFirstAction),
                    subtitle: "среднее: braindump -> action_started"
                )

                metricRow(
                    title: "Time to First Completion",
                    value: durationString(coreMetrics.avgTimeToFirstCompletion),
                    subtitle: "среднее: braindump -> action_completed"
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

            Section("God Mode (Осторожно)") {
                Button(role: .destructive) {
                    isWipingData = true
                    viewModel.deleteAllData()
                    AnalyticsManager.shared.track("diagnostics_god_mode_wipe_data", properties: ["channel": "debug"])
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        isWipingData = false
                        await refreshData()
                    }
                } label: {
                    HStack {
                        Text(isWipingData ? "Удаление..." : "Сбросить все данные")
                        Spacer()
                        if isWipingData {
                            ProgressView()
                        }
                    }
                    .foregroundStyle(.red)
                }
                .disabled(isWipingData)

                Button("Сбросить кэш уведомлений") {
                    UserDefaults.standard.removeObject(forKey: "mentorio_last_open_date")
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
        var braindumpIDs = Set<String>()
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
                braindumpIDs.insert(noteID)
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

        let engagementRate: Double?
        if braindumpIDs.isEmpty {
            engagementRate = nil
        } else {
            engagementRate = Double(startedIDs.count) / Double(braindumpIDs.count)
        }

        let completionRate: Double?
        if startedIDs.isEmpty {
            completionRate = nil
        } else {
            completionRate = Double(completedIDs.count) / Double(startedIDs.count)
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
            braindumpCount: braindumpIDs.count,
            generatedCount: generatedIDs.count,
            startedCount: startedIDs.count,
            completedCount: completedIDs.count,
            completionRate: completionRate,
            engagementRate: engagementRate,
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
