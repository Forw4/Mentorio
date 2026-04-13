//
//  PreviewHelpers.swift
//  Mentorio
//

import SwiftData

@MainActor
func makePreviewModelContext() -> ModelContext {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: BraindumpNote.self,
        MentorioSession.self,
        AnalyticsEventRecord.self,
        configurations: configuration
    )
    return ModelContext(container)
}

@MainActor
func makePreviewViewModel() -> MentorioViewModel {
    MentorioViewModel(modelContext: makePreviewModelContext())
}
