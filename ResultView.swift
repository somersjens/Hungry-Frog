//
//  ResultView.swift
//  Math Memory
//
//  The end-of-session card: a level-specific completion title (or game-over
//  title), a short message, the score out of what the board holds, and the two
//  ways onward. Its sizing mirrors the Jumping Fox end-level card.
//

import SwiftUI

struct ResultView: View {
    let result: SessionResult
    /// Which scoreboard was played: it sets what a full score is worth here.
    let board: LevelBoard
    let character: AnimalCharacter
    let onPlayAgain: () -> Void
    let onExit: () -> Void

    @State private var isPresented = false
    @State private var badgeLanded = false
    @State private var shineSweep = false
    @State private var showsFlySwarm = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isPad: Bool { AppLayout.isPad }
    private var scale: CGFloat { isPad ? 1.2 : 1 }
    private var textScale: CGFloat { isPad ? 1.296 : 1 }

    private var maximum: Int { board.maximum }
    /// The level's score tops out at its maximum, exactly as the menu stores
    /// it; cards beyond that still count toward the player's grand total.
    private var levelScore: Int { min(result.cardsEarned, maximum) }
    private var showsNewBest: Bool { result.isNewPersonalBest && result.cardsEarned > 0 }

    private var isCompleted: Bool { result.reason == .roundsCompleted }

    /// A completed board always gets the same celebratory description. When
    /// the player runs out of lives, every three bubbles advance to the next
    /// encouraging message, capped at the tenth message.
    private var encouragement: String {
        guard !isCompleted else { return L(key: "game.end.completionSubtitle") }
        let index = min(max(levelScore, 0) / 3, 9)
        return L(key: "game.encouragement.\(index)")
    }

