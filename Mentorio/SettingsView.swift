//
//  SettingsView.swift
//  Mentorio
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("userName") var userName: String = ""
    @Environment(\.dismiss) private var dismiss
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
                    }

                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label("Приватность", systemImage: "lock.shield")
                    }
                }

                Section("Отладка") {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Диагностика", systemImage: "waveform.path.ecg")
                    }
                }
            }
        }
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .tint(MentorioColor.accent)
        .toolbarBackground(MentorioColor.background, for: .navigationBar)
        .scrollContentBackground(.hidden)
        .background(MentorioColor.background)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Готово") {
                    dismiss()
                }
                .foregroundStyle(MentorioColor.charcoal.opacity(0.7))
            }
        }
        .onAppear {
            nameFieldFocused = true
        }
    }
}

#Preview {
    SettingsView()
    .environmentObject(makePreviewViewModel())
}
