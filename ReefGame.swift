//
//  ReefGame.swift
//  Number Reef
//
//  The reef playing surface: the sum sits on a piece of coral on the sea floor,
//  the coral releases answer bubbles at irregular intervals, and the player
//  steers a fish into the bubble carrying the right answer.
//
//  This file holds the whole of the new gameplay and nothing else. Every rule
//  about scoring, lives, rounds and progress still lives in `MemoryGame`; this
//  scene only decides *when* an answer is touched and hands that answer over.
//  Wrong bubbles are free to drift off the top of the screen — reaching them is
//  never required.
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Screen edges

/// The window's own safe area. The reef is laid out edge to edge, so it needs
/// the real insets to keep the sum clear of the home indicator and the fish
/// clear of the HUD — and a `GeometryReader` nested inside the playing field
/// reports zero for them, because its container has already been inset.
///
/// Sample this in `onAppear` and keep the value in state. Reading it from
/// inside a `body` wedges SwiftUI's update pass: the view renders once and then
/// stops receiving updates entirely, which shows up as a frozen playing field
/// with no sum on the coral.
struct ScreenSafeArea: Equatable {
    var top: CGFloat = 0
    var bottom: CGFloat = 0

    @MainActor
    static var current: ScreenSafeArea {
#if canImport(UIKit)
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        guard let insets = window?.safeAreaInsets else { return ScreenSafeArea() }
        return ScreenSafeArea(top: insets.top, bottom: insets.bottom)
#else
        return ScreenSafeArea()
#endif
    }
}

// MARK: - Tuning

/// Every tunable number of the reef scene, kept together the way `GameConfig`
/// keeps the session's.
enum ReefConfig {
    /// Simulation step. The scene is driven by one timer at this rate.
    static let tick = 1.0 / 60.0

    // MARK: Bubbles

    static func bubbleDiameter(isPad: Bool) -> CGFloat { isPad ? 118 : 88 }

    /// Rise speed, in points per second. Slow enough to read the answer and to
    /// steer around it, quick enough that a wrong bubble leaves on its own.
    static let riseSpeed: ClosedRange<CGFloat> = 68...84
    /// Sideways sway, so no two bubbles share a path.
    static let driftAmplitude: ClosedRange<CGFloat> = 6...22
    static let driftPeriod: ClosedRange<Double> = 2.4...4.4

    /// Gap between two releases. Irregular, but short enough that a quick
    /// player does not spend most of a round waiting for the next answer.
    static let spawnGap: ClosedRange<Double> = 1.5...2.35
    /// Now and then two bubbles follow each other closely, which is what breaks
    /// the rhythm; `closeGapChance` decides how often.
    static let closeGap: ClosedRange<Double> = 0.75...1.05
    static let closeGapChance = 0.32
    /// A breather before the coral starts over with the same set of answers.
    static let waveGap: ClosedRange<Double> = 2.4...3.2
    /// Delay before the very first bubble of a round, so the sum can be read.
    static let firstGap: ClosedRange<Double> = 0.55...0.85
    /// Retry delay when there is no room to release a bubble yet.
    static let blockedGap = 0.25

    /// Chance that the correct answer occupies each successive place in a
    /// fresh five-bubble wave. This favours an early answer without making its
    /// arrival predictable: first 35%, then 30%, 20%, 10% and 5%.
    static let correctAnswerPositionWeights = [35, 30, 20, 10, 5]

    /// Most bubbles allowed in the water at once — a whole set of answers, so
    /// every one of them can be up there together. Crowding is not left to this
    /// number alone: a release still needs a crater with room above it, so the
    /// water thins itself out when the bubbles bunch up.
    static let maximumLiveBubbles = GameConfig.answerBubbleCount
    /// Least horizontal distance between a new bubble and one still near the
    /// coral, as a share of the bubble diameter.
    static let separationFactor: CGFloat = 1.06
    /// A new bubble also leaves this much of a gap from the previous vent, so
    /// they do not stream out of one spot.
    static let ventSpreadFactor: CGFloat = 0.55
    /// How far above the coral a bubble still counts as "in the way" when the
    /// next release looks for a free spot.
    static let crowdBandFactor: CGFloat = 1.7

    /// How long a burst stays on screen after a bubble is touched or burned.
    static let popDuration = 0.26
    /// A bubble starts as a speck in its crater and swells to full size as it
    /// leaves, the way a real one does.
    static let emergeDuration = 0.55
    /// Size it starts at, as a share of full.
    static let emergeStartScale = 0.14

    // MARK: Fish

    static func fishLength(isPad: Bool) -> CGFloat { isPad ? 96 : 72 }
    /// Body radius used for touches, a little inside the artwork so a near miss
    /// reads as a miss.
    static let fishHitFactor: CGFloat = 0.30
    /// Bubbles are forgiving by the same margin, so contact matches what is on
    /// screen.
    static let bubbleHitFactor: CGFloat = 0.46

    /// Ceiling on the fish's speed, in points per second.
    static let fishMaximumSpeed: CGFloat = 620
    /// How eagerly the fish closes the remaining distance. Higher is snappier;
    /// this is the balance between "responds at once" and "glides".
    static let fishApproach: CGFloat = 7.0
    /// Below this distance the fish holds still, so a resting finger does not
    /// make it jitter.
    static let fishDeadzone: CGFloat = 7
    /// How quickly the fish swings round to face where it is going.
    static let fishTurnRate: Double = 9.0

    /// The opening swim curls inward from beyond the right edge before the
    /// first answer is released. Long enough to read as an entrance, without
    /// making a child wait to play.
    static let fishEntranceDuration = 1.85
    /// Opens the first round just before the fish settles, so the crown of its
    /// first bubble can already peek out as the entrance finishes.
    static let fishEntranceAnswerLead = 0.90

    // MARK: Level completion

    /// A compact finale: gather, draw the heart, then let the bubbles fill the
    /// water before the result card arrives.
    static let completionDuration = 3.45
    static let completionGatherDuration = 0.55
    static let completionHeartDuration = 2.45

    /// The tail sheds short underwater eddies rather than surface-like rings.
    /// Tiny air pockets live a little longer so they can peel away and rise.
    static let wakeLifetime = 0.78
    static let miniBubbleLifetime = 1.05
    static let wakeInterval = 0.075

    /// After a touch, no second answer can be taken for this long — one bump
    /// can never select two bubbles.
    static let collisionCooldown = 0.22

    // MARK: Decorative air bubbles

    static let ambientBubbleGap: ClosedRange<Double> = 0.32...0.72
    static let ambientBubbleSpeed: ClosedRange<CGFloat> = 28...54
    static let ambientBubbleRadius: ClosedRange<CGFloat> = 3.5...9
    static let maximumAmbientBubbles = 18
    static let ambientBubblePopDuration = 0.24

    // MARK: 2x fish

    static func bonusFishLength(isPad: Bool) -> CGFloat { isPad ? 82 : 62 }
    /// Slow enough to notice and intercept, while still clearly being a
    /// passing power-up rather than another answer bubble.
    static let bonusFishSpeed: ClosedRange<CGFloat> = 155...190
    /// After one of the preselected questions appears, this little extra delay
    /// keeps the exact arrival surprising and independent of answer releases.
    static let bonusFishQuestionDelay: ClosedRange<Double> = 2.0...5.0
    static let bonusFishPopDuration = 0.32

    // MARK: Heart fish

    static func heartFishLength(isPad: Bool) -> CGFloat { isPad ? 88 : 66 }
    /// Slightly slower than the 2x fish: this reward follows eight correct
    /// answers and should be an attainable comeback opportunity.
    static let heartFishSpeed: ClosedRange<CGFloat> = 125...155
    static let heartFishDelay: ClosedRange<Double> = 1.5...3.5
    static let heartFishPopDuration = 0.36

    // MARK: Sea floor

    /// How far the reef block sits above the bottom edge, on top of whatever
    /// the home indicator already reserves.
    static func floorInset(isPad: Bool) -> CGFloat { isPad ? 26 : 18 }
    /// The doorway the sum is written in.
    static func doorHeight(isPad: Bool) -> CGFloat { isPad ? 86 : 68 }
    /// The coral rim on top of the doorway, which the craters are set into.
    static func craterRimHeight(isPad: Bool) -> CGFloat { isPad ? 24 : 18 }
    /// How much of the reef block the coral sides take, so the sum never runs
    /// edge to edge and the mound stays visible beside it.
    static func blockInset(isPad: Bool) -> CGFloat { isPad ? 72 : 28 }
    /// How far inside the block the outermost crater sits.
    static func craterInset(isPad: Bool) -> CGFloat { isPad ? 44 : 32 }

    /// Everything from the crest down: rim, sum and sea floor.
    static func bandHeight(isPad: Bool, bottomReserve: CGFloat) -> CGFloat {
        floorInset(isPad: isPad) + bottomReserve
            + doorHeight(isPad: isPad) + craterRimHeight(isPad: isPad)
    }
    /// The sand runs off the bottom of the screen, so the floor never ends in
    /// a visible edge, and its crown rises either side of the reef block.
    static func sandHeight(isPad: Bool, bottomReserve: CGFloat) -> CGFloat {
        floorInset(isPad: isPad) + bottomReserve + (isPad ? 118 : 92)
    }
    /// Margin between a bubble and the side of the screen.
    static func sideInset(isPad: Bool) -> CGFloat { isPad ? 12 : 8 }

    /// The coral has a fixed set of craters, and every bubble comes out of one
    /// of them. Fixing the positions is what lets the craters actually be drawn
    /// where the bubbles appear.
    static let craterCount = 5

    static func craterPositions(width: CGFloat, isPad: Bool) -> [CGFloat] {
        let inset = blockInset(isPad: isPad) + craterInset(isPad: isPad)
        let minX = inset
        let maxX = max(minX, width - inset)
        guard craterCount > 1, maxX > minX else { return [(minX + maxX) / 2] }
        return (0..<craterCount).map {
            minX + (maxX - minX) * CGFloat($0) / CGFloat(craterCount - 1)
        }
    }

    // MARK: Ambience

    /// Specks of drifting plankton, purely decorative. They freeze with the
    /// rest of the scene when the game is paused.
    static let moteCount = 16
    static let moteSpeed: ClosedRange<CGFloat> = 8...22
    static let moteRadius: ClosedRange<CGFloat> = 1.5...4.5
}

// MARK: - Palette

/// The reef's colours. Each one starts from the player's own character colours
/// and is pulled toward the sea, so a fox reef and a penguin reef are still
/// recognisably theirs while both read as water.
struct ReefPalette {
    let character: AnimalCharacter

    private static let surface = (0.60, 0.87, 0.95)
    private static let depth = (0.10, 0.45, 0.66)
    private static let sandTone = (0.96, 0.90, 0.74)
    private static let sandShadow = (0.80, 0.68, 0.46)

    var waterTop: Color { Self.mix(character.skyRGB, Self.surface, 0.72) }
    var waterDeep: Color { Self.mix(character.primaryRGB, Self.depth, 0.85) }
    var sand: Color { Self.mix(character.tintRGB, Self.sandTone, 0.72) }
    var sandDeep: Color { Self.mix(character.deepRGB, Self.sandShadow, 0.62) }

    /// The coral keeps the character's own colour: it is the one warm thing on
    /// the reef, and it is what the sum stands on.
    var coral: Color { character.color }
    var coralDeep: Color { character.deepColor }
    var plant: Color { Color(red: 0.18, green: 0.56, blue: 0.34) }
    var plantLight: Color { Color(red: 0.43, green: 0.72, blue: 0.30) }

    private static func mix(_ base: (Double, Double, Double),
                            _ target: (Double, Double, Double),
                            _ amount: Double) -> Color {
        let t = min(max(amount, 0), 1)
        return Color(red: base.0 + (target.0 - base.0) * t,
                     green: base.1 + (target.1 - base.1) * t,
                     blue: base.2 + (target.2 - base.2) * t)
    }
}

// MARK: - Model

/// One answer bubble on its way up.
struct ReefBubble: Identifiable {
    let id = UUID()
    /// The engine's option, which is what a touch reports back.
    let optionID: UUID
    let text: String
    let isCorrect: Bool
    let diameter: CGFloat

    /// Centre of the sway, and the current position around it.
    let baseX: CGFloat
    var position: CGPoint
    let speed: CGFloat
    let driftAmplitude: CGFloat
    let driftPeriod: Double
    let phase: Double

    var age: Double = 0
    /// Set the moment the bubble bursts; it is removed once the burst ends.
    var popAge: Double?

    var isPopping: Bool { popAge != nil }

    /// 0 → just released, 1 → full size.
    var emergence: Double {
        min(1, age / ReefConfig.emergeDuration)
    }
}

/// A speck of drifting plankton. Decoration only — it is never touched and
/// never carries an answer.
struct ReefMote: Identifiable {
    let id = UUID()
    var position: CGPoint
    let radius: CGFloat
    let speed: CGFloat
    let sway: CGFloat
    let period: Double
    let phase: Double
    let baseX: CGFloat
    var age: Double = 0
}

/// Where the fish is, which way it is pointing, and whether a finger is
/// currently steering it.
struct ReefFish {
    var position: CGPoint = .zero
    /// Radians, 0 pointing right.
    var heading: Double = 0
    var isSwimming = false
}

