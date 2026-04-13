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
    private let inactivityIdentifier = "mentorio.inactivity.3days"
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
        cancelInactivityNotification()
        scheduleInactivityNotification()
    }

    func schedulePostActionNotification(for noteId: UUID) {
        let content = UNMutableNotificationContent()
        content.title = "Mentorio"
        content.body = "Ты вчера закрыл задачу. Действие дало результат, или просто поставил галочку?"
        content.sound = .default
        content.userInfo = ["note_id": noteId.uuidString]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 24 * 60 * 60, repeats: false)
        let request = UNNotificationRequest(
            identifier: "mentorio.postAction.\(noteId.uuidString)",
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("[Notifications] Failed to schedule post-action: \(error.localizedDescription)")
            }
        }
    }

    func scheduleInactivityNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Mentorio"
        content.body = "Три дня тишины. Сливаемся или возвращаемся в фокус?"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3 * 24 * 60 * 60, repeats: false)
        let request = UNNotificationRequest(
            identifier: inactivityIdentifier,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("[Notifications] Failed to schedule inactivity: \(error.localizedDescription)")
            }
        }
    }

    private func cancelInactivityNotification() {
        center.removePendingNotificationRequests(withIdentifiers: [inactivityIdentifier])
    }

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
