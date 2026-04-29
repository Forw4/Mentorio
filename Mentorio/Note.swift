import Foundation

enum NoteStatus: String, Codable, CaseIterable {
    case draft
    case active
    case archived
}

enum ReflectionStatus {
    case pending
    case completed
}

struct Note: Identifiable, Equatable, Hashable {
    let id: UUID
    var text: String
    var status: NoteStatus
    var createdAt: Date
    var artifactPlaceholder: String?
    var originalBraindump: String = ""
    var aiInsight: String = ""
    var chosenTactic: String = ""
    var oneActionText: String = ""
    var artifactImageName: String? = nil
    var reflectionStatus: ReflectionStatus = .pending
    var reflectionText: String? = nil

    init(
        id: UUID = UUID(),
        text: String,
        status: NoteStatus,
        createdAt: Date = Date(),
        artifactPlaceholder: String? = nil
    ) {
        self.id = id
        self.text = text
        self.status = status
        self.createdAt = createdAt
        self.artifactPlaceholder = artifactPlaceholder
    }
}
