//
//  SettingsView.swift
//  Mentorio
//

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var viewModel: MentorioViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userName") var userName: String = ""
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome: Bool = false
    @AppStorage("customOpenRouterKey") private var customOpenRouterKey: String = ""
    @FocusState private var nameFieldFocused: Bool

    @State private var notifStatus: UNAuthorizationStatus = .notDetermined

    private let bg      = Color(red: 0.051, green: 0.051, blue: 0.051)
    private let cardFill  = Color.white.opacity(0.05)
    private let cardStroke = Color.white.opacity(0.08)
    private let textPrimary = Color.white.opacity(0.9)
    private let accent  = Color(red: 1.0, green: 0.671, blue: 0.569)

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("Настройки")
                                .font(.largeTitle.bold())
                                .fontDesign(.serif)
                                .foregroundStyle(textPrimary)
                            Spacer()
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(Color.white.opacity(0.2))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 6)

                        profileSection
                        notificationsSection
                        apiSection
                        dataSection
                        debugSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            notifStatus = await NotificationManager.shared.fetchAuthorizationStatus()
        }
    }

    // MARK: - Profile

    private var profileSection: some View {
        settingsCard {
            sectionLabel("Профиль")

            TextField("Как к тебе обращаться?", text: $userName, axis: .vertical)
                .lineLimit(1...2)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(false)
                .font(.body)
                .foregroundStyle(textPrimary)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(cardStroke, lineWidth: 1)
                        )
                )
                .focused($nameFieldFocused)
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        settingsCard {
            sectionLabel("Уведомления")

            HStack(spacing: 12) {
                Image(systemName: notifIconName)
                    .foregroundStyle(notifStatus == .authorized ? accent : Color.white.opacity(0.45))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(notifStatusLabel)
                        .font(.body.weight(.medium))
                        .foregroundStyle(textPrimary)
                    Text(notifStatusSubtitle)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.5))
                }

                Spacer()

                if notifStatus == .notDetermined {
                    Button("Включить") {
                        Task {
                            NotificationManager.shared.requestPermissionIfNeeded()
                            try? await Task.sleep(for: .seconds(1))
                            notifStatus = await NotificationManager.shared.fetchAuthorizationStatus()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(accent)
                    .clipShape(Capsule())
                } else if notifStatus == .denied {
                    Button("Открыть настройки") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - API

    private var apiSection: some View {
        settingsCard {
            sectionLabel("OpenRouter API Ключ")

            Text("Оставь пустым, чтобы использовать встроенный ключ Mentorio.")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.bottom, 4)

            SecureField("sk-or-v1-...", text: $customOpenRouterKey)
                .font(.body)
                .foregroundStyle(textPrimary)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(cardStroke, lineWidth: 1)
                        )
                )
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        settingsCard {
            sectionLabel("Данные")

            NavigationLink {
                RecentlyDeletedView()
            } label: {
                settingsRow(title: "Недавно удаленные", systemImage: "trash")
            }
            .buttonStyle(.plain)

            NavigationLink {
                PrivacyView()
            } label: {
                settingsRow(title: "Приватность", systemImage: "lock.shield")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Debug

    private var debugSection: some View {
        settingsCard {
            sectionLabel("Отладка")

            NavigationLink {
                DiagnosticsView()
            } label: {
                settingsRow(title: "Диагностика", systemImage: "waveform.path.ecg")
            }
            .buttonStyle(.plain)

            Button {
                hasSeenWelcome = false
            } label: {
                settingsRow(title: "Сбросить приветствие", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(cardStroke, lineWidth: 1)
                )
        )
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .fontDesign(.serif)
            .foregroundStyle(textPrimary.opacity(0.8))
    }

    private func settingsRow(title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(accent)
                .frame(width: 24)

            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(textPrimary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.3))
        }
        .padding(.vertical, 6)
    }

    // MARK: - Notification helpers

    private var notifIconName: String {
        switch notifStatus {
        case .authorized, .provisional: return "bell.fill"
        case .denied: return "bell.slash"
        default: return "bell"
        }
    }

    private var notifStatusLabel: String {
        switch notifStatus {
        case .authorized, .provisional: return "Уведомления включены"
        case .denied: return "Уведомления отключены"
        default: return "Уведомления не настроены"
        }
    }

    private var notifStatusSubtitle: String {
        switch notifStatus {
        case .authorized, .provisional: return "Напомним вернуться через 3 дня тишины"
        case .denied: return "Включи в системных настройках iOS"
        default: return "Разреши, чтобы мы напоминали о возвращении"
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(makePreviewViewModel())
}
