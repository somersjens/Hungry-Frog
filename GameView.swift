//
//  GameView.swift
//  Math Memory
//
//  The playing surface. A round runs on the reef: the sum stands on a piece of
//  coral on the sea floor, the coral lets answer bubbles up through the water,
//  and the player steers a fish into the bubble carrying the right answer.
//
//  All rules live in `MemoryGame` and the whole of the reef lives in
//  `ReefGame.swift`; this file only puts the HUD, the reef and the helper
//  together and hands every touched answer straight to the engine, which is the
//  single place that decides whether it counts.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Everything a session needs to start: which level to draw questions from and
/// how many answer cards each round lays out.
struct GameSessionRequest: Identifiable {
    let level: MathLevel
    /// Only meaningful for Supermix levels; every other topic has one operation.
    var mixedVariant: MixedVariant = .all
    /// Which of the three order buttons was chosen. Supermix ignores it.
    var mode: PracticeMode = .mixed
    var id: String { "\(level.id).\(mixedVariant.rawValue).\(mode.rawValue)" }

    /// The scoreboard this session plays on.
    var board: LevelBoard {
        LevelBoard(level: level, mixedVariant: mixedVariant, mode: mode)
    }
}

struct GameView: View {
    let request: GameSessionRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var premium = PremiumStore.shared
    @ObservedObject private var language = LanguageManager.shared
    @StateObject private var model: GameViewModel

    /// The window's safe area, sampled once the view is on screen — never from
    /// inside `body`; see `ScreenSafeArea`.
    @State private var screenInsets = ScreenSafeArea()

    /// The level's start card, shown before the first round and dismissed by
    /// the player. The session only begins once it is gone.
    @State private var showsIntro = true
    /// The same card doubles as the in-level pause screen. Keeping this state
    /// separate from `showsIntro` lets a brand-new run still say Start while a
    /// pause made before the first answer already says Continue.
    @State private var showsPauseCard = false
    /// After the card, the fish gets the stage to itself for one short looping
    /// entrance. The first round only opens when that animation is finished.
    @State private var playsFishEntrance = false
    /// A completed board gets one last moment in the reef before its result
    /// card appears. Other endings (no lives, or leaving) remain immediate.
    @State private var playsLevelCompletion = false
    @State private var showsResult = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(request: GameSessionRequest) {
        self.request = request
        _model = StateObject(wrappedValue: GameViewModel(request: request))
    }

    private var character: AnimalCharacter { CharacterCatalog.current(isPremium: premium.isPremium) }
    private var isPad: Bool { AppLayout.isPad }

