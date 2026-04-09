//
//  OnboardingView.swift
//  Mentorio
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage("userName") var userName: String = ""
    @State private var nameInput: String = ""
    @FocusState private var nameFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()
                
                VStack(spacing: 16) {
                    Text("Mentorio")
                        .font(.largeTitle.weight(.bold))
                        .fontDesign(.serif)
                        .foregroundStyle(MentorioColor.charcoal)
                    
                    Text("Умный журнал и когнитивное зеркало")
                        .font(.title3)
                        .fontDesign(.serif)
                        .foregroundStyle(MentorioColor.charcoal.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
                
                VStack(spacing: 24) {
                    TextField("Как к тебе обращаться?", text: $nameInput)
                        .font(.title3)
                        .fontDesign(.serif)
                        .foregroundStyle(MentorioColor.charcoal)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(white: 0.97))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(MentorioColor.charcoal.opacity(0.1), lineWidth: 1)
                        )
                        .focused($nameFieldFocused)
                    
                    Button {
                        let trimmedName = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedName.isEmpty {
                            userName = trimmedName
                        }
                    } label: {
                        Text("Начать")
                            .font(.title3.weight(.medium))
                            .fontDesign(.serif)
                            .foregroundStyle(nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? MentorioColor.charcoal.opacity(0.4) : MentorioColor.charcoal.opacity(0.9))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color(white: 0.94) : MentorioColor.charcoal.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(MentorioColor.charcoal.opacity(0.12), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 24)
                
                Spacer()
                Spacer()
            }
            .padding(.horizontal, 32)
            .background(MentorioColor.paper)
            .navigationBarHidden(true)
        }
        .onAppear {
            nameFieldFocused = true
        }
    }
}

#Preview {
    OnboardingView()
}
