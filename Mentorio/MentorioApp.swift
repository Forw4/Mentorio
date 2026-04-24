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
    @AppStorage("hasSeenWelcome") var hasSeenWelcome: Bool = false
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
            ZStack {
                if !hasSeenWelcome {
                    WelcomeView()
                        .transition(.opacity)
                } else {
                    RootView(modelContext: sharedModelContainer.mainContext)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: hasSeenWelcome)
            .fontDesign(.serif)
            .toolbar {
                if hasSeenWelcome {
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
