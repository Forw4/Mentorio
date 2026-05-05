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
    @AppStorage("customAIBaseURL") private var customAIBaseURL: String = ""
    @AppStorage("customAIKey") private var customAIKey: String = ""
    @AppStorage("customAIModel") private var customAIModel: String = ""
    @AppStorage("isContinuationEnabled") private var isContinuationEnabled: Bool = false
    @FocusState private var nameFieldFocused: Bool

    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                MentorioTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("Настройки")
                                .font(.largeTitle.bold())
                                .fontDesign(.serif)
                                .foregroundStyle(MentorioTheme.primaryText)
                            Spacer()
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(MentorioTheme.secondaryText.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 6)

                        profileSection
                        appearanceSection
                        notificationsSection
                        apiSection
                        customAISection
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
                .foregroundStyle(MentorioTheme.primaryText)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MentorioTheme.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(MentorioTheme.stroke, lineWidth: 1)
                        )
                )
                .focused($nameFieldFocused)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        settingsCard {
            sectionLabel("Оформление")

            Picker("Тема", selection: $appTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.rawValue).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        settingsCard {
            sectionLabel("Уведомления")

            HStack(spacing: 12) {
                Image(systemName: notifIconName)
                    .foregroundStyle(notifStatus == .authorized ? MentorioTheme.accent : MentorioTheme.secondaryText)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(notifStatusLabel)
                        .font(.body.weight(.medium))
                        .foregroundStyle(MentorioTheme.primaryText)
                    Text(notifStatusSubtitle)
                        .font(.caption)
                        .foregroundStyle(MentorioTheme.secondaryText)
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
                    .background(MentorioTheme.accent)
                    .clipShape(Capsule())
                } else if notifStatus == .denied {
                    Button("Открыть настройки") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MentorioTheme.accent)
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
                .foregroundStyle(MentorioTheme.secondaryText)
                .padding(.bottom, 4)

            SecureField("sk-or-v1-...", text: $customOpenRouterKey)
                .font(.body)
                .foregroundStyle(MentorioTheme.primaryText)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MentorioTheme.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(MentorioTheme.stroke, lineWidth: 1)
                        )
                )
        }
    }

    // MARK: - Custom AI

    private var customAISection: some View {
        settingsCard {
            sectionLabel("Кастомный AI (Ollama и др.)")

            Text("Опционально. Если все поля заполнены, Mentorio будет использовать этот сервер вместо OpenRouter.")
                .font(.caption)
                .foregroundStyle(MentorioTheme.secondaryText)
                .padding(.bottom, 4)

            TextField("Base URL, например http://localhost:11434", text: $customAIBaseURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .disableAutocorrection(true)
                .font(.body)
                .foregroundStyle(MentorioTheme.primaryText)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MentorioTheme.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(MentorioTheme.stroke, lineWidth: 1)
                        )
                )

            TextField("API key (для Ollama можно любое слово)", text: $customAIKey)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.body)
                .foregroundStyle(MentorioTheme.primaryText)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MentorioTheme.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(MentorioTheme.stroke, lineWidth: 1)
                        )
                )

            TextField("Модель, например llama3.1", text: $customAIModel)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.body)
                .foregroundStyle(MentorioTheme.primaryText)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MentorioTheme.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(MentorioTheme.stroke, lineWidth: 1)
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

    private var debugSection: some View {
        settingsCard {
            sectionLabel("Отладка")

            Toggle(isOn: $isContinuationEnabled) {
                HStack(spacing: 12) {
                    Image(systemName: "flask")
                        .foregroundStyle(MentorioTheme.accent)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Эксперимент: ещё один шаг")
                            .font(.body.weight(.medium))
                            .foregroundStyle(MentorioTheme.primaryText)
                        Text("Экспериментальная кнопка продолжения задачи")
                            .font(.caption)
                            .foregroundStyle(MentorioTheme.secondaryText)
                    }
                }
            }
            .tint(MentorioTheme.accent)
            .padding(.vertical, 6)

            Divider()
                .background(MentorioTheme.stroke)

            NavigationLink {
                DiagnosticsView()
            } label: {
                settingsRow(title: "Диагностика", systemImage: "waveform.path.ecg")
            }
            .buttonStyle(.plain)

            Button {
                showResetConfirm = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash.fill")
                        .foregroundStyle(Color.red.opacity(0.8))
                        .frame(width: 24)
                    Text("Сбросить всё")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.red.opacity(0.9))
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .alert("Сбросить всё?", isPresented: $showResetConfirm) {
            Button("Удалить всё", role: .destructive) {
                viewModel.deleteAllData()
                hasSeenWelcome = false
                customOpenRouterKey = ""
                customAIBaseURL = ""
                customAIKey = ""
                customAIModel = ""
                isContinuationEnabled = false
                userName = ""
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Будут удалены все брейндампы, заметки и победы. Это действие нельзя отменить.")
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
                .fill(MentorioTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(MentorioTheme.stroke, lineWidth: 1)
                )
        )
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .fontDesign(.serif)
            .foregroundStyle(MentorioTheme.secondaryText)
    }

    private func settingsRow(title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(MentorioTheme.accent)
                .frame(width: 24)

            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(MentorioTheme.primaryText)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MentorioTheme.secondaryText)
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
