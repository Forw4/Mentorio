//
//  ContentView.swift
//  Mentorio
//
//  Created by Nick Dobr on 03.04.2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    private enum AppState {
        case braindump
        case focus
        case choices
        case action
    }

    @State private var currentState: AppState = .braindump
    @State private var braindumpText: String = ""
    @State private var selectedChoice: String? = nil
    @State private var highlightText: String = ""
    @State private var insightText: String = ""

    var body: some View {
        Group {
            switch currentState {
            case .braindump:
                BraindumpView(
                    text: $braindumpText,
                    onContinue: {
                        currentState = .focus
                    }
                )

            case .focus:
                FocusView(
                    braindumpText: braindumpText,
                    onChoiceSelected: { choice, highlight, insight in
                        selectedChoice = choice
                        highlightText = highlight
                        insightText = insight
                        currentState = .action
                    },
                    onBack: {
                        currentState = .braindump
                    }
                )

            case .choices:
                PlaceholderView(title: "Экран Выбора") {
                    currentState = .braindump
                }

            case .action:
                ActionView(
                    braindumpText: braindumpText,
                    highlight: highlightText,
                    insight: insightText,
                    choice: selectedChoice ?? "",
                    onBack: {
                        currentState = .braindump
                    }
                )
            }
        }
    }
}

private struct BraindumpView: View {
    @Binding var text: String
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Что сейчас давит?")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.top, 24)

            ZStack(alignment: .topLeading) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Что сейчас давит? Пиши всё как есть, без структуры...")
                        .foregroundColor(.secondary)
                        .padding(16)
                }

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(MentorioColor.surface)
                    .foregroundStyle(MentorioColor.textPrimary)
                    .cornerRadius(14)
                    .frame(minHeight: 240)
            }
            .padding(.horizontal, 16)

            Spacer()

            Button(action: onContinue) {
                Text("Посмотреть глубже")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? MentorioColor.stroke : MentorioColor.accent)
                    .cornerRadius(16)
                    .padding(.horizontal, 16)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.bottom, 24)
        }
    }
}

private struct FocusView: View {
    let braindumpText: String
    let onChoiceSelected: (String, String, String) -> Void
    let onBack: () -> Void

    @State private var isLoading = true
    @State private var response: FocusResponse? = nil
    @State private var rawResponseDebug: String? = nil
    @State private var errorMessage: String? = nil
    @State private var didLoad = false
    @State private var userAnswer: String = ""

