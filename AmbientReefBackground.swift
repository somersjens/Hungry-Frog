//
//  AmbientReefBackground.swift
//  Number Reef
//
//  A quiet menu version of the playing reef. It borrows the water column,
//  light shafts, bubbles and sea-floor silhouette from gameplay, while keeping
//  the contrast low enough for controls and longer translated copy.
//

import SwiftUI

/// Warm, land-based backdrop for the welcome flow and main menu. It deliberately
/// avoids water gradients, bubbles, coral and a sea-floor strip; the soft meadow
/// shapes keep the wide screens friendly without competing with the controls.
struct MenuMeadowBackground: View {
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 1.00, green: 0.965, blue: 0.90)

                Circle()
                    .fill(Color.white.opacity(0.58))
                    .frame(width: proxy.size.width * 0.52,
                           height: proxy.size.width * 0.52)
                    .blur(radius: 22)
                    .offset(x: -proxy.size.width * 0.28,
                            y: -proxy.size.height * 0.28)

                Ellipse()
                    .fill(Color(red: 0.82, green: 0.92, blue: 0.70).opacity(0.52))
                    .frame(width: proxy.size.width * 0.72,
                           height: max(110, proxy.size.height * 0.30))
                    .offset(x: proxy.size.width * 0.25,
                            y: proxy.size.height * 0.46)

                Ellipse()
                    .fill(accent.opacity(0.10))
                    .frame(width: proxy.size.width * 0.58,
                           height: max(90, proxy.size.height * 0.23))
                    .offset(x: -proxy.size.width * 0.32,
                            y: proxy.size.height * 0.50)

                MenuLeafSprinkles(accent: accent)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct MenuLeafSprinkles: View {
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            ForEach(0..<11, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 2)
                          ? accent.opacity(0.13)
                          : Color.green.opacity(0.12))
                    .frame(width: CGFloat(7 + index % 3 * 3),
                           height: CGFloat(20 + index % 4 * 5))
                    .rotationEffect(.degrees(Double(index * 31 - 70)))
                    .position(x: proxy.size.width * CGFloat((index * 37 + 9) % 100) / 100,
                              y: proxy.size.height * CGFloat((index * 53 + 17) % 100) / 100)
            }
        }
    }
}

struct AmbientReefBackground: View {
    let character: AnimalCharacter
    var showsSeaFloor = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: ReefPalette { ReefPalette(character: character) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { timeline in
            GeometryReader { proxy in
                let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

                ZStack {
                    character.tintColor

                    LinearGradient(
                        colors: [palette.waterTop.opacity(0.88), character.skyColor, character.tintColor],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    AmbientLightShafts(phase: phase)
                        .opacity(0.16)

                    AmbientBubbleField(phase: phase, size: proxy.size)

                    if showsSeaFloor {
                        AmbientSeaFloor(palette: palette)
                            .frame(height: min(150, proxy.size.height * 0.17))
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }

                    // A soft veil keeps dark theme colours and decoration from
                    // reducing the contrast of text placed over the backdrop.
                    Color.white.opacity(0.12)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct AmbientLightShafts: View {
    let phase: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .topLeading) {
                shaft(width: width * 0.34)
                    .rotationEffect(.degrees(-12), anchor: .top)
                    .offset(x: width * (0.15 + 0.025 * sin(phase * 0.10)))

                shaft(width: width * 0.22)
                    .rotationEffect(.degrees(-8), anchor: .top)
                    .offset(x: width * (0.68 + 0.03 * sin(phase * 0.08 + 1.8)))
            }
        }
    }

    private func shaft(width: CGFloat) -> some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0.9), location: 0.18),
                .init(color: .white.opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: width)
        .blur(radius: 28)
    }
}

private struct AmbientBubbleField: View {
    private struct Bubble: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let diameter: CGFloat
        let speed: CGFloat
    }

    let phase: Double
    let size: CGSize

    private let bubbles: [Bubble] = [
        .init(id: 0, x: 0.06, y: 0.18, diameter: 12, speed: 3.2),
        .init(id: 1, x: 0.13, y: 0.66, diameter: 22, speed: 4.0),
        .init(id: 2, x: 0.22, y: 0.90, diameter: 8, speed: 2.7),
        .init(id: 3, x: 0.78, y: 0.30, diameter: 10, speed: 3.5),
        .init(id: 4, x: 0.88, y: 0.74, diameter: 18, speed: 3.0),
        .init(id: 5, x: 0.96, y: 0.48, diameter: 7, speed: 4.4),
        .init(id: 6, x: 0.68, y: 0.94, diameter: 13, speed: 3.8)
    ]

    var body: some View {
        ZStack {
            ForEach(bubbles) { bubble in
                let travel = size.height + 100
                let shifted = bubble.y * travel - CGFloat(phase) * bubble.speed
                let wrapped = shifted.truncatingRemainder(dividingBy: travel)
                let y = wrapped >= 0 ? wrapped : wrapped + travel

                Circle()
                    .fill(.white.opacity(0.08))
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.32), lineWidth: max(1, bubble.diameter * 0.08))
                    }
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(.white.opacity(0.48))
                            .frame(width: bubble.diameter * 0.22, height: bubble.diameter * 0.22)
                            .padding(bubble.diameter * 0.2)
                    }
                    .frame(width: bubble.diameter, height: bubble.diameter)
                    .position(x: bubble.x * size.width, y: y)
            }
        }
        .opacity(0.78)
    }
}

private struct AmbientSeaFloor: View {
    let palette: ReefPalette

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                AmbientSandShape()
                    .fill(
                        LinearGradient(
                            colors: [palette.sand.opacity(0.48), palette.sandDeep.opacity(0.38)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                HStack(alignment: .bottom, spacing: proxy.size.width * 0.035) {
                    plant(height: proxy.size.height * 0.34, rotation: 8)
                    plant(height: proxy.size.height * 0.50, rotation: -5)
                    plant(height: proxy.size.height * 0.28, rotation: 12)
                    Spacer()
                    plant(height: proxy.size.height * 0.42, rotation: -10)
                    plant(height: proxy.size.height * 0.58, rotation: 5)
                }
                .padding(.horizontal, max(18, proxy.size.width * 0.045))
                .padding(.bottom, proxy.size.height * 0.18)
                .opacity(0.22)
            }
        }
    }

    private func plant(height: CGFloat, rotation: Double) -> some View {
        Capsule()
            .fill(palette.plant)
            .frame(width: max(5, height * 0.12), height: height)
            .rotationEffect(.degrees(rotation), anchor: .bottom)
    }
}

private struct AmbientSandShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.48))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.52, y: rect.height * 0.38),
            control1: CGPoint(x: rect.width * 0.17, y: rect.height * 0.28),
            control2: CGPoint(x: rect.width * 0.34, y: rect.height * 0.58)
        )
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.44),
            control1: CGPoint(x: rect.width * 0.70, y: rect.height * 0.22),
            control2: CGPoint(x: rect.width * 0.84, y: rect.height * 0.60)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}
