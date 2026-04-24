//
//  SettingsView.swift
//  Mentorio
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("userName") var userName: String = ""
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome: Bool = false
    @FocusState private var nameFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Профиль") {
                    TextField("Как к тебе обращаться?", text: $userName)
                        .font(MentorioType.body)
                        .focused($nameFieldFocused)
                        .textFieldStyle(.plain)
                }
                
                Section("Данные") {
                    NavigationLink {
                        RecentlyDeletedView()
                    } label: {
                        Label("Недавно удаленные", systemImage: "trash")
                            .foregroundStyle(MentorioColor.textPrimary, MentorioColor.accent)
                    }

                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label("Приватность", systemImage: "lock.shield")
                            .foregroundStyle(MentorioColor.textPrimary, MentorioColor.accent)
                    }
                }

                Section("Отладка") {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Диагностика", systemImage: "waveform.path.ecg")
                            .foregroundStyle(MentorioColor.textPrimary, MentorioColor.accent)
                    }

                    Button("Сбросить приветствие") {
                        hasSeenWelcome = false
                    }
                    .foregroundStyle(MentorioColor.textPrimary, MentorioColor.accent)
                }
            }
            .mentorioSettingsChrome(title: "Настройки")
        }
        .scrollContentBackground(.hidden)
        .background(MentorioColor.background)
    }
}

#Preview {
    SettingsView()
    .environmentObject(makePreviewViewModel())
}