/// One sideways wisp or tiny rising air pocket shed by the fish's tail.
struct ReefWake: Identifiable {
    enum Kind {
        case wisp
        case bubble
    }

    let id = UUID()
    var position: CGPoint
    let radius: CGFloat
    let kind: Kind
    /// Direction of travel when the wake was released. Wisps retain this
    /// orientation while the fish turns away from them.
    let heading: Double
    /// Alternates across the tail to keep the disturbance organic.
    let side: CGFloat
    var velocity: CGPoint
    var age: Double = 0

    var lifetime: Double {
        kind == .bubble ? ReefConfig.miniBubbleLifetime : ReefConfig.wakeLifetime
    }
}

/// A fast 2x power-up fish crossing the open water from either side.
struct ReefBonusFish: Identifiable {
    let id = UUID()
    var position: CGPoint
    let direction: CGFloat
    let speed: CGFloat
    let length: CGFloat
    var popAge: Double?

    var isPopping: Bool { popAge != nil }
}

/// A passing recovery fish earned by a run of correct answers after damage.
struct ReefHeartFish: Identifiable {
    let id = UUID()
    var position: CGPoint
    let direction: CGFloat
    let speed: CGFloat
    let length: CGFloat
    var popAge: Double?

    var isPopping: Bool { popAge != nil }
}

/// One decorative bubble in the completed-level finale. Answer bubbles keep
/// their separate model because these carry no text and can never be touched.
struct ReefCelebrationBubble: Identifiable {
    enum Kind { case stream, trail }

    let id = UUID()
    var position: CGPoint
    let radius: CGFloat
    let speed: CGFloat
    let phase: Double
    let kind: Kind
    var age: Double = 0
}

/// A small, purely decorative air pocket. It never carries an answer or
/// changes score; touching the player's fish only starts its visual pop.
struct ReefAmbientBubble: Identifiable {
    let id = UUID()
    let baseX: CGFloat
    var position: CGPoint
    let radius: CGFloat
    let speed: CGFloat
    let phase: Double
    var age: Double = 0
    var popAge: Double?
}

// MARK: - Engine

/// Drives the bubbles and the fish. It owns exactly one timer, holds no rules
/// about scoring, and reports a touched answer through `onHit`.
@MainActor
final class ReefEngine: ObservableObject {
    @Published private(set) var bubbles: [ReefBubble] = []
    @Published private(set) var fish = ReefFish()
    @Published private(set) var motes: [ReefMote] = []
    @Published private(set) var wakes: [ReefWake] = []
    @Published private(set) var bonusFish: ReefBonusFish?
    @Published private(set) var heartFish: ReefHeartFish?
    @Published private(set) var celebrationBubbles: [ReefCelebrationBubble] = []
    @Published private(set) var ambientBubbles: [ReefAmbientBubble] = []
    @Published private(set) var hasBonusAura = false
    /// Seconds of running time, which the swaying coral reads. It stops when
    /// the game does, so nothing moves behind a pause.
    @Published private(set) var clock: Double = 0

    /// Called when the fish touches an answer bubble. Returns whether the
    /// session accepted it, so a touch the engine ignores leaves the water
    /// exactly as it was.
    var onHit: ((UUID) -> Bool)?
    var onBonusFishCaught: (() -> Void)?
    var onHeartFishCaught: (() -> Bool)?
    var onHeartFishMissed: (() -> Void)?

    // Geometry, set from the view's layout.
    private var size: CGSize = .zero
    private var spawnLine: CGFloat = 0
    /// Kept clear at the top so the fish never swims under the HUD.
    private var topReserve: CGFloat = 0
    private var isPad = false
    private var diameter: CGFloat = 88
    private var fishLength: CGFloat = 72

    // Round state.
    private var round: GameRound?
    private var queue: [AnswerOption] = []
    private var timeToNextSpawn: Double = 0
    private var lastVentX: CGFloat?

    /// Whether answers may be released and touched. False while feedback plays,
    /// on the intro card and once the session is over.
    private var isLive = false
    private var collisionCooldown: Double = 0
    private var speedMultiplier = 1.0

    // At the start, one to three hidden question numbers are picked across the
    // whole board. This makes a passage possible near the beginning or near
    // the end without tying it to how many seconds the player needs.
    private var maximumRounds = 1
    private var bonusFishTriggerRounds: [Int] = []
    private var nextBonusFishTrigger = 0
    private var pendingBonusFishDelays: [Double] = []

    // A heart fish is scheduled by the rules engine once its earned meter is
    // full. This scene only owns the short randomized arrival delay.
    private var isHeartFishAvailable = false
    private var heartFishDelay: Double?

    // Steering.
    private var target: CGPoint?
    /// Residual velocity after the scripted entrance. It gently decays until a
    /// finger takes over, which avoids the fish stopping dead at the endpoint.
    private var coastVelocity: CGPoint = .zero

    // Opening swim. A non-nil elapsed time temporarily owns the fish, so touch
    // steering cannot pull it out of the entrance before it reaches centre.
    private var entranceElapsed: Double?
    private var entranceCompletion: (() -> Void)?
    private var entranceDidOpenRound = false
    private var wakeCountdown: Double = 0
    private var wakeSide: CGFloat = -1
    private var wakeEmissionIndex = 0

    // Completed-level swim. It deliberately lives in this engine so the real
    // fish continues from its final gameplay position without a visual jump.
    private var completionElapsed: Double?
    private var completionStart = CGPoint.zero
    private var completionCallback: (() -> Void)?
    private var completionBubbleCountdown = 0.0
    private var completionTrailCountdown = 0.0
    private var reducesCompletionMotion = false
    private var ambientBubbleCountdown = Double.random(in: ReefConfig.ambientBubbleGap)

    private var timer: Timer?

    deinit { timer?.invalidate() }

    // MARK: Layout

    /// Called from the view's geometry. Re-running it on a size change keeps
    /// the fish and the bubbles inside the new bounds.
    func layout(size: CGSize, spawnLine: CGFloat, topReserve: CGFloat, isPad: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        let isFirst = self.size == .zero
        self.size = size
        self.spawnLine = spawnLine
        self.topReserve = topReserve
        self.isPad = isPad
        self.diameter = ReefConfig.bubbleDiameter(isPad: isPad)
        self.fishLength = ReefConfig.fishLength(isPad: isPad)
        if isFirst {
            fish.position = CGPoint(x: size.width / 2, y: spawnLine - fishLength)
        } else {
            fish.position = clampedFishPosition(fish.position)
        }
        seedMotes()
    }

    /// Scatters the drifting specks over the water, once per size.
    private func seedMotes() {
        motes = (0..<ReefConfig.moteCount).map { _ in
            let x = CGFloat.random(in: 0...size.width)
            return ReefMote(position: CGPoint(x: x, y: CGFloat.random(in: 0...size.height)),
                            radius: CGFloat.random(in: ReefConfig.moteRadius),
                            speed: CGFloat.random(in: ReefConfig.moteSpeed),
                            sway: CGFloat.random(in: 4...14),
                            period: Double.random(in: 3...7),
                            phase: Double.random(in: 0..<(2 * .pi)),
                            baseX: x)
        }
    }

    // MARK: Session control

    /// Supplies the board length before its first question is loaded. The
    /// actual hidden trigger questions are chosen when that question arrives,
    /// which also makes a resumed board plan only over its remaining rounds.
    func configureBonusFish(maximumRounds: Int) {
        self.maximumRounds = max(1, maximumRounds)
    }

    /// Installs a round. Called only when the sum actually changes, so a wrong
    /// answer leaves the water — and the sum — as it was.
    func load(round: GameRound?) {
        let previousRoundNumber = self.round?.number
        self.round = round
        bubbles.removeAll()
        queue.removeAll()
        lastVentX = nil
        collisionCooldown = 0
        timeToNextSpawn = Double.random(in: ReefConfig.firstGap)
        guard let round else { return }

        // Playing again reuses this SwiftUI playfield and therefore this
        // engine. A fresh round one starts a genuinely fresh hidden plan.
        if round.number == 1, previousRoundNumber != nil {
            bonusFish = nil
            bonusFishTriggerRounds.removeAll()
            nextBonusFishTrigger = 0
            pendingBonusFishDelays.removeAll()
            heartFish = nil
            isHeartFishAvailable = false
            heartFishDelay = nil
        }
        if bonusFishTriggerRounds.isEmpty {
            makeBonusFishPlan(startingAt: round.number)
        }
        while nextBonusFishTrigger < bonusFishTriggerRounds.count,
              round.number >= bonusFishTriggerRounds[nextBonusFishTrigger] {
            pendingBonusFishDelays.append(
                Double.random(in: ReefConfig.bonusFishQuestionDelay)
            )
            nextBonusFishTrigger += 1
        }
    }

    private func makeBonusFishPlan(startingAt firstRound: Int) {
        let requestedCount = Int.random(in: GameConfig.bonusFishCount)

        // `maximumRounds` is only the one-card-per-answer ceiling. A perfect
        // streak pays two cards, and every caught 2x fish can make one of those
        // answers worth four. Plan against that shortest possible run; a fish
        // may then be late, but never on a question the level cannot reach.
        let streakStart = min(GameConfig.streakThreshold, maximumRounds)
        let cardsAfterStreakStart = max(0,
            maximumRounds - streakStart - requestedCount * GameConfig.bonusFishMultiplier
        )
        let shortestPossibleRun = streakStart
            + Int(ceil(Double(cardsAfterStreakStart) / Double(GameConfig.streakMultiplier)))
        let lastRound = max(firstRound, min(maximumRounds, shortestPossibleRun))
        let availableRounds = Array(firstRound...lastRound)
        let count = min(requestedCount, availableRounds.count)
        bonusFishTriggerRounds = Array(availableRounds.shuffled().prefix(count)).sorted()
        nextBonusFishTrigger = 0
    }

    /// Play is live only while the session is accepting an answer.
    func setLive(_ live: Bool) {
        guard isLive != live else { return }
        isLive = live
        // Coming back from feedback, the fish may still be sitting where the
        // last bubble was. A moment's grace keeps one collision from turning
        // into two lives.
        if live { collisionCooldown = ReefConfig.collisionCooldown }
    }

    func setBonusAura(_ active: Bool) {
        hasBonusAura = active
    }

    func setHeartFishAvailable(_ available: Bool) {
        if available && !isHeartFishAvailable && heartFish == nil {
            heartFishDelay = Double.random(in: ReefConfig.heartFishDelay)
        } else if !available {
            heartFishDelay = nil
        }
        isHeartFishAvailable = available
    }

    func setSpeedMultiplier(_ multiplier: Double) {
        speedMultiplier = max(1, multiplier)
    }

