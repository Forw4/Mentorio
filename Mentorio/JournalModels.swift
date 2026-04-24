//
//  JournalModels.swift
//  Mentorio
//

import Foundation
import SwiftData

// MARK: - Braindump Note State Machine

enum RealityCheckResult: String, Codable {
    case easierThanExpected = "Оказалось проще, чем я думал"
    case hardWork = "Пришлось попотеть"
}

@Model
final class AnalyticsEventRecord: Identifiable {
    var id: UUID
    var name: String
    private var propertiesJSON: String = "{}"
    var createdAt: Date

    var properties: [String: String] {
        get {
            guard let data = propertiesJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue),
               let json = String(data: encoded, encoding: .utf8) {
                propertiesJSON = json
            }
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        properties: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        if let encoded = try? JSONEncoder().encode(properties),
           let json = String(data: encoded, encoding: .utf8) {
            self.propertiesJSON = json
        }
        self.createdAt = createdAt
    }
}

enum NoteState: Equatable, Codable {
    case idle
    case analyzing
    case needsTopic(topics: [String])
    case clarifying(question: String)
    case hasTactics(choices: [String], highlight: String, insight: String, topics: [String]? = nil)
    case executing(action: String)
    
    enum CodingKeys: String, CodingKey {
        case idle, analyzing, needsTopic, clarifying, hasTactics, executing
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try container.encode(true, forKey: .idle)
        case .analyzing:
            try container.encode(true, forKey: .analyzing)
        case .needsTopic(let topics):
            try container.encode(topics, forKey: .needsTopic)
        case .clarifying(let question):
            try container.encode(question, forKey: .clarifying)
        case .hasTactics(let choices, let highlight, let insight, let topics):
            var nested = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .hasTactics)
            try nested.encode(choices, forKey: .needsTopic)
            try nested.encode(highlight, forKey: .clarifying)
            try nested.encode(insight, forKey: .idle)
            if let topics = topics {
                try nested.encode(topics, forKey: .analyzing)
            }
        case .executing(let action):
            try container.encode(action, forKey: .executing)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.idle) {
            self = .idle
        } else if container.contains(.analyzing) {
            self = .analyzing
        } else if container.contains(.needsTopic) {
            let topics = try container.decode([String].self, forKey: .needsTopic)
            self = .needsTopic(topics: topics)
        } else if container.contains(.clarifying) {
            let question = try container.decode(String.self, forKey: .clarifying)
            self = .clarifying(question: question)
        } else if container.contains(.hasTactics) {
            let nested = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .hasTactics)
            let choices = try nested.decode([String].self, forKey: .needsTopic)
            let highlight = try nested.decode(String.self, forKey: .clarifying)
            let insight = try nested.decode(String.self, forKey: .idle)
            let topics = try nested.decodeIfPresent([String].self, forKey: .analyzing)
            self = .hasTactics(choices: choices, highlight: highlight, insight: insight, topics: topics)
        } else if container.contains(.executing) {
            let action = try container.decode(String.self, forKey: .executing)
            self = .executing(action: action)
        } else {
            self = .idle
        }
    }
}

// MARK: - Braindump Note (SwiftData Persistent Model)

@Model
final class BraindumpNote: Identifiable {
    var id: UUID
    var text: String
    var createdAt: Date
    
    // Store state as JSON string for SwiftData compatibility
    private var stateJSON: String = "{}"
    var state: NoteState {
        get {
            guard let data = stateJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(NoteState.self, from: data) else {
                return .idle
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue),
               let json = String(data: encoded, encoding: .utf8) {
                stateJSON = json
            }
        }
    }
    
    var selectedTopic: String? = nil
    var userAnswer: String? = nil
    var selectedChoiceIndex: Int? = nil
    var lastIntentRoute: String? = nil
    var lastIsHighStakes: Bool = false
    var lastIntentUpdatedAt: Date? = nil
    
    // Spec Branch B: "Fair Try" Gate - clarifying attempts counter
    var clarifyingAttempts: Int = 0
    
    // Archive system fields
    var isCompleted: Bool = false
    var isInTrash: Bool = false
    var deletedAt: Date? = nil
    var userClarification: String? = nil
    var insight: String? = nil
    var selectedChoice: String? = nil
    var finalAction: String? = nil
    var completionProof: String? = nil
    var realityCheck: RealityCheckResult? = nil
    var completedAt: Date? = nil
    var storedInsight: String? = nil
    var storedHighlight: String? = nil
    var storedAction: String? = nil
    
    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        state: NoteState = .idle,
        selectedTopic: String? = nil,
        userAnswer: String? = nil,
        selectedChoiceIndex: Int? = nil,
        lastIntentRoute: String? = nil,
        lastIsHighStakes: Bool = false,
        lastIntentUpdatedAt: Date? = nil,
        clarifyingAttempts: Int = 0,
        isCompleted: Bool = false,
        isInTrash: Bool = false,
        deletedAt: Date? = nil,
        userClarification: String? = nil,
        insight: String? = nil,
        selectedChoice: String? = nil,
        finalAction: String? = nil,
        completionProof: String? = nil,
        realityCheck: RealityCheckResult? = nil,
        completedAt: Date? = nil,
        storedInsight: String? = nil,
        storedHighlight: String? = nil,
        storedAction: String? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.state = state
        self.selectedTopic = selectedTopic
        self.userAnswer = userAnswer
        self.selectedChoiceIndex = selectedChoiceIndex
        self.lastIntentRoute = lastIntentRoute
        self.lastIsHighStakes = lastIsHighStakes
        self.lastIntentUpdatedAt = lastIntentUpdatedAt
        self.clarifyingAttempts = clarifyingAttempts
        self.isCompleted = isCompleted
        self.isInTrash = isInTrash
        self.deletedAt = deletedAt
        self.userClarification = userClarification
        self.insight = insight
        self.selectedChoice = selectedChoice
        self.finalAction = finalAction
        self.completionProof = completionProof
        self.realityCheck = realityCheck
        self.completedAt = completedAt
        self.storedInsight = storedInsight
        self.storedHighlight = storedHighlight
        self.storedAction = storedAction
    }
}

@Model
class MentorioSession: Identifiable {
    var id: UUID
    var createdAt: Date
    var braindumpText: String
    var coreHighlight: String?
    @Attribute(.externalStorage) var choiceOptions: [String]
    var selectedChoiceIndex: Int?
    var oneAction: String?
    var isCleared: Bool
    var isActionCompleted: Bool

    var selectedChoice: String? {
        guard let index = selectedChoiceIndex,
              choiceOptions.indices.contains(index) else {
            return nil
        }
        return choiceOptions[index]
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        braindumpText: String,
        coreHighlight: String? = nil,
        choiceOptions: [String] = [],
        selectedChoiceIndex: Int? = nil,
        oneAction: String? = nil,
        isCleared: Bool = false,
        isActionCompleted: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.braindumpText = braindumpText
        self.coreHighlight = coreHighlight
        self.choiceOptions = choiceOptions
        self.selectedChoiceIndex = selectedChoiceIndex
        self.oneAction = oneAction
        self.isCleared = isCleared
        self.isActionCompleted = isActionCompleted
    }
}

