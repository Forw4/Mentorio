//
//  AnalyticsManager.swift
//  Mentorio
//

import Foundation
import SwiftData

struct AnalyticsEventSnapshot: Identifiable {
    let id = UUID()
    let name: String
    let properties: [String: String]
    let timestamp: Date
}

final class AnalyticsManager {
    static let shared = AnalyticsManager()

    private var events: [AnalyticsEventSnapshot] = []
    private weak var modelContext: ModelContext?
    private let maxStoredEvents = 50

    private init() {}

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadPersistedEvents(using: modelContext)
    }

    func track(_ event: String, properties: [String: String] = [:]) {
        let entry = AnalyticsEventSnapshot(name: event, properties: properties, timestamp: Date())
        events.insert(entry, at: 0)
        if events.count > maxStoredEvents {
            events = Array(events.prefix(maxStoredEvents))
        }

        if let modelContext {
            let record = AnalyticsEventRecord(name: event, properties: properties)
            modelContext.insert(record)
            do {
                try modelContext.save()
            } catch {
                print("[Analytics] Failed to persist event: \(error.localizedDescription)")
            }
        }

        if properties.isEmpty {
            print("[Analytics] event=\(event)")
            return
        }

        let serialized = properties
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ",")
        print("[Analytics] event=\(event) properties={\(serialized)}")
    }

    func recentEvents(limit: Int = 20) -> [AnalyticsEventSnapshot] {
        Array(events.prefix(limit))
    }

    private func loadPersistedEvents(using modelContext: ModelContext) {
        var descriptor = FetchDescriptor<AnalyticsEventRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = maxStoredEvents

        do {
            let records = try modelContext.fetch(descriptor)
            events = records.map {
                AnalyticsEventSnapshot(
                    name: $0.name,
                    properties: $0.properties,
                    timestamp: $0.createdAt
                )
            }
        } catch {
            print("[Analytics] Failed to preload events: \(error.localizedDescription)")
            events = []
        }
    }
}