    /// Starts and stops the simulation itself. Everything freezes when the game
    /// is paused, covered or left.
    func setRunning(_ running: Bool) {
        if running {
            guard timer == nil else { return }
            let timer = Timer(timeInterval: ReefConfig.tick, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
            // A paused game is not being steered; the fish must not carry on
            // toward a target chosen before the pause.
            releaseTouch()
        }
    }

    /// Tears the scene down for good: no timer, no bubbles, nothing pending.
    func stop() {
        setRunning(false)
        bubbles.removeAll()
        queue.removeAll()
        round = nil
        entranceElapsed = nil
        entranceCompletion = nil
        wakes.removeAll()
        bonusFish = nil
        heartFish = nil
        celebrationBubbles.removeAll()
        ambientBubbles.removeAll()
        completionElapsed = nil
        completionCallback = nil
        onHit = nil
        onBonusFishCaught = nil
        onHeartFishCaught = nil
        onHeartFishMissed = nil
    }

    /// Sends the fish in from beyond the right edge along a tightening loop.
    /// Gameplay is deliberately started by the completion, not alongside it.
    func beginFishEntrance(completion: @escaping () -> Void) {
        guard size.width > 0, size.height > 0 else {
            completion()
            return
        }
        releaseTouch()
        entranceElapsed = 0
        entranceCompletion = completion
        entranceDidOpenRound = false
        wakeCountdown = 0
        fish.position = fishEntrancePosition(progress: 0)
        let firstStep = fishEntrancePosition(progress: 0.002)
        fish.heading = atan2(Double(firstStep.y - fish.position.y),
                             Double(firstStep.x - fish.position.x))
        fish.isSwimming = true
    }

    /// Takes control after the final answer. Normal answer bubbles disappear,
    /// the current fish gathers toward the heart's lower point and then traces
    /// the curve while air streams up from the same coral vents used in play.
    func beginLevelCompletion(reduceMotion: Bool, completion: @escaping () -> Void) {
        guard completionElapsed == nil else { return }
        releaseTouch()
        isLive = false
        bubbles.removeAll()
        bonusFish = nil
        heartFish = nil
        celebrationBubbles.removeAll()
        ambientBubbles.removeAll()
        completionStart = fish.position
        completionElapsed = 0
        completionCallback = completion
        completionBubbleCountdown = 0
        completionTrailCountdown = 0
        reducesCompletionMotion = reduceMotion
        fish.isSwimming = !reduceMotion
    }

    func endLevelCompletion() {
        completionElapsed = nil
        completionCallback = nil
        celebrationBubbles.removeAll()
        fish.isSwimming = false
    }

    // MARK: Steering

    /// The finger moved, or landed. The fish swims toward this point for as
    /// long as the touch lasts.
    func steer(toward point: CGPoint) {
        guard entranceElapsed == nil else { return }
        target = point
        coastVelocity = .zero
        fish.isSwimming = true
    }

    /// The finger left the glass. The fish coasts to a stop where it is: no new
    /// movement is started, and the last direction is not carried on.
    func releaseTouch() {
        target = nil
        coastVelocity = .zero
        fish.isSwimming = false
    }

    // MARK: Simulation

    private func tick() {
        let dt = ReefConfig.tick
        clock += dt
        if completionElapsed != nil {
            moveMotes(dt)
            moveWakes(dt)
            moveLevelCompletion(dt)
            return
        }
        moveWakes(dt)
        let previousFishPosition = fish.position
        if entranceElapsed != nil {
            moveFishEntrance(dt)
        } else {
            moveFish(dt)
        }
        leaveWakeIfMoving(from: previousFishPosition, dt: dt)
        moveMotes(dt)
        moveAmbientBubbles(dt)
        spawnAmbientBubbleIfDue(dt)
        popAmbientBubblesTouchedByFish()
        moveBubbles(dt * speedMultiplier)
        moveBonusFish(dt)
        moveHeartFish(dt)
        if collisionCooldown > 0 { collisionCooldown = max(0, collisionCooldown - dt) }
        spawnBonusFishIfDue(dt)
        spawnHeartFishIfDue(dt)
        if isLive {
            spawnIfDue(dt * speedMultiplier)
        }
        // The 2x fish remains catchable during answer feedback. Answer bubbles
        // still consult `isLive` below, so they retain their existing timing.
        // Nothing can be collected during the scripted entrance.
        if entranceElapsed == nil { checkCollisions() }
    }

    // MARK: Level completion

    private func moveLevelCompletion(_ dt: Double) {
        guard let elapsed = completionElapsed else { return }
        let next = elapsed + dt
        let previous = fish.position

        // The completion path owns the fish. Do not consult the normal
        // steering flag here: setRunning(false) may clear it during the same
        // SwiftUI update in which the finale begins.
        if !reducesCompletionMotion {
            fish.isSwimming = true
            let gatherEnd = ReefConfig.completionGatherDuration
            if next < gatherEnd {
                let p = smoothstep(next / gatherEnd)
                fish.position = interpolate(completionStart, completionPathPoint(progress: 0), p)
            } else {
                let raw = (next - gatherEnd) / ReefConfig.completionHeartDuration
                let p = min(max(raw, 0), 1)
                fish.position = completionPathPoint(progress: p)
                completionTrailCountdown -= dt
                if completionTrailCountdown <= 0, p < 0.99 {
                    completionTrailCountdown = 0.045
                    celebrationBubbles.append(ReefCelebrationBubble(
                        position: fish.position,
                        radius: CGFloat.random(in: isPad ? 4...8 : 3...6),
                        speed: CGFloat.random(in: 5...14),
                        phase: Double.random(in: 0..<(2 * .pi)),
                        kind: .trail
                    ))
                }
            }
            let dx = fish.position.x - previous.x
            let dy = fish.position.y - previous.y
            if abs(dx) + abs(dy) > 0.01 {
                fish.heading = atan2(Double(dy), Double(dx))
            }
        }

        if !reducesCompletionMotion {
            completionBubbleCountdown -= dt
            if completionBubbleCountdown <= 0 {
                completionBubbleCountdown = 0.035
                spawnCompletionStreamBubble()
            }
        }

        moveCelebrationBubbles(dt)
        completionElapsed = next
        let duration = reducesCompletionMotion ? 0.9 : ReefConfig.completionDuration
        if next >= duration {
            completionElapsed = nil
            fish.isSwimming = false
            let callback = completionCallback
            completionCallback = nil
            callback?()
        }
    }

    /// The user's loose single-stroke ribbon: up from the lower-left, around a
    /// broad top loop, across its own trail, and out through a curled lower
    /// tail. Six joined Bézier arcs preserve the hand-drawn character while
    /// matching tangents at every join keeps the fish's steering fluid.
    private func completionPathPoint(progress: Double) -> CGPoint {
        let openHeight = max(1, spawnLine - topReserve)
        let scale = min(size.width * 0.84 / 0.81, openHeight * 0.84 / 1.10)
        let centre = CGPoint(x: size.width / 2,
                             y: topReserve + openHeight * 0.51)

        let lowerLeft = CGPoint(x: -0.38, y: 0.43)
        let upperRight = CGPoint(x: 0.22, y: -0.43)
        let upperLeft = CGPoint(x: -0.12, y: -0.48)
        let loopExit = CGPoint(x: -0.32, y: 0.02)
        let lowerRight = CGPoint(x: 0.20, y: 0.16)
        let lowerBend = CGPoint(x: 0.24, y: 0.44)
        let tail = CGPoint(x: 0.43, y: 0.39)
        let segments: [(CGPoint, CGPoint, CGPoint, CGPoint)] = [
            (lowerLeft, CGPoint(x: -0.28, y: 0.25),
             CGPoint(x: 0.15, y: -0.27), upperRight),
            (upperRight, CGPoint(x: 0.30, y: -0.58),
             CGPoint(x: -0.02, y: -0.56), upperLeft),
            (upperLeft, CGPoint(x: -0.22, y: -0.40),
             CGPoint(x: -0.39, y: -0.09), loopExit),
            (loopExit, CGPoint(x: -0.25, y: 0.13),
             CGPoint(x: 0.10, y: 0.08), lowerRight),
            (lowerRight, CGPoint(x: 0.30, y: 0.24),
             CGPoint(x: 0.23, y: 0.36), lowerBend),
            (lowerBend, CGPoint(x: 0.25, y: 0.52),
             CGPoint(x: 0.36, y: 0.42), tail)
        ]

        let point = pointAlongBezierPath(segments, progress: progress)
        return CGPoint(x: centre.x + point.x * scale,
                       y: centre.y + point.y * scale)
    }

    /// Maps time to approximate distance rather than assigning every segment
    /// equal time. Short curls and long diagonals are therefore swum at the
    /// same apparent speed.
    private func pointAlongBezierPath(
        _ segments: [(CGPoint, CGPoint, CGPoint, CGPoint)],
        progress: Double
    ) -> CGPoint {
        let samplesPerSegment = 10
        let lengths = segments.map { segment in
            var length: CGFloat = 0
            var previous = segment.0
            for sample in 1...samplesPerSegment {
                let point = cubicBezier(from: segment.0, control1: segment.1,
                                        control2: segment.2, to: segment.3,
                                        t: CGFloat(sample) / CGFloat(samplesPerSegment))
                length += hypot(point.x - previous.x, point.y - previous.y)
                previous = point
            }
            return length
        }
        let total = max(0.001, lengths.reduce(0, +))
        var remaining = CGFloat(min(max(progress, 0), 1)) * total
        for (index, length) in lengths.enumerated() {
            if remaining <= length || index == segments.count - 1 {
                let t = length > 0 ? min(1, remaining / length) : 0
                let segment = segments[index]
                return cubicBezier(from: segment.0, control1: segment.1,
                                   control2: segment.2, to: segment.3, t: t)
            }
            remaining -= length
        }
        return segments.last?.3 ?? .zero
    }

    private func cubicBezier(from start: CGPoint, control1: CGPoint,
                             control2: CGPoint, to end: CGPoint,
                             t: CGFloat) -> CGPoint {
        let inverse = 1 - t
        let a = inverse * inverse * inverse
        let b = 3 * inverse * inverse * t
        let c = 3 * inverse * t * t
        let d = t * t * t
        return CGPoint(x: a * start.x + b * control1.x + c * control2.x + d * end.x,
                       y: a * start.y + b * control1.y + c * control2.y + d * end.y)
    }

    private func spawnCompletionStreamBubble() {
        let vents = ReefConfig.craterPositions(width: size.width, isPad: isPad)
        guard let x = vents.randomElement() else { return }
        celebrationBubbles.append(ReefCelebrationBubble(
            position: CGPoint(x: x + CGFloat.random(in: -8...8), y: spawnLine + 8),
            radius: CGFloat.random(in: isPad ? 5...15 : 4...11),
            speed: CGFloat.random(in: 90...190),
            phase: Double.random(in: 0..<(2 * .pi)),
            kind: .stream
        ))
    }

    private func moveCelebrationBubbles(_ dt: Double) {
        for index in celebrationBubbles.indices {
            celebrationBubbles[index].age += dt
            switch celebrationBubbles[index].kind {
            case .stream, .trail:
                celebrationBubbles[index].position.y -= celebrationBubbles[index].speed * CGFloat(dt)
                celebrationBubbles[index].position.x += CGFloat(sin(
                    celebrationBubbles[index].age * 3 + celebrationBubbles[index].phase
                )) * CGFloat(dt) * 9
            }
        }
        celebrationBubbles.removeAll {
            $0.position.y < -$0.radius * 2
        }
    }

    private func smoothstep(_ value: Double) -> CGFloat {
        let t = min(max(value, 0), 1)
        return CGFloat(t * t * (3 - 2 * t))
    }

    private func interpolate(_ from: CGPoint, _ to: CGPoint, _ amount: CGFloat) -> CGPoint {
        CGPoint(x: from.x + (to.x - from.x) * amount,
                y: from.y + (to.y - from.y) * amount)
    }

    // MARK: Fish

    private func moveFishEntrance(_ dt: Double) {
        guard let elapsed = entranceElapsed else { return }
        let nextElapsed = min(ReefConfig.fishEntranceDuration, elapsed + dt)
        let progress = nextElapsed / ReefConfig.fishEntranceDuration
        let previous = fish.position
        let next = fishEntrancePosition(progress: progress)

        fish.position = next
        let dx = next.x - previous.x
        let dy = next.y - previous.y
        if abs(dx) + abs(dy) > 0.01 {
            // The scripted path already has smooth curvature; following its
            // tangent exactly prevents the artwork from visibly lagging behind
            // the tight inner part of the spiral.
            fish.heading = atan2(Double(dy), Double(dx))
        }

        if !entranceDidOpenRound,
           nextElapsed >= ReefConfig.fishEntranceDuration - ReefConfig.fishEntranceAnswerLead {
            entranceDidOpenRound = true
            let completion = entranceCompletion
            entranceCompletion = nil
            completion?()
        }

        if progress >= 1 {
            entranceElapsed = nil
            let speed = min(CGFloat(165), (dx * dx + dy * dy).squareRoot() / CGFloat(dt))
            let distance = max(0.001, (dx * dx + dy * dy).squareRoot())
            coastVelocity = CGPoint(x: dx / distance * speed,
                                    y: dy / distance * speed)
            fish.isSwimming = true
            // Normally delivered during the last arc, but keep a fallback so
            // an extreme timing or future tuning change can never stall play.
            if !entranceDidOpenRound {
                entranceDidOpenRound = true
                let completion = entranceCompletion
                entranceCompletion = nil
                completion?()
            }
        } else {
            entranceElapsed = nextElapsed
        }
    }

    /// One continuous inward spiral, matching the broad hand-drawn loop: it
    /// enters at the right, sweeps around the whole playfield, then curls into
    /// the middle without a join or sudden change in curvature.
    private func fishEntrancePosition(progress: Double) -> CGPoint {
        let t = CGFloat(min(max(progress, 0), 1))
        let centre = fishEntranceCentre
        let outsideX = size.width + fishLength * 0.9
        let outerRadius = outsideX - centre.x
        let innerRadius = fishLength * 0.36
        let radius = outerRadius + (innerRadius - outerRadius) * t
        // One and a quarter turns place the endpoint just below centre, with
        // its tangent pointing naturally forward and to the left.
        let angle = 2.5 * .pi * t
        return CGPoint(x: centre.x + radius * cos(angle),
                       y: centre.y + radius * sin(angle))
    }

    private var fishEntranceCentre: CGPoint {
        CGPoint(x: size.width / 2,
                y: topReserve + max(0, spawnLine - topReserve) * 0.48)
    }

    // MARK: Wake

    private func leaveWakeIfMoving(from previous: CGPoint, dt: Double) {
        wakeCountdown -= dt
        let dx = fish.position.x - previous.x
        let dy = fish.position.y - previous.y
        guard dx * dx + dy * dy > 0.7, wakeCountdown <= 0 else { return }
        wakeCountdown = ReefConfig.wakeInterval

        let speed = (dx * dx + dy * dy).squareRoot() / max(CGFloat(dt), 0.001)
        let strength = min(max(speed / 360, 0.55), 1.15)
        let tailDistance = fishLength * 0.43
        let side = wakeSide
        let perpendicular = fishLength * 0.075 * side
        let cosHeading = CGFloat(cos(fish.heading))
        let sinHeading = CGFloat(sin(fish.heading))
        let tail = CGPoint(
            x: fish.position.x - cosHeading * tailDistance - sinHeading * perpendicular,
            y: fish.position.y - sinHeading * tailDistance + cosHeading * perpendicular
        )

        // Water is pushed mostly sideways by the tail, with only a small
        // backward component. The wisp then slows in place instead of
        // expanding like a ring on the surface.
        let lateralSpeed = CGFloat(24) * strength * side
        let backwardSpeed = CGFloat(8) * strength
        wakes.append(ReefWake(position: tail,
                              radius: fishLength * 0.10 * strength,
                              kind: .wisp,
                              heading: fish.heading,
                              side: side,
                              velocity: CGPoint(
                                x: -cosHeading * backwardSpeed - sinHeading * lateralSpeed,
                                y: -sinHeading * backwardSpeed + cosHeading * lateralSpeed
                              )))

        // A sparse, uneven bubble trail reads as trapped air. Emitting one on
        // two out of every three tail beats avoids a foamy motorboat wake.
        if wakeEmissionIndex % 3 != 2 {
            let sizeStep = CGFloat(wakeEmissionIndex % 3) * 0.006
            let bubbleSide = side * fishLength * 0.035
            wakes.append(ReefWake(
                position: CGPoint(x: tail.x - sinHeading * bubbleSide,
                                  y: tail.y + cosHeading * bubbleSide),
                radius: fishLength * (0.020 + sizeStep),
                kind: .bubble,
                heading: fish.heading,
                side: side,
                velocity: CGPoint(x: -cosHeading * 5 - sinHeading * side * 3,
                                  y: -sinHeading * 5 - 13)
            ))
        }
        wakeEmissionIndex += 1
        wakeSide *= -1
    }

    private func moveWakes(_ dt: Double) {
        for index in wakes.indices {
            wakes[index].age += dt
            let step = CGFloat(dt)
            wakes[index].position.x += wakes[index].velocity.x * step
            wakes[index].position.y += wakes[index].velocity.y * step

            switch wakes[index].kind {
            case .bubble:
                // Buoyancy gradually wins over the small amount of momentum
                // inherited from the fish; a tiny sideways meander prevents a
                // mechanically straight dotted line.
                wakes[index].velocity.y -= 5 * step
                wakes[index].position.x += CGFloat(sin(wakes[index].age * 7
                                                       + Double(wakes[index].side))) * step * 2.2
            case .wisp:
                let damping = CGFloat(pow(0.09, dt))
                wakes[index].velocity.x *= damping
                wakes[index].velocity.y *= damping
            }
        }
        wakes.removeAll { $0.age >= $0.lifetime }
    }

    private func moveFish(_ dt: Double) {
        guard fish.isSwimming else { return }
        guard let target else {
            moveCoastingFish(dt)
            return
        }
        let dx = target.x - fish.position.x
        let dy = target.y - fish.position.y
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance > ReefConfig.fishDeadzone else {
            fish.isSwimming = false
            return
        }

        // Speed falls off as the fish arrives, which is what makes small
        // corrections precise without the whole motion feeling nervous.
        let speed = min(ReefConfig.fishMaximumSpeed, distance * ReefConfig.fishApproach)
        let step = min(distance, speed * CGFloat(dt))
        let moved = CGPoint(x: fish.position.x + dx / distance * step,
                            y: fish.position.y + dy / distance * step)
        fish.position = clampedFishPosition(moved)
        turn(toward: atan2(Double(dy), Double(dx)), dt: dt)
    }

    private func moveCoastingFish(_ dt: Double) {
        let speed = (coastVelocity.x * coastVelocity.x
                     + coastVelocity.y * coastVelocity.y).squareRoot()
        guard speed > 5 else {
            coastVelocity = .zero
            fish.isSwimming = false
            return
        }

        let proposed = CGPoint(x: fish.position.x + coastVelocity.x * CGFloat(dt),
                               y: fish.position.y + coastVelocity.y * CGFloat(dt))
        let moved = clampedFishPosition(proposed)
        if abs(moved.x - fish.position.x) + abs(moved.y - fish.position.y) < 0.01 {
            coastVelocity = .zero
            fish.isSwimming = false
            return
        }
        fish.position = moved
        fish.heading = atan2(Double(coastVelocity.y), Double(coastVelocity.x))
        let damping = CGFloat(pow(0.20, dt))
        coastVelocity.x *= damping
        coastVelocity.y *= damping
    }

    /// Swings the fish round the short way, so crossing from just under π to
    /// just over −π does not spin it all the way about.
    private func turn(toward angle: Double, dt: Double) {
        var delta = angle - fish.heading
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        fish.heading += delta * min(1, ReefConfig.fishTurnRate * dt)
    }

    /// The fish stays in open water: inside the sides, below the top edge and
    /// above the coral, so it can never cover the sum.
    private func clampedFishPosition(_ point: CGPoint) -> CGPoint {
        let radius = fishLength * 0.5
        let minX = radius * 0.6
        let maxX = max(minX, size.width - radius * 0.6)
        let minY = topReserve + radius * 0.6
        let maxY = max(minY, spawnLine - 4)
        return CGPoint(x: min(max(point.x, minX), maxX),
                       y: min(max(point.y, minY), maxY))
    }

    // MARK: Ambience

    /// The specks rise slowly and start again from the sea floor, so the water
    /// is never still.
    private func moveMotes(_ dt: Double) {
        guard size.height > 0 else { return }
        for index in motes.indices {
            motes[index].age += dt
            var mote = motes[index]
            mote.position.y -= mote.speed * CGFloat(dt)
            let sway = sin(mote.age * 2 * .pi / mote.period + mote.phase)
            mote.position.x = mote.baseX + mote.sway * CGFloat(sway)
            if mote.position.y < -mote.radius {
                mote.position.y = size.height + mote.radius
            }
            motes[index] = mote
        }
    }

    private func spawnAmbientBubbleIfDue(_ dt: Double) {
        ambientBubbleCountdown -= dt
        guard ambientBubbleCountdown <= 0 else { return }
        ambientBubbleCountdown = Double.random(in: ReefConfig.ambientBubbleGap)
        guard ambientBubbles.count < ReefConfig.maximumAmbientBubbles,
              size.width > 0, spawnLine > topReserve else { return }

        let inset = ReefConfig.sideInset(isPad: isPad) + ReefConfig.ambientBubbleRadius.upperBound
        let x = CGFloat.random(in: inset...max(inset, size.width - inset))
        ambientBubbles.append(ReefAmbientBubble(
            baseX: x,
            position: CGPoint(x: x, y: spawnLine + CGFloat.random(in: 2...18)),
            radius: CGFloat.random(in: ReefConfig.ambientBubbleRadius),
            speed: CGFloat.random(in: ReefConfig.ambientBubbleSpeed),
            phase: Double.random(in: 0..<(2 * .pi))
        ))
    }

    private func moveAmbientBubbles(_ dt: Double) {
        for index in ambientBubbles.indices {
            ambientBubbles[index].age += dt
            if ambientBubbles[index].popAge != nil {
                ambientBubbles[index].popAge! += dt
                continue
            }
            ambientBubbles[index].position.y -= ambientBubbles[index].speed * CGFloat(dt)
            ambientBubbles[index].position.x = ambientBubbles[index].baseX
                + CGFloat(sin(ambientBubbles[index].age * 2.4
                              + ambientBubbles[index].phase)) * 8
        }
        ambientBubbles.removeAll { bubble in
            if let popAge = bubble.popAge {
                return popAge >= ReefConfig.ambientBubblePopDuration
            }
            return bubble.position.y < -bubble.radius * 2
        }
    }

    private func popAmbientBubblesTouchedByFish() {
        let fishRadius = fishLength * ReefConfig.fishHitFactor
        for index in ambientBubbles.indices where ambientBubbles[index].popAge == nil {
            let bubble = ambientBubbles[index]
            guard bubble.age > 0.12 else { continue }
            let dx = bubble.position.x - fish.position.x
            let dy = bubble.position.y - fish.position.y
            if (dx * dx + dy * dy).squareRoot() <= fishRadius + bubble.radius {
                ambientBubbles[index].popAge = 0
            }
        }
    }

    // MARK: Bubbles

    private func moveBubbles(_ dt: Double) {
        for index in bubbles.indices {
            bubbles[index].age += dt
            if bubbles[index].popAge != nil {
                bubbles[index].popAge! += dt
                continue
            }
            var bubble = bubbles[index]
            bubble.position.y -= bubble.speed * CGFloat(dt)
            let sway = sin(bubble.age * 2 * .pi / bubble.driftPeriod + bubble.phase)
            // The sway must never carry an answer off the side of the screen:
            // a half-visible number is not a readable one.
            let radius = bubble.diameter / 2
            let limit = max(radius, size.width - radius)
            bubble.position.x = min(max(bubble.baseX + bubble.driftAmplitude * CGFloat(sway),
                                        radius), limit)
            bubbles[index] = bubble
        }
        // A wrong answer that was never touched simply leaves at the top.
        bubbles.removeAll { bubble in
            if let popAge = bubble.popAge { return popAge >= ReefConfig.popDuration }
            return bubble.position.y < -bubble.diameter
        }
    }

    private func spawnIfDue(_ dt: Double) {
        guard round != nil, size.width > 0 else { return }
        timeToNextSpawn -= dt
        guard timeToNextSpawn <= 0 else { return }

        if queue.isEmpty { refillQueue() }
        guard !queue.isEmpty else {
            timeToNextSpawn = ReefConfig.blockedGap
            return
        }

        let live = bubbles.filter { !$0.isPopping }
        guard live.count < ReefConfig.maximumLiveBubbles else {
            timeToNextSpawn = ReefConfig.blockedGap
            return
        }
        // The same answer is never in the water twice: two identical bubbles
        // would read as two right answers.
        let liveIDs = Set(live.map(\.optionID))
        guard let index = queue.firstIndex(where: { !liveIDs.contains($0.id) }) else {
            timeToNextSpawn = ReefConfig.blockedGap
            return
        }
        guard let x = freeVentX(avoiding: live) else {
            timeToNextSpawn = ReefConfig.blockedGap
            return
        }

        let option = queue.remove(at: index)
        bubbles.append(makeBubble(for: option, at: x))
        lastVentX = x
        // The wave that just emptied gets a longer pause than the beats inside
        // it, so the set reads as a set.
        if queue.isEmpty {
            timeToNextSpawn = Double.random(in: ReefConfig.waveGap)
        } else if Double.random(in: 0..<1) < ReefConfig.closeGapChance {
            timeToNextSpawn = Double.random(in: ReefConfig.closeGap)
        } else {
            timeToNextSpawn = Double.random(in: ReefConfig.spawnGap)
        }
    }

    /// The coral keeps offering the same set of answers for as long as the sum
    /// stands, in a fresh order each time, so a missed right answer always
    /// comes back around.
    private func refillQueue() {
        guard let round else { return }
        var wrongAnswers = round.options.filter { !$0.isCorrect }.shuffled()
        guard let correctAnswer = round.options.first(where: \.isCorrect) else {
            queue = wrongAnswers
            return
        }

        let positionCount = wrongAnswers.count + 1
        let weights = Array(ReefConfig.correctAnswerPositionWeights.prefix(positionCount))
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else {
            queue = wrongAnswers
            queue.insert(correctAnswer, at: 0)
            return
        }

        var draw = Int.random(in: 0..<totalWeight)
        var correctPosition = 0
        for (position, weight) in weights.enumerated() {
            if draw < weight {
                correctPosition = position
                break
            }
            draw -= weight
        }

        wrongAnswers.insert(correctAnswer,
                            at: min(correctPosition, wrongAnswers.endIndex))
        queue = wrongAnswers
    }

    private func makeBubble(for option: AnswerOption, at x: CGFloat) -> ReefBubble {
        ReefBubble(optionID: option.id,
                   text: option.text,
                   isCorrect: option.isCorrect,
                   diameter: diameter,
                   baseX: x,
                   position: CGPoint(x: x, y: spawnLine + diameter * 0.22),
                   speed: CGFloat.random(in: ReefConfig.riseSpeed),
                   driftAmplitude: CGFloat.random(in: ReefConfig.driftAmplitude),
                   driftPeriod: Double.random(in: ReefConfig.driftPeriod),
                   phase: Double.random(in: 0..<(2 * .pi)))
    }

    /// Picks a crater with room above it. Bubbles still close to the coral are
    /// what matter: keeping clear of those is what stops them overlapping, and
    /// what keeps a route open to every answer.
    private func freeVentX(avoiding live: [ReefBubble]) -> CGFloat? {
        let craters = ReefConfig.craterPositions(width: size.width, isPad: isPad)
        guard !craters.isEmpty else { return nil }

        let separation = diameter * ReefConfig.separationFactor
        let band = spawnLine - diameter * ReefConfig.crowdBandFactor
        let blockers = live.filter { $0.position.y > band }.map(\.position.x)

        let clear = craters.filter { crater in
            blockers.allSatisfy { abs($0 - crater) >= separation }
        }
        guard !clear.isEmpty else { return nil }

        // Prefer a different crater from the last one; fall back if that is the
        // only room left rather than skipping the release altogether.
        if let lastVentX {
            let spread = diameter * ReefConfig.ventSpreadFactor
            let apart = clear.filter { abs($0 - lastVentX) >= spread }
            if let pick = apart.randomElement() { return pick }
        }
        return clear.randomElement()
    }

    // MARK: Collisions

    private func checkCollisions() {
        guard collisionCooldown == 0 else { return }
        let fishRadius = fishLength * ReefConfig.fishHitFactor

        if let bonusFish, !bonusFish.isPopping, !hasBonusAura {
            let dx = bonusFish.position.x - fish.position.x
            let dy = bonusFish.position.y - fish.position.y
            if (dx * dx + dy * dy).squareRoot() <= fishRadius + bonusFish.length * 0.34 {
                self.bonusFish?.popAge = 0
                hasBonusAura = true
                collisionCooldown = ReefConfig.collisionCooldown
                onBonusFishCaught?()
                return
            }
        }

        if let heartFish, !heartFish.isPopping {
            let dx = heartFish.position.x - fish.position.x
            let dy = heartFish.position.y - fish.position.y
            if (dx * dx + dy * dy).squareRoot() <= fishRadius + heartFish.length * 0.36,
               onHeartFishCaught?() == true {
                self.heartFish?.popAge = 0
                isHeartFishAvailable = false
                heartFishDelay = nil
                collisionCooldown = ReefConfig.collisionCooldown
                return
            }
        }

        guard isLive else { return }
        for bubble in bubbles where !bubble.isPopping {
            // A bubble still swelling out of the coral cannot be taken yet,
            // which keeps the vent itself from being a hair trigger.
            guard bubble.emergence >= 1 else { continue }
            let radius = bubble.diameter * ReefConfig.bubbleHitFactor
            let dx = bubble.position.x - fish.position.x
            let dy = bubble.position.y - fish.position.y
            guard (dx * dx + dy * dy).squareRoot() <= radius + fishRadius else { continue }

            // The session has the final say. If it does not take the answer —
            // feedback still playing, round already resolved — nothing happens.
            guard onHit?(bubble.optionID) == true else { return }
            collisionCooldown = ReefConfig.collisionCooldown
            pop(bubbleID: bubble.id)
            // A right answer clears the water; the sum is about to change.
            if bubble.isCorrect { popAll(except: bubble.id) }
            return
        }
    }

    // MARK: 2x fish

    private func spawnBonusFishIfDue(_ dt: Double) {
        guard bonusFish == nil,
              heartFish == nil,
              !hasBonusAura,
              !pendingBonusFishDelays.isEmpty,
              size.width > 0 else { return }
        pendingBonusFishDelays[0] -= dt
        guard pendingBonusFishDelays[0] <= 0 else { return }

        let length = ReefConfig.bonusFishLength(isPad: isPad)
        let direction: CGFloat = Bool.random() ? 1 : -1
        let startX = direction > 0 ? -length : size.width + length
        let minY = topReserve + length
        let maxY = max(minY, spawnLine - length * 0.8)
        bonusFish = ReefBonusFish(position: CGPoint(x: startX,
                                                    y: CGFloat.random(in: minY...maxY)),
                                  direction: direction,
                                  speed: CGFloat.random(in: ReefConfig.bonusFishSpeed),
                                  length: length)
        pendingBonusFishDelays.removeFirst()
    }

    private func moveBonusFish(_ dt: Double) {
        guard var swimmer = bonusFish else { return }
        if let popAge = swimmer.popAge {
            swimmer.popAge = popAge + dt
            bonusFish = swimmer.popAge! >= ReefConfig.bonusFishPopDuration ? nil : swimmer
            return
        }
        swimmer.position.x += swimmer.direction * swimmer.speed * CGFloat(dt)
        // The fish starts a full body-length outside the entry edge. Only the
        // opposite edge may remove it; checking both edges made every new fish
        // disappear again before its nose could enter the screen.
        let hasLeftScreen = swimmer.direction > 0
            ? swimmer.position.x > size.width + swimmer.length
            : swimmer.position.x < -swimmer.length
        if hasLeftScreen {
            swimmer.popAge = 0
            bonusFish = swimmer
        } else {
            bonusFish = swimmer
        }
    }

    // MARK: Heart fish

    private func spawnHeartFishIfDue(_ dt: Double) {
        guard heartFish == nil,
              bonusFish == nil,
              isHeartFishAvailable,
              var delay = heartFishDelay,
              size.width > 0 else { return }
        delay -= dt
        heartFishDelay = delay
        guard delay <= 0 else { return }

        let length = ReefConfig.heartFishLength(isPad: isPad)
        let direction: CGFloat = Bool.random() ? 1 : -1
        let startX = direction > 0 ? -length : size.width + length
        let minY = topReserve + length
        let maxY = max(minY, spawnLine - length * 0.8)
        heartFish = ReefHeartFish(position: CGPoint(x: startX,
                                                    y: CGFloat.random(in: minY...maxY)),
                                  direction: direction,
                                  speed: CGFloat.random(in: ReefConfig.heartFishSpeed),
                                  length: length)
        heartFishDelay = nil
    }

    private func moveHeartFish(_ dt: Double) {
        guard var swimmer = heartFish else { return }
        if let popAge = swimmer.popAge {
            swimmer.popAge = popAge + dt
            heartFish = swimmer.popAge! >= ReefConfig.heartFishPopDuration ? nil : swimmer
            return
        }
        swimmer.position.x += swimmer.direction * swimmer.speed * CGFloat(dt)
        let hasLeftScreen = swimmer.direction > 0
            ? swimmer.position.x > size.width + swimmer.length
            : swimmer.position.x < -swimmer.length
        if hasLeftScreen {
            swimmer.popAge = 0
            heartFish = swimmer
            isHeartFishAvailable = false
            heartFishDelay = nil
            onHeartFishMissed?()
        } else {
            heartFish = swimmer
        }
    }

    private func pop(bubbleID: UUID) {
        guard let index = bubbles.firstIndex(where: { $0.id == bubbleID }) else { return }
        bubbles[index].popAge = 0
    }

    private func popAll(except bubbleID: UUID) {
        for index in bubbles.indices where bubbles[index].id != bubbleID
            && !bubbles[index].isPopping {
            bubbles[index].popAge = 0
        }
    }
}

// MARK: - Level completion bubbles

private struct CelebrationBubbleView: View {
    let bubble: ReefCelebrationBubble
    let palette: ReefPalette

