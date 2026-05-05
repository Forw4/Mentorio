import SwiftUI

struct EntryOverlayView: View {
    @ObservedObject var viewModel: MentorioViewModel
    @Binding var isPresented: Bool
    private let existingNote: BraindumpNote?
    private let continuationContext: ContinuationContext?

    init(
        viewModel: MentorioViewModel,
        isPresented: Binding<Bool>,
        existingNote: BraindumpNote? = nil,
        continuationContext: ContinuationContext? = nil
    ) {
        self.viewModel = viewModel
        self._isPresented = isPresented
        self.existingNote = existingNote
        self.continuationContext = continuationContext
    }

    @State private var entryState: EntryState = .braindump
    @State private var inputText = ""
    @State private var answerText = ""
    @State private var braindumpText = ""
    @State private var analyzingMessage = "Собираю фокус..."
    @State private var errorMessage: String? = nil
    
    @State private var selectedTopic: String? = nil
    @State private var selectedChoice: String? = nil
    @State private var highlight: String = ""
    @State private var insight: String = ""
    
    // clarifyingAttempts is NOT kept as @State — the note model is the source of truth.
    // Read from note in runFocusAnalysis; write via updateDraft in submitAnswer.

    @State private var pendingDraftID: UUID? = nil
    @State private var choiceOptions: [String] = []
    @State private var activeTask: Task<Void, Never>? = nil
    @State private var didLoadExisting = false

    @FocusState private var focusedField: FocusField?

    private enum FocusField {
        case braindump
        case clarification
    }

    private enum ClarificationKind: Equatable {
        case question
        case topic
        case choice
    }

    private enum EntryState: Equatable {
        case braindump
        case analyzing
        case clarification(question: String, kind: ClarificationKind, options: [String])
        case oneAction(action: String)
    }

    /// Single source of truth for system navigation prompt strings (#13).
    /// These appear in chat history, duplicate-detection, and context sanitization.
    private enum DialogLabel {
        static let pickTopic  = "Выбери фокус"
        static let pickTactic = "Выбери тактику"
        static let all: Set<String> = [pickTopic, pickTactic]
    }

    private struct ChatMessage: Identifiable, Equatable {
        let id: UUID
        let isAI: Bool
        let text: String

        init(id: UUID = UUID(), isAI: Bool, text: String) {
            self.id = id
            self.isAI = isAI
            self.text = text
        }
    }

    @State private var chatHistory: [ChatMessage] = []



