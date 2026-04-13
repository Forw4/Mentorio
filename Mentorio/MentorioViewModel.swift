//
//  MentorioViewModel.swift
//  Mentorio
//

import Foundation
import SwiftUI
import SwiftData

@MainActor
class MentorioViewModel: ObservableObject {
    @Published var notes: [BraindumpNote] = []
    @Published var archivedNotes: [BraindumpNote] = []
    @Published var deletedNotes: [BraindumpNote] = []
    @Published var selectedNoteId: UUID? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    // Track which note is currently in execution (showing One Action overlay)
    @Published var executingNoteId: UUID? = nil
    
    // Track which note is focused (expanded) for interaction; others collapse to preview
    @Published var focusedNoteID: UUID? = nil
    
    // Error recovery: track last failed operation for retry
    @Published var lastFailedNoteId: UUID? = nil
    private var lastFailedOperation: (() -> Void)? = nil
    
    // SwiftData context for persistence
    let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        AnalyticsManager.shared.configure(modelContext: self.modelContext)
        loadNotes()
    }
    
    // Computed property for active notes
    var activeNotes: [BraindumpNote] {
        notes.filter { !$0.isCompleted && !$0.isInTrash }
    }

    // MARK: - Note Management

    private func fetchNote(by id: UUID) -> BraindumpNote? {
        let descriptor = FetchDescriptor<BraindumpNote>(
            predicate: #Predicate { note in
                note.id == id
            }
        )
        return try? modelContext.fetch(descriptor).first
    }
    
    func addNote(_ text: String) {
        let newNote = BraindumpNote(text: text)
        modelContext.insert(newNote)  // Insert into SwiftData
        notes.insert(newNote, at: 0)
        selectedNoteId = newNote.id
        AnalyticsManager.shared.track("braindump_started")
        saveNotes()  // Persist immediately
    }

    @discardableResult
    func purgeNotes(matchingTexts texts: [String]) -> Int {
        let targetTexts = Set(texts.map(Self.normalizedText).filter { !$0.isEmpty })
        guard !targetTexts.isEmpty else { return 0 }

        let merged = notes + archivedNotes + deletedNotes
        var uniqueByID: [UUID: BraindumpNote] = [:]
        for note in merged {
            uniqueByID[note.id] = note
        }

        let matched = uniqueByID.values.filter { note in
            targetTexts.contains(Self.normalizedText(note.text))
        }

        guard !matched.isEmpty else { return 0 }

        let removedIDs = Set(matched.map(\.id))
        for note in matched {
            modelContext.delete(note)
        }

        if let selected = selectedNoteId, removedIDs.contains(selected) {
            selectedNoteId = nil
        }
        if let focused = focusedNoteID, removedIDs.contains(focused) {
            focusedNoteID = nil
        }
        if let executing = executingNoteId, removedIDs.contains(executing) {
            executingNoteId = nil
        }

        do {
            try modelContext.save()
            loadNotes()
            AnalyticsManager.shared.track("test_scenarios_cleared", properties: [
                "removed": "\(matched.count)"
            ])
            return matched.count
        } catch {
            print("❌ Failed to clear matching notes: \(error)")
            setError("Не удалось очистить тестовые сценарии")
            return 0
        }
    }
    
    func deleteNote(id: UUID) {
        guard let note = (notes + archivedNotes).first(where: { $0.id == id }) ?? fetchNote(by: id) else { return }

        // Trash rule: keep only raw braindump text and clear interaction history.
        note.state = .idle
        note.selectedTopic = nil
        note.userAnswer = nil
        note.selectedChoiceIndex = nil
        note.lastIntentRoute = nil
        note.lastIsHighStakes = false
        note.lastIntentUpdatedAt = nil
        note.clarifyingAttempts = 0
        note.userClarification = nil
        note.insight = nil
        note.selectedChoice = nil
        note.finalAction = nil
        note.storedInsight = nil
        note.storedHighlight = nil
        note.storedAction = nil
        note.completionProof = nil
        note.realityCheck = nil
        note.completedAt = nil
        note.isCompleted = false
        saveContextSilently()

        note.deletedAt = Date()
        note.isInTrash = true

        if selectedNoteId == id {
            selectedNoteId = nil
        }
        if focusedNoteID == id {
            focusedNoteID = nil
        }
        if executingNoteId == id {
            executingNoteId = nil
        }
        persistAndReload(userFacingError: "Не удалось удалить заметку")
    }

    func restoreNote(id: UUID) {
        guard let note = deletedNotes.first(where: { $0.id == id }) ?? fetchNote(by: id) else { return }
        note.deletedAt = nil
        note.isInTrash = false

        persistAndReload(userFacingError: "Не удалось восстановить заметку")
    }

    func permanentlyDeleteNote(id: UUID) {
        guard let note = deletedNotes.first(where: { $0.id == id }) ?? fetchNote(by: id) else { return }
        modelContext.delete(note)

        if selectedNoteId == id {
            selectedNoteId = nil
        }
        if focusedNoteID == id {
            focusedNoteID = nil
        }
        if executingNoteId == id {
            executingNoteId = nil
        }
        persistAndReload(userFacingError: "Не удалось удалить заметку навсегда")
    }
    
    func archiveNote(id: UUID, realityCheck: RealityCheckResult? = nil) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        
        // Mark as completed and set timestamp
        note.completedAt = Date()
        note.isCompleted = true
        saveContextSilently()
        note.realityCheck = realityCheck
        note.completionProof = nil
        
        // CRITICAL: Extract ALL data EXPLICITLY from current state BEFORE archiving
        // This ensures integrity per spec: "Hall of Legends - Сохраняется вся история"
        
        // Extract insight and choices from hasTactics state if available
        if case .hasTactics(let choices, let highlight, let insight, _) = note.state {
            note.insight = insight
            // Also capture highlight for snapshot rule compliance
            if highlight.isEmpty == false {
                // Store as metadata if needed
            }
            // Extract selected choice if index is set
            if let index = note.selectedChoiceIndex, index < choices.count {
                note.selectedChoice = choices[index]
            }
        }
        
        // Extract user clarification/answer (consolidate for archive)
        // "Snapshot Rule": capture exact text from workflow
        if note.userAnswer != nil && !note.userAnswer!.isEmpty {
            note.userClarification = note.userAnswer
        }
        
        // Extract final action from executing state if available
        if case .executing(let action) = note.state {
            note.finalAction = action
        }
        
        // Ensure note is visible only in archive partition after save.
        note.deletedAt = nil
        note.isInTrash = false

        NotificationManager.shared.schedulePostActionNotification(for: note.id)
        persistAndReload(userFacingError: "Не удалось архивировать заметку")
    }
    
    // MARK: - State Transitions
    
    func startTransformation(for note: BraindumpNote) {
        guard let mutableNote = notes.first(where: { $0.id == note.id }) else { return }
        
        // Set this note as the focused one (others will collapse)
        focusedNoteID = note.id

        let intentRoute = MentorioAIService.classifyIntent(
            for: mutableNote.text,
            selectedTopic: mutableNote.selectedTopic,
            userAnswer: mutableNote.userAnswer
        )
        let highStakes = MentorioAIService.isHighStakesContext(
            for: mutableNote.text,
            selectedTopic: mutableNote.selectedTopic,
            userAnswer: mutableNote.userAnswer
        )

        mutableNote.lastIntentRoute = intentRoute
        mutableNote.lastIsHighStakes = highStakes
        mutableNote.lastIntentUpdatedAt = Date()
        AnalyticsManager.shared.track("intent_route_detected", properties: [
            "route": intentRoute,
            "high_stakes": highStakes ? "true" : "false",
            "attempts": "\(mutableNote.clarifyingAttempts)"
        ])
        
        mutableNote.state = .analyzing
        updateNote(mutableNote)
        
        // Store operation for retry capability
        lastFailedNoteId = note.id
        lastFailedOperation = { [weak self] in
            self?.startTransformation(for: note)
        }
        
        Task {
            do {
                let response = try await MentorioAIService.getCoreHighlightChoices(
                    for: mutableNote.text,
                    selectedTopic: mutableNote.selectedTopic,
                    userAnswer: mutableNote.userAnswer,
                    clarifyingAttempts: mutableNote.clarifyingAttempts
                )
                
                loadFocusResponse(noteId: mutableNote.id, response: response)
            } catch {
                // Save error and failed operation for retry
                setError("Не удалось получить анализ: \(error.localizedDescription)")
                self.lastFailedNoteId = mutableNote.id
                updateNoteState(noteId: mutableNote.id, to: .idle)
            }
        }
    }
    
    // MARK: - Error Recovery
    
    func retryLastOperation() {
        guard let operation = lastFailedOperation else { return }
        errorMessage = nil  // Clear error before retry
        operation()
    }
    
    @MainActor
    private func updateNoteState(noteId: UUID, with response: FocusResponse) {
        guard let note = notes.first(where: { $0.id == noteId }) else { return }
        
        // Логирование для отладки
        print("📋 API Response:")
        print("   topics: \(response.topics?.isEmpty == false ? "✓ (\(response.topics?.count ?? 0))" : "✗")")
        print("   highlight: \(response.highlight?.isEmpty == false ? "✓" : "✗")")
        print("   insight: \(response.insight?.isEmpty == false ? "✓" : "✗")")
        print("   question: \(response.question?.isEmpty == false ? "✓" : "✗")")
        print("   choices: \(response.choices?.isEmpty == false ? "✓ (\(response.choices?.count ?? 0))" : "✗")")

        let route = note.lastIntentRoute ?? "unknown"
        let highStakes = note.lastIsHighStakes ? "true" : "false"
        let attempts = "\(note.clarifyingAttempts)"
        
        // FAULT-TOLERANT LOGIC: Proceed even if some fields are null
        if let topics = response.topics, !topics.isEmpty {
            print("→ Transitioning to .needsTopic")
            note.state = .needsTopic(topics: topics)
            AnalyticsManager.shared.track("gate_branch_triggered", properties: ["branch_type": "A"])
            AnalyticsManager.shared.track("intent_route_outcome", properties: [
                "route": route,
                "high_stakes": highStakes,
                "attempts": attempts,
                "outcome": "topics"
            ])
        } else if let question = response.question, !question.isEmpty {
            print("→ Transitioning to .clarifying")
            note.state = .clarifying(question: question)
            AnalyticsManager.shared.track("gate_branch_triggered", properties: ["branch_type": "B"])
            AnalyticsManager.shared.track("intent_route_outcome", properties: [
                "route": route,
                "high_stakes": highStakes,
                "attempts": attempts,
                "outcome": "question"
            ])

            if route == "decision_paralysis" && note.clarifyingAttempts == 0 {
                AnalyticsManager.shared.track("decision_research_cycle_started", properties: [
                    "high_stakes": highStakes
                ])
            }

            if route == "decision_paralysis" && note.clarifyingAttempts >= 1 {
                AnalyticsManager.shared.track("decision_research_cycle_violation", properties: [
                    "high_stakes": highStakes,
                    "attempts": attempts
                ])
            }
        } else if let choices = response.choices, !choices.isEmpty {
            // FAULT-TOLERANT: highlight and insight are optional now
            // Use provided values or empty strings as fallback
            let highlight = response.highlight ?? ""
            let insight = response.insight ?? ""
            print("→ Transitioning to .hasTactics with \(choices.count) choices (highlight: \(highlight.isEmpty ? "empty" : "present"), insight: \(insight.isEmpty ? "empty" : "present"))")
            note.state = .hasTactics(choices: choices, highlight: highlight, insight: insight, topics: response.topics)
            AnalyticsManager.shared.track("gate_branch_triggered", properties: ["branch_type": "C"])
            AnalyticsManager.shared.track("mirror_viewed")
            AnalyticsManager.shared.track("intent_route_outcome", properties: [
                "route": route,
                "high_stakes": highStakes,
                "attempts": attempts,
                "outcome": "choices"
            ])

            if route == "decision_paralysis" && note.clarifyingAttempts >= 1 {
                AnalyticsManager.shared.track("decision_research_cycle_closed", properties: [
                    "high_stakes": highStakes,
                    "attempts": attempts
                ])
            }
        } else {
            // No viable state - show error but DON'T crash
            let errorMsg = "Incomplete response: needs choices, topics, or question. Got: topics=\(response.topics?.count ?? 0), choices=\(response.choices?.count ?? 0)"
            print("❌ \(errorMsg)")
            errorMessage = errorMsg
            note.state = .idle
            AnalyticsManager.shared.track("intent_route_outcome", properties: [
                "route": route,
                "high_stakes": highStakes,
                "attempts": attempts,
                "outcome": "invalid"
            ])
        }
        
        updateNote(note)
    }
    
    @MainActor
    private func updateNoteState(noteId: UUID, to state: NoteState) {
        guard let note = notes.first(where: { $0.id == noteId }) else { return }
        note.state = state
        updateNote(note)
    }

    @MainActor
    private func loadFocusResponse(noteId: UUID, response: FocusResponse) {
        guard let note = notes.first(where: { $0.id == noteId }) else { return }

        if let highlight = response.highlight,
           !highlight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            note.storedHighlight = highlight
        }

        if let insight = response.insight,
           !insight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            note.storedInsight = insight
        }

        updateNote(note)
        saveContextSilently()
        updateNoteState(noteId: noteId, with: response)
    }
    
    // MARK: - User Actions
    
    func selectTopic(_ topic: String, for noteId: UUID) {
        guard let note = notes.first(where: { $0.id == noteId }) else { return }
        note.selectedTopic = topic
        updateNote(note)
        startTransformation(for: note)
    }
    
    func submitAnswer(_ answer: String, for noteId: UUID) {
        guard let note = notes.first(where: { $0.id == noteId }) else { return }
        note.userAnswer = answer
        note.clarifyingAttempts += 1  // SPEC: "Счётчик инкрементируется при каждом submitAnswer()"
        AnalyticsManager.shared.track("clarification_submitted", properties: [
            "route": note.lastIntentRoute ?? "unknown",
            "attempts": "\(note.clarifyingAttempts)",
            "high_stakes": note.lastIsHighStakes ? "true" : "false"
        ])
        updateNote(note)
        startTransformation(for: note)
    }
    
    func selectChoice(_ choiceIndex: Int, for noteId: UUID) {
        guard let note = notes.first(where: { $0.id == noteId }) else { return }
        note.selectedChoiceIndex = choiceIndex
        updateNote(note)
        
        // Extract choice text and trigger final action
        if case .hasTactics(let choices, let highlight, let insight, _) = note.state {
            guard choiceIndex < choices.count else { return }
            let selectedChoice = choices[choiceIndex]
            triggerFinalAction(for: note, choice: selectedChoice, highlight: highlight, insight: insight)
        }
    }
    
    // MARK: - Final Action
    
    private func triggerFinalAction(
        for note: BraindumpNote,
        choice: String,
        highlight: String,
        insight: String
    ) {
        let mutableNote = note
        mutableNote.state = .analyzing
        updateNote(mutableNote)
        executingNoteId = note.id

        AnalyticsManager.shared.track("one_action_requested", properties: [
            "route": note.lastIntentRoute ?? "unknown",
            "high_stakes": note.lastIsHighStakes ? "true" : "false"
        ])
        
        Task {
            do {
                let action = try await MentorioAIService.getOneAction(
                    for: choice,
                    braindump: note.text,
                    highlight: highlight,
                    insight: insight
                )
                
                setExecutingAction(noteId: note.id, action: action)
            } catch {
                setError("Не удалось создать действие: \(error.localizedDescription)")
                updateNoteState(noteId: note.id, to: .idle)
                executingNoteId = nil
            }
        }
    }
    
    @MainActor
    private func setExecutingAction(noteId: UUID, action: String) {
        guard let note = notes.first(where: { $0.id == noteId }) else { return }
        note.storedAction = action
        note.state = .executing(action: action)
        AnalyticsManager.shared.track("one_action_generated", properties: [
            "route": note.lastIntentRoute ?? "unknown",
            "high_stakes": note.lastIsHighStakes ? "true" : "false"
        ])
        updateNote(note)
        saveContextSilently()
    }

    func presentStoredActionIfAvailable(for noteId: UUID) {
        guard let note = notes.first(where: { $0.id == noteId }) else { return }
        guard !note.isInTrash, !note.isCompleted else { return }
        guard let action = note.storedAction,
              !action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        focusedNoteID = noteId
        note.state = .executing(action: action)
        updateNote(note)
        executingNoteId = noteId
        saveContextSilently()
    }
    
    func completeAction(noteId: UUID, realityCheck: RealityCheckResult) {
        archiveNote(id: noteId, realityCheck: realityCheck)
        AnalyticsManager.shared.track("action_completed")
        executingNoteId = nil
        focusedNoteID = nil
    }
    
    func continueWithNextStep(for noteId: UUID) {
        guard let note = notes.first(where: { $0.id == noteId }) else { return }
        // Reset to idle, prepare for next iteration
        note.state = .idle
        note.selectedTopic = nil
        note.userAnswer = nil
        note.selectedChoiceIndex = nil
        note.lastIntentRoute = nil
        note.lastIsHighStakes = false
        note.lastIntentUpdatedAt = nil
        updateNote(note)
        AnalyticsManager.shared.track("action_skipped")
        executingNoteId = nil
        focusedNoteID = nil
    }
    
    // MARK: - Helpers
    
    @MainActor
    private func setError(_ message: String) {
        errorMessage = message
        // Auto-clear after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if self.errorMessage == message {
                self.errorMessage = nil
            }
        }
    }
    
    private func updateNote(_ note: BraindumpNote) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
            return
        }
        if let index = archivedNotes.firstIndex(where: { $0.id == note.id }) {
            archivedNotes[index] = note
            return
        }
        if let index = deletedNotes.firstIndex(where: { $0.id == note.id }) {
            deletedNotes[index] = note
        }
    }
    
    // MARK: - Persistence
    
    private func loadNotes() {
        do {
            // Fetch all notes from SwiftData
            let descriptor = FetchDescriptor<BraindumpNote>(
                predicate: #Predicate { _ in true },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let allNotes = try modelContext.fetch(descriptor)
            
            // Split into active and archived
            self.notes = allNotes.filter { !$0.isCompleted && !$0.isInTrash && $0.deletedAt == nil }
            self.archivedNotes = allNotes.filter { $0.isCompleted && !$0.isInTrash && $0.deletedAt == nil }
            self.deletedNotes = allNotes.filter { $0.isInTrash || $0.deletedAt != nil }
                .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
            
            print("✅ Loaded \(self.notes.count) active notes, \(self.archivedNotes.count) archived, \(self.deletedNotes.count) deleted")
        } catch {
            print("❌ Failed to load notes from SwiftData: \(error)")
            // Gracefully continue with empty arrays
            self.notes = []
            self.archivedNotes = []
            self.deletedNotes = []
        }
    }
    
    func saveNotes() {
        do {
            try modelContext.save()
            print("💾 Notes saved to SwiftData")
        } catch {
            print("❌ Failed to save notes: \(error)")
            setError("Не удалось сохранить заметки")
        }
    }

    private func saveContextSilently() {
        try? modelContext.save()
    }

    private func persistAndReload(userFacingError: String) {
        do {
            try modelContext.save()
            loadNotes()
        } catch {
            print("❌ Persistence failed: \(error)")
            setError(userFacingError)
        }
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