    private var scale: CGFloat {
        switch bubble.kind {
        case .stream: return min(1, CGFloat(bubble.age / 0.18))
        case .trail:  return max(0.45, 1 - CGFloat(bubble.age / 2.8) * 0.42)
        }
    }

    var body: some View {
        Circle()
            .fill(
                RadialGradient(colors: [
                    .white.opacity(0.42),
                    palette.waterTop.opacity(0.22),
                    .white.opacity(0.16)
                ], center: .topLeading, startRadius: 1, endRadius: bubble.radius * 1.4)
            )
            .overlay {
                Circle().stroke(.white.opacity(0.48),
                                lineWidth: max(1, bubble.radius * 0.09))
            }
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.white.opacity(0.72))
                    .frame(width: bubble.radius * 0.34, height: bubble.radius * 0.34)
                    .padding(bubble.radius * 0.32)
            }
            .frame(width: bubble.radius * 2, height: bubble.radius * 2)
            .scaleEffect(scale)
            .opacity(bubble.kind == .trail
                     ? max(0, 1 - bubble.age / 3.0)
                     : 1)
            .allowsHitTesting(false)
    }
}

private struct AmbientBubbleView: View {
    let bubble: ReefAmbientBubble

    private var popProgress: CGFloat {
        guard let age = bubble.popAge else { return 0 }
        return min(1, CGFloat(age / ReefConfig.ambientBubblePopDuration))
    }

