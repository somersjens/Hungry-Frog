//
//  MenuMeadowBackground.swift
//  Hungry Frog
//
//  The quiet backdrop behind the welcome flow and the main menu: soft meadow
//  shapes kept low enough in contrast for controls and longer translated copy.
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