    var body: some View {
        VStack(spacing: 16) {
            if isLoading {
                Spacer()
                ProgressView("Ищем самую важную нить...")
                    .progressViewStyle(CircularProgressViewStyle())
                Spacer()
            } else if let response {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // DEBUG: Show raw response if all fields are nil
                        if response.topics == nil && response.highlight == nil && response.insight == nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("СЫРОЙ ОТВЕТ API:")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.secondary)
                                if let rawDebug = rawResponseDebug {
                                    Text(rawDebug)
                                        .font(.caption.monospaced())
                                        .foregroundColor(.secondary)
                                        .padding(8)
                                        .background(MentorioColor.surface)
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                        }

                        // If topics exist, show topic selection
                        if let topics = response.topics, !topics.isEmpty {
                            Text("О чем поговорим сейчас?")
                                .font(.headline.weight(.bold))
                                .padding(.bottom, 8)

                            VStack(spacing: 12) {
                                ForEach(topics, id: \.self) { topic in
                                    Button(action: {
                                        loadFocusResponse(selectedTopic: topic)
                                    }) {
                                        Text(topic)
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .background(MentorioColor.accent)
                                            .foregroundColor(.white)
                                            .cornerRadius(14)
                                    }
                                }
                            }
                        }
                        // If highlight and insight exist, show standard view
                        else if let highlight = response.highlight, let insight = response.insight {
                            Text("Суть")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)

                            Text(highlight)
                                .font(.title2.weight(.bold))
                                .fixedSize(horizontal: false, vertical: true)

                            Text(insight)
                                .font(.body)
                                .foregroundColor(.primary)

                            // If question exists, show question form
                            if let question = response.question {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(question)
                                        .font(.body.weight(.semibold))
                                        .foregroundColor(.primary)

                                    TextField("Твой ответ...", text: $userAnswer)
                                        .padding(12)
                                        .background(MentorioColor.surface)
                                        .cornerRadius(12)
                                }
                                .padding(.top, 12)

                            // If choices exist, show choice buttons
                            } else if let choices = response.choices, !choices.isEmpty {
                                VStack(spacing: 12) {
                                    ForEach(choices, id: \.self) { choice in
                                        Button(action: {
                                            onChoiceSelected(choice, highlight, insight)
                                        }) {
                                            Text(choice)
                                                .frame(maxWidth: .infinity)
                                                .padding()
                                                .background(MentorioColor.accent)
                                                .foregroundColor(.white)
                                                .cornerRadius(14)
                                        }
                                    }
                                }
                                .padding(.top, 12)
                            }
                        }
                    }
                    .padding(20)
                }
            } else if let errorMessage {
                Spacer()
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.red)
                    .padding()
                Button("Назад") {
                    onBack()
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            } else {
                Spacer()
                Text("Данные не загружены")
                Spacer()
            }

            if !isLoading {
                // Show "Ответить" button if we have a question with an answer
                if let response = response, let _ = response.highlight, let _ = response.insight, response.question != nil {
                    Button("Ответить") {
                        submitAnswer()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 16)
                    .disabled(userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Button("Назад") {
                    onBack()
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            if !didLoad {
                didLoad = true
                loadFocusResponse()
            }
        }
    }

    private func loadFocusResponse(selectedTopic: String? = nil, userAnswer: String? = nil) {
        Task {
            isLoading = true
            errorMessage = nil
            do {
                response = try await MentorioAIService.getCoreHighlightChoices(
                    for: braindumpText,
                    selectedTopic: selectedTopic,
                    userAnswer: userAnswer
                )
                
                // Store raw response for debugging
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let jsonData = try? encoder.encode(response),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    rawResponseDebug = jsonString
                } else {
                    rawResponseDebug = "Не удалось сериализовать response"
                }
                
                // Check if response is empty
                if response?.topics == nil && 
                   response?.highlight == nil && 
                   response?.insight == nil {
                    errorMessage = "ИИ вернул пустой ответ. Попробуй ещё раз."
                }
            } catch {
                errorMessage = "Ошибка подключения: \(error.localizedDescription)"
                print("🚨 ОШИБКА В FOCUS VIEW: \(error)")
            }
            isLoading = false
        }
    }

    private func submitAnswer() {
        let answer = userAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        self.userAnswer = ""
        loadFocusResponse(userAnswer: answer)
    }
}

private struct ActionView: View {
    let braindumpText: String
    let highlight: String
    let insight: String
    let choice: String
    let onBack: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var isLoading = true
    @State private var actionText: String? = nil
    @State private var errorMessage: String? = nil
    @State private var didLoad = false

    var body: some View {
        VStack(spacing: 16) {
            if isLoading {
                Spacer()
                ProgressView("Генерируем действие...")
                Spacer()
            } else if let actionText {
                ScrollView {
                    VStack(spacing: 20) {
                        Text("Один шаг")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        Text(actionText)
                            .font(.title2.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 40)
                }
            } else if let errorMessage {
                Spacer()
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.red)
                    .padding()
                Spacer()
            } else {
                Spacer()
                Text("Не удалось создать действие")
                Spacer()
            }

            if let actionText {
                Button("Очистить голову") {
                    saveSession(action: actionText)
                    onBack()
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 16)
            }

            Button("Назад") {
                onBack()
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .onAppear {
            if !didLoad {
                didLoad = true
                loadAction()
            }
        }
    }

    private func loadAction() {
        Task {
            isLoading = true
            errorMessage = nil
            do {
                actionText = try await MentorioAIService.getOneAction(
                    for: choice,
                    braindump: braindumpText,
                    highlight: highlight,
                    insight: insight
                )
            } catch {
                print("🚨 ОШИБКА В ACTION: \(error)")
                errorMessage = "Не удалось получить ответ. Попробуй ещё раз."
            }
            isLoading = false
        }
    }

    private func saveSession(action: String) {
        let session = MentorioSession(
            braindumpText: braindumpText,
            coreHighlight: highlight,
            choiceOptions: [choice],
            selectedChoiceIndex: 0,
            oneAction: action,
            isCleared: true
        )
        modelContext.insert(session)
    }
}

private struct PlaceholderView: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(title)
                .font(.title)
                .fontWeight(.semibold)
            Button("Назад") {
                onBack()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