    var body: some View {
        Circle()
            .fill(.white.opacity(0.10))
            .overlay {
                Circle().stroke(.white.opacity(0.48),
                                lineWidth: max(1, bubble.radius * 0.16))
            }
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.white.opacity(0.68))
                    .frame(width: bubble.radius * 0.38, height: bubble.radius * 0.38)
                    .padding(bubble.radius * 0.28)
            }
            .frame(width: bubble.radius * 2, height: bubble.radius * 2)
            .scaleEffect(bubble.popAge == nil ? 1 : 1 + popProgress * 1.15)
            .opacity(bubble.popAge == nil ? 1 : 1 - popProgress)
            .allowsHitTesting(false)
    }
}

// MARK: - Playfield

/// The reef itself. Everything below the HUD and above the helper button.
struct ReefPlayfield: View {
    let round: GameRound?
    let maximumRounds: Int
    let character: AnimalCharacter
    let isPad: Bool
    /// Whether an answer may be released and taken right now.
    let isLive: Bool
    /// Whether the simulation runs at all.
    let isRunning: Bool
    /// True between dismissing the level card and opening the first round.
    let playsFishEntrance: Bool
    let hasBonusFishPower: Bool
    let isHeartFishAvailable: Bool
    let isStreakBoostActive: Bool
    let playsLevelCompletion: Bool
    let reduceMotion: Bool
    /// Screen edges the reef works around: the HUD at the top, the home
    /// indicator at the bottom.
    let topReserve: CGFloat
    let bottomReserve: CGFloat
    /// Hands a touched answer to the session; the return value says whether it
    /// counted.
    let onHit: (UUID) -> Bool
    let onBonusFishCaught: () -> Void
    let onHeartFishCaught: () -> Bool
    let onHeartFishMissed: () -> Void
    let onFishEntranceComplete: () -> Void
    let onLevelCompletionFinished: () -> Void

    @StateObject private var engine = ReefEngine()

    private var bandHeight: CGFloat {
        ReefConfig.bandHeight(isPad: isPad, bottomReserve: bottomReserve)
    }
    private var sandHeight: CGFloat {
        ReefConfig.sandHeight(isPad: isPad, bottomReserve: bottomReserve)
    }
    private var palette: ReefPalette { ReefPalette(character: character) }

    private var coralBed: CoralBed {
        CoralBed(palette: palette,
                 isPad: isPad,
                 bandHeight: bandHeight,
                 sandHeight: sandHeight,
                 clock: engine.clock,
                 prompt: round?.question.prompt ?? "",
                 roundID: round?.id,
                 bottomReserve: bottomReserve)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let spawnLine = max(0, size.height - bandHeight)

            ZStack(alignment: .topLeading) {
                // The open water takes the touch; the fish only ever moves
                // while a finger is down on it.
                WaterColumn(palette: palette, clock: engine.clock)
                    .contentShape(Rectangle())

                MoteField(motes: engine.motes)
                    .allowsHitTesting(false)

                FishWakeField(wakes: engine.wakes)
                    .allowsHitTesting(false)

                ForEach(engine.ambientBubbles) { bubble in
                    AmbientBubbleView(bubble: bubble)
                        .position(bubble.position)
                }

                ForEach(engine.celebrationBubbles) { bubble in
                    CelebrationBubbleView(bubble: bubble, palette: palette)
                        .position(bubble.position)
                }

                ForEach(engine.bubbles) { bubble in
                    AnswerBubbleView(bubble: bubble, palette: palette, isPad: isPad)
                        .position(bubble.position)
                }

                if let bonusFish = engine.bonusFish {
                    BonusFishView(fish: bonusFish, palette: palette, isPad: isPad)
                        .position(bonusFish.position)
                        .allowsHitTesting(false)
                }

                if let heartFish = engine.heartFish {
                    HeartFishView(fish: heartFish, palette: palette, isPad: isPad)
                        .position(heartFish.position)
                        .allowsHitTesting(false)
                }

                ZStack {
                    if isStreakBoostActive {
                        StreakAuraView(fish: engine.fish,
                                       clock: engine.clock,
                                       isPad: isPad)
                    }
                    if engine.hasBonusAura {
                        BonusAuraView(character: character, isPad: isPad)
                    }
                    FishView(fish: engine.fish,
                             character: character,
                             isPad: isPad,
                             clock: engine.clock)
                }
                .position(engine.fish.position)
                .allowsHitTesting(false)

                // Sea floor and coral last, so the sum is never covered by a
                // bubble or by the fish.
                coralBed
                    .frame(width: size.width, height: bandHeight)
                    .offset(y: spawnLine)
                    .allowsHitTesting(false)

            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { engine.steer(toward: $0.location) }
                    .onEnded { _ in engine.releaseTouch() }
            )
            .allowsHitTesting(!playsLevelCompletion)
            .onAppear {
                engine.onHit = onHit
                engine.onBonusFishCaught = onBonusFishCaught
                engine.onHeartFishCaught = onHeartFishCaught
                engine.onHeartFishMissed = onHeartFishMissed
                engine.layout(size: size, spawnLine: spawnLine,
                              topReserve: topReserve, isPad: isPad)
                engine.configureBonusFish(maximumRounds: maximumRounds)
                engine.load(round: round)
                engine.setLive(isLive)
                engine.setBonusAura(hasBonusFishPower)
                engine.setHeartFishAvailable(isHeartFishAvailable)
                engine.setSpeedMultiplier(isStreakBoostActive
                                          ? GameConfig.streakSpeedMultiplier : 1)
                engine.setRunning(isRunning)
                if playsFishEntrance {
                    engine.beginFishEntrance(completion: onFishEntranceComplete)
                }
                if playsLevelCompletion {
                    engine.beginLevelCompletion(reduceMotion: reduceMotion,
                                                completion: onLevelCompletionFinished)
                }
            }
            .onChange(of: size) { _, newSize in
                engine.layout(size: newSize,
                              spawnLine: max(0, newSize.height - bandHeight),
                              topReserve: topReserve,
                              isPad: isPad)
            }
        }
        // A new sum clears the water and starts a fresh set of answers. A wrong
        // answer keeps the same round, so this deliberately does not fire.
        .onChange(of: round?.id) { _, _ in
            engine.load(round: round)
        }
        .onChange(of: isLive) { _, live in
            engine.setLive(live)
        }
        .onChange(of: isRunning) { _, running in
            engine.setRunning(running)
        }
        .onChange(of: hasBonusFishPower) { _, active in
            engine.setBonusAura(active)
        }
        .onChange(of: isHeartFishAvailable) { _, available in
            engine.setHeartFishAvailable(available)
        }
        .onChange(of: isStreakBoostActive) { _, active in
            engine.setSpeedMultiplier(active ? GameConfig.streakSpeedMultiplier : 1)
        }
        .onChange(of: playsFishEntrance) { _, shouldPlay in
            if shouldPlay {
                engine.beginFishEntrance(completion: onFishEntranceComplete)
            }
        }
        .onChange(of: playsLevelCompletion) { _, shouldPlay in
            if shouldPlay {
                engine.beginLevelCompletion(reduceMotion: reduceMotion,
                                            completion: onLevelCompletionFinished)
            } else {
                engine.endLevelCompletion()
            }
        }
        .onDisappear {
            engine.stop()
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Heart fish

private struct HeartFishView: View {
    let fish: ReefHeartFish
    let palette: ReefPalette
    let isPad: Bool

    private var popProgress: Double {
        min(1, (fish.popAge ?? 0) / ReefConfig.heartFishPopDuration)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.94))
                .frame(width: fish.length * 0.66, height: fish.length * 0.66)
                .overlay {
                    Circle().stroke(.pink.opacity(0.9), lineWidth: isPad ? 4 : 3)
                }
            Image(systemName: "fish.fill")
                .font(.system(size: fish.length * 0.76, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: [.pink, .red],
                                   startPoint: .top, endPoint: .bottom)
                )
                .scaleEffect(x: fish.direction < 0 ? -1 : 1, y: 1)
            Image(systemName: "heart.fill")
                .font(.system(size: fish.length * 0.25, weight: .black))
                .foregroundStyle(.red)
                .padding(5)
                .background(.white.opacity(0.96), in: Circle())
                .offset(y: -fish.length * 0.49)
        }
        .frame(width: fish.length * 1.25, height: fish.length * 1.25)
        .scaleEffect(1 + popProgress * 0.75)
        .opacity(1 - popProgress)
        .shadow(color: .pink.opacity(0.8), radius: 12)
        .accessibilityHidden(true)
    }
}

