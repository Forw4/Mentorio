//
//  NotificationManager.swift
//  Mentorio
//

import Foundation
import UserNotifications

struct NotificationDebugItem: Identifiable {
    let id: String
    let title: String
    let body: String
    let nextTriggerDescription: String
}

final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let inactivityIdentifiers = [
        "mentorio.inactivity.3days",
        "mentorio.inactivity.7days",
        "mentorio.inactivity.14days"
    ]
    private let testIdentifier = "mentorio.debug.test"
    private let lastOpenKey = "mentorio.lastOpenDate"

    private init() {}

    func requestPermissionIfNeeded() {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            if settings.authorizationStatus == .notDetermined {
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error {
                        print("[Notifications] Permission error: \(error.localizedDescription)")
                    } else {
                        print("[Notifications] Permission granted: \(granted)")
                    }
                }
            }
        }
    }

    func handleAppBecameActive() {
        UserDefaults.standard.set(Date(), forKey: lastOpenKey)
        cancelInactivityNotifications()
        scheduleInactivityLadder()
        scheduleWeeklyDigestNotification()
    }

    // MARK: - Scenario 1: Abandoned Intake (Забытый брейндамп)
    func scheduleAbandonedIntakeNotification(for noteId: UUID) {
        let identifier = "mentorio.abandoned.\(noteId.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Забытый брейндамп"
        content.body = "Мысли выгружены, но шаг не принят. Энергия слита впустую? Вернись и выбери одно физическое действие."
        content.sound = .default
        content.userInfo = ["note_id": noteId.uuidString]

        // 3 hours
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3 * 60 * 60, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("[Notifications] Failed to schedule abandoned intake (\(identifier)): \(error.localizedDescription)")
            }
        }
    }

    func cancelAbandonedIntakeNotification(for noteId: UUID) {
        let identifier = "mentorio.abandoned.\(noteId.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // MARK: - Scenario 2: Overdue Active Action Ladder (Лестница зависшего шага)
    func scheduleOverdueActiveStepNotifications(for noteId: UUID, actionText: String, emoji: String) {
        let displayEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "🎯" : emoji
        
        // 1. 5 hours
        scheduleOverdueStepPush(
            identifier: "mentorio.overdue.5h.\(noteId.uuidString)",
            noteId: noteId,
            body: "Прошло 5 часов. На шаг \(displayEmoji) '\(actionText)' нужно всего 15 минут. Сделай его прямо сейчас.",
            timeInterval: 5 * 60 * 60
        )
        
        // 2. 24 hours
        scheduleOverdueStepPush(
            identifier: "mentorio.overdue.24h.\(noteId.uuidString)",
            noteId: noteId,
            body: "Обещал сделать шаг: \(displayEmoji) '\(actionText)'. Прошли сутки. Сделал или испугался сопротивления?",
            timeInterval: 24 * 60 * 60
        )
        
        // 3. 48 hours
        scheduleOverdueStepPush(
            identifier: "mentorio.overdue.48h.\(noteId.uuidString)",
            noteId: noteId,
            body: "Вторые сутки пошли. Шаг \(displayEmoji) '\(actionText)' так и не сделан. Будем смотреть правде в глаза или продолжим саботировать?",
            timeInterval: 48 * 60 * 60
        )
    }

    private func scheduleOverdueStepPush(identifier: String, noteId: UUID, body: String, timeInterval: TimeInterval) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Фокус потерян"
        content.body = body
        content.sound = .default
        content.userInfo = ["note_id": noteId.uuidString]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("[Notifications] Failed to schedule overdue step push (\(identifier)): \(error.localizedDescription)")
            }
        }
    }

    func cancelOverdueActiveStepNotifications(for noteId: UUID) {
        let identifiers = [
            "mentorio.overdue.5h.\(noteId.uuidString)",
            "mentorio.overdue.24h.\(noteId.uuidString)",
            "mentorio.overdue.48h.\(noteId.uuidString)"
        ]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    // MARK: - Scenario 3: Inactivity Ladder (Лестница тишины)
    func scheduleInactivityLadder() {
        // 3 days
        scheduleInactivityNotification(
            identifier: "mentorio.inactivity.3days",
            body: "Три дня тишины. Сливаемся или возвращаемся в фокус?",
            timeInterval: 3 * 24 * 60 * 60
        )
        // 7 days
        scheduleInactivityNotification(
            identifier: "mentorio.inactivity.7days",
            body: "Неделя простоя. Прокрастинация победила, или ты боишься посмотреть фактам в глаза?",
            timeInterval: 7 * 24 * 60 * 60
        )
        // 14 days
        scheduleInactivityNotification(
            identifier: "mentorio.inactivity.14days",
            body: "Две недели без действий. Мы отключаем авто-напоминания, чтобы не создавать иллюзию контроля. Вернуться к реальности можно в любое время.",
            timeInterval: 14 * 24 * 60 * 60
        )
    }

    private func scheduleInactivityNotification(identifier: String, body: String, timeInterval: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Mentorio"
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("[Notifications] Failed to schedule inactivity push (\(identifier)): \(error.localizedDescription)")
            }
        }
    }

    func cancelInactivityNotifications() {
        center.removePendingNotificationRequests(withIdentifiers: inactivityIdentifiers)
    }

    // MARK: - Scenario 4: Weekly Digest Alert (Дайджест саботажа)
    func scheduleWeeklyDigestNotification() {
        let identifier = "mentorio.weeklyDigest"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Отчет о саботаже"
        content.body = "Собран недельный отчет о твоем саботаже. Зайди посмотреть, какие темы тебя стопорят чаще всего."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.weekday = 1 // Sunday
        dateComponents.hour = 19
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("[Notifications] Failed to schedule weekly digest push: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Debug
    func scheduleTestNotification() {
        center.removePendingNotificationRequests(withIdentifiers: [testIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Mentorio Debug"
        content.body = "Тестовое уведомление: notification pipeline работает"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        let request = UNNotificationRequest(
            identifier: testIdentifier,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("[Notifications] Failed to schedule test: \(error.localizedDescription)")
            }
        }
    }

    func fetchAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func fetchPendingNotifications() async -> [NotificationDebugItem] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                let items = requests.map { request in
                    let triggerDescription: String
                    if let trigger = request.trigger as? UNTimeIntervalNotificationTrigger {
                        let hours = Int(trigger.timeInterval / 3600)
                        triggerDescription = hours > 0 ? "через ~\(hours)ч" : "скоро"
                    } else {
                        triggerDescription = "кастомный trigger"
                    }

                    return NotificationDebugItem(
                        id: request.identifier,
                        title: request.content.title,
                        body: request.content.body,
                        nextTriggerDescription: triggerDescription
                    )
                }
                .sorted { $0.id < $1.id }
                continuation.resume(returning: items)
            }
        }
    }
}