    var body: some View {
        ZStack {
            LinearGradient(colors: [character.skyColor, character.tintColor],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // The level's own wallpaper used to sit here. The pond fills the
            // whole screen opaquely on top of it, so all it ever contributed
            // was a screenful of glyph layers for the compositor to blend away
            // behind the playfield on every single frame.

            // Keep the level visible underneath every card. The result is an
            // overlay over the reef that was just played, exactly like the
            // start and pause cards, rather than a replacement for the game.
            playfield
                .transition(.opacity)

            if showsResult {
                ResultView(result: model.result,
                           board: request.board,
                           character: character,
                           onPlayAgain: {
                               showsResult = false
                               playsLevelCompletion = false
                               model.restart()
                           },
                           onExit: { dismiss() })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(1)
            }

            if showsIntro {
                LevelIntroCard(board: request.board,
                               theme: character,
                               isPauseCard: showsPauseCard,
                               onStart: startSession,
                               onExit: { dismiss() })
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        // What the level fills with is what the HUD counts and what the
        // celebrations rain down, all the way through the start card, the
        // playfield and the result card.
        .currencyIcon(for: character)
        .animation(.easeInOut(duration: 0.28), value: model.isGameOver)
        .animation(.easeInOut(duration: 0.25), value: showsIntro)
        .onAppear { screenInsets = ScreenSafeArea.current }
        .onChange(of: model.isGameOver) { _, isOver in
            guard isOver else {
                showsResult = false
                playsLevelCompletion = false
                return
            }
            if model.result.reason == .roundsCompleted {
                playsLevelCompletion = true
            } else {
                showsResult = true
            }
        }
        .onDisappear { model.end() }
    }

    private func startSession() {
        showsIntro = false
        if showsPauseCard, model.state != .intro {
            showsPauseCard = false
            model.resume()
        } else {
            showsPauseCard = false
            playsFishEntrance = true
        }
    }

    private func finishFishEntrance() {
        guard playsFishEntrance else { return }
        playsFishEntrance = false
        model.begin()
    }

    // MARK: - Playfield

    private var playfield: some View {
        // The reef is the whole screen — water from the very top edge down to
        // the sea floor at the very bottom — with the HUD laid over it. Reading
        // the insets here is what keeps the fish clear of the HUD and the sum
        // clear of the home indicator.
        // The HUD keeps a floor under it, so it still clears the status bar on
        // the very first frame, before the insets have been sampled.
        let topInset = max(screenInsets.top, isPad ? 24 : 16)

        return GeometryReader { proxy in
            // On an iPad held in portrait the HUD row and the sum card both
            // want the top-right corner: the row is wide (bigger controls,
            // bigger type) and the sum card is pinned to the right regardless
            // of width. Splitting the double-points chip onto a row of its
            // own keeps the primary row short enough to leave the card clear,
            // rather than letting the two fight over the same strip.
            let isPortraitPad = isPad && proxy.size.height > proxy.size.width
            let hudExtraReserve: CGFloat = isPortraitPad ? hudControlSize + hudRowSpacing : 0

            ZStack(alignment: .top) {
                FlyPlayfield(rounds: model.visibleRounds,
                              maximumRounds: model.maximumRounds,
                              character: character,
                              isPad: isPad,
                              isLive: model.acceptsInput,
                              isRunning: isReefRunning,
                              playsFishEntrance: playsFishEntrance,
                              playsLevelCompletion: playsLevelCompletion,
                              reduceMotion: reduceMotion,
                              // The HUD's own height, so the swarm's ceiling is
                              // the underside of the HUD and never the status bar
                              // or the Dynamic Island behind it. Taller still when
                              // the double-points chip drops to its own row.
                              topReserve: topInset + (isPad ? 64 : 50) + hudExtraReserve,
                              bottomReserve: screenInsets.bottom,
                              onHit: { model.select(optionID: $0) },
                              onImpact: { AppAudio.shared.playSplash() },
                              onSwallow: { model.reportCatchOutcome(isCorrect: $0) },
                              onFishEntranceComplete: finishFishEntrance,
                              onLevelCompletionFinished: finishLevelCompletion)

                hud(isPortraitPad: isPortraitPad)
                    .padding(.horizontal, isPad ? 28 : 16)
                    .padding(.top, topInset + (isPad ? 12 : 6))
                    .opacity(playsLevelCompletion ? 0 : 1)
                    .animation(.easeOut(duration: 0.22), value: playsLevelCompletion)
                    .allowsHitTesting(!playsLevelCompletion)

                if model.comboAnnouncementID > 0 {
                    ComboFlyBanner(token: model.comboAnnouncementID,
                                   character: character,
                                   isPad: isPad)
                        .padding(.top, topInset + (isPad ? 116 : 88) + hudExtraReserve)
                        .allowsHitTesting(false)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func finishLevelCompletion() {
        guard playsLevelCompletion else { return }
        withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
            showsResult = true
        }
        // Keep the final bubble bloom under the card during its entrance so
        // there is never a flash of the bare playfield between both scenes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            playsLevelCompletion = false
        }
    }

    // MARK: - HUD

    /// On every layout but an iPad in portrait, the double-points chip shares
    /// the top row with the pause button, the counter and the hearts. An iPad
    /// in portrait doesn't have the width to spare — that row is pinned next
    /// to the sum card — so the chip drops to a row of its own underneath.
    private func hud(isPortraitPad: Bool) -> some View {
        Group {
            if isPortraitPad {
                VStack(alignment: .leading, spacing: hudRowSpacing) {
                    primaryHudRow
                    if let deadline = model.boostDeadline {
                        HStack(spacing: 0) {
                            doublePointsChip(deadline: deadline)
                            Spacer(minLength: 0)
                        }
                    }
                }
            } else {
                HStack(spacing: hudRowSpacing) {
                    primaryHudRow
                    if let deadline = model.boostDeadline {
                        doublePointsChip(deadline: deadline)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.62),
                   value: model.boostDeadline)
    }

    @ViewBuilder
    private var primaryHudRow: some View {
        pauseButton
        progressCounter
        LivesView(lives: model.livesRemaining,
                  character: character,
                  isPad: isPad,
                  glyphSize: hudHeartSize,
                  rowHeight: hudControlSize)
            .padding(.horizontal, isPad ? 12 : 10)
    }

    private func doublePointsChip(deadline: Date) -> some View {
        DoublePointsChip(deadline: deadline,
                          token: model.streakAnnouncementID,
                          character: character,
                          isPad: isPad,
                          height: hudControlSize)
            .transition(.scale(scale: 0.4).combined(with: .opacity))
    }

    private var hudRowSpacing: CGFloat { isPad ? 10 : 8 }

    /// Pausing freezes the reef in place and puts the level card over it. The
    /// player can continue immediately or leave for the main menu from there.
    private var pauseButton: some View {
        Button {
            AppAudio.shared.playMenuTap()
            model.pause()
            showsPauseCard = true
            showsIntro = true
        } label: {
            Circle()
                .fill(character.deepColor)
                .frame(width: hudControlSize, height: hudControlSize)
                .overlay {
                    Image(systemName: "pause.fill")
                        .font(.system(size: pauseGlyphSize, weight: .bold))
                        .foregroundStyle(.white)
                }
                .overlay {
                    Circle().stroke(.white.opacity(0.92), lineWidth: 3)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pause")
        .accessibilityLabel(Text("game.pause"))
    }

    /// Every status capsule shares one comfortable touch height, while the
    /// symbols retain enough breathing room to stay legible over the pond.
    private var hudControlSize: CGFloat { isPad ? 52 : 44 }
    private var hudSymbolSize: CGFloat { isPad ? 34 : 26 }
    private var hudHeartSize: CGFloat { isPad ? 30 : 24 }
    private var pauseGlyphSize: CGFloat { isPad ? 24 : 20 }
    private var hudNumberSize: CGFloat { isPad ? 30 : 23 }

    /// Just the bubbles banked this session. What the board holds is quoted on
    /// the start card and again on the result card, so the playing field does
    /// not have to carry it too.
    private var progressCounter: some View {
        HStack(alignment: .center, spacing: isPad ? 7 : 5) {
            Text(verbatim: "\(model.cards)")
                .font(.system(size: hudNumberSize, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(model.cards)))
            ZStack {
                CurrencyIcon(size: hudSymbolSize)
                    .foregroundStyle(.white.opacity(0.85))
                    .scaleEffect(1.22)
                CurrencyIcon(size: hudSymbolSize)
            }
        }
        .padding(.horizontal, isPad ? 13 : 11)
        .frame(height: hudControlSize, alignment: .center)
        .foregroundStyle(character.deepColor)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.cards)
        .accessibilityIdentifier("progress")
        // Named after what this character actually collects, in the app's
        // language — the counter has not been flies-for-everyone since each
        // animal got its own food.
        .accessibilityLabel(Text(verbatim: "\(model.cards) "
                                 + FoodCatalog.word(for: character.id, count: model.cards)))
    }

    /// The reef only ticks while the level is actually being played: never
    /// behind the start card or the result card, and never while the app is in
    /// the background.
    private var isReefRunning: Bool {
        !showsIntro && (!model.isGameOver || playsLevelCompletion) && scenePhase == .active
    }
}

private struct ComboFlyBanner: View {
    let token: Int
    let character: AnimalCharacter
    let isPad: Bool
    @State private var visible = false

    var body: some View {
        Text("Combo! +1")
            .font(.system(size: isPad ? 22 : 17, weight: .black, design: .rounded))
            .foregroundStyle(character.deepColor)
            .padding(.horizontal, isPad ? 18 : 14)
            .padding(.vertical, isPad ? 9 : 7)
            .background(.white.opacity(0.92), in: Capsule())
            .scaleEffect(visible ? 1 : 0.65)
            .opacity(visible ? 1 : 0)
            .onAppear { animate() }
            .onChange(of: token) { _, _ in animate() }
    }

    private func animate() {
        visible = false
        withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) { visible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            withAnimation(.easeOut(duration: 0.2)) { visible = false }
        }
    }
}

/// The double-points window, in the HUD next to the score it is doubling.
///
/// It sits in the top row rather than over the pond on purpose: the reward has
/// to be unmissable, but the question and the swarm underneath it are what the
/// child is actually working with, and a banner across them would cost more
/// time than the boost gives back.
private struct DoublePointsChip: View {
    let deadline: Date
    /// Bumped on every fifth correct answer, so a window renewed while it is
    /// still running replays the flash instead of quietly resetting its ring.
    let token: Int
    let character: AnimalCharacter
    let isPad: Bool
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flash: CGFloat = 0
    /// True over the last three seconds of the window. Held as state and
    /// animated once rather than recomputed per frame, so the chip's gradient,
    /// stroke and shadow are laid out a single time and the pulse afterwards
    /// costs nothing but a transform.
    @State private var isEnding = false
    @State private var endingWork: DispatchWorkItem?

    private var ringSize: CGFloat { isPad ? 34 : 27 }

    var body: some View {
        // Only the countdown ring is redrawn on a clock (see `CountdownRing`).
        // Wrapping the whole chip in a `TimelineView`, as this used to, rebuilt
        // its gradient, its shadow and a `ViewThatFits` — which lays its
        // contents out twice — twenty times a second, for the entire length of
        // a streak. That is exactly the stretch of play the chip appears in.
        //
        // The ring is a sibling of the `ViewThatFits`, not inside it: only the
        // wording is in question, and a candidate that is merely measured
        // should not be a second live countdown.
        HStack(spacing: isPad ? 9 : 6) {
            // Spelling the reward out is worth the width wherever the HUD has
            // it; where it does not, the multiplier and the ring say the same
            // thing in a third of the space.
            ViewThatFits(in: .horizontal) {
                wording(spellsItOut: true)
                wording(spellsItOut: false)
            }
            CountdownRing(deadline: deadline, size: ringSize, isPad: isPad)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, isPad ? 14 : 11)
        .frame(height: height)
        .background {
            Capsule()
                .fill(LinearGradient(colors: [character.color, character.deepColor],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .overlay {
                    Capsule().stroke(.white.opacity(0.9), lineWidth: 2)
                }
                .shadow(color: character.deepColor.opacity(0.35), radius: 7, y: 3)
        }
        // The last three seconds pulse, so the window closing is felt
        // rather than only read off the number.
        .scaleEffect(isEnding ? 1.06 : 1)
        .overlay {
            Capsule()
                .stroke(.white, lineWidth: 3)
                .scaleEffect(1 + flash * 0.5)
                .opacity(Double(1 - flash))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("game.streakBoost.title"))
        .accessibilityValue(Text(verbatim:
            "\(Int(ceil(max(0, deadline.timeIntervalSinceNow))))s"))
        .onAppear { pulse(); armEndingPulse() }
        .onChange(of: token) { _, _ in pulse() }
        // A window renewed while it is still running pushes the closing pulse
        // back out with it.
        .onChange(of: deadline) { _, _ in armEndingPulse() }
        .onDisappear { endingWork?.cancel() }
    }

    private func wording(spellsItOut: Bool) -> some View {
        HStack(spacing: isPad ? 9 : 6) {
            Text(verbatim: "\(GameConfig.streakMultiplier)×")
                .font(.system(size: isPad ? 26 : 20, weight: .black, design: .rounded))
            if spellsItOut {
                Text("game.streakBoost.title")
                    .font(.system(size: isPad ? 17 : 13, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private func pulse() {
        guard !reduceMotion else { return }
        flash = 0
        withAnimation(.easeOut(duration: 0.55)) { flash = 1 }
    }

    /// Schedules the closing pulse for the moment three seconds are left. The
    /// swell itself is a repeating animation the render server owns, so no
    /// frame of it costs a body evaluation.
    private func armEndingPulse() {
        endingWork?.cancel()
        withTransaction(Transaction(animation: nil)) { isEnding = false }
        guard !reduceMotion else { return }
        let work = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                isEnding = true
            }
        }
        endingWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, deadline.timeIntervalSinceNow - 3),
            execute: work
        )
    }
}

/// A ring that empties over the double-points window, with the whole seconds
/// left in it. The only part of the chip that is on a clock.
private struct CountdownRing: View {
    let deadline: Date
    let size: CGFloat
    let isPad: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { context in
            let remaining = max(0, deadline.timeIntervalSince(context.date))
            let share = min(1, max(0, remaining / GameConfig.streakBoostDuration))
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.32), lineWidth: isPad ? 4 : 3)
                Circle()
                    .trim(from: 0, to: share)
                    .stroke(.white,
                            style: StrokeStyle(lineWidth: isPad ? 4 : 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(verbatim: "\(Int(ceil(remaining)))")
                    .font(.system(size: isPad ? 15 : 12, weight: .heavy, design: .rounded))
                    .monospacedDigit()
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Level wallpaper

/// The level's own quiet wallpaper: a staggered grid of the level's number and
/// sign ("3×", "−4", "25%") or a stacked fraction, in a faint wash of the
/// theme colour. Carried over from the original game.
struct LevelWallpaper: View {
    let level: MathLevel
    let tint: Color

    /// The glyph that fills the wallpaper, built from the level's own card
    /// number so it reads like the level itself. Fractions draw a stacked
    /// fraction instead and return nil here.
    private var glyph: String? {
        let n = level.cardNumber
        switch level.topic {
        case .addition:    return "\(n)+"
        case .subtraction: return "−\(n)"
        case .tables:      return "\(n)×"
        case .percentages: return "\(n)%"
        case .mixed:       return "\(n)★"
        case .fractions:   return nil
        }
    }

    private var isPad: Bool { AppLayout.isPad }
    private var fontSize: CGFloat { isPad ? 30 : 22 }
    private var spacingX: CGFloat { isPad ? 118 : 86 }
    private var spacingY: CGFloat { isPad ? 104 : 76 }

    var body: some View {
        GeometryReader { proxy in
            let columns = Int(ceil(proxy.size.width / spacingX)) + 1
            let rows = Int(ceil(proxy.size.height / spacingY)) + 1

            ZStack {
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<columns, id: \.self) { column in
                        tile
                            .position(
                                // Every other row is offset by half a step, so
                                // the pattern staggers instead of gridding.
                                x: CGFloat(column) * spacingX
                                    + (row.isMultiple(of: 2) ? 0 : spacingX / 2),
                                y: CGFloat(row) * spacingY
                            )
                    }
                }
            }
        }
        .foregroundStyle(tint.opacity(0.10))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var tile: some View {
        if let glyph {
            Text(verbatim: glyph)
                .font(.system(size: fontSize, weight: .heavy, design: .rounded))
        } else {
            // The fraction levels have one denominator each, so the wallpaper
            // mirrors it: 1/3 on the thirds level, and so on.
            VStack(spacing: 1) {
                Text(verbatim: "1")
                Rectangle().frame(height: 2)
                Text(verbatim: level.cardNumber)
            }
            .font(.system(size: fontSize * 0.62, weight: .heavy, design: .rounded))
            .fixedSize()
        }
    }
}

// MARK: - Lives

struct LivesView: View {
    let lives: Double
    let character: AnimalCharacter
    let isPad: Bool
    /// Matches the bubble in the centre of the HUD.
    var glyphSize: CGFloat = 16
    /// Keeps every HUD group centred on the pause button's horizontal axis.
    var rowHeight: CGFloat = 34

    private var wholeHearts: Int { Int(lives.rounded(.down)) }
    private var hasHalf: Bool { lives - Double(wholeHearts) >= 0.5 }
    private var capacity: Int { Int(GameConfig.startingLives.rounded(.up)) }

    /// Hearts wear the character's own deep colour — the same one the counter
    /// and the close button use — rather than a generic red.
    private var heartColor: Color { character.deepColor }

    var body: some View {
        HStack(spacing: isPad ? 5 : 3) {
            ForEach(0..<capacity, id: \.self) { index in
                heart(at: index)
            }
        }
        .frame(height: rowHeight, alignment: .center)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: lives)
        .accessibilityElement()
        .accessibilityIdentifier("lives")
        .accessibilityLabel(Text(L("game.livesRemaining \(livesText)")))
        .accessibilityValue(Text(verbatim: livesText))
    }

    private var livesText: String {
        // Halves read as "2.5"; whole lives never show a decimal tail.
        lives == lives.rounded() ? "\(Int(lives))" : String(format: "%.1f", lives)
    }

    /// A full, half or empty heart. The half heart is the full glyph masked to
    /// its leading half over the empty one, so the two always align exactly.
    private func heart(at index: Int) -> some View {
        let size = glyphSize
        return ZStack {
            // A soft white outline behind every heart, full or empty, so the
            // row stays legible over any part of the pond.
            Image(systemName: "heart.fill")
                .foregroundStyle(.white.opacity(0.85))
                .scaleEffect(1.22)

            Image(systemName: "heart.fill")
                .foregroundStyle(heartColor.opacity(0.22))
            if index < wholeHearts {
                Image(systemName: "heart.fill")
                    .foregroundStyle(heartColor)
            } else if index == wholeHearts && hasHalf {
                Image(systemName: "heart.fill")
                    .foregroundStyle(heartColor)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: size / 2)
                    }
            }
        }
        .font(.system(size: size, weight: .bold))
        .frame(width: size, height: size)
    }
}