// MARK: - 2x power-up fish

private struct BonusFishView: View {
    let fish: ReefBonusFish
    let palette: ReefPalette
    let isPad: Bool

    private var popProgress: Double {
        min(1, (fish.popAge ?? 0) / ReefConfig.bonusFishPopDuration)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.90))
                .frame(width: fish.length * 0.62, height: fish.length * 0.62)
                .overlay {
                    Circle().stroke(.cyan.opacity(0.8), lineWidth: isPad ? 4 : 3)
                }
            Image(systemName: "fish.fill")
                .font(.system(size: fish.length * 0.72, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: [.yellow, .orange],
                                   startPoint: .top, endPoint: .bottom)
                )
                .scaleEffect(x: fish.direction < 0 ? -1 : 1, y: 1)
            Text(verbatim: "2×")
                .font(.system(size: fish.length * 0.27, weight: .black, design: .rounded))
                .foregroundStyle(palette.waterDeep)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.white.opacity(0.95), in: Capsule())
                .offset(y: -fish.length * 0.48)
        }
        .frame(width: fish.length * 1.2, height: fish.length * 1.2)
        .scaleEffect(1 + popProgress * 0.7)
        .opacity(1 - popProgress)
        .shadow(color: .yellow.opacity(0.7), radius: 10)
        .accessibilityHidden(true)
    }
}

private struct StreakAuraView: View {
    let fish: ReefFish
    let clock: Double
    let isPad: Bool

    private var length: CGFloat { ReefConfig.fishLength(isPad: isPad) }
    private var height: CGFloat { length * 0.58 }
    private var isFacingLeft: Bool { cos(fish.heading) < 0 }

    var body: some View {
        // Keep the effect attached to the playable character's silhouette.
        // The restrained pulse makes the streak feel alive without changing
        // the apparent hit area or turning the aura into a separate object.
        let pulse = CGFloat(sin(clock * 4.4)) * 0.012

        ZStack {
            // A broad, low-opacity underlay softens the edge against both the
            // light surface water and the darker deep-water gradient.
            FishAuraSilhouette(length: length, height: height, color: .orange)
                .scaleEffect(1.25 + pulse)
                .blur(radius: isPad ? 8 : 6)
                .opacity(0.52)

            // The smaller bright layer is mostly covered by FishView. What
            // remains is a clean 5-8 pt rim that follows tail, fin and body.
            FishAuraSilhouette(length: length, height: height, color: .yellow)
                .scaleEffect(1.15 + pulse)
                .shadow(color: .white.opacity(0.95), radius: isPad ? 2.5 : 2)
                .shadow(color: .yellow.opacity(0.72), radius: isPad ? 7 : 5)
        }
        .frame(width: length, height: height)
        .scaleEffect(x: 1, y: isFacingLeft ? -1 : 1)
        .rotationEffect(.radians(fish.heading))
        .accessibilityHidden(true)
    }
}

/// A solid copy of only the fish's outside shapes. Enlarging this underneath
/// `FishView` produces a true contour instead of a generic circular halo.
private struct FishAuraSilhouette: View {
    let length: CGFloat
    let height: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            TailShape()
                .fill(color)
                .frame(width: length * 0.30, height: height * 0.82)
                .offset(x: -length * 0.40)

            Capsule()
                .fill(color)
                .frame(width: length * 0.30, height: height * 0.22)
                .rotationEffect(.degrees(-16))
                .offset(x: -length * 0.04, y: -height * 0.40)

            Ellipse()
                .fill(color)
                .frame(width: length * 0.80, height: height)
        }
        .frame(width: length, height: height)
        .compositingGroup()
    }
}

private struct BonusAuraView: View {
    let character: AnimalCharacter
    let isPad: Bool

    var body: some View {
        let size: CGFloat = isPad ? 126 : 94
        ZStack {
            Circle()
                .fill(character.tintColor.opacity(0.20))
            Circle()
                .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, dash: [7, 5]))
            Text(verbatim: "2×")
                .font(.system(size: isPad ? 22 : 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(character.deepColor, in: Capsule())
                .offset(y: -size * 0.57)
        }
        .frame(width: size, height: size)
        .shadow(color: .white.opacity(0.55), radius: 10)
        .accessibilityHidden(true)
    }
}

// MARK: - Bubble

private struct AnswerBubbleView: View {
    let bubble: ReefBubble
    let palette: ReefPalette
    let isPad: Bool

    /// The burst: the shell swells and fades away in one short beat.
    private var popProgress: Double {
        guard let popAge = bubble.popAge else { return 0 }
        return min(1, popAge / ReefConfig.popDuration)
    }

    private var scale: Double {
        let start = ReefConfig.emergeStartScale
        let emerge = start + (1 - start) * easeOut(bubble.emergence)
        return emerge * (1 + 0.45 * popProgress)
    }

    private var opacity: Double {
        min(1, bubble.emergence * 3) * (1 - popProgress)
    }

    private func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

    var body: some View {
        ZStack {
            // A pale, glassy shell: light enough for a dark answer to be read
            // straight through it, and clearly a bubble against the water.
            Circle()
                .fill(
                    RadialGradient(colors: [.white.opacity(0.97), .white.opacity(0.62)],
                                   center: UnitPoint(x: 0.34, y: 0.30),
                                   startRadius: 2,
                                   endRadius: bubble.diameter * 0.74)
                )
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: isPad ? 3 : 2.2)

            // A small highlight, which is what makes the disc read as a bubble.
            Circle()
                .fill(.white)
                .frame(width: bubble.diameter * 0.17, height: bubble.diameter * 0.17)
                .offset(x: -bubble.diameter * 0.22, y: -bubble.diameter * 0.24)

            Text(verbatim: bubble.text)
                .font(.system(size: isPad ? 34 : 26, weight: .black, design: .rounded))
                .minimumScaleFactor(0.35)
                .lineLimit(1)
                .foregroundStyle(palette.coralDeep)
                // Long answers still have to sit inside the round shell.
                .frame(width: bubble.diameter * 0.74)
                .opacity(1 - popProgress)
        }
        .frame(width: bubble.diameter, height: bubble.diameter)
        .shadow(color: palette.waterDeep.opacity(0.28), radius: 6, y: 3)
        .scaleEffect(scale)
        .opacity(opacity)
        .accessibilityLabel(Text(verbatim: bubble.text))
        .accessibilityValue(Text(verbatim: bubble.isCorrect ? "correct" : "wrong"))
    }
}

// MARK: - Fish

/// The playable character, drawn in the player's own colours so the reef stays
/// themed to whichever animal they picked.
private struct FishView: View {
    let fish: ReefFish
    let character: AnimalCharacter
    let isPad: Bool
    let clock: Double

    private var length: CGFloat { ReefConfig.fishLength(isPad: isPad) }
    private var height: CGFloat { length * 0.58 }

    /// Facing left is a mirror rather than an upside-down turn, so the fish is
    /// never swimming on its back.
    private var isFacingLeft: Bool { cos(fish.heading) < 0 }
    /// Even at rest a fish balances itself in the current. The active beat is
    /// deliberately much quicker and wider, so starting to swim is legible.
    private var tailAngle: Double {
        fish.isSwimming ? sin(clock * 12.5) * 16 : sin(clock * 2.2) * 4
    }
    private var finAngle: Double {
        fish.isSwimming ? sin(clock * 12.5 + .pi) * 5 : sin(clock * 1.8 + 0.8) * 3
    }
    private var idleRoll: Double {
        fish.isSwimming ? 0 : sin(clock * 1.35) * 0.020
    }
    private var idleLift: CGFloat {
        fish.isSwimming ? 0 : CGFloat(sin(clock * 1.55)) * 1.6
    }

