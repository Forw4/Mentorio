//
//  JournalModels.swift
//  Mentorio
//

import Foundation
import SwiftData

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

extension MentorioSession: @unchecked Sendable {}
