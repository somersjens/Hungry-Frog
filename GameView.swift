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
    @State private var showsStreakBanner = false
    @State private var streakBannerToken = 0
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

            // The level's own wallpaper, exactly as the original game had it.
            LevelWallpaper(level: request.level, tint: character.color)
                .ignoresSafeArea()

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

        return ZStack(alignment: .top) {
            FlyPlayfield(rounds: model.visibleRounds,
                          maximumRounds: model.maximumRounds,
                          character: character,
                          isPad: isPad,
                          isLive: model.acceptsInput,
                          isRunning: isReefRunning,
                          playsFishEntrance: playsFishEntrance,
                          playsLevelCompletion: playsLevelCompletion,
                          reduceMotion: reduceMotion,
                          topReserve: topInset + (isPad ? 54 : 42),
                          bottomReserve: screenInsets.bottom,
                          onHit: { model.select(optionID: $0) },
                          onFishEntranceComplete: finishFishEntrance,
                          onLevelCompletionFinished: finishLevelCompletion)

            hud
                .padding(.horizontal, isPad ? 28 : 16)
                .padding(.top, topInset + (isPad ? 12 : 6))
                .opacity(playsLevelCompletion ? 0 : 1)
                .animation(.easeOut(duration: 0.22), value: playsLevelCompletion)
                .allowsHitTesting(!playsLevelCompletion)

            if showsStreakBanner {
                StreakBoostBanner(character: character, isPad: isPad)
                    .padding(.top, topInset + (isPad ? 70 : 52))
                    .transition(.scale(scale: 0.65).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            if model.comboAnnouncementID > 0 {
                ComboFlyBanner(token: model.comboAnnouncementID,
                               character: character,
                               isPad: isPad)
                    .padding(.top, topInset + (isPad ? 116 : 88))
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .onChange(of: model.streakAnnouncementID) { _, id in
            guard id > 0 else { return }
            showStreakBanner(for: id)
        }
    }

    private func showStreakBanner(for token: Int) {
        streakBannerToken = token
        withAnimation(.spring(response: 0.38, dampingFraction: 0.68)) {
            showsStreakBanner = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            guard streakBannerToken == token else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                showsStreakBanner = false
            }
        }
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

    private var hud: some View {
        HStack(spacing: isPad ? 10 : 8) {
            pauseButton
            progressCounter
            LivesView(lives: model.livesRemaining,
                      character: character,
                      isPad: isPad,
                      glyphSize: hudHeartSize,
                      rowHeight: hudControlSize)
                .padding(.horizontal, isPad ? 12 : 10)
                .background(.white.opacity(0.88), in: Capsule())
                .shadow(color: character.deepColor.opacity(0.12), radius: 5, y: 3)
            Spacer(minLength: 0)
        }
    }

    /// Pausing freezes the reef in place and puts the level card over it. The
    /// player can continue immediately or leave for the main menu from there.
    private var pauseButton: some View {
        Button {
            AppAudio.shared.playMenuTap()
            model.pause()
            showsPauseCard = true
            showsIntro = true
        } label: {
            // Inverted against the rest of the HUD: the disc carries the theme
            // colour and the bars are punched clean out of it, so the playing
            // field shows through where the glyph used to be.
            Circle()
                .fill(character.deepColor)
                .frame(width: hudControlSize, height: hudControlSize)
                .overlay {
                    Image(systemName: "pause.fill")
                        .font(.system(size: pauseGlyphSize, weight: .bold))
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
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
            FlyCurrencyIcon(size: hudSymbolSize)
        }
        .padding(.horizontal, isPad ? 13 : 11)
        .frame(height: hudControlSize, alignment: .center)
        .background(.white.opacity(0.88), in: Capsule())
        .shadow(color: character.deepColor.opacity(0.12), radius: 5, y: 3)
        .foregroundStyle(character.deepColor)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.cards)
        .accessibilityIdentifier("progress")
        .accessibilityLabel(Text(verbatim: "\(model.cards) vliegen"))
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

private struct StreakBoostBanner: View {
    let character: AnimalCharacter
    let isPad: Bool

    var body: some View {
        HStack(spacing: isPad ? 10 : 7) {
            Image(systemName: "flame.fill")
            VStack(spacing: 0) {
                Text("game.streakBoost.title")
                    .font(.system(size: isPad ? 22 : 17, weight: .black, design: .rounded))
                Text("game.streakBoost.subtitle")
                    .font(.system(size: isPad ? 14 : 11, weight: .bold, design: .rounded))
                    .opacity(0.82)
            }
            Image(systemName: "forward.fill")
        }
        .foregroundStyle(character.deepColor)
        .padding(.horizontal, isPad ? 20 : 15)
        .padding(.vertical, isPad ? 12 : 9)
        .background {
            Capsule()
                .fill(.white.opacity(0.92))
                .overlay {
                    Capsule().stroke(.white, lineWidth: 2)
                }
                .shadow(color: character.deepColor.opacity(0.22), radius: 9, y: 5)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(.white.opacity(0.8))
                .frame(width: 10, height: 10)
                .offset(x: 18, y: 10)
        }
        .accessibilityElement(children: .combine)
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