    var body: some View {
        ZStack {
            // Tail, behind the body.
            TailShape()
                .fill(character.deepColor)
                .frame(width: length * 0.30, height: height * 0.82)
                .rotationEffect(.degrees(tailAngle), anchor: .trailing)
                .offset(x: -length * 0.40)

            // Top fin.
            Capsule()
                .fill(character.deepColor.opacity(0.9))
                .frame(width: length * 0.30, height: height * 0.22)
                .rotationEffect(.degrees(-16))
                .offset(x: -length * 0.04, y: -height * 0.40)

            Ellipse()
                .fill(
                    LinearGradient(colors: [character.color, character.deepColor],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: length * 0.80, height: height)
                .overlay {
                    Ellipse()
                        .stroke(.white.opacity(0.55), lineWidth: isPad ? 2.4 : 1.8)
                        .frame(width: length * 0.80, height: height)
                }

            // Side fin.
            Ellipse()
                .fill(.white.opacity(0.45))
                .frame(width: length * 0.20, height: height * 0.28)
                .rotationEffect(.degrees(18 + finAngle))
                .offset(x: -length * 0.02, y: height * 0.20)

            // Eye.
            Circle()
                .fill(.white)
                .frame(width: height * 0.26, height: height * 0.26)
                .overlay {
                    Circle()
                        .fill(character.deepColor)
                        .frame(width: height * 0.13, height: height * 0.13)
                        .offset(x: height * 0.03)
                }
                .offset(x: length * 0.22, y: -height * 0.12)
        }
        .frame(width: length, height: height)
        .scaleEffect(x: 1, y: isFacingLeft ? -1 : 1)
        .rotationEffect(.radians(fish.heading + idleRoll))
        .offset(y: idleLift)
        .shadow(color: character.deepColor.opacity(0.22), radius: 6, y: 4)
        .accessibilityHidden(true)
    }
}

private struct TailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY),
                          control: CGPoint(x: rect.midX * 0.9, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Water

/// The water column: the whole screen, from the surface at the very top edge
/// down to the sea floor.
private struct WaterColumn: View {
    let palette: ReefPalette
    let clock: Double

    var body: some View {
        LinearGradient(colors: [palette.waterTop, palette.waterDeep],
                       startPoint: .top, endPoint: .bottom)
            .overlay { SunShafts(clock: clock) }
    }
}

/// Two wide, very faint shafts of light leaning in from above. They drift
/// slowly, which is most of what makes the water feel like water.
private struct SunShafts: View {
    let clock: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                shaft(width: width * 0.30, lean: -13)
                    .offset(x: width * (0.24 + 0.03 * CGFloat(sin(clock * 0.18))))
                shaft(width: width * 0.20, lean: -9)
                    .offset(x: width * (0.70 + 0.04 * CGFloat(sin(clock * 0.13 + 1.7))))
            }
            .frame(width: width, height: proxy.size.height, alignment: .topLeading)
        }
        .opacity(0.13)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Kept deliberately faint: the shafts are there to be felt, not looked at,
    /// and the answers have to stay the brightest thing in the water.
    private func shaft(width: CGFloat, lean: Double) -> some View {
        LinearGradient(stops: [.init(color: .white.opacity(0), location: 0),
                               .init(color: .white, location: 0.22),
                               .init(color: .white.opacity(0), location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: width)
            .rotationEffect(.degrees(lean), anchor: .top)
            .blur(radius: 26)
    }
}

/// The drifting plankton.
private struct MoteField: View {
    let motes: [ReefMote]

    var body: some View {
        ZStack {
            ForEach(motes) { mote in
                Circle()
                    .fill(.white.opacity(0.34))
                    .frame(width: mote.radius * 2, height: mote.radius * 2)
                    .position(mote.position)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Sideways eddies and tiny rising air pockets left behind by the fish's tail.
/// The wisps stay narrow and dissolve in place, so they read as displaced
/// underwater flow rather than ripples spreading across a surface.
private struct FishWakeField: View {
    let wakes: [ReefWake]

    var body: some View {
        ZStack {
            ForEach(wakes) { wake in
                let progress = min(1, wake.age / wake.lifetime)
                switch wake.kind {
                case .bubble:
                    Circle()
                        .fill(.white.opacity(0.14 * (1 - progress)))
                        .overlay {
                            Circle().stroke(.white.opacity(0.60 * (1 - progress)),
                                            lineWidth: 0.9)
                        }
                        .frame(width: wake.radius * 2, height: wake.radius * 2)
                        .scaleEffect(0.72 + progress * 0.42)
                        .position(wake.position)
                case .wisp:
                    WakeWispShape(bend: wake.side)
                        .stroke(.white.opacity(0.34 * (1 - progress)),
                                style: StrokeStyle(lineWidth: 1.6,
                                                   lineCap: .round))
                        .frame(width: wake.radius * (3.1 + progress * 0.7),
                               height: wake.radius * 1.65)
                        .rotationEffect(.radians(wake.heading))
                        .blur(radius: 0.35 + progress * 0.45)
                        .position(wake.position)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A single tapered-looking curl. Its shallow bend alternates with the tail
/// beat; rotation happens in `FishWakeField`, where the original swim heading
/// is still available.
private struct WakeWispShape: Shape {
    let bend: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.midY - bend * rect.height * 0.12),
            control1: CGPoint(x: rect.width * 0.70,
                              y: rect.midY + bend * rect.height * 0.44),
            control2: CGPoint(x: rect.width * 0.30,
                              y: rect.midY + bend * rect.height * 0.24)
        )
        return path
    }
}

// MARK: - Sea floor
/// The sea bed: a sand mound, coral swaying in the current, the craters the
/// bubbles come out of, and the sum set into a doorway in the reef. The sum is
/// drawn in front of everything, so neither a bubble nor the fish can cover it.
private struct CoralBed: View {
    let palette: ReefPalette
    let isPad: Bool
    let bandHeight: CGFloat
    let sandHeight: CGFloat
    let clock: Double
    let prompt: String
    /// Changes when a new sum is installed; the door opens on it.
    let roundID: UUID?
    let bottomReserve: CGFloat

    private var doorHeight: CGFloat { ReefConfig.doorHeight(isPad: isPad) }
    private var rimHeight: CGFloat { ReefConfig.craterRimHeight(isPad: isPad) }
    private var floorInset: CGFloat { ReefConfig.floorInset(isPad: isPad) + bottomReserve }
    private var questionInset: CGFloat { isPad ? 126 : 48 }

    var body: some View {
        ZStack(alignment: .bottom) {
            SandBank(palette: palette)
                .frame(height: sandHeight)

            // Fronds sway either side of the block, out where the mound shows.
            CoralClump(palette: palette,
                       isPad: isPad,
                       clock: clock,
                       rootDepth: sandHeight * 0.46)
                .frame(height: bandHeight)

            // One low coral boulder, partly buried in the hill.
            ReefMass(palette: palette, isPad: isPad, clock: clock)
                .padding(.horizontal, ReefConfig.blockInset(isPad: isPad))
                .padding(.bottom, floorInset * 0.25)
                .frame(height: doorHeight + rimHeight + floorInset * 0.75,
                       alignment: .bottom)

            // The vents and sum share that same mass; neither draws a separate
            // rectangular backing of its own.
            CraterRim(palette: palette, isPad: isPad, clock: clock)
                .frame(height: rimHeight)
                .padding(.horizontal, ReefConfig.blockInset(isPad: isPad))
                .padding(.bottom, floorInset + doorHeight)

            CoralQuestion(prompt: prompt,
                          roundID: roundID,
                          palette: palette,
                          isPad: isPad)
                .frame(height: doorHeight)
                .padding(.horizontal, questionInset)
                .padding(.bottom, floorInset)

            SeaPlantField(palette: palette, isPad: isPad, clock: clock)
                .frame(height: bandHeight)

            // This is a full foreground bank, not a narrow strip: it hides the
            // complete foot of the coral and lets the plants emerge from sand.
            ForegroundSandLip(palette: palette)
                .frame(height: floorInset + (isPad ? 18 : 12))
                .allowsHitTesting(false)
        }
    }
}

private struct ForegroundSandLip: View {
    let palette: ReefPalette

    var body: some View {
        ForegroundSandShape()
            .fill(
                LinearGradient(colors: [palette.sand.opacity(0.96), palette.sandDeep],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay {
                ForegroundSandShape()
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

private struct ForegroundSandShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.18))
        path.addCurve(to: CGPoint(x: rect.width * 0.32, y: rect.height * 0.10),
                      control1: CGPoint(x: rect.width * 0.10, y: rect.height * 0.06),
                      control2: CGPoint(x: rect.width * 0.22, y: rect.height * 0.17))
        path.addCurve(to: CGPoint(x: rect.width * 0.68, y: rect.height * 0.11),
                      control1: CGPoint(x: rect.width * 0.43, y: rect.height * 0.02),
                      control2: CGPoint(x: rect.width * 0.56, y: rect.height * 0.19))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.height * 0.16),
                      control1: CGPoint(x: rect.width * 0.80, y: rect.height * 0.03),
                      control2: CGPoint(x: rect.width * 0.91, y: rect.height * 0.21))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The main piece of coral. Its scalloped crown and flared roots are a single
/// silhouette, which visually welds the question niche to the sandy hill.
private struct ReefMass: View {
    let palette: ReefPalette
    let isPad: Bool
    let clock: Double

    private let texture: [(CGFloat, CGFloat, CGFloat)] = [
        (0.08, 0.54, 0.026), (0.14, 0.78, 0.018), (0.22, 0.34, 0.014),
        (0.78, 0.31, 0.016), (0.87, 0.66, 0.024), (0.92, 0.45, 0.013),
        (0.31, 0.88, 0.019), (0.68, 0.84, 0.015)
    ]

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                ReefMassShape()
                    .fill(
                        LinearGradient(colors: [palette.coral.opacity(0.98), palette.coralDeep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .overlay {
                        ReefMassShape()
                            .stroke(.white.opacity(0.17), lineWidth: isPad ? 2 : 1.3)
                    }
                    .shadow(color: palette.coralDeep.opacity(0.32), radius: 12, y: 8)

                // Quiet pits in the coral keep the large surface from reading
                // as a flat slab. They breathe by only a few percent.
                ForEach(Array(texture.enumerated()), id: \.offset) { index, spot in
                    let pulse = 1 + 0.07 * sin(clock * 0.55 + Double(index) * 1.7)
                    Circle()
                        .fill(palette.coralDeep.opacity(0.32))
                        .overlay {
                            Circle().stroke(.white.opacity(0.12), lineWidth: 1)
                        }
                        .frame(width: max(4, w * spot.2), height: max(4, w * spot.2))
                        .scaleEffect(pulse)
                        .position(x: w * spot.0, y: h * spot.1)
                }

                CoralSurfaceLife(palette: palette, isPad: isPad, clock: clock)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Living details that grow from the boulder itself: small coral fans, flower-
/// like polyps and buds. Motion stays deliberately slow and asynchronous.
private struct CoralSurfaceLife: View {
    let palette: ReefPalette
    let isPad: Bool
    let clock: Double

    /// x, root y, scale, resting lean, animation phase.
    private let twigs: [(CGFloat, CGFloat, CGFloat, Double, Double)] = [
        // A dense low cluster on the left shoulder.
        (0.060, 0.68, 1.00, -14, 0.2), (0.105, 0.55, 0.72, 9, 1.5),
        (0.155, 0.66, 0.88, -5, 3.2), (0.215, 0.46, 0.60, 12, 4.7),
        (0.285, 0.58, 0.68, -8, 2.3),
        // The opposite side deliberately has a different rhythm and outline.
        (0.705, 0.48, 0.58, 9, 5.1), (0.770, 0.61, 0.76, -12, 3.8),
        (0.835, 0.45, 0.62, 7, 0.9), (0.885, 0.66, 0.90, -7, 4.1),
        (0.940, 0.70, 1.04, 14, 2.0)
    ]

    /// x, y, size, animation phase.
    private let polyps: [(CGFloat, CGFloat, CGFloat, Double)] = [
        (0.10, 0.70, 1.00, 0.5), (0.18, 0.61, 0.78, 2.1),
        (0.27, 0.73, 0.70, 4.2), (0.36, 0.34, 0.62, 1.2),
        (0.43, 0.78, 0.72, 3.4), (0.57, 0.76, 0.64, 5.5),
        (0.64, 0.35, 0.66, 2.7), (0.73, 0.72, 0.76, 0.1),
        (0.82, 0.60, 0.82, 4.8), (0.90, 0.70, 0.96, 1.8)
    ]

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let baseTwigHeight = h * (isPad ? 0.34 : 0.31)
            let basePolyp = isPad ? 14.0 : 10.0

            ZStack {
                ForEach(Array(twigs.enumerated()), id: \.offset) { index, twig in
                    let twigHeight = baseTwigHeight * twig.2
                    let wave = sin(clock * (0.56 + Double(index) * 0.022) + twig.4)
                    let ripple = sin(clock * 1.08 + twig.4 * 1.7)
                    let sway = 5.8 * wave + 1.4 * ripple

                    BranchingCoralShape(bend: CGFloat(wave) * 0.13
                                              + CGFloat(ripple) * 0.035)
                        .stroke(
                            LinearGradient(colors: [.white.opacity(0.48),
                                                    palette.coralDeep.opacity(0.88)],
                                           startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: isPad ? 4.2 : 3,
                                               lineCap: .round,
                                               lineJoin: .round)
                        )
                        .frame(width: twigHeight * 0.82, height: twigHeight)
                        .rotationEffect(.degrees(twig.3 + sway), anchor: .bottom)
                        .position(x: w * twig.0,
                                  y: h * twig.1 - twigHeight / 2)
                }

                ForEach(Array(polyps.enumerated()), id: \.offset) { index, polyp in
                    CoralPolyp(palette: palette,
                               clock: clock,
                               phase: polyp.3)
                        .frame(width: basePolyp * polyp.2,
                               height: basePolyp * polyp.2)
                        .position(x: w * polyp.0, y: h * polyp.1)
                        .rotationEffect(.degrees(3 * sin(clock * 0.30 + Double(index))))
                }
            }
        }
    }
}

private struct CoralPolyp: View {
    let palette: ReefPalette
    let clock: Double
    let phase: Double

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let bloom = 0.90 + 0.10 * sin(clock * 0.58 + phase)

            ZStack {
                ForEach(0..<6, id: \.self) { petal in
                    Capsule()
                        .fill(.white.opacity(0.36))
                        .frame(width: size * 0.20, height: size * 0.52)
                        .offset(y: -size * 0.25)
                        .rotationEffect(.degrees(Double(petal) * 60))
                }
                Circle()
                    .fill(palette.coralDeep)
                    .frame(width: size * 0.31, height: size * 0.31)
            }
            .frame(width: size, height: size)
            .scaleEffect(bloom)
        }
    }
}

private struct ReefMassShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.02, y: h))
        path.addCurve(to: CGPoint(x: w * 0.04, y: h * 0.23),
                      control1: CGPoint(x: w * 0.00, y: h * 0.72),
                      control2: CGPoint(x: w * 0.01, y: h * 0.37))
        path.addCurve(to: CGPoint(x: w * 0.14, y: h * 0.08),
                      control1: CGPoint(x: w * 0.06, y: h * 0.14),
                      control2: CGPoint(x: w * 0.09, y: h * 0.08))
        path.addCurve(to: CGPoint(x: w * 0.31, y: h * 0.06),
                      control1: CGPoint(x: w * 0.20, y: h * 0.01),
                      control2: CGPoint(x: w * 0.26, y: h * 0.12))
        path.addCurve(to: CGPoint(x: w * 0.49, y: h * 0.07),
                      control1: CGPoint(x: w * 0.37, y: h * 0.01),
                      control2: CGPoint(x: w * 0.43, y: h * 0.03))
        path.addCurve(to: CGPoint(x: w * 0.68, y: h * 0.05),
                      control1: CGPoint(x: w * 0.55, y: h * 0.12),
                      control2: CGPoint(x: w * 0.62, y: h * 0.10))
        path.addCurve(to: CGPoint(x: w * 0.86, y: h * 0.08),
                      control1: CGPoint(x: w * 0.75, y: -h * 0.01),
                      control2: CGPoint(x: w * 0.81, y: h * 0.01))
        path.addCurve(to: CGPoint(x: w * 0.96, y: h * 0.23),
                      control1: CGPoint(x: w * 0.91, y: h * 0.08),
                      control2: CGPoint(x: w * 0.94, y: h * 0.14))
        path.addCurve(to: CGPoint(x: w * 0.98, y: h),
                      control1: CGPoint(x: w * 0.99, y: h * 0.48),
                      control2: CGPoint(x: w, y: h * 0.75))
        path.closeSubpath()
        return path
    }
}

// MARK: Sand

/// The floor: one soft mound rather than a straight edge, so the reef sits on a
/// little hill.
private struct SandBank: View {
    let palette: ReefPalette

    var body: some View {
        SandShape()
            .fill(
                LinearGradient(colors: [palette.sand, palette.sandDeep],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay {
                SandShape()
                    .stroke(palette.sandDeep.opacity(0.40), lineWidth: 1.5)
            }
            .accessibilityHidden(true)
    }
}

private struct SandShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        // The crown of the hill sits well above the sides, which is what makes
        // it read as a mound instead of a band across the bottom.
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: h * 0.72))
        path.addCurve(to: CGPoint(x: w * 0.50, y: h * 0.28),
                      control1: CGPoint(x: w * 0.14, y: h * 0.70),
                      control2: CGPoint(x: w * 0.28, y: h * 0.20))
        path.addCurve(to: CGPoint(x: rect.maxX, y: h * 0.66),
                      control1: CGPoint(x: w * 0.74, y: h * 0.22),
                      control2: CGPoint(x: w * 0.88, y: h * 0.66))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: Craters

/// The crest of the reef block: knobbly coral with the craters sunk into it.
/// Every bubble is released from one of these, at exactly these positions, so
/// an answer really does grow out of the hole it appears above.
private struct CraterRim: View {
    let palette: ReefPalette
    let isPad: Bool
    let clock: Double

    /// Fixed differences make the little vents feel grown rather than stamped.
    private static let ventScale: [CGFloat] = [0.76, 1.12, 0.66, 0.96, 0.80]
    private static let ventRise: [CGFloat] = [0.04, -0.04, 0.10, -0.07, 0.03]

    var body: some View {
        GeometryReader { proxy in
            // Craters are placed in screen coordinates, so the crest undoes its
            // own inset to line them up with where bubbles actually appear.
            let inset = ReefConfig.blockInset(isPad: isPad)
            let screenWidth = proxy.size.width + inset * 2
            let height = proxy.size.height
            let craters = ReefConfig.craterPositions(width: screenWidth, isPad: isPad)
                .map { $0 - inset }

            ZStack {
                ForEach(Array(crownPositions(between: craters).enumerated()), id: \.offset) { index, x in
                    crownSprout(height: height, index: index)
                        .position(x: x, y: height * 0.56)
                }

                ForEach(Array(craters.enumerated()), id: \.offset) { index, x in
                    vent(height: height, index: index)
                        .position(x: x,
                                  y: height * (0.74 + Self.ventRise[index % Self.ventRise.count]))
                }
            }
            .frame(width: proxy.size.width, height: height)
        }
        .accessibilityHidden(true)
    }

    /// A small raised lip with a dark centre. The answer bubble appears from
    /// this exact x-coordinate, so the animation still reads as an eruption.
    private func vent(height: CGFloat, index: Int) -> some View {
        let scale = Self.ventScale[index % Self.ventScale.count]
        let diameter = height * 0.64 * scale
        let breath = 1 + 0.055 * sin(clock * 0.85 + Double(index) * 1.3)
        return ZStack {
            Capsule()
                .fill(
                    LinearGradient(colors: [palette.coral.opacity(0.94), palette.coralDeep],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: diameter * 0.60, height: diameter * 0.88)
                .offset(y: diameter * 0.24)
            Ellipse()
                .fill(
                    LinearGradient(colors: [.white.opacity(0.38), palette.coralDeep],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: diameter, height: diameter * 0.52)
            Ellipse()
                .fill(palette.coralDeep.opacity(0.95))
                .frame(width: diameter * 0.50, height: diameter * 0.20)
                .overlay {
                    Ellipse()
                        .stroke(.black.opacity(0.18), lineWidth: 1)
                }
        }
        .scaleEffect(breath)
    }

    private func crownPositions(between craters: [CGFloat]) -> [CGFloat] {
        guard craters.count > 1 else { return [] }
        return zip(craters, craters.dropFirst()).map { ($0 + $1) / 2 }
    }

    private func crownSprout(height: CGFloat, index: Int) -> some View {
        let scales: [CGFloat] = [0.74, 0.52, 0.82, 0.60]
        let sproutHeight = height * scales[index % scales.count]
        let wave = sin(clock * (0.54 + Double(index) * 0.04) + Double(index) * 1.6)
        return BranchingCoralShape(bend: CGFloat(wave) * 0.12)
            .stroke(
                LinearGradient(colors: [.white.opacity(0.46), palette.coralDeep.opacity(0.82)],
                               startPoint: .top, endPoint: .bottom),
                style: StrokeStyle(lineWidth: isPad ? 3.2 : 2.3,
                                   lineCap: .round,
                                   lineJoin: .round)
            )
            .frame(width: sproutHeight * 0.72, height: sproutHeight)
            .rotationEffect(.degrees(4.5 * wave), anchor: .bottom)
    }
}

// MARK: Coral

/// Branching coral gardens at both shoulders of the central boulder.
private struct CoralClump: View {
    let palette: ReefPalette
    let isPad: Bool
    let clock: Double
    /// How far above the bottom of the band the fronds are rooted, so they come
    /// out of the sand rather than off the edge of the screen.
    let rootDepth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let root = max(isPad ? 72 : 54, height - rootDepth)
            let clusterWidth = isPad ? 128.0 : 86.0
            let leftWave = sin(clock * 0.62 + 0.3)
            let rightWave = sin(clock * 0.57 + 2.7)

            ZStack {
                branchCluster(bend: CGFloat(leftWave) * 0.16)
                    .frame(width: clusterWidth, height: root)
                    .rotationEffect(.degrees(5.5 * leftWave), anchor: .bottom)
                    .position(x: width * 0.09, y: root / 2)

                branchCluster(bend: CGFloat(rightWave) * 0.16)
                    .frame(width: clusterWidth, height: root)
                    .scaleEffect(x: -1, y: 1)
                    .rotationEffect(.degrees(5.2 * rightWave), anchor: .bottom)
                    .position(x: width * 0.91, y: root / 2)
            }
            .frame(width: width, height: height)
        }
        .accessibilityHidden(true)
    }

    private func branchCluster(bend: CGFloat) -> some View {
        BranchingCoralShape(bend: bend)
            .stroke(
                LinearGradient(colors: [palette.coral.opacity(0.92), palette.coralDeep],
                               startPoint: .top, endPoint: .bottom),
                style: StrokeStyle(lineWidth: isPad ? 13 : 9,
                                   lineCap: .round,
                                   lineJoin: .round)
            )
            .shadow(color: palette.coralDeep.opacity(0.22), radius: 3, y: 3)
    }
}

private struct BranchingCoralShape: Shape {
    var bend: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()

        path.move(to: CGPoint(x: w * 0.52, y: h))
        path.addCurve(to: CGPoint(x: w * (0.43 + bend), y: h * 0.08),
                      control1: CGPoint(x: w * 0.54, y: h * 0.68),
                      control2: CGPoint(x: w * (0.39 + bend * 0.72), y: h * 0.36))

        path.move(to: CGPoint(x: w * 0.48, y: h * 0.66))
        path.addCurve(to: CGPoint(x: w * (0.16 + bend * 0.68), y: h * 0.29),
                      control1: CGPoint(x: w * 0.38, y: h * 0.52),
                      control2: CGPoint(x: w * (0.24 + bend * 0.45), y: h * 0.47))

        path.move(to: CGPoint(x: w * 0.46, y: h * 0.48))
        path.addCurve(to: CGPoint(x: w * (0.74 + bend * 1.12), y: h * 0.17),
                      control1: CGPoint(x: w * 0.57, y: h * 0.38),
                      control2: CGPoint(x: w * (0.68 + bend * 0.78), y: h * 0.31))

        path.move(to: CGPoint(x: w * 0.28, y: h * 0.43))
        path.addCurve(to: CGPoint(x: w * (0.10 + bend * 0.54), y: h * 0.10),
                      control1: CGPoint(x: w * 0.20, y: h * 0.34),
                      control2: CGPoint(x: w * (0.13 + bend * 0.40), y: h * 0.22))

        return path
    }
}

// MARK: Plants

/// Small grass-like plants distributed over the foreground. Their roots are
/// covered by the near sand bank and every blade gets a slightly different
/// current, avoiding the synchronized metronome look.
private struct SeaPlantField: View {
    let palette: ReefPalette
    let isPad: Bool
    let clock: Double

    private let plants: [(CGFloat, CGFloat, Double)] = [
        // Lower shoulder plants: still lively, but kept clear of the equation.
        (0.035, 0.58, 0.2), (0.105, 0.76, 1.4), (0.185, 0.52, 3.1),
        (0.270, 0.60, 4.6),
        // A short foreground garden directly beneath the equation.
        (0.365, 0.28, 2.5), (0.435, 0.34, 5.6), (0.500, 0.30, 0.8),
        (0.565, 0.36, 3.7), (0.635, 0.27, 1.9),
        // An intentionally different rhythm on the right shoulder.
        (0.730, 0.58, 2.2), (0.810, 0.50, 5.3),
        (0.895, 0.74, 3.8), (0.970, 0.56, 0.9)
    ]

    var body: some View {
        GeometryReader { proxy in
            let baseHeight = isPad ? 112.0 : 82.0
            let rootY = proxy.size.height - (isPad ? 31.0 : 24.0)

            ForEach(Array(plants.enumerated()), id: \.offset) { index, plant in
                SeaPlant(palette: palette,
                         clock: clock,
                         phase: plant.2,
                         isPad: isPad)
                    .frame(width: (isPad ? 88 : 62) * min(1, max(0.58, plant.1)),
                           height: baseHeight * plant.1)
                    .position(x: proxy.size.width * plant.0,
                              y: rootY - baseHeight * plant.1 / 2)
                    .opacity(plant.1 < 0.40 ? 0.84 : (index == 2 || index == 10 ? 0.82 : 1))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SeaPlant: View {
    let palette: ReefPalette
    let clock: Double
    let phase: Double
    let isPad: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack(alignment: .bottom) {
                ForEach(0..<4, id: \.self) { blade in
                    let bladePhase = phase + Double(blade) * 1.15
                    let sway = sin(clock * (0.60 + Double(blade) * 0.045) + bladePhase)
                    let ripple = sin(clock * 1.16 + bladePhase * 1.4)
                    let bladeHeight = height * (0.62 + CGFloat(blade) * 0.105)

                    PlantBladeShape(bend: CGFloat(sway) * 0.31
                                          + CGFloat(ripple) * 0.06
                                          + CGFloat(blade - 1) * 0.08)
                        .stroke(
                            LinearGradient(colors: [palette.plantLight, palette.plant],
                                           startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: isPad ? 7 : 5,
                                               lineCap: .round)
                        )
                        .frame(width: width, height: bladeHeight)
                        .offset(x: CGFloat(blade - 1) * width * 0.09)
                }
            }
            .frame(width: width, height: height)
        }
    }
}

private struct PlantBladeShape: Shape {
    let bend: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.midX + rect.width * bend, y: rect.minY),
                      control1: CGPoint(x: rect.midX, y: rect.height * 0.68),
                      control2: CGPoint(x: rect.midX + rect.width * bend * 1.4,
                                        y: rect.height * 0.30))
        return path
    }
}

// MARK: The sum

/// The equation is printed directly on the coral. It changes with a short
/// dissolve, but deliberately has no card, panel, cavity or own background.
private struct CoralQuestion: View {
    let prompt: String
    let roundID: UUID?
    let palette: ReefPalette
    let isPad: Bool

    @State private var shownPrompt = ""
    @State private var isVisible = true

    var body: some View {
        VStack(spacing: isPad ? 4 : 1) {
            Text(verbatim: shownPrompt)
                .font(.system(size: isPad ? 46 : 35,
                              weight: .black, design: .rounded))
                .minimumScaleFactor(0.32)
                .lineLimit(1)
                .foregroundStyle(.white)
                .shadow(color: palette.coralDeep.opacity(0.95), radius: 1, y: 3)
        }
        .padding(.horizontal, isPad ? 12 : 8)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.96)
        .onAppear {
            shownPrompt = prompt
        }
        .onChange(of: roundID) { _, _ in revealNewQuestion() }
        .accessibilityIdentifier("question-card")
        .accessibilityLabel(Text(L("game.question \(prompt)")))
    }

    private func revealNewQuestion() {
        guard !shownPrompt.isEmpty else {
            shownPrompt = prompt
            return
        }
        withAnimation(.easeOut(duration: 0.10)) { isVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            shownPrompt = prompt
            withAnimation(.easeOut(duration: 0.20)) { isVisible = true }
        }
    }
}
