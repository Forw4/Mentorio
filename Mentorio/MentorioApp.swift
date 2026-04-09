//
//  MentorioApp.swift
//  Mentorio
//

import SwiftUI
import SwiftData

@main
struct MentorioApp: App {
    @AppStorage("userName") var userName: String = ""
    
    var body: some Scene {
        WindowGroup {
            Group {
                if userName.isEmpty {
                    OnboardingView()
                } else {
                    ContentView()
                }
            }
            .accentColor(.primary)
        }
        .modelContainer(for: [MentorioSession.self])
    }
}
