//
//  MentorioStyle.swift
//  Mentorio
//

import SwiftUI
import UIKit

enum MentorioColor {
    static let claudeOrange = Color(red: 0.92, green: 0.61, blue: 0.39)

    // Semantic palette backed by iOS system colors for native contrast.
    static let background = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let surfaceElevated = Color(uiColor: .systemBackground)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let accent = claudeOrange
    static let accentMuted = claudeOrange.opacity(0.16)
    static let stroke = Color(uiColor: .separator)
    static let textOnAccent = Color.white
    static let danger = Color(uiColor: .systemRed)
    static let dangerDeep = Color(uiColor: .systemRed).opacity(0.82)
    static let neutralStrong = Color(uiColor: .secondaryLabel)
    static let neutralStrongAlt = Color(uiColor: .tertiaryLabel)
    static let scrim = Color.black.opacity(0.54)

    // Legacy aliases
    static let paper = background
    static let charcoal = textPrimary
    static let mentorGray = textSecondary
}

enum MentorioMetric {
    static let radiusS: CGFloat = 10
    static let radiusM: CGFloat = 14
    static let radiusL: CGFloat = 20

    static let spaceS: CGFloat = 8
    static let spaceM: CGFloat = 12
    static let spaceL: CGFloat = 16
    static let spaceXL: CGFloat = 24
}

enum MentorioType {
    static let title = Font.system(size: 30, weight: .bold, design: .default)
    static let sectionTitle = Font.system(size: 20, weight: .semibold, design: .default)
    static let body = Font.system(size: 15, weight: .regular, design: .default)
    static let caption = Font.system(size: 12, weight: .regular, design: .default)
}



struct ReflectingPulseView: View {
    @State private var dim = false

    var body: some View {
        Text("Момент...")
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
