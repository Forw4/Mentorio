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
                        .foregroundStyle(MentorioColor.claudeOrange)
                    
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
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(MentorioColor.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(MentorioColor.stroke, lineWidth: 1)
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
                            .foregroundStyle(nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.primary : MentorioColor.textOnAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? MentorioColor.surface : MentorioColor.claudeOrange)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(MentorioColor.stroke, lineWidth: 1)
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