    var body: some View {
        if #available(iOS 16.4, *) {
            content.presentationBackground(.clear)
        } else {
            content
        }
    }

    private var content: some View {
        VStack {
            Spacer(minLength: 0)
            dialogCard
                .frame(maxWidth: 520)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            backgroundLayer
                .onTapGesture {
                    focusedField = nil
                }
        )
        .onAppear {
            if !didLoadExisting {
                didLoadExisting = true
                if let existingNote {
                    hydrateFromExisting(existingNote)
                } else if let ctx = continuationContext {
                    startContinuation(ctx)
                }
            }
            updateFocusForState()
        }
        .onDisappear {
            activeTask?.cancel()
        }
        .animation(.spring(response: 0.46, dampingFraction: 0.9), value: entryState)
    }

    private var backgroundLayer: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    MentorioTheme.accent.opacity(0.22),
                    Color.white.opacity(0.04),
                    Color.black.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [MentorioTheme.accent.opacity(0.18), Color.clear],
                center: .top,
                startRadius: 40,
                endRadius: 320
            )
            .ignoresSafeArea()
        }
    }

    private var dialogCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // 1. Приветствие или исходный текст пользователя
                        if entryState == .braindump {
                            bubble(text: "Коротко. Что мешает прямо сейчас?", role: .mentor)
                        } else if !braindumpText.isEmpty {
                            bubble(text: braindumpText, role: .user)
                        }

                        // 2. Единая история чата без дублей
                        ForEach(chatHistory) { message in
                            bubble(text: message.text, role: message.isAI ? .mentor : .user)
                        }

                        // 3. Индикатор загрузки (когда ИИ думает)
                        if entryState == .analyzing {
                            bubble(text: analyzingMessage, role: .mentor)
                        }

                        // 4. Финальное действие (One Action)
                        if case .oneAction(let action) = entryState {
                            bubble(text: "Твое действие на сейчас:", role: .mentor)
                            bubble(text: action, role: .mentor, emphasis: true)
                        }

                        // 5. Ошибки
                        if let errorMessage {
                            bubble(text: errorMessage, role: .error)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
                    .id("BottomSpacer")
                }
                // Instead of a strict 320, we allow it to shrink if the keyboard pushes it on small screens
                .frame(minHeight: 150, maxHeight: 320)
                .scrollIndicators(.hidden)
                .onTapGesture {
                    focusedField = nil
                }
                .onChange(of: chatHistory.count) {
                    withAnimation { proxy.scrollTo("BottomSpacer", anchor: .bottom) }
                }
                .onChange(of: entryState) {
                    withAnimation { proxy.scrollTo("BottomSpacer", anchor: .bottom) }
                }
            }

            controlsSection
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(MentorioTheme.stroke, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 16)
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mentorio")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MentorioTheme.accent)

                Text(titleText)
                    .font(.title3.weight(.semibold))
                    .fontDesign(.serif)
                    .foregroundStyle(MentorioTheme.primaryText)
            }

            Spacer()

            Button {
                closeOverlay()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MentorioTheme.primaryText.opacity(0.8))
                    .frame(width: 30, height: 30)
                    .background(MentorioTheme.stroke)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var controlsSection: some View {
        VStack(spacing: 12) {
            switch entryState {
            case .braindump:
                inputField(
                    placeholder: "Хаос мыслей...",
                    text: $inputText,
                    focus: .braindump,
                    lineLimit: 1...10,
                    submitLabel: "Отправить",
                    action: submitBraindump
                )
            case .analyzing:
                ProgressView()
                    .tint(MentorioTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            case .clarification(_, let kind, let options):
                if kind == .question {
                    inputField(
                        placeholder: "Короткий ответ.",
                        text: $answerText,
                        focus: .clarification,
                        submitLabel: "Ответить",
                        action: submitAnswer
                    )
                } else {
                    optionList(kind: kind, options: options)
                }
            case .oneAction(let action):
                Button {
                    acceptAction(action)
                } label: {
                    Text("Сделать")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(MentorioTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func inputField(
        placeholder: String,
        text: Binding<String>,
        focus: FocusField,
        lineLimit: ClosedRange<Int> = 1...10,
        submitLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        let isTextEmpty = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        return HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(lineLimit)
                .textInputAutocapitalization(.sentences)
                .disableAutocorrection(false)
                .foregroundStyle(MentorioTheme.primaryText)
                .focused($focusedField, equals: focus)
                .padding(.vertical, 10)
                .padding(.leading, 14)

            Button(action: action) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isTextEmpty ? MentorioTheme.primaryText.opacity(0.3) : .black)
                    .frame(width: 32, height: 32)
                    .background(isTextEmpty ? MentorioTheme.primaryText.opacity(0.1) : MentorioTheme.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isTextEmpty)
            .padding(.trailing, 6)
            .padding(.bottom, 6)
        }
        .background(inputFieldBackground)
    }

    private func optionList(kind: ClarificationKind, options: [String]) -> some View {
        VStack(spacing: 10) {
            ForEach(options, id: \.self) { option in
                Button {
                    handleOption(option, kind: kind)
                } label: {
                    Text(option)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(MentorioTheme.accent.opacity(0.5), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var inputFieldBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(MentorioTheme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(MentorioTheme.stroke, lineWidth: 1)
            )
    }

    private enum BubbleRole {
        case mentor
        case user
        case error
    }

    private func bubble(text: String, role: BubbleRole, emphasis: Bool = false) -> some View {
        let fill: Color
        let stroke: Color

        switch role {
        case .mentor:
            fill = MentorioTheme.card
            stroke = MentorioTheme.stroke
        case .user:
            fill = Color.mentorioPeach.opacity(0.22)
            stroke = Color.mentorioPeach.opacity(0.6)
        case .error:
            fill = Color.red.opacity(0.18)
            stroke = Color.red.opacity(0.55)
        }

        return HStack {
            if role == .user {
                Spacer(minLength: 24)
            }

            Text(text)
                .font(emphasis ? .title3.weight(.semibold) : .body)
                .foregroundStyle(MentorioTheme.primaryText)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(fill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(stroke, lineWidth: 1)
                        )
                )

            if role != .user {
                Spacer(minLength: 24)
            }
        }
    }

    private var titleText: String {
        switch entryState {
        case .braindump: return "В чем затык?"
        case .analyzing: return "Даю фокус"
        case .clarification: return "Уточняю"
        case .oneAction: return "Одно действие"
        }
    }

    private func updateFocusForState() {
        switch entryState {
        case .braindump:
            focusedField = .braindump
        case .clarification(_, let kind, _):
            focusedField = kind == .question ? .clarification : nil
        case .analyzing, .oneAction:
            focusedField = nil
        }
    }

    // Умное добавление без дубликатов
    private func appendChat(isAI: Bool, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // System navigation prompts ("Выбери фокус", "Выбери тактику") must never
        // be added twice — check the ENTIRE history, not just the last message.
        let isSystemPrompt = DialogLabel.all.contains(trimmed)
        if isSystemPrompt, chatHistory.contains(where: { $0.isAI && $0.text == trimmed }) {
            return
        }
        
        // For regular messages, block only consecutive duplicates
        if let last = chatHistory.last, last.isAI == isAI, last.text == trimmed {
            return
        }
        chatHistory.append(ChatMessage(isAI: isAI, text: trimmed))
    }

    private func activeMentorQuestionText() -> String? {
        if case .clarification(let question, _, _) = entryState {
            return question
        }
        return nil
    }

    private func hydrateFromExisting(_ note: BraindumpNote) {
        pendingDraftID = note.id
        braindumpText = note.text
        // inputText intentionally NOT set: it is the pre-submission TextField binding.
        // When reopening an existing note the braindump was already submitted;
        // braindumpText is the source of truth, inputText must stay empty.
        chatHistory = viewModel.decodeChatHistory(note.chatHistoryData).map { ChatMessage(isAI: $0.isAI, text: $0.text) }
        selectedTopic = note.selectedTopic
        selectedChoice = note.selectedChoice
        // clarifyingAttempts is now read from the note in runFocusAnalysis directly (#5)
        highlight = note.storedHighlight ?? ""
        insight = note.storedInsight ?? ""
        answerText = note.userAnswer ?? ""
        errorMessage = nil
        choiceOptions = []
        analyzingMessage = "Собираю фокус..."

        // Only restore oneAction UI if the session is genuinely finalized:
        // the note must be in .executing state OR status == .active.
        // storedAction alone is not enough — it may be a temp value from a cancelled session.
        let isFinalized: Bool
        if case .executing = note.state {
            isFinalized = true
        } else {
            isFinalized = note.status == .active
        }
        if isFinalized, let storedAction = note.storedAction,
           !storedAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            entryState = .oneAction(action: storedAction)
            return
        }

        // If there is a pending session saved, prefer restoring its pending fields.
        // Priority: choices > topics > plain question.
        // Rationale: if pendingChoicesJSON is set, the user is already past topic selection
        // regardless of what pendingTopicsJSON contains (it may be stale from a previous step).
        if let pq = note.pendingQuestion, !pq.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let pcj = note.pendingChoicesJSON,
               let data = pcj.data(using: .utf8),
               let pcs = try? JSONDecoder().decode([String].self, from: data),
               !pcs.isEmpty {
                // Choices take priority — user was at tactic selection
                choiceOptions = pcs
                entryState = .clarification(question: pq, kind: .choice, options: pcs)
            } else if let ptj = note.pendingTopicsJSON,
                      let data = ptj.data(using: .utf8),
                      let pts = try? JSONDecoder().decode([String].self, from: data),
                      !pts.isEmpty {
                entryState = .clarification(question: pq, kind: .topic, options: pts)
            } else {
                entryState = .clarification(question: pq, kind: .question, options: [])
            }
            return
        }
        
        if let pcj = note.pendingChoicesJSON, let data = pcj.data(using: .utf8), let pcs = try? JSONDecoder().decode([String].self, from: data), !pcs.isEmpty {
            choiceOptions = pcs
            entryState = .clarification(question: DialogLabel.pickTactic, kind: .choice, options: pcs)
            return
        }
        
        if let ptj = note.pendingTopicsJSON, let data = ptj.data(using: .utf8), let pts = try? JSONDecoder().decode([String].self, from: data), !pts.isEmpty {
            entryState = .clarification(question: DialogLabel.pickTopic, kind: .topic, options: pts)
            return
        }

        switch note.state {
        case .idle:
            entryState = .braindump
        case .analyzing:
            entryState = .analyzing
        case .needsTopic(let topics):
            let question = DialogLabel.pickTopic
            appendChat(isAI: true, text: question)
            entryState = .clarification(question: question, kind: .topic, options: topics)
        case .clarifying(let question):
            appendChat(isAI: true, text: question)
            entryState = .clarification(question: question, kind: .question, options: [])
        case .hasTactics(let choices, let stateHighlight, let stateInsight, _):
            if highlight.isEmpty { highlight = stateHighlight }
            if insight.isEmpty { insight = stateInsight }
            choiceOptions = choices
            let question = DialogLabel.pickTactic
            appendChat(isAI: true, text: question)
            entryState = .clarification(question: question, kind: .choice, options: choices)
        case .executing(let action):
            entryState = .oneAction(action: action)
        }
    }

    private func closeOverlay() {
        activeTask?.cancel()
        withAnimation(.easeInOut(duration: 0.22)) {
            isPresented = false
        }
    }

    private func startContinuation(_ ctx: ContinuationContext) {
        let firstMsg = "Шаг сделан: \(ctx.pastAction). Формирую следующий."

        let simulatedBraindump = "[Продолжение задачи: \(ctx.pastAction)]"
        ensureDraft(for: simulatedBraindump)
        braindumpText = simulatedBraindump

        appendChat(isAI: true, text: firstMsg)

        entryState = .analyzing
        updateDraft { $0.state = .analyzing }

        activeTask?.cancel()
        activeTask = Task {
            await runFocusAnalysis(contextText: simulatedBraindump, selectedTopic: nil, userAnswer: nil)
        }
    }

    private func submitBraindump() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        braindumpText = trimmed
        inputText = ""
        chatHistory = []
        ensureDraft(for: trimmed)
        // clarifyingAttempts resets in the note via updateDraft below (not local state)
        updateDraft { $0.clarifyingAttempts = 0 }
        selectedTopic = nil
        selectedChoice = nil
        highlight = ""
        insight = ""
        choiceOptions = []
        errorMessage = nil
        
        startFocusAnalysis(selectedTopic: nil, userAnswer: nil)
    }

    private func submitAnswer() {
        let trimmed = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        answerText = ""
        errorMessage = nil
        appendChat(isAI: false, text: trimmed)

        updateDraft { note in
            note.userAnswer = trimmed
            note.clarifyingAttempts += 1  // note is the single source of truth
        }
        if let pending = pendingDraftID {
            let currentQuestion = activeMentorQuestionText()
            viewModel.saveDraftSession(
                noteId: pending,
                chatHistory: chatHistory.map { (isAI: $0.isAI, text: $0.text) },
                pendingQuestion: currentQuestion,
                pendingChoices: nil,
                pendingTopics: nil
            )
        }
        startFocusAnalysis(selectedTopic: selectedTopic, userAnswer: trimmed)
    }

    private func handleOption(_ option: String, kind: ClarificationKind) {
        errorMessage = nil
        appendChat(isAI: false, text: option)

        switch kind {
        case .topic:
            selectedTopic = option
            updateDraft { $0.selectedTopic = option }
            if let pending = pendingDraftID {
                let currentQuestion = activeMentorQuestionText()
                viewModel.saveDraftSession(
                    noteId: pending,
                    chatHistory: chatHistory.map { (isAI: $0.isAI, text: $0.text) },
                    pendingQuestion: currentQuestion,
                    pendingChoices: nil,
                    pendingTopics: nil
                )
            }
            startFocusAnalysis(selectedTopic: option, userAnswer: nil)
        case .choice:
            selectedChoice = option
            updateDraft { note in
                note.selectedChoice = option
                if let index = choiceOptions.firstIndex(of: option) {
                    note.selectedChoiceIndex = index
                }
            }
            if let pending = pendingDraftID {
                let currentQuestion = activeMentorQuestionText()
                viewModel.saveDraftSession(
                    noteId: pending,
                    chatHistory: chatHistory.map { (isAI: $0.isAI, text: $0.text) },
                    pendingQuestion: currentQuestion,
                    pendingChoices: choiceOptions,
                    pendingTopics: nil
                )
            }
            generateOneAction(choice: option)
        case .question:
            break
        }
    }

    private func startFocusAnalysis(selectedTopic: String?, userAnswer: String?) {
        analyzingMessage = "Собираю фокус..."
        entryState = .analyzing
        updateDraft { $0.state = .analyzing }
        let contextText = conversationContextText()
        activeTask?.cancel()
        activeTask = Task {
            await runFocusAnalysis(contextText: contextText, selectedTopic: selectedTopic, userAnswer: userAnswer)
        }
    }

    private func runFocusAnalysis(contextText: String, selectedTopic: String?, userAnswer: String?) async {
        // Resolve current note fields — note is the single source of truth for
        // clarifyingAttempts, isFastTrack, and contextSummary.
        let clarifyingAttempts: Int
        let isFastTrack: Bool
        let contextSummary: String?
        if let id = pendingDraftID,
           let note = viewModel.notes.first(where: { $0.id == id }) {
            clarifyingAttempts = note.clarifyingAttempts
            isFastTrack = note.isFastTrack
            contextSummary = note.contextSummary
        } else {
            clarifyingAttempts = 0
            isFastTrack = false
            contextSummary = nil
        }

        do {
            let response = try await MentorioAIService.getCoreHighlightChoices(
                for: contextText,
                selectedTopic: selectedTopic,
                userAnswer: userAnswer,
                clarifyingAttempts: clarifyingAttempts,
                isFastTrack: isFastTrack,
                contextSummary: contextSummary,
                continuation: continuationContext
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                applyFocusResponse(response)
            }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                errorMessage = error.localizedDescription
                entryState = .braindump
                inputText = braindumpText
            }
        }
    }

    private func applyFocusResponse(_ response: FocusResponse) {
        if let h = response.highlight {
            highlight = h
            updateDraft { $0.storedHighlight = h }
        }
        if let i = response.insight {
            insight = i
            updateDraft { $0.storedInsight = i }
        }

        // HARD INVARIANT: if user already selected a topic, NEVER show topic
        // selection again regardless of what the AI returned.
        // LLMs cannot reliably enforce prompt-level rules — Swift is the gatekeeper.
        let topicsAllowed = selectedTopic == nil
        if topicsAllowed, let topics = response.topics, !topics.isEmpty {
            let question = DialogLabel.pickTopic
            appendChat(isAI: true, text: question)
            entryState = .clarification(question: question, kind: .topic, options: topics)
            updateDraft { note in
                note.state = .needsTopic(topics: topics)
            }
            if let pending = pendingDraftID {
                viewModel.saveDraftSession(
                    noteId: pending,
                    chatHistory: chatHistory.map { (isAI: $0.isAI, text: $0.text) },
                    pendingQuestion: question,
                    pendingChoices: nil,
                    pendingTopics: topics
                )
            }
            updateFocusForState()
            return
        }

        if let question = response.question, !question.isEmpty {
            appendChat(isAI: true, text: question)
            entryState = .clarification(question: question, kind: .question, options: [])
            updateDraft { note in
                note.state = .clarifying(question: question)
            }
            if let pending = pendingDraftID {
                viewModel.saveDraftSession(
                    noteId: pending,
                    chatHistory: chatHistory.map { (isAI: $0.isAI, text: $0.text) },
                    pendingQuestion: question,
                    pendingChoices: nil,
                    pendingTopics: nil
                )
            }
            updateFocusForState()
            return
        }

        if let choices = response.choices, !choices.isEmpty {
            let question = DialogLabel.pickTactic
            choiceOptions = choices
            appendChat(isAI: true, text: question)
            entryState = .clarification(question: question, kind: .choice, options: choices)
            updateDraft { note in
                note.state = .hasTactics(choices: choices, highlight: highlight, insight: insight, topics: response.topics)
            }
            if let pending = pendingDraftID {
                viewModel.saveDraftSession(
                    noteId: pending,
                    chatHistory: chatHistory.map { (isAI: $0.isAI, text: $0.text) },
                    pendingQuestion: question,
                    pendingChoices: choices,
                    pendingTopics: nil  // Always nil at choices stage — topics are stale and
                                       // would cause hydrateFromExisting to show topic picker
                )
            }
            updateFocusForState()
            return
        }

        errorMessage = "AI-сервис вернул пустой ответ"
        entryState = .braindump
        updateFocusForState()
    }

    private func generateOneAction(choice: String) {
        analyzingMessage = "Формирую действие..."
        entryState = .analyzing
        updateDraft { $0.state = .analyzing }
        let contextText = conversationContextText()
        activeTask?.cancel()
        activeTask = Task {
            await runOneAction(choice: choice, contextText: contextText)
        }
    }

    private func runOneAction(choice: String, contextText: String) async {
        do {
            let action = try await MentorioAIService.getOneAction(
                for: choice,
                braindump: contextText,
                highlight: highlight,
                insight: insight,
                selectedTopic: selectedTopic
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                entryState = .oneAction(action: action)
                // Do NOT write storedAction to the note yet.
                // storedAction/finalAction are only persisted in acceptAction(),
                // which is the explicit user-triggered promotion to .active.
                // Writing here would cause hydrateFromExisting to show OneAction UI
                // on next open, even if the user never tapped "Accept".
                updateDraft { note in
                    note.state = .hasTactics(choices: choiceOptions, highlight: highlight, insight: insight, topics: nil)
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                errorMessage = error.localizedDescription
                entryState = .clarification(
                    question: DialogLabel.pickTactic,
                    kind: .choice,
                    options: choiceOptions
                )
            }
        }
    }

    private func acceptAction(_ action: String) {
        let trimmedAction = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAction.isEmpty else { return }

        if pendingDraftID == nil {
            let baseText = braindumpText.trimmingCharacters(in: .whitespacesAndNewlines)
            viewModel.addNote(baseText.isEmpty ? trimmedAction : baseText, source: "entry_overlay", status: .draft)
            pendingDraftID = viewModel.selectedNoteId
        }

        guard let pendingDraftID,
              let note = viewModel.notes.first(where: { $0.id == pendingDraftID }) else {
            return
        }

        if !highlight.isEmpty { note.storedHighlight = highlight }
        if !insight.isEmpty { note.storedInsight = insight }
        if let selectedTopic { note.selectedTopic = selectedTopic }
        if let selectedChoice { note.selectedChoice = selectedChoice }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            note.finalAction = trimmedAction
            note.storedAction = trimmedAction
            note.state = .executing(action: trimmedAction)
            viewModel.executingNoteId = note.id
        }
        viewModel.saveNotes()
        // Promote draft to active now that user accepted an action
        viewModel.promoteDraftToActive(noteId: pendingDraftID)
        closeOverlay()
    }

    private func ensureDraft(for text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let currentPendingID = pendingDraftID,
           let note = viewModel.notes.first(where: { $0.id == currentPendingID }) {
            if note.text != trimmed {
                note.text = trimmed
                viewModel.saveNotes()
            }
            return
        }

        viewModel.addNote(trimmed, source: "entry_overlay", status: .draft)
        pendingDraftID = viewModel.selectedNoteId
        if let pending = pendingDraftID {
            viewModel.saveDraftSession(
                noteId: pending,
                chatHistory: [],
                pendingQuestion: nil,
                pendingChoices: nil,
                pendingTopics: nil
            )
        }
    }

    private func conversationContextText() -> String {
        let baseText = braindumpText.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []

        if !baseText.isEmpty {
            lines.append(baseText)
        }

        // Skip system navigation prompts from AI ("Выбери фокус", "Выбери тактику"):
        // they are UI labels, NOT real conversation content, and including them in
        // the prompt confuses the model into thinking topic selection is still pending.
        let systemPrompts = DialogLabel.all
        for message in chatHistory {
            if message.isAI {
                guard !systemPrompts.contains(message.text) else { continue }
                lines.append("Вопрос: \(message.text)")
            } else {
                lines.append("Ответ: \(message.text)")
            }
        }

        return lines.joined(separator: "\n\n")
    }

    private func updateDraft(_ update: (BraindumpNote) -> Void) {
        guard let pendingDraftID,
              let note = viewModel.notes.first(where: { $0.id == pendingDraftID }) else {
            return
        }
        update(note)
        viewModel.saveNotes()
    }
}
