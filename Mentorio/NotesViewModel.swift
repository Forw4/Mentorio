import Foundation
import SwiftUI

@MainActor
final class NotesViewModel: ObservableObject {
    @Published private(set) var notes: [Note]

    // Keeps active note priority by most recent activation.
    private var activeOrder: [UUID]

    init() {
        let firstActive = Note(text: "Write 3 lines of code", status: .active)
        let secondActive = Note(text: "Open Notes and list one blocker", status: .active)

        let mocks: [Note] = [
            firstActive,
            secondActive,
            Note(text: "I am overthinking the first step", status: .draft),
            Note(text: "Need to send one short update", status: .draft),
            Note(text: "Push tiny improvement", status: .archived, artifactPlaceholder: "artifact_mock.jpg")
        ]

        notes = mocks
        activeOrder = [secondActive.id, firstActive.id]
    }

    var drafts: [Note] {
        notes.filter { $0.status == .draft }
    }

    var archived: [Note] {
        notes.filter { $0.status == .archived }
    }

    var activeNote: Note? {
        for id in activeOrder {
            if let note = notes.first(where: { $0.id == id && $0.status == .active }) {
                return note
            }
        }
        return notes.first(where: { $0.status == .active })
    }

    @discardableResult
    func createDraft(from text: String) -> UUID {
        let draft = Note(text: text, status: .draft)
        notes.insert(draft, at: 0)
        return draft.id
    }

    func activateDraft(noteID: UUID, actionText: String) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else {
            activateNewAction(actionText)
            return
        }

        notes[index].text = actionText
        notes[index].status = .active
        notes[index].artifactPlaceholder = nil
        moveToFrontOfActiveOrder(noteID)
    }

    func activateNewAction(_ actionText: String) {
        let note = Note(text: actionText, status: .active)
        notes.insert(note, at: 0)
        moveToFrontOfActiveOrder(note.id)
    }

    func completeCurrentActiveNote() -> Note? {
        guard let activeID = activeNote?.id,
              let index = notes.firstIndex(where: { $0.id == activeID }) else {
            return nil
        }

        notes[index].status = .archived
        activeOrder.removeAll { $0 == activeID }
        return notes[index]
    }

    func attachArtifact(to noteID: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[index].artifactPlaceholder = "artifact_\(Int(Date().timeIntervalSince1970)).jpg"
    }

    func note(for noteID: UUID) -> Note? {
        notes.first(where: { $0.id == noteID })
    }

    func binding(for noteID: UUID) -> Binding<Note>? {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return nil }
        return Binding(
            get: { self.notes[index] },
            set: { self.notes[index] = $0 }
        )
    }

    func setArtifactImageName(noteID: UUID, name: String?) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[index].artifactImageName = name
    }

    private func moveToFrontOfActiveOrder(_ noteID: UUID) {
        activeOrder.removeAll { $0 == noteID }
        activeOrder.insert(noteID, at: 0)
    }
}
