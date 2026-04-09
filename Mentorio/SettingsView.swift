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
                        .focused($nameFieldFocused)
                        .textFieldStyle(.plain)
                }
                
                Section("Данные") {
                    NavigationLink {
                        RecentlyDeletedView()
                    } label: {
                        Label("Недавно удаленные", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(MentorioColor.paper, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
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
}
