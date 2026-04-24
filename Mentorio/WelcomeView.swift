//
//  WelcomeView.swift
//  Mentorio
//

import SwiftUI

struct WelcomeView: View {
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome: Bool = false
    @State private var name: String = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 12)

                Text("Mentorio")
                    .font(.largeTitle.weight(.bold))
                    .fontDesign(.serif)
                    .foregroundStyle(MentorioColor.accent)

                VStack(alignment: .leading, spacing: 12) {
                    Text("• Это не бесконечный чат-бот для нытья.")
                    Text("• Ты получаешь одну физическую задачу на 10–15 минут.")
                    Text("• Каждый шаг заканчивается артефактом: заметкой, сообщением или файлом.")
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(MentorioColor.charcoal)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Я не буду тебя жалеть. Я покажу, где ты врешь себе, и помогу сделать один конкретный шаг.")
                    .font(.body)
                    .foregroundStyle(MentorioColor.charcoal.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Как тебя зовут?")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MentorioColor.charcoal)

                    TextField("Имя (необязательно)", text: $name)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(MentorioColor.surface)
                        .cornerRadius(12)
                        .focused($nameFieldFocused)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 16)

                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        userName = trimmed
                    }
                    hasSeenWelcome = true
                } label: {
                    Text("Начать")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(MentorioColor.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(MentorioColor.accent)
                        .cornerRadius(14)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .background(MentorioColor.paper.ignoresSafeArea())
        .onAppear {
            nameFieldFocused = true
        }
    }
}

#Preview {
    WelcomeView()
}
