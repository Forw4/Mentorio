//
//  PrivacyView.swift
//  Mentorio
//

import SwiftUI

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Твой хаос остается у тебя. История хранится только на твоем устройстве.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(MentorioColor.charcoal)

                Text("Mentorio не отправляет историю брайндампов и историю действий на внешние серверы хранения.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .mentorioSettingsChrome(title: "Приватность")
        .background(MentorioColor.paper)
    }
}

#Preview {
    NavigationStack {
        PrivacyView()
    }
}