    private var titleKey: LocalizedStringKey {
        switch result.reason {
        case .outOfLives:      return "game.end.gameOverTitle"
        case .roundsCompleted: return "result.complete"
        case .quit:            return "result.stopped"
        }
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(isPresented ? 0.56 : 0)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.24), value: isPresented)

            GeometryReader { proxy in
                ScrollView {
                    card
                        .padding(22 * scale)
                        .frame(maxWidth: isPad ? 820 : 700)
                        .background(
                            LinearGradient(colors: [character.skyColor, .white, character.tintColor],
                                           startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(.white.opacity(0.82), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: proxy.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .opacity(isPresented ? 1 : 0)
            .scaleEffect(isPresented ? 1 : 0.93)
            .offset(y: isPresented ? 0 : 18)

            // Layered above the card, so the swarm passes over the result
            // rather than behind it. It starts once the card entrance is
            // underway.
            if showsFlySwarm {
                FlySwarmCelebration(color: character.deepColor)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) {
                isPresented = true
            }
            // Only a score this level has never seen before draws the swarm;
            // matching or falling short of the old best ends quietly.
            guard showsNewBest else { return }
            if !reduceMotion {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                    showsFlySwarm = true
                }
            }
            // The badge drops in after the card has settled, then glints once.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                withAnimation(.spring(response: 0.44, dampingFraction: 0.52)) {
                    badgeLanded = true
                }
                withAnimation(.easeInOut(duration: 0.7).delay(0.22)) {
                    shineSweep = true
                }
            }
        }
    }

    private var card: some View {
        HStack(alignment: .center, spacing: 28 * scale) {
            VStack(spacing: 0) {
                characterBadge
                    // Pulled up so the title reads as sitting on the badge
                    // rather than as a separate block underneath it.
                    .padding(.bottom, -10 * scale)

                if isCompleted {
                    completionTitle.frame(maxWidth: .infinity)
                } else {
                    Text(titleKey)
                        .font(.system(size: 38 * textScale, weight: .heavy, design: .rounded))
                        .foregroundStyle(character.deepColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                }

                encouragementRow

                scoreCapsule
                    .padding(.top, 12 * scale)

                if !result.unlockedCharacterIDs.isEmpty {
                    unlockedRow.padding(.top, 8 * scale)
                }
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(character.deepColor.opacity(0.14))
                .frame(width: 1, height: isPad ? 240 : 200)

            // The action side contains actions only. Result, explanation and
            // score form one uninterrupted reading column on the left.
            buttons
                .frame(width: isPad ? 330 : 280)
        }
    }

    /// The played character, styled exactly like the large preview in the
    /// Premium screen: a soft colour-tinted glow, a thin ring and the artwork
    /// floating free with its own drop shadow — no white-ringed disc.
    private var characterBadge: some View {
        let heroSize = 118 * scale
        return ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [character.color.opacity(0.35), character.color.opacity(0.05)],
                    center: .center, startRadius: 6, endRadius: heroSize * 0.8
                ))
                .frame(width: heroSize, height: heroSize)
            Circle()
                .stroke(character.color.opacity(0.30), lineWidth: 2)
                .frame(width: heroSize * 0.92, height: heroSize * 0.92)
            character.artwork
                .resizable()
                .scaledToFit()
                .frame(width: heroSize * 0.86, height: heroSize * 0.86)
                .shadow(color: character.deepColor.opacity(0.25), radius: 16, y: 9)
        }
        .frame(width: heroSize, height: heroSize)
        .accessibilityHidden(true)
    }

    /// The level-based description, flanked by the small leaf ornaments the
    /// original reference used around "Good try".
    private var encouragementRow: some View {
        HStack(spacing: 6 * scale) {
            leafOrnament
            Text(verbatim: encouragement)
                .font(.system(size: (isCompleted ? 13 : 14) * textScale,
                              weight: isCompleted ? .medium : .semibold))
                .foregroundStyle(character.deepColor.opacity(0.64))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            // The right leaf is the left one's exact mirror image, not an
            // independently rotated copy.
            leafOrnament.scaleEffect(x: -1, y: 1)
        }
        .frame(minHeight: 20 * scale)
    }

    private var leafOrnament: some View {
        Image(systemName: "leaf.fill")
            .font(.system(size: 10 * textScale, weight: .semibold))
            .foregroundStyle(character.color.opacity(0.5))
            .rotationEffect(.degrees(18))
    }

    private var completionTitle: some View {
        let fontSize = 38 * textScale
        return HStack(spacing: 7 * scale) {
            operationLabel(fontSize: fontSize)
            Text("game.end.completionSuffix")
                .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(character.deepColor)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func operationLabel(fontSize: CGFloat) -> some View {
        let level = board.level
        let font = Font.system(size: fontSize, weight: .heavy, design: .rounded)

        switch level.topic {
        case .addition:
            scalableTitleText("+\(level.cardNumber)", font: font)
        case .subtraction:
            scalableTitleText("−\(level.cardNumber)", font: font)
        case .tables:
            scalableTitleText("×\(level.cardNumber)", font: font)
        case .percentages:
            scalableTitleText("\(level.cardNumber)%", font: font)
        case .fractions:
            stackedTitleFraction(denominator: level.cardNumber, fontSize: fontSize)
        case .mixed:
            HStack(spacing: 5 * scale) {
                scalableTitleText(level.cardNumber, font: font)
                Image(systemName: "star.fill")
                    .font(.system(size: fontSize * 0.7, weight: .heavy))
            }
        }
    }

    private func scalableTitleText(_ value: String, font: Font) -> some View {
        Text(verbatim: value)
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private func stackedTitleFraction(denominator: String, fontSize: CGFloat) -> some View {
        let thickness = max(2, fontSize * 0.07)
        let font = Font.system(size: fontSize * 0.6, weight: .heavy, design: .rounded)

        return VStack(spacing: thickness + 3 * scale) {
            Text(verbatim: "1")
                .font(font)
                .lineLimit(1)
            Text(verbatim: denominator)
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .overlay {
            Rectangle()
                .fill(character.deepColor)
                .frame(height: thickness)
        }
        .fixedSize()
        .padding(.horizontal, 2 * scale)
    }

    private var scoreCapsule: some View {
        Text(verbatim: "\(levelScore) / \(maximum)")
            // Keep "x / y" from flipping around.
            .environment(\.layoutDirection, .leftToRight)
            .font(.system(size: 28 * textScale, weight: .heavy, design: .rounded))
            .foregroundStyle(character.color)
            .padding(.horizontal, 24 * scale)
            .padding(.vertical, 10 * scale)
            .background(character.tintColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(character.color.opacity(0.16), lineWidth: 1)
            }
            // Detached from the box rather than stacked inside it: it floats
            // above, centred, straddling the top edge.
            .overlay(alignment: .top) {
                if showsNewBest {
                    newBestBadge
                        .scaleEffect(badgeLanded ? 1 : 0.4)
                        .opacity(badgeLanded ? 1 : 0)
                        .offset(y: -12 * scale)
                }
            }
            .accessibilityIdentifier("score")
            .accessibilityLabel(Text(L("game.accessibility.scoreOutOf \(levelScore) \(maximum)")))
    }

    /// A small pill centred above the score, detached from the box itself.
    private var newBestBadge: some View {
        HStack(spacing: 3) {
            Text("game.highScore")
                .lineLimit(1)
            CurrencyIcon(size: 9 * textScale)
        }
        .fixedSize()
        .font(.system(size: 9.5 * textScale, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 7 * textScale)
        .padding(.vertical, 3.5 * textScale)
        .background(character.color, in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.85), lineWidth: 1.5) }
        .shadow(color: character.deepColor.opacity(0.28), radius: 4, y: 2)
        // A soft diagonal highlight sweeps across once as the badge lands.
        // Clipped to the capsule and starting off-badge, it is invisible before
        // and after that single pass — no fade bookkeeping needed.
        .overlay {
            Capsule()
                .fill(
                    LinearGradient(colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 20)
                .rotationEffect(.degrees(18))
                .offset(x: shineSweep ? 70 : -70)
                .allowsHitTesting(false)
        }
        .clipShape(Capsule())
        .accessibilityIdentifier("new-best")
    }

    private var unlockedRow: some View {
        VStack(spacing: 8) {
            Text("result.unlocked")
                .font(.system(size: 15 * textScale, weight: .heavy, design: .rounded))
                .foregroundStyle(character.deepColor)
            HStack(spacing: 14) {
                ForEach(result.unlockedCharacterIDs, id: \.self) { id in
                    let animal = CharacterCatalog.character(id: id)
                    VStack(spacing: 4) {
                        animal.artwork
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50 * scale, height: 50 * scale)
                        Text(verbatim: animal.localizedName)
                            .font(.system(size: 11 * textScale, weight: .bold, design: .rounded))
                            .foregroundStyle(character.deepColor)
                    }
                }
            }
        }
        .padding(12 * scale)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var buttons: some View {
        VStack(spacing: 12 * scale) {
            Button(action: onPlayAgain) {
                Label("game.end.playAgain", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 20 * textScale, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17 * scale)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(colors: [character.color, character.deepColor],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("play-again")

            Button(action: onExit) {
                Label("game.end.mainMenu", systemImage: "house.fill")
                    .font(.system(size: 18 * textScale, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17 * scale)
                    .foregroundStyle(character.deepColor)
                    .background(character.skyColor, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(character.color.opacity(0.24), lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("back-to-menu")
        }
    }
}

/// A swarm of flies for a new personal best: the reward the whole game is
/// played for rises up over the card, wandering the way flies actually do,
/// instead of the bubble rain this used to shower.
private struct FlySwarmCelebration: View {
    let color: Color

    @State private var flies: [CelebrationFly]
    @State private var startedAt = Date()
    /// Every fly is drawn from the elapsed time, so once the last one has left
    /// the top edge there is nothing further to redraw and the clock can stop.
    @State private var hasSettled = false

    init(color: Color) {
        self.color = color
        // Enough to read as a swarm, few enough to leave the card readable
        // underneath it.
        _flies = State(initialValue: (0..<16).map { _ in CelebrationFly() })
    }

    /// When the slowest fly is gone, plus a moment's margin.
    private var span: Double {
        (flies.map { $0.delay + $0.riseDuration }.max() ?? 0) + 0.2
    }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: hasSettled)) { context in
                let elapsed = context.date.timeIntervalSince(startedAt)
                ZStack {
                    ForEach(flies) { fly in
                        CelebrationFlyView(fly: fly, elapsed: elapsed,
                                           area: proxy.size, color: color)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(nanoseconds: UInt64(span * 1_000_000_000))
            guard !Task.isCancelled else { return }
            hasSettled = true
        }
    }
}

private struct CelebrationFly: Identifiable {
    let id = UUID()
    /// Share of the width the fly climbs around.
    let x = CGFloat.random(in: 0.06...0.94)
    let size = CGFloat.random(in: 15...30)
    let riseDuration = Double.random(in: 2.0...3.1)
    let delay = Double.random(in: 0...0.95)
    /// How far it wanders sideways, and how many times it crosses back over on
    /// the way up. The two together are what make the climb read as a fly's
    /// path rather than a balloon's.
    let sway = CGFloat.random(in: 24...62)
    let waves = Double.random(in: 1.3...2.5)
    let phase = Double.random(in: 0...(2 * .pi))
    /// Wingbeat, in beats per second: fast enough to blur, slow enough that the
    /// body still visibly bobs with it.
    let beat = Double.random(in: 15...21)
}

private struct CelebrationFlyView: View {
    let fly: CelebrationFly
    let elapsed: TimeInterval
    let area: CGSize
    let color: Color

    var body: some View {
        let t = (elapsed - fly.delay) / fly.riseDuration

        if t >= 0, t <= 1 {
            let angle = t * fly.waves * 2 * .pi + fly.phase
            // The climb is linear: a fly holds its speed, it does not coast to
            // a stop the way a falling bubble did.
            let travel = area.height + fly.size * 2
            let wingPhase = elapsed * fly.beat * 2 * .pi + fly.phase

            CurrencyIcon(size: fly.size)
                // A white copy just behind the fly keeps it legible over both
                // the dark scrim and the light card underneath it.
                .foregroundStyle(.white.opacity(0.5))
                .scaleEffect(1.2)
                .overlay { CurrencyIcon(size: fly.size).foregroundStyle(color) }
                // Wings beating: the body squeezes narrow and springs back.
                .scaleEffect(x: 1 - 0.1 * abs(sin(wingPhase)), y: 1)
                // It banks into each turn rather than sliding sideways flat.
                .rotationEffect(.degrees(cos(angle) * 15))
                .opacity(fade(at: t))
                .position(
                    x: area.width * fly.x + sin(angle) * fly.sway,
                    y: area.height + fly.size - travel * t
                        // A small bob on the wingbeat itself.
                        + sin(wingPhase) * fly.size * 0.05
                )
        }
    }

    /// In as it enters at the bottom, out before it reaches the top edge, so no
    /// fly is ever cut off by the frame.
    private func fade(at t: Double) -> Double {
        if t < 0.12 { return t / 0.12 }
        if t > 0.82 { return (1 - t) / 0.18 }
        return 1
    }
}
