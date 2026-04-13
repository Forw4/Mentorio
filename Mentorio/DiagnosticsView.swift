//
//  DiagnosticsView.swift
//  Mentorio
//

import SwiftUI
import UserNotifications

struct DiagnosticsView: View {
    private struct SeedScenario: Identifiable {
        let id = UUID()
        let title: String
        let prompt: String
    }

    @EnvironmentObject var viewModel: MentorioViewModel

    @State private var analyticsEvents: [AnalyticsEventSnapshot] = []
    @State private var notifications: [NotificationDebugItem] = []
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var testStatus: String? = nil
    @State private var seedStatus: String? = nil
    @State private var isSpawningScenarios = false
    @State private var isClearingScenarios = false

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
                if analyticsEvents.isEmpty {
                    Text("События еще не зафиксированы")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(analyticsEvents) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.name)
                                .font(.subheadline.weight(.semibold))
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
        .task {
            await refreshData()
        }
        .refreshable {
            await refreshData()
        }
    }

    private func refreshData() async {
        authStatus = await NotificationManager.shared.fetchAuthorizationStatus()
        notifications = await NotificationManager.shared.fetchPendingNotifications()
        analyticsEvents = AnalyticsManager.shared.recentEvents(limit: 20)
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

            viewModel.addNote(scenario.prompt)
            existing.insert(normalizedPrompt)
            added += 1
        }

        seedStatus = "Добавлено: \(added), пропущено (уже были): \(skipped). Проверь основной экран заметок."
        AnalyticsManager.shared.track("diagnostics_seed_scenarios_spawned", properties: [
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
}

#Preview {
    NavigationStack {
        DiagnosticsView()
    }
    .environmentObject(makePreviewViewModel())
}
