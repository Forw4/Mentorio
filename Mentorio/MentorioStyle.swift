//
//  MentorioStyle.swift
//  Mentorio
//

import SwiftUI

enum MentorioColor {
    static let paper = Color(red: 253 / 255, green: 252 / 255, blue: 248 / 255)
    static let charcoal = Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255)
    static let mentorGray = Color(red: 58 / 255, green: 58 / 255, blue: 60 / 255)
}

struct PaperBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(MentorioColor.paper.ignoresSafeArea())
    }
}

extension View {
    func mentorioPaperBackground() -> some View {
        modifier(PaperBackgroundModifier())
    }
}

struct ReflectingPulseView: View {
    @State private var dim = false

    var body: some View {
        Text("One moment.")
            .font(.subheadline)
            .foregroundStyle(MentorioColor.charcoal.opacity(0.48))
            .opacity(dim ? 0.38 : 0.78)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}
