//
//  GameViewModel.swift
//  Elephant Challenge: Math Memory
//
//  The bridge between the pure `MemoryGame` engine and SwiftUI. It owns the
//  timing of a round (sum → answers → feedback → next sum), the audio and
//  haptics, and the persistence of a finished session.
//
//  It never re-implements a rule: every tap is forwarded to the engine, and the
//  engine's answer decides what happens. That is what keeps rapid tapping from
//  scoring twice or costing two lives.
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class GameViewModel: ObservableObject {
    private let request: GameSessionRequest
    private var engine: MemoryGame

    // Published mirrors of the engine, so SwiftUI observes value changes.
    @Published private(set) var state: GameState = .intro
    @Published private(set) var round: GameRound?
    @Published private(set) var roundNumber = 0
    @Published private(set) var cards = 0
    @Published private(set) var livesRemaining = GameConfig.startingLives
    @Published private(set) var selectedOptionID: UUID?
    @Published private(set) var isGameOver = false
    @Published private(set) var result = SessionResult()
    @Published private(set) var hasBonusFishPower = false
    @Published private(set) var correctStreak = 0
    @Published private(set) var isStreakBoostActive = false
    @Published private(set) var isHeartFishAvailable = false
    /// Changes each time the streak boost starts, allowing the view to replay
    /// its bubble-style announcement even after an earlier streak was broken.
    @Published private(set) var streakAnnouncementID = 0

    /// Invalidates pending timed work when a round is superseded (restart, or
    /// leaving the screen), so a late callback can never touch a newer round.
    private var generation = 0
    private var hasRecordedResult = false
    private var isPaused = false
    /// A round-resolution callback that became due while the pause card was
    /// covering the reef. It runs once on continue instead of behind the card.
    private var pendingScheduledWork: (() -> Void)?

    var maximumRounds: Int { engine.maximumRounds }
    var acceptsInput: Bool { state == .answering && !isPaused }

    init(request: GameSessionRequest) {
        self.request = request
        self.engine = MemoryGame(level: request.level,
                            mixedVariant: request.mixedVariant,
                            mode: request.mode)
    }

    // MARK: - Lifecycle

    /// Starts the level, resuming a paused session when one is waiting.
    func begin() {
        guard engine.state == .intro else { return }
        isPaused = false
        PlaytimeTracker.shared.challengeStarted()
        AppAudio.shared.setGameplayActive(true, questionText: nil)
        AppAudio.shared.playSessionStart()
        if let paused = PausedSessionStore.shared.session(request.board) {
            engine.resume(from: paused)
            hasBonusFishPower = paused.hasBonusFishPower ?? false
        } else {
            engine.start()
        }
        openRound()
        announceRound()
        sync()
    }

    /// Opens a round for play. Under water there is nothing to memorise: the
    /// sum stands on the coral from the first frame, so the round goes straight
    /// through to accepting an answer.
    private func openRound() {
        engine.turnCardsOver()
        engine.beginAnswering()
    }

    private func announceRound() {
        AppAudio.shared.playCardReveal()
    }

    func end() {
        // Leaving without finishing pauses the level rather than discarding it.
        savePausedSessionIfNeeded()
        recordResultIfNeeded()
        PlaytimeTracker.shared.challengeEnded()
        AppAudio.shared.setGameplayActive(false, questionText: nil)
        AppAudio.shared.setGameplayRate(1)
        generation &+= 1
        pendingScheduledWork = nil
    }

    /// Temporarily stops an active run without ending it. The snapshot also
    /// makes the same run available if the player chooses the main menu from
    /// the pause card instead of continuing immediately.
    func pause() {
        guard engine.state != .gameOver else { return }
        isPaused = true
        savePausedSessionIfNeeded()
        PlaytimeTracker.shared.challengeEnded()
        AppAudio.shared.setGameplayActive(false, questionText: nil)
        AppAudio.shared.setGameplayRate(1)
    }

    /// Continues the in-memory run after its pause card. No round is rebuilt,
    /// so the player returns to the exact question, score and remaining lives.
    func resume() {
        guard engine.state != .intro, engine.state != .gameOver else { return }
        isPaused = false
        PlaytimeTracker.shared.challengeStarted()
        AppAudio.shared.setGameplayActive(true, questionText: nil)
        AppAudio.shared.setGameplayRate(isStreakBoostActive
                                        ? Float(GameConfig.streakSpeedMultiplier) : 1)
        let work = pendingScheduledWork
        pendingScheduledWork = nil
        work?()
    }

    /// The close button: the level is put on pause with its cards intact, and
    /// those cards are banked to the player's total straight away.
    func quit() {
        savePausedSessionIfNeeded()
        engine.quit()
        recordResultIfNeeded()
        sync()
    }

    /// Freezes the session for this level, so re-entering it continues from
    /// here. A finished session has nothing to store and clears the record.
    ///
    /// A run that has not banked a single card is not worth coming back to:
    /// storing it would only put a pause marker on the menu for a level the
    /// player would restart from zero anyway.
    private func savePausedSessionIfNeeded() {
        guard !hasRecordedResult,
              let paused = engine.pausedSession(hasBonusFishPower: hasBonusFishPower)
        else { return }
        guard paused.cards > 0 else {
            PausedSessionStore.shared.clear(request.board)
            return
        }
        PausedSessionStore.shared.save(paused)
    }

    /// Play again always starts a clean run, so any paused record for this
    /// level is spent.
    func restart() {
        generation &+= 1
        hasRecordedResult = false
        isPaused = false
        pendingScheduledWork = nil
        PausedSessionStore.shared.clear(request.board)
        engine = MemoryGame(level: request.level,
                            mixedVariant: request.mixedVariant,
                            mode: request.mode)
        engine.start()
        hasBonusFishPower = false
        streakAnnouncementID = 0
        AppAudio.shared.playSessionStart()
        openRound()
        announceRound()
        sync()
    }

    // MARK: - Round flow

    /// Forwards an answer bubble the fish touched. The engine decides whether
    /// it counts; a touch that arrives while feedback is still playing comes
    /// back as `.ignored` and changes nothing at all. The returned flag tells
    /// the reef whether to burst the bubble.
    @discardableResult
    func select(optionID: UUID) -> Bool {
        let outcome = engine.select(optionID: optionID,
                                    usesBonusFish: hasBonusFishPower)
        guard outcome != .ignored else { return false }
        // Every real interaction advances the playtime clock. Without these the
        // tracker only ever sees one gap from the first touch to the last,
        // which its idle limit then discards — a whole session counting as no
        // time.
        PlaytimeTracker.shared.registerInteraction()
        sync()

        let token = generation
        let delay: Double
        switch outcome {
        case .correct(_, let usedBonusFish, let startedStreak):
            AppAudio.shared.playCorrect()
            if usedBonusFish {
                hasBonusFishPower = false
                AppAudio.shared.playDoubleScore()
            }
            if startedStreak {
                streakAnnouncementID &+= 1
                AppAudio.shared.playDoubleScore()
            }
            haptic(.success)
            delay = GameConfig.nextRoundDelay.correct
        case .wrong(_, let lostHalfLife):
            AppAudio.shared.playWrong()
            if lostHalfLife {
                AppAudio.shared.playHalfLife()
            } else {
                AppAudio.shared.playLifeLost()
            }
            haptic(.error)
            delay = GameConfig.nextRoundDelay.wrong
        case .ignored:
            return false
        }

        schedule(after: delay, token: token) { [weak self] in
            guard let self else { return }
            guard self.engine.finishResolving() else { return }
            let previousRoundID = self.engine.round?.id
            self.engine.advance()
            if self.engine.state == .gameOver {
                self.finishSession()
            } else if self.engine.round?.id != previousRoundID {
                // A new sum is announced and opened. A wrong answer leaves the
                // same sum in place, and play simply resumes.
                self.announceRound()
                self.openRound()
            }
            self.sync()
        }
        return true
    }

    /// Called by the reef when the player catches the passing 2x fish. Multiple
    /// catches do not stack: one aura always represents one doubled answer.
    func catchBonusFish() {
        guard !hasBonusFishPower else { return }
        hasBonusFishPower = true
        AppAudio.shared.playDoubleCardAppear()
        haptic(.rigid)
    }

    /// The heart fish is a direct life reward, not a power held for the next
    /// answer, so the engine applies it immediately.
    @discardableResult
    func catchHeartFish() -> Bool {
        let restoredHalves = engine.catchHeartFish()
        guard restoredHalves > 0 else { return false }
        PlaytimeTracker.shared.registerInteraction()
        sync()
        AppAudio.shared.playLifeRestored()
        haptic(.success)
        return true
    }

    func missHeartFish() {
        engine.missHeartFish()
        sync()
    }

    // MARK: - Finishing

    private func finishSession() {
        AppAudio.shared.setGameplayRate(1)
        recordResultIfNeeded()
    }

    /// Writes the session to disk exactly once, whichever way the screen is
    /// left: game over, the close button, or a swipe away.
    private func recordResultIfNeeded() {
        guard engine.state == .gameOver, !hasRecordedResult else { return }
        hasRecordedResult = true
        // A level that reached its end is finished, not paused.
        if engine.gameOverReason != .quit {
            PausedSessionStore.shared.clear(request.board)
        }

        let store = Progress.store
        let previousTotal = store.totalCards
        let newTotal = store.addCards(engine.cards)
        // The score belongs to the board this session was played on: the card
        // count, and on Supermix the combination, keep separate bests.
        let board = request.board
        let best = store.recordScore(engine.cards, board: board)
        let unlocked = CharacterUnlocks.newlyUnlocked(from: previousTotal, to: newTotal)

        // Reaching this board's maximum is tallied every time, which is what
        // the ×N badge on a completed card counts.
        let maximum = board.maximum
        if engine.cards >= maximum {
            store.recordMaxCompletion(board)
        }

        engine.applyProgressOutcome(previousBest: best.previousBest,
                                    isNewPersonalBest: best.isNewBest,
                                    unlockedCharacterIDs: unlocked)

        ReviewRequestCoordinator.shared.recordCompletedGame(
            isNewHighScore: best.isNewBest,
            score: engine.cards,
            maximumScore: maximum
        )

        // Leaving a level part-way through is not an achievement: the pause
        // button banks the cards quietly, with no end-of-session fanfare.
        if engine.gameOverReason != .quit {
            if best.isNewBest && engine.cards > 0 { AppAudio.shared.playHighScore() }
            else { AppAudio.shared.playSessionComplete() }
        }
        result = engine.result
    }

    // MARK: - Plumbing

    /// Copies the engine's state onto the published properties in one pass, so
    /// a single tap causes exactly one SwiftUI update rather than eight.
    private func sync() {
        state = engine.state
        round = engine.round
        roundNumber = engine.roundNumber
        cards = engine.cards
        livesRemaining = engine.livesRemaining
        selectedOptionID = engine.selectedOptionID
        // Publish the completed result before the game-over flag. GameView
        // uses its reason to decide whether to play the reef finale first.
        if engine.state == .gameOver { result = engine.result }
        isGameOver = engine.state == .gameOver
        correctStreak = engine.correctStreak
        isStreakBoostActive = engine.isStreakBoostActive
        isHeartFishAvailable = engine.isHeartFishAvailable
        AppAudio.shared.setGameplayRate(isStreakBoostActive
                                        ? Float(GameConfig.streakSpeedMultiplier) : 1)
    }

    /// Runs `work` after a delay, unless the session moved on in the meantime.
    private func schedule(after delay: Double, token: Int, work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == token else { return }
            guard !self.isPaused else {
                self.pendingScheduledWork = work
                return
            }
            work()
        }
    }

    private enum Haptic { case light, rigid, success, error }

    private func haptic(_ kind: Haptic) {
#if canImport(UIKit)
        switch kind {
        case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .rigid: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
#endif
    }
}
