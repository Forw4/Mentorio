//
//  MentorioApp.swift
//  Mentorio
//

import SwiftUI
import SwiftData
import UIKit

@main
struct MentorioApp: App {
    @AppStorage("userName") var userName: String = ""
    @Environment(\.scenePhase) private var scenePhase
    private let sharedModelContainer: ModelContainer

    init() {
        do {
            sharedModelContainer = try ModelContainer(
                for: BraindumpNote.self,
                MentorioSession.self,
                AnalyticsEventRecord.self
            )
        } catch {
            preconditionFailure("Failed to initialize SwiftData container: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if userName.isEmpty {
                    OnboardingView()
                } else {
                    RootView(modelContext: sharedModelContainer.mainContext)
                }
            }
            .fontDesign(.serif)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                }
            }
            .tint(MentorioColor.accent)
            .onAppear {
                NotificationManager.shared.requestPermissionIfNeeded()
                NotificationManager.shared.handleAppBecameActive()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    NotificationManager.shared.handleAppBecameActive()
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
