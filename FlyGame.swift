//
//  FlyGame.swift
//  Hungry Frog
//
//  The replacement for the reef's concrete play interaction. Session rules,
//  questions, scoring, lives and persistence remain owned by MemoryGame.
//

import SwiftUI
import Combine
import QuartzCore

private enum FlyConfig {
    static let tick = 1.0 / 60.0
    static let extensionTime = 0.13
    static let contactTime = 0.10
    static let retractionTime = 0.19
    /// How long the sticky pad stays visibly flattened. Slightly longer than
    /// the contact hold so the squash relaxes into the start of the pull-back.
    static let splatTime = 0.14

    /// A new swarm arrives as a ripple rather than a single pop: this is the
    /// gap between one fly starting its swoop and the next.
    static let entryStagger = 0.06
    /// The swoop covers ground at a steady pace whatever edge it comes from.
    /// Timing it by distance rather than by the clock is what stops a fly from
    /// the far corner tearing across the screen while its neighbour drifts in.
    static func entryApproachSpeed(isPad: Bool) -> CGFloat { isPad ? 520 : 340 }
    /// The band that pace is allowed to work out to.
    static let entryDuration: ClosedRange<Double> = 0.45...0.85
    /// How far past its place the swoop carries before settling back.
    static let entryOvershoot: CGFloat = 0.42
    /// Where the swoop hands over to free flight. The curve is 99% arrived by
    /// here and still carrying about a cruising speed's worth of momentum;
    /// letting it run to the very end would park the fly for a fifth of a
    /// second and then jerk it into a wander from a standstill.
    static let entryHandover = 0.66

    /// A finished question's flies sweep away from the character. They leave at
    /// whatever pace they were already flying and ease up to a full sweep-out
    /// over a quarter of a second, so the turn outwards is the only thing the
    /// eye catches: no kick at the start, and no jolt when they top out.
    static func scatterLaunchSpeed(isPad: Bool) -> CGFloat { isPad ? 150 : 120 }
    static func scatterTopSpeed(isPad: Bool) -> CGFloat { isPad ? 2000 : 1600 }
    static let scatterRamp = 0.26

    static func scatterSpeed(at age: Double, launch: CGFloat, isPad: Bool) -> CGFloat {
        let x = CGFloat(min(1, max(0, age / scatterRamp)))
        return launch + (scatterTopSpeed(isPad: isPad) - launch) * x * x * (3 - 2 * x)
    }

    /// The three droppings a swallowed wrong answer leaves behind. They are
    /// thrown up out of the top of the head and fall back past it under their
    /// own weight, each one a little later and a little differently than the
    /// last so the burst never reads as one object split in three.
    ///
    /// All of it is measured against the character it comes out of rather than
    /// given in points, so the burst keeps its proportions on a phone and on a
    /// pad instead of needing a size for each. Launch and gravity are scaled
    /// together, which lowers the arc without changing how long it takes.
    static let poopLifetime = 1.05
    static let poopDelays: [Double] = [0, 0.055, 0.11]
    static func poopLaunchSpeed(bodyWidth: CGFloat) -> CGFloat { bodyWidth * 1.47 }
    static func poopGravity(bodyWidth: CGFloat) -> CGFloat { bodyWidth * 3.92 }
    static func poopDrift(bodyWidth: CGFloat) -> CGFloat { bodyWidth * 0.35 }
    static func poopSize(bodyWidth: CGFloat) -> CGFloat { bodyWidth * 0.14 }

    /// The tick a right answer leaves instead. Same size as a dropping, so the
    /// two verdicts read as the same kind of thing, but it hops out once and
    /// holds where it can be seen rather than tumbling back down.
    static let praiseLifetime = 0.85
    static func praiseSize(bodyWidth: CGFloat) -> CGFloat { poopSize(bodyWidth: bodyWidth) }

    /// Where both leave from, as a fraction of the playing artwork, measured off
    /// the character's own mouth: every pose is drawn around the same lounger,
    /// so the top of the head sits this far above the muzzle whichever animal is
    /// being played.
    static let poopHeadOffset = CGSize(width: -0.02, height: -0.28)
    /// Where the tick comes to rest, measured off the mouth the same way: out
    /// past the brow on the side the character faces, and barely above the top
    /// of the head. It belongs to the animal, so it stays against it instead of
    /// climbing off into the sky the way a thrown dropping does.
    static let praiseRestOffset = CGSize(width: -0.234, height: -0.341)

    /// Belt and braces: a scattered fly is dropped after this long even if the
    /// geometry somehow kept it inside the frame. Comfortably past the worst
    /// case the sweep-out speeds above produce on any screen the game runs at,
    /// because nothing fades any more — a fly still in frame would simply pop.
    static let scatterLifetime = 0.85

    /// Where the pond's surface sits, and with it the bank the character
    /// lounges on.
    static let waterlineShare: CGFloat = 0.72

    static func flySize(isPad: Bool) -> CGFloat { isPad ? 92 : 70 }
    /// The food art and its answer number are drawn a third larger than the
    /// tap target itself, so the number has real room at the food's centre —
    /// the tap target, spacing and swarm density it flies in are unaffected.
    static let foodVisualScale: CGFloat = 1.3
    static func offscreenMargin(isPad: Bool) -> CGFloat { isPad ? 118 : 86 }
    static func obstaclePadding(isPad: Bool) -> CGFloat { isPad ? 14 : 10 }

    /// The character keeps a smaller no-fly ring around it than the interface
    /// does. It is a painted pose, not a control that has to stay readable, so
    /// the flies are allowed to buzz close around it — down the sides and
    /// across the water beneath it — as long as they never overlap it.
    static func characterPadding(isPad: Bool) -> CGFloat { isPad ? 9 : 6 }

    /// The playing artwork is a wide reclining pose rather than the square
    /// portrait the scene used to be built around, so it is sized off both
    /// axes: as wide as the scene affords, but never so tall that the pose eats
    /// the airspace the flies need. One rule covers all ten characters — they
    /// are drawn around the same lounger, which is what fixes their scale
    /// relative to one another. The shares are deliberately modest: the pose is
    /// the target the tongue leaves from, not the subject of the screen, and
    /// the room it gives back is airspace the flies can be caught in.
    static func characterWidth(isPad: Bool, in size: CGSize) -> CGFloat {
        min(size.width * (isPad ? 0.41 : 0.34),
            size.height * (isPad ? 0.31 : 0.36) * AnimalCharacter.playAspectRatio)
    }

    /// The frame the playing artwork is drawn in: centred, and pushed down to
    /// the foot of the scene, with the lounger's feet in the shallows. Sitting
    /// it any higher wastes the airspace the flies are caught in and leaves an
    /// empty strip of pond under the pose.
    static func characterRect(isPad: Bool, in size: CGSize) -> CGRect {
        let width = characterWidth(isPad: isPad, in: size)
        let height = width / AnimalCharacter.playAspectRatio
        // Held just off the very bottom edge so the lounger's legs are never
        // cropped by the screen or lost under the home indicator.
        let bottom = min(size.height - height * 0.04,
                         size.height * waterlineShare + height * 0.86)
        return CGRect(x: (size.width - width) * 0.5, y: bottom - height,
                      width: width, height: height)
    }
}

/// The one measurement the scenery has to agree with the game about. A scene is
/// handed the frame the reclining pose is drawn in directly; the height its
/// ground line sits at belongs to the simulation, and a scene that guessed at it
/// would leave the lounger standing on nothing.
enum PlayStage {
    static func horizon(in size: CGSize) -> CGFloat {
        size.height * FlyConfig.waterlineShare
    }
}

private enum FlyPattern: CaseIterable {
    case wander
    case wave
    case looper
    case dart
}

/// The swoop that carries a fly from off screen onto its place in the swarm.
private struct FlyEntry {
    let from: CGPoint
    let to: CGPoint
    let duration: Double
    /// Time still to run before the swoop starts, which is what staggers a
    /// freshly dealt swarm.
    var delay: Double
    var elapsed: Double = 0

    var hasStarted: Bool { delay <= 0 }
    var isFinished: Bool {
        hasStarted && elapsed >= duration * FlyConfig.entryHandover
    }

    /// Straight out of the wing and easing into a small overshoot, so the fly
    /// arrives with a settle rather than braking to a dead stop.
    var progress: CGFloat {
        let t = CGFloat(min(1, max(0, elapsed / duration)))
        let overshoot = FlyConfig.entryOvershoot
        return 1 + (overshoot + 1) * pow(t - 1, 3) + overshoot * pow(t - 1, 2)
    }

    /// The pace the swoop itself is carrying at the handover, so free flight
    /// picks up where the curve leaves off instead of restarting from nothing.
    var handoverSpeed: CGFloat {
        let t = CGFloat(FlyConfig.entryHandover)
        let overshoot = FlyConfig.entryOvershoot
        let slope = 3 * (overshoot + 1) * pow(t - 1, 2) + 2 * overshoot * (t - 1)
        return abs(slope) * hypot(to.x - from.x, to.y - from.y) / CGFloat(duration)
    }

    var point: CGPoint {
        let p = progress
        return CGPoint(x: from.x + (to.x - from.x) * p,
                       y: from.y + (to.y - from.y) * p)
    }

    var heading: CGFloat { atan2(to.y - from.y, to.x - from.x) }
}

private struct AnswerFly: Identifiable {
    let id = UUID()
    var roundID: UUID
    var optionID: UUID
    let text: String
    var isCorrect: Bool
    var position: CGPoint
    var velocity: CGVector
    let phase: Double
    let pattern: FlyPattern
    let baseSpeed: CGFloat
    var age: Double = 0
    var isLocked = false
    var isRetiring = false
    /// True from the frame the sticky pad lands on this fly until the strike
    /// lets go of it. The swarm stops drawing it then — the tongue is carrying
    /// its own copy home. Held on the fly rather than looked up on the strike so
    /// the swarm never has to observe the tongue.
    var isCaptured = false
    /// Non-nil only while the fly is still swooping in.
    var entry: FlyEntry? = nil
    /// Seconds since this fly was scattered, driving its tumble away.
    var exitAge: Double = 0
    /// The pace it was already flying at when it was dismissed, which is where
    /// its sweep out of frame picks up from.
    var exitSpeed: CGFloat = 0
    /// Degrees per second the scattered fly tumbles at.
    var spin: Double = 0

    /// Whether the fly is under its own steam and can be caught: not still
    /// swooping in, not on its way out, and not already held by the tongue.
    var isFlying: Bool { entry == nil && !isRetiring && !isLocked }

    /// 0 the moment the swarm is dismissed, 1 once it is up to full speed.
    /// Drives a slight shrink, so the sweep out reads as distance. Nothing
    /// fades: a fly that is off screen inside half a second has no need to be
    /// dimmed on its way, and dimming it only made the swap look like a
    /// transition rather than flies flying off.
    var scatterProgress: CGFloat {
        guard isRetiring else { return 0 }
        return CGFloat(min(1, exitAge / FlyConfig.scatterRamp))
    }

    /// A fly that has not begun its swoop must not be drawn hanging off screen,
    /// and one the pad already has is drawn by the tongue instead. The struck
    /// fly keeps flying until the pad actually reaches it: hiding it on tap made
    /// it blink away well before the tongue arrived.
    var isVisible: Bool {
        guard !isCaptured else { return false }
        guard let entry else { return true }
        return entry.hasStarted
    }
}

private struct FlySpec: Equatable {
    let roundID: UUID
    let option: AnswerOption
}

private struct TongueCatch {
    let flyID: UUID
    let roundID: UUID
    let optionID: UUID
    let text: String
    let isCorrect: Bool
    let flyPhase: Double
    let start: CGPoint
    let target: CGPoint
    var elapsed: Double = 0
    var didReportContact = false
    var wasAccepted: Bool?

    var total: Double {
        FlyConfig.extensionTime + FlyConfig.contactTime + FlyConfig.retractionTime
    }

    /// Ballistic launch: nearly all of the distance is covered immediately, and
    /// the pad presses a little past the fly before settling onto it. The
    /// overshoot stays small — at 7% of a screen-wide reach the pad visibly
    /// shoots straight through its target.
    var extensionProgress: CGFloat {
        let t = CGFloat(min(1, max(0, elapsed / FlyConfig.extensionTime)))
        let overshoot: CGFloat = 0.5
        return 1 + (overshoot + 1) * pow(t - 1, 3) + overshoot * pow(t - 1, 2)
    }

    /// The stick has to be broken before the tongue reels in, so the pull-back
    /// starts heavy and then snaps home.
    var retractionProgress: CGFloat {
        let begin = FlyConfig.extensionTime + FlyConfig.contactTime
        guard elapsed > begin else { return 0 }
        let t = CGFloat(min(1, (elapsed - begin) / FlyConfig.retractionTime))
        return t * t * (1.7 - 0.7 * t)
    }

    /// 1 at the frame the pad lands, decaying to 0 across the splat window.
    var impact: CGFloat {
        guard elapsed >= FlyConfig.extensionTime else { return 0 }
        let t = (elapsed - FlyConfig.extensionTime) / FlyConfig.splatTime
        return CGFloat(max(0, 1 - t))
    }

    var hasLanded: Bool { elapsed >= FlyConfig.extensionTime }

    /// How far the catch is into being eaten, across the whole pull-back rather
    /// than only its last stretch. Everything the tongue is carrying is sized
    /// off this, so the fly is already small by the time it reaches the lip
    /// instead of arriving full size and being wished away.
    var swallowProgress: CGFloat {
        let t = retractionProgress
        return t * t
    }

    var tip: CGPoint {
        let outward = CGPoint(x: start.x + (target.x - start.x) * extensionProgress,
                              y: start.y + (target.y - start.y) * extensionProgress)
        return CGPoint(x: outward.x + (start.x - outward.x) * retractionProgress,
                       y: outward.y + (start.y - outward.y) * retractionProgress)
    }
}

/// One dropping of the burst a wrong answer produces, thrown out of the top of
/// the character's head. Positions are offsets from that head, so the layer
/// drawing them only has to know where the head is.
private struct PoopDrop: Identifiable {
    let id = UUID()
    /// How much later than the first of the burst this one leaves.
    let delay: Double
    /// Sideways travel and upward launch, in points per second.
    let drift: CGFloat
    let launch: CGFloat
    let gravity: CGFloat
    /// Degrees per second it tumbles at, and how big it is drawn.
    let spin: Double
    let size: CGFloat
    var elapsed: Double = 0

    var isFinished: Bool { elapsed >= delay + FlyConfig.poopLifetime }

    /// Time this one has actually been in the air.
    private var flight: Double { max(0, elapsed - delay) }

    var offset: CGSize {
        let t = CGFloat(flight)
        return CGSize(width: drift * t,
                      height: -launch * t + gravity * t * t * 0.5)
    }

    var rotation: Double { spin * flight }

    /// Pops to full size as it leaves, then thins out over the last stretch of
    /// the fall rather than vanishing at the top of its arc.
    var scale: CGFloat {
        CGFloat(min(1, flight / 0.11)) * 0.35 + (flight > 0 ? 0.65 : 0)
    }

    var opacity: Double {
        guard flight > 0 else { return 0 }
        let fade = FlyConfig.poopLifetime - 0.32
        return flight <= fade ? 1 : max(0, 1 - (flight - fade) / 0.32)
    }
}

/// The tick a right answer pops out of the head with. The sound is the usual
/// confirmation, but a child playing with it switched off — or in a noisy
/// room — needs to be told they were right just as plainly, and this is that.
private struct HeadPraise {
    let id = UUID()
    let size: CGFloat
    var elapsed: Double = 0

    var isFinished: Bool { elapsed >= FlyConfig.praiseLifetime }

    /// How far along the hop from the head to its resting place it is: out fast
    /// and easing to a stop, so it reads as thrown clear of the head rather
    /// than slid into place. The two ends are the layer's to know — they come
    /// off the artwork, which the simulation has no picture of.
    var travel: CGFloat {
        let t = CGFloat(min(1, elapsed / 0.34))
        return 1 - pow(1 - t, 3)
    }

    /// A spring-loaded pop: past full size at the top of the climb and back.
    var scale: CGFloat {
        let t = CGFloat(min(1, elapsed / 0.30))
        let overshoot: CGFloat = 0.55
        return 1 + (overshoot + 1) * pow(t - 1, 3) + overshoot * pow(t - 1, 2)
    }

    var opacity: Double {
        let fade = FlyConfig.praiseLifetime - 0.26
        return elapsed <= fade ? 1 : max(0, 1 - (elapsed - fade) / 0.26)
    }
}

/// `CADisplayLink` keeps its target alive, so the engine cannot be it: the
/// link would hold the engine that holds the link and neither would ever go.
/// This forwards the frame on and lets the engine be released normally.
private final class FlyEngineTicker: NSObject {
    weak var engine: FlyEngine?

    init(engine: FlyEngine) {
        self.engine = engine
    }

    @objc func step(_ link: CADisplayLink) {
        // The link was added to the main run loop, so this is the main thread.
        MainActor.assumeIsolated { engine?.step(link.timestamp) }
    }
}

#if PERF_WATCH
/// Counts the frames the game actually got, and files the ones it missed under
/// whatever was on screen at the time.
///
/// This exists so a stutter can be attributed rather than guessed at. The
/// display link is handed a frame at a fixed rate; a gap wider than one refresh
/// means the main thread did not finish its work in time and the system skipped
/// a frame. Grouping those gaps by what the simulation was doing is what tells
/// the difference between "the swoop-in is expensive" and "the swoop-in happens
/// to be when something else is expensive".
///
/// Debug only — it never reaches a shipped build.
@MainActor
final class FlyFrameWatch {
    static let shared = FlyFrameWatch()

    private struct Tally {
        var dropped = 0
        var hitches = 0
        var worst = 0
    }

    /// The link is asked for 60, so a well-fed frame is one sixtieth apart.
    private let expected = 1.0 / 60.0
    private let reportEvery = 5.0

    private var last: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var drawn = 0
    private var byPhase: [String: Tally] = [:]

    /// How long the main thread is actually busy each turn of the run loop —
    /// the display-link callback, the SwiftUI update behind it and the Core
    /// Animation commit at the end, all together.
    ///
    /// This is the number that decides what a dropped frame means. Sixteen
    /// milliseconds of work and dropped frames is our problem to fix. Two
    /// milliseconds of work and dropped frames is something below us — a
    /// simulator rendering through the host, most likely — and no amount of
    /// tuning up here would move it.
    private var observer: CFRunLoopObserver?
    private var busyStart: CFTimeInterval = 0
    /// Wall time says how long the turn took; CPU time says how much of that
    /// was this thread actually working. A wide gap between them means the main
    /// thread is blocked — waiting on the render server, most likely — rather
    /// than computing, and no amount of tuning our own code would close it.
    private var cpuStart: Double = 0
    private var cpuTotal: Double = 0

    fileprivate static func threadCPUSeconds() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1_000_000_000
    }
    private var busyTotal: Double = 0
    private var busyPeak: Double = 0
    private var busySamples = 0

    private func watchRunLoop() {
        guard observer == nil else { return }
        let activities = CFRunLoopActivity.afterWaiting.rawValue
            | CFRunLoopActivity.beforeWaiting.rawValue
        let created = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, activities, true, 0
        ) { _, activity in
            MainActor.assumeIsolated {
                let watch = FlyFrameWatch.shared
                if activity == .afterWaiting {
                    watch.busyStart = CACurrentMediaTime()
                    watch.cpuStart = FlyFrameWatch.threadCPUSeconds()
                } else if watch.busyStart > 0 {
                    let busy = CACurrentMediaTime() - watch.busyStart
                    watch.busyTotal += busy
                    watch.busyPeak = max(watch.busyPeak, busy)
                    watch.cpuTotal += FlyFrameWatch.threadCPUSeconds() - watch.cpuStart
                    watch.busySamples += 1
                    watch.busyStart = 0
                }
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), created, .commonModes)
        observer = created
    }

    /// Called once per display frame. `phase` is only built when a frame was
    /// actually missed, so a healthy frame costs a subtraction.
    func frame(at timestamp: CFTimeInterval, phase: @autoclosure () -> String) {
        defer { last = timestamp }
        guard last > 0 else {
            windowStart = timestamp
            return
        }
        drawn += 1
        let missed = Int(((timestamp - last) / expected).rounded()) - 1
        if missed > 0 {
            let key = phase()
            var tally = byPhase[key] ?? Tally()
            tally.dropped += missed
            tally.hitches += 1
            tally.worst = max(tally.worst, missed)
            byPhase[key] = tally
        }
        if timestamp - windowStart >= reportEvery {
            let window = timestamp - windowStart
            let tallies = byPhase
            let frames = drawn
            let busy = Busy(average: busySamples > 0 ? busyTotal / Double(busySamples) : 0,
                            peak: busyPeak, turns: busySamples,
                            cpu: busySamples > 0 ? cpuTotal / Double(busySamples) : 0)
            windowStart = timestamp
            drawn = 0
            byPhase.removeAll()
            busyTotal = 0
            busyPeak = 0
            busySamples = 0
            cpuTotal = 0
            // Printing is not free, and doing it here would inflate the very
            // frame the next reading starts from.
            DispatchQueue.main.async { Self.report(frames, tallies, busy, over: window) }
        }
    }

    /// Wipes the running figures, so a report covers play rather than the
    /// transition into it.
    func reset() {
        watchRunLoop()
        last = 0
        drawn = 0
        byPhase.removeAll()
        busyTotal = 0
        busyPeak = 0
        busySamples = 0
        cpuTotal = 0
    }

    private struct Busy {
        let average: Double
        let peak: Double
        let turns: Int
        let cpu: Double
    }

    private static func report(_ drawn: Int, _ byPhase: [String: Tally],
                               _ busy: Busy, over seconds: Double) {
        let dropped = byPhase.values.reduce(0) { $0 + $1.dropped }
        let total = drawn + dropped
        let share = total > 0 ? Double(dropped) / Double(total) * 100 : 0
        print(String(format: "[frames] %.0fs — drew %d, dropped %d (%.1f%%)",
                     seconds, drawn, dropped, share))
        print(String(format: "[frames]   main thread busy %.1fms avg, %.1fms peak, over %d turns"
                     + "  (a 60fps frame allows 16.7ms)",
                     busy.average * 1000, busy.peak * 1000, busy.turns))
        print(String(format: "[frames]   of which actual CPU %.1fms — the rest is the main "
                     + "thread blocked, not working", busy.cpu * 1000))
        for (phase, tally) in byPhase.sorted(by: { $0.value.dropped > $1.value.dropped }) {
            print("[frames]   \(phase): \(tally.dropped) dropped "
                  + "over \(tally.hitches) hitches, worst \(tally.worst) in a row")
        }
    }
}
#endif

/// One observable value, and nothing else in the same object.
///
/// The engine used to be a single `ObservableObject` with five `@Published`
/// properties. Combine has no idea which of them a given view reads: any change
/// to any one of them wakes every view observing the engine. The clock alone
/// ticks sixty times a second, so the tongue layer and the head-mark layer were
/// rebuilt on every frame of the game — including the great majority of frames
/// where there is no tongue and no mark to draw.
///
/// Splitting the state into separate boxes is what makes "only the layers that
/// actually changed" true rather than merely intended.
/// Three concrete boxes rather than one generic one. A generic
/// `ObservableObject` reads better, but its `deinit` crashes the Swift
/// optimizer outright — the whole-module Release build fails with an
/// `EarlyPerfInliner` assertion, which is to say the app cannot be archived at
/// all. Written out long-hand it compiles, and there are only ever three.
@MainActor
private final class SwarmChannel: ObservableObject {
    @Published fileprivate(set) var value = SwarmFrame()
}

@MainActor
private final class StrikeChannel: ObservableObject {
    @Published fileprivate(set) var value: TongueCatch?
}

@MainActor
private final class MarkChannel: ObservableObject {
    @Published fileprivate(set) var value = HeadMarks()
}

/// Everything the swarm layer draws, handed over in one publish per frame.
private struct SwarmFrame {
    var clock: Double = 0
    var flies: [AnswerFly] = []
}

/// The verdict marks over the character's head. Empty on all but a fraction of
/// the frames in a session, which is the point of keeping them in their own box.
private struct HeadMarks {
    var poops: [PoopDrop] = []
    var praise: HeadPraise?

    var isEmpty: Bool { poops.isEmpty && praise == nil }
}

@MainActor
private final class FlyEngine {
    /// The swarm and the clock it flies on: new every frame, by definition.
    let swarm = SwarmChannel()
    /// The strike, published only while one is in the air.
    let strike = StrikeChannel()
    /// The droppings and the tick, published only while one of them exists.
    let marks = MarkChannel()

    private var flies: [AnswerFly] = []
    private var tongue: TongueCatch?
    private var poops: [PoopDrop] = []
    private var praise: HeadPraise?
    private var clock: Double = 0

    var onHit: ((UUID) -> Bool)?
    /// The frame the sticky pad lands on a piece of food, right or wrong.
    var onImpact: (() -> Void)?
    /// The frame a caught answer reaches the mouth, with whether it was right.
    /// The outcome is only sounded here, at the swallow: the strike itself is a
    /// third of a second long, and a verdict at the far end of it arrives
    /// before the child has seen the food move.
    var onSwallow: ((Bool) -> Void)?

    private var rounds: [GameRound] = []
    /// The question the swarm on screen belongs to. A wrong answer leaves the
    /// same sum standing, and that must not deal a fresh swarm on top of it.
    private var activeRoundID: UUID?
    private var size: CGSize = .zero
    private var topReserve: CGFloat = 0
    private var protectedRects: [CGRect] = []
    private var characterRect: CGRect = .zero
    /// The lowest a fly may fly. It sits just above the home indicator rather
    /// than at the waterline, so the swarm can use the banks either side of the
    /// character and the stretch of water in front of it.
    private var flightFloor: CGFloat = 0
    private var isPad = false
    private var isLive = false
    private var isRunning = false
    /// Answers waiting for a playing field to be dealt onto.
    private var pendingSpecs: [FlySpec] = []
    /// Answers already eaten on the standing question, which must not come back.
    private var retiredOptionIDs: Set<UUID> = []
    /// The simulation runs off the display's own heartbeat rather than a
    /// `Timer`: a timer at 1/60 drifts against the refresh rate, so some frames
    /// got two steps and others none — visible as a stutter in a swarm that is
    /// otherwise moving smoothly. The link also stops cleanly with the screen.
    private var displayLink: CADisplayLink?
    private var lastFrameTime: CFTimeInterval = 0
    /// Left-over frame time, so the simulation still advances in fixed steps
    /// (every constant in `FlyConfig` is expressed per step) whatever the
    /// display is actually running at.
    private var stepAccumulator: Double = 0

    deinit { displayLink?.invalidate() }

    // MARK: - Publishing

    /// Hands this frame's state to the layers that draw it. The swarm goes out
    /// every time; the other two only when there is something to say, so a view
    /// with nothing on screen is never invalidated.
    private func publish() {
        swarm.value = SwarmFrame(clock: clock, flies: flies)
        if tongue != nil || strike.value != nil { strike.value = tongue }
        if !poops.isEmpty || praise != nil || !marks.value.isEmpty {
            marks.value = HeadMarks(poops: poops, praise: praise)
        }
    }

    // MARK: - Layout

    func layout(size: CGSize, topReserve: CGFloat,
                protectedRects: [CGRect], characterRect: CGRect,
                flightFloor: CGFloat, isPad: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        self.size = size
        self.topReserve = topReserve
        self.protectedRects = protectedRects
        self.characterRect = characterRect
        self.flightFloor = flightFloor
        self.isPad = isPad
        for index in flies.indices where flies[index].isFlying {
            flies[index].position = clampToFlightRoute(flies[index].position)
        }
        // The first real layout is usually what a swarm dealt on the very first
        // frame was waiting for.
        dealPendingSwarm()
        publish()
    }

    // MARK: - Question changes

    /// Deals the swarm for the active question. A correct catch scatters the
    /// whole of the previous swarm outwards and swoops five fresh answers in
    /// behind it. The two overlap on purpose: that overlap is what turns the
    /// gap between questions into a beat instead of a wait.
    func sync(rounds: [GameRound]) {
        self.rounds = rounds
        guard let activeRound = rounds.first else {
            activeRoundID = nil
            pendingSpecs.removeAll()
            retiredOptionIDs.removeAll()
            releaseTongue()
            // The simulation stops with the session, so anything still in the
            // air would hang there for as long as the scene is up.
            poops.removeAll()
            praise = nil
            scatter { _ in true }
            publish()
            return
        }

        // The same sum standing again after a mistake keeps its swarm, minus
        // the fly that was just burned.
        guard activeRound.id != activeRoundID else { return }
        activeRoundID = activeRound.id
        retiredOptionIDs.removeAll()

        // A strike already in the air is left alone: the round only turns over
        // because that strike landed, and the last stretch of the pull-back now
        // overlaps the next question by a hair. `scatter` steps around the fly
        // the tongue is holding, so it stays put under the pad and is cleaned
        // up by the strike itself.
        scatter { $0.roundID != activeRound.id }

        var specs = activeRound.options
            .map { FlySpec(roundID: activeRound.id, option: $0) }
            .shuffled()
        // Whichever way the swarm is shuffled, the answer actually being asked
        // for is in the first two swoops. Waiting on the right fly to arrive is
        // the one delay a child feels.
        if let index = specs.firstIndex(where: { $0.option.isCorrect }), index > 1 {
            specs.swapAt(index, Int.random(in: 0...1))
        }
        // Queued, not dealt. The frame a round turns over on is already the
        // fattest in the game — the session advances, a sum is generated, the
        // whole game screen is rebuilt behind it, the score starts animating and
        // the old swarm is sent packing, all at once — and it is also the first
        // frame of the swoop the child is watching. Placing and spawning the new
        // answers waits for the next tick, a sixtieth later: nobody can see the
        // difference, and the two lots of work stop sharing a frame.
        pendingSpecs = specs
        publish()
    }

    func setLive(_ live: Bool) {
        isLive = live
        if live {
            dealPendingSwarm()
            publish()
        }
    }

    func setRunning(_ running: Bool) {
        isRunning = running
        if running {
            guard displayLink == nil else { return }
            lastFrameTime = 0
            stepAccumulator = 0
#if PERF_WATCH
            // Starting play is itself a heavy frame; it is not what is being
            // measured, so the count begins after it.
            FlyFrameWatch.shared.reset()
#endif
            let link = CADisplayLink(target: FlyEngineTicker(engine: self),
                                     selector: #selector(FlyEngineTicker.step(_:)))
            // The swarm is authored at 60 steps a second; asking a 120 Hz
            // display for twice the frames would double the work for motion
            // the simulation does not produce.
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30,
                                                            maximum: 60,
                                                            preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    /// One display frame: catches the simulation up in whole steps, never more
    /// than a couple at a time so a stall (a lock screen, a heavy transition)
    /// cannot be paid back as one enormous jump.
    fileprivate func step(_ timestamp: CFTimeInterval) {
        guard isRunning else { return }
#if PERF_WATCH
        FlyFrameWatch.shared.frame(at: timestamp, phase: framePhase)
#endif
        let elapsed = lastFrameTime == 0 ? FlyConfig.tick : timestamp - lastFrameTime
        lastFrameTime = timestamp
        stepAccumulator += min(max(0, elapsed), FlyConfig.tick * 3)
        var stepped = false
        while stepAccumulator >= FlyConfig.tick {
            stepAccumulator -= FlyConfig.tick
            tick()
            stepped = true
        }
        // Once per frame, not once per step: catching up after a stall runs the
        // simulation two or three times, and only the state it ends on is ever
        // drawn.
        if stepped { publish() }
    }

#if PERF_WATCH
    /// What the simulation had on screen, for the frame watch to file a dropped
    /// frame under. Only built when a frame was actually missed.
    private var framePhase: String {
        var parts: [String] = []
        let swooping = flies.reduce(into: 0) { $0 += $1.entry != nil ? 1 : 0 }
        let sweeping = flies.reduce(into: 0) { $0 += $1.isRetiring ? 1 : 0 }
        parts.append("\(flies.count) flies")
        if swooping > 0 { parts.append("\(swooping) swooping in") }
        if sweeping > 0 { parts.append("\(sweeping) sweeping out") }
        if tongue != nil { parts.append("tongue") }
        if !poops.isEmpty { parts.append("droppings") }
        if praise != nil { parts.append("tick") }
        return parts.joined(separator: " + ")
    }
#endif

    /// A tap on the playing field. The swarm is drawn rather than laid out, so
    /// the hit test is done here against the positions the simulation already
    /// holds — the same circle each fly used to carry as its own tap target,
    /// tried from the top of the pile down so the answer the child can see is
    /// the one that is caught.
    func catchFly(at point: CGPoint, mouth: CGPoint) {
        guard isLive, tongue == nil else { return }
        let reach = FlyConfig.flySize(isPad: isPad) * 1.32 * 0.5
        for fly in flies.reversed() where fly.isFlying && fly.isVisible {
            if hypot(fly.position.x - point.x, fly.position.y - point.y) <= reach {
                catchFly(fly.id, mouth: mouth)
                return
            }
        }
    }

    func catchFly(_ id: UUID, mouth: CGPoint) {
        guard isLive, tongue == nil,
              let index = flies.firstIndex(where: { $0.id == id && $0.isFlying })
        else { return }

        // The number on the fly is what the child answers with. A fly may have
        // entered as a distractor for an earlier question, so bind that visible
        // value to the active round before handing it to MemoryGame. Without
        // this, an identical number could look correct but carry the UUID of
        // another question and appear mysteriously untappable.
        if let activeRound = rounds.first,
           let activeOption = activeRound.options.first(where: {
               $0.text == flies[index].text
           }) {
            flies[index].roundID = activeRound.id
            flies[index].optionID = activeOption.id
            flies[index].isCorrect = activeOption.isCorrect
        }
        flies[index].isLocked = true
        let fly = flies[index]
        tongue = TongueCatch(flyID: fly.id, roundID: fly.roundID,
                             optionID: fly.optionID, text: fly.text,
                             isCorrect: fly.isCorrect, flyPhase: fly.phase,
                             start: mouth, target: fly.position)
        publish()
    }

    // MARK: - Simulation

    private func tick() {
        guard isRunning else { return }
        clock += FlyConfig.tick
        // A swarm queued by the last round change is dealt here rather than on
        // the frame that queued it (see `sync`).
        dealPendingSwarm()
        moveFlies()
        advanceTongue()
        advanceHeadMarks()
    }

    private func moveFlies() {
        // `flies` is plain storage now rather than a `@Published` array, so the
        // swarm is stepped in place: no per-fly change notification, and no
        // copy of the whole array on every frame to avoid one.
        for index in flies.indices {
            if flies[index].isRetiring {
                advanceScatter(&flies[index])
            } else if flies[index].entry != nil {
                advanceEntry(&flies[index])
            } else if !flies[index].isLocked {
                advanceFlight(&flies[index])
            }
        }
        let bounds = outerRouteBounds
        flies.removeAll {
            $0.isRetiring
                && ($0.exitAge >= FlyConfig.scatterLifetime
                    || !bounds.contains($0.position))
        }
    }

    /// The swoop in from off screen. The whole of the fly's position is driven
    /// by the curve; it only takes over its own steering once it has arrived.
    private func advanceEntry(_ fly: inout AnswerFly) {
        guard var entry = fly.entry else { return }
        guard entry.hasStarted else {
            entry.delay -= FlyConfig.tick
            fly.entry = entry
            fly.position = entry.from
            return
        }

        entry.elapsed += FlyConfig.tick
        fly.age += FlyConfig.tick
        var position = entry.point
        var heading = CGVector(dx: cos(entry.heading), dy: sin(entry.heading))
        // Only the tail of the swoop is corrected. Steering it any earlier
        // would bend the whole approach around obstacles it is nowhere near.
        if entry.elapsed > entry.duration * 0.5 {
            resolveProtectedAreas(position: &position, velocity: &heading)
            position = clampToFlightRoute(position)
        }
        fly.position = position

        guard entry.isFinished else {
            fly.entry = entry
            return
        }
        fly.entry = nil
        // It flies on at the pace and heading the swoop was already carrying,
        // held near its cruising speed so neither end of the handover shows.
        // The wander patterns bend it off course over the next second by
        // themselves, which is smoother than snapping it onto a new heading
        // the instant it arrives.
        let speed = min(max(entry.handoverSpeed, fly.baseSpeed * 0.75),
                        fly.baseSpeed * 1.35)
        fly.velocity = CGVector(dx: cos(entry.heading) * speed,
                                dy: sin(entry.heading) * speed)
    }

    /// A dismissed fly sweeps straight out of the frame, easing up to speed
    /// rather than snapping to it. Nothing steers it: it is already pointed
    /// away from the character, and the interface it may cross is on its way
    /// out of sight. `velocity` is only carrying its heading here — the pace
    /// comes off the ramp.
    private func advanceScatter(_ fly: inout AnswerFly) {
        fly.exitAge += FlyConfig.tick
        let heading = atan2(fly.velocity.dy, fly.velocity.dx)
        let speed = FlyConfig.scatterSpeed(at: fly.exitAge,
                                           launch: fly.exitSpeed,
                                           isPad: isPad)
        fly.position.x += cos(heading) * speed * FlyConfig.tick
        fly.position.y += sin(heading) * speed * FlyConfig.tick
    }

    private func advanceFlight(_ fly: inout AnswerFly) {
        fly.age += FlyConfig.tick
        let motion = motion(for: fly)
        let angle = atan2(fly.velocity.dy, fly.velocity.dx) + motion.turn * FlyConfig.tick
        let speed = fly.baseSpeed * motion.pulse
        fly.velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)

        var next = CGPoint(x: fly.position.x + fly.velocity.dx * FlyConfig.tick,
                           y: fly.position.y + fly.velocity.dy * FlyConfig.tick)
        let bounds = flightRouteBounds
        if next.x < bounds.minX || next.x > bounds.maxX {
            fly.velocity.dx *= -1
            next.x = min(max(next.x, bounds.minX), bounds.maxX)
        }
        if next.y < bounds.minY || next.y > bounds.maxY {
            fly.velocity.dy *= -1
            next.y = min(max(next.y, bounds.minY), bounds.maxY)
        }
        resolveProtectedAreas(position: &next, velocity: &fly.velocity)
        // Being nudged out of an obstacle can land a fly past an edge. The
        // swarm is only pickable while every answer in it is on screen, so the
        // frame wins over the nudge.
        fly.position = clampToFlightRoute(next)
    }

    private func advanceTongue() {
        guard var catchState = tongue else { return }
        catchState.elapsed += FlyConfig.tick
        if !catchState.didReportContact,
           catchState.elapsed >= FlyConfig.extensionTime {
            catchState.didReportContact = true
            // The pad has it: the swarm stops drawing this fly and the tongue
            // carries its own copy home from here.
            if let index = flies.firstIndex(where: { $0.id == catchState.flyID }) {
                flies[index].isCaptured = true
            }
            // The splat belongs to the collision, not to the answer: it sounds
            // the same whether the food that was hit was the right one or not.
            onImpact?()
            catchState.wasAccepted = onHit?(catchState.optionID) ?? false
        }
        if catchState.elapsed >= catchState.total {
            if catchState.wasAccepted == true {
                retiredOptionIDs.insert(catchState.optionID)
                flies.removeAll { $0.id == catchState.flyID }
                if catchState.isCorrect {
                    pendingSpecs.removeAll { $0.roundID == catchState.roundID }
                    emitPraise()
                } else {
                    emitPoopBurst()
                }
                onSwallow?(catchState.isCorrect)
            } else if let index = flies.firstIndex(where: { $0.id == catchState.flyID }) {
                // Input can close while the tongue is already travelling. The
                // fly was never eaten: it resumes if its sum still stands, and
                // otherwise leaves after the swarm it belonged to.
                flies[index].isLocked = false
                flies[index].isCaptured = false
                if flies[index].roundID != activeRoundID {
                    scatter { $0.id == catchState.flyID }
                }
            }
            tongue = nil
        } else {
            tongue = catchState
        }
    }

    /// Abandons a strike whose scene is going away, handing its fly back first.
    /// Dropping the strike without unlocking would leave that fly frozen in mid
    /// air for good — nothing else ever moves a locked fly.
    private func releaseTongue() {
        guard let tongue else { return }
        if let index = flies.firstIndex(where: { $0.id == tongue.flyID }) {
            flies[index].isLocked = false
            flies[index].isCaptured = false
        }
        self.tongue = nil
    }

    /// Three droppings out of the head, fanned left, up and right. A burst that
    /// is still in the air is replaced rather than added to, so answering wrong
    /// twice in quick succession cannot pile them up.
    private func emitPoopBurst() {
        let body = characterRect.width
        guard body > 0 else { return }
        let launch = FlyConfig.poopLaunchSpeed(bodyWidth: body)
        let gravity = FlyConfig.poopGravity(bodyWidth: body)
        let drift = FlyConfig.poopDrift(bodyWidth: body)
        let size = FlyConfig.poopSize(bodyWidth: body)
        let fan: [(drift: CGFloat, launch: CGFloat, spin: Double, size: CGFloat)] = [
            (-1.00, 0.88, -168, 0.86),
            (-0.12, 1.00,   96, 1.00),
            ( 0.94, 0.91,  184, 0.79)
        ]
        poops = zip(fan, FlyConfig.poopDelays).map { shape, delay in
            PoopDrop(delay: delay,
                     drift: drift * shape.drift,
                     launch: launch * shape.launch,
                     gravity: gravity,
                     spin: shape.spin,
                     size: size * shape.size)
        }
    }

    /// The tick for a right answer. Like the burst it replaces whatever is
    /// still on screen, so a fast run shows the newest verdict rather than
    /// stacking one over another.
    private func emitPraise() {
        let body = characterRect.width
        guard body > 0 else { return }
        praise = HeadPraise(size: FlyConfig.praiseSize(bodyWidth: body))
    }

    private func advanceHeadMarks() {
        if !poops.isEmpty {
            var burst = poops
            for index in burst.indices { burst[index].elapsed += FlyConfig.tick }
            burst.removeAll { $0.isFinished }
            poops = burst
        }
        if var current = praise {
            current.elapsed += FlyConfig.tick
            praise = current.isFinished ? nil : current
        }
    }

    // MARK: - Dealing a swarm

    /// Turns the queued answers into flies in one pass, so their places can be
    /// spread against one another instead of each landing where it lands.
    private func dealPendingSwarm() {
        guard !pendingSpecs.isEmpty, size != .zero else { return }
        let specs = pendingSpecs.filter { !retiredOptionIDs.contains($0.option.id) }
        pendingSpecs.removeAll()
        let places = swarmPlaces(count: specs.count)
        for (index, spec) in specs.enumerated() {
            spawn(spec, at: places[index],
                  delay: Double(index) * FlyConfig.entryStagger)
        }
    }

    private func spawn(_ spec: FlySpec, at place: CGPoint, delay: Double) {
        let from = entryOrigin(for: place)
        let travel = hypot(place.x - from.x, place.y - from.y)
        let pace = Double(travel / FlyConfig.entryApproachSpeed(isPad: isPad))
        let entry = FlyEntry(from: from,
                             to: place,
                             duration: min(max(pace, FlyConfig.entryDuration.lowerBound),
                                           FlyConfig.entryDuration.upperBound),
                             delay: delay)
        flies.append(AnswerFly(roundID: spec.roundID,
                               optionID: spec.option.id,
                               text: spec.option.text,
                               isCorrect: spec.option.isCorrect,
                               position: entry.from,
                               velocity: .zero,
                               phase: Double.random(in: 0..<(2 * .pi)),
                               pattern: FlyPattern.allCases.randomElement() ?? .wander,
                               baseSpeed: CGFloat.random(in: isPad ? 58...92 : 50...84),
                               entry: entry))
    }

    /// Where the flies of a new swarm are headed. Candidates are drawn at
    /// random and the one furthest from everything already placed wins, which
    /// spreads five answers over the airspace without ever pinning any of them
    /// to a fixed slot.
    private func swarmPlaces(count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }
        let bounds = flightRouteBounds
        var placed = flies.filter(\.isFlying).map(\.position)
        var result: [CGPoint] = []
        for _ in 0..<count {
            var best = CGPoint(x: bounds.midX, y: bounds.midY)
            var bestScore: CGFloat = -1
            for _ in 0..<28 {
                let candidate = CGPoint(
                    x: CGFloat.random(in: bounds.minX...bounds.maxX),
                    y: CGFloat.random(in: bounds.minY...bounds.maxY)
                )
                guard isClear(candidate) else { continue }
                let score = placed
                    .map { hypot($0.x - candidate.x, $0.y - candidate.y) }
                    .min() ?? .greatestFiniteMagnitude
                if score > bestScore {
                    bestScore = score
                    best = candidate
                }
            }
            // A field with no clear room left anywhere still has to put the fly
            // somewhere sane, so the centre is pushed out of whatever it is in.
            if bestScore < 0 { best = nearestClearPoint(to: best) }
            placed.append(best)
            result.append(best)
        }
        return result
    }

    /// The point just off screen a fly swoops in from. The nearest edge wins,
    /// unless the approach from it would pass behind the character or a panel —
    /// a fly that blinks out mid-flight reads as a glitch.
    private func entryOrigin(for place: CGPoint) -> CGPoint {
        let margin = FlyConfig.offscreenMargin(isPad: isPad)
        let drift = CGFloat.random(in: -0.13...0.13)
        let candidates = [
            CGPoint(x: -margin, y: place.y + size.height * drift),
            CGPoint(x: size.width + margin, y: place.y + size.height * drift),
            CGPoint(x: place.x + size.width * drift, y: -margin),
            CGPoint(x: place.x + size.width * drift, y: size.height + margin)
        ].sorted {
            hypot($0.x - place.x, $0.y - place.y) < hypot($1.x - place.x, $1.y - place.y)
        }
        return candidates.first { hasClearPath(from: $0, to: place) } ?? candidates[0]
    }

    private func hasClearPath(from origin: CGPoint, to place: CGPoint) -> Bool {
        let steps = 7
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: origin.x + (place.x - origin.x) * t,
                                y: origin.y + (place.y - origin.y) * t)
            if !isClear(point) { return false }
        }
        return true
    }

    private func nearestClearPoint(to point: CGPoint) -> CGPoint {
        var position = point
        var heading = CGVector(dx: 0, dy: -1)
        resolveProtectedAreas(position: &position, velocity: &heading)
        return clampToFlightRoute(position)
    }

    // MARK: - Scattering

    /// Sends a finished swarm off in every direction away from the character,
    /// turning out of whatever each fly was already doing and sweeping away. It
    /// reads as the frog having scared them off, and it clears the airspace
    /// while the replacements are still swooping in.
    private func scatter(where shouldScatter: (AnswerFly) -> Bool) {
        let origin = scatterOrigin
        for index in flies.indices
        where !flies[index].isRetiring
            && !flies[index].isLocked
            && shouldScatter(flies[index]) {
            let fly = flies[index]
            flies[index].isRetiring = true
            flies[index].entry = nil
            flies[index].exitAge = 0
            flies[index].exitSpeed = max(FlyConfig.scatterLaunchSpeed(isPad: isPad),
                                         hypot(fly.velocity.dx, fly.velocity.dy))
            flies[index].spin = Double.random(in: 150...360) * (Bool.random() ? 1 : -1)
            flies[index].velocity = scatterVelocity(from: fly.position, origin: origin)
        }
    }

    /// Everything scatters away from the character: it is both where the tongue
    /// came from and the one thing on screen a fly must not cross.
    private var scatterOrigin: CGPoint {
        guard characterRect.width > 0 else {
            return CGPoint(x: size.width * 0.5, y: size.height * 0.75)
        }
        return CGPoint(x: characterRect.midX, y: characterRect.midY)
    }

    private func scatterVelocity(from point: CGPoint, origin: CGPoint) -> CGVector {
        var dx = Double(point.x - origin.x)
        var dy = Double(point.y - origin.y)
        if abs(dx) < 0.001 && abs(dy) < 0.001 {
            dx = Double.random(in: -1...1)
            dy = -1
        }
        // Only the heading matters; `advanceScatter` takes the pace off the ramp.
        let angle = atan2(dy, dx) + Double.random(in: -0.28...0.28)
        return CGVector(dx: CGFloat(cos(angle)), dy: CGFloat(sin(angle)))
    }

    // MARK: - Motion patterns

    private func motion(for fly: AnswerFly) -> (turn: Double, pulse: CGFloat) {
        let t = fly.age
        let p = fly.phase
        switch fly.pattern {
        case .wander:
            return (sin(t * 1.7 + p) * 0.78 + sin(t * 0.63 + p * 1.8) * 0.34,
                    1 + CGFloat(sin(t * 2.1 + p)) * 0.08)
        case .wave:
            return (sin(t * 2.55 + p) * 1.28,
                    0.96 + CGFloat(sin(t * 1.25 + p)) * 0.07)
        case .looper:
            return (0.72 + sin(t * 1.15 + p) * 0.42,
                    0.90 + CGFloat(sin(t * 2.8 + p)) * 0.06)
        case .dart:
            let burst = max(0, sin(t * 1.9 + p))
            return (sin(t * 3.4 + p) * 0.48,
                    0.72 + CGFloat(burst * burst) * 0.48)
        }
    }

    // MARK: - Obstacles

    /// Whether a whole fly fits at this point without touching the interface or
    /// the character.
    private func isClear(_ point: CGPoint) -> Bool {
        let radius = FlyConfig.flySize(isPad: isPad) * 0.5
        let panelClearance = radius + FlyConfig.obstaclePadding(isPad: isPad)
        for rect in protectedRects
        where rect.insetBy(dx: -panelClearance, dy: -panelClearance).contains(point) {
            return false
        }
        guard characterRect.width > 0, characterRect.height > 0 else { return true }
        let clearance = radius + FlyConfig.characterPadding(isPad: isPad)
        let rx = characterRect.width * 0.5 + clearance
        let ry = characterRect.height * 0.5 + clearance
        let dx = (point.x - characterRect.midX) / rx
        let dy = (point.y - characterRect.midY) / ry
        return dx * dx + dy * dy >= 1
    }

    /// Keeps the complete fly, not merely its centre, clear of interface
    /// elements and the character. Collisions are resolved at the protected
    /// edge so even fast darting flies cannot slip underneath another layer.
    private func resolveProtectedAreas(position: inout CGPoint, velocity: inout CGVector) {
        let radius = FlyConfig.flySize(isPad: isPad) * 0.5
        let panelClearance = radius + FlyConfig.obstaclePadding(isPad: isPad)

        for rect in protectedRects {
            let expanded = rect.insetBy(dx: -panelClearance, dy: -panelClearance)
            guard expanded.contains(position) else { continue }
            let distances: [(CGFloat, Int)] = [
                (position.x - expanded.minX, 0),
                (expanded.maxX - position.x, 1),
                (position.y - expanded.minY, 2),
                (expanded.maxY - position.y, 3)
            ]
            switch distances.min(by: { $0.0 < $1.0 })?.1 ?? 3 {
            case 0:
                position.x = expanded.minX
                velocity.dx = -abs(velocity.dx)
            case 1:
                position.x = expanded.maxX
                velocity.dx = abs(velocity.dx)
            case 2:
                position.y = expanded.minY
                velocity.dy = -abs(velocity.dy)
            default:
                position.y = expanded.maxY
                velocity.dy = abs(velocity.dy)
            }
        }

        guard characterRect.width > 0, characterRect.height > 0 else { return }
        // The pose keeps a tighter ring than the interface does, and the
        // airspace now runs all the way down past it, so a fly is free to
        // circle the character on every side instead of being held above it.
        let clearance = radius + FlyConfig.characterPadding(isPad: isPad)
        let center = CGPoint(x: characterRect.midX, y: characterRect.midY)
        let rx = characterRect.width * 0.5 + clearance
        let ry = characterRect.height * 0.5 + clearance
        let dx = position.x - center.x
        let dy = position.y - center.y
        let normalized = dx * dx / (rx * rx) + dy * dy / (ry * ry)
        guard normalized < 1 else { return }

        if normalized < 0.0001 {
            position.y = center.y - ry
            velocity.dy = -abs(velocity.dy)
            return
        }

        // Pushed straight out along the ray it came in on, then bounced off the
        // surface it was pushed to.
        let scale = 1 / max(0.001, sqrt(normalized))
        position = CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
        var nx = (position.x - center.x) / (rx * rx)
        var ny = (position.y - center.y) / (ry * ry)
        let normalLength = max(0.001, hypot(nx, ny))
        nx /= normalLength
        ny /= normalLength
        let inwardSpeed = velocity.dx * nx + velocity.dy * ny
        if inwardSpeed < 0 {
            velocity.dx -= 2 * inwardSpeed * nx
            velocity.dy -= 2 * inwardSpeed * ny
        }
    }

    // MARK: - Bounds

    /// The frame plus a generous border, used only to tell when a scattered fly
    /// is safely out of sight.
    private var outerRouteBounds: CGRect {
        let margin = FlyConfig.offscreenMargin(isPad: isPad)
        return CGRect(x: -margin, y: -margin,
                      width: size.width + margin * 2,
                      height: size.height + margin * 2)
    }

    /// Where a fly under its own steam is allowed to be. Every edge of it is
    /// inside the frame: an answer that has drifted off screen is an answer the
    /// child cannot pick, which is exactly what used to stall a round while a
    /// perfectly good swarm was in the air.
    private var flightRouteBounds: CGRect {
        let inset = FlyConfig.flySize(isPad: isPad) * 0.5
        let minY = topReserve
        let maxY = max(minY + 80, flightFloor)
        return CGRect(x: inset, y: minY,
                      width: max(1, size.width - inset * 2),
                      height: maxY - minY)
    }

    private func clampToFlightRoute(_ point: CGPoint) -> CGPoint {
        let bounds = flightRouteBounds
        return CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                       y: min(max(point.y, bounds.minY), bounds.maxY))
    }
}

#if PERF_WATCH
/// Answers by itself, for measurement only.
///
/// Human tapping cannot be repeated exactly, and a stutter that only shows up
/// under fast consecutive answers has to be reproduced the same way twice to be
/// attributed to anything. This drives a strike every `interval` seconds at the
/// fly *furthest* from the mouth, which is both the longest ribbon the tongue
/// ever draws and the widest sweep of its mask — the worst case on purpose.
enum PerfAuto {
    static let enabled = ProcessInfo.processInfo.arguments.contains("-autoAnswer")
    static let interval = 0.45
}
#endif

struct FlyPlayfield: View {
    let rounds: [GameRound]
    let maximumRounds: Int
    let character: AnimalCharacter
    let isPad: Bool
    let isLive: Bool
    let isRunning: Bool
    let playsFishEntrance: Bool
    let playsLevelCompletion: Bool
    let reduceMotion: Bool
    let topReserve: CGFloat
    let bottomReserve: CGFloat
    /// What the guided run is saying, the glyph that goes with it, and which
    /// answer it is pointing at. All nil in an ordinary session.
    var tutorialMessage: String? = nil
    var tutorialSymbol: String? = nil
    var tutorialPointer: TutorialPointer? = nil
    let onHit: (UUID) -> Bool
    /// The strike landing on a piece of food, and the catch arriving in the
    /// mouth a third of a second later with the answer it was carrying.
    let onImpact: () -> Void
    let onSwallow: (Bool) -> Void
    let onFishEntranceComplete: () -> Void
    let onLevelCompletionFinished: () -> Void

    /// The engine is held through a box that never publishes anything, so this
    /// view is *not* re-run sixty times a second. Each moving layer observes one
    /// channel of the engine and nothing else (see `FlySwarmLayer` and friends),
    /// so a frame invalidates only the layer whose contents changed; everything
    /// else here — the pond, the character, the sum — is laid out once and left
    /// alone.
    @StateObject private var box = FlyEngineBox()
    @State private var entranceToken = 0
    @State private var completionToken = 0
    @Environment(\.displayScale) private var displayScale

    private var engine: FlyEngine { box.engine }

    var body: some View {
        GeometryReader { proxy in
            let stage = FlyConfig.characterRect(isPad: isPad, in: proxy.size)
            // The head, not the whole reclining body, is what the tongue's
            // girth and unrolling length are measured against.
            let headSize = stage.width * AnimalCharacter.playHeadWidthShare
            let questionFrame = questionRect(in: proxy.size)
            // Anchored on the painted mouth of this character's own artwork, in
            // the same coordinate space as the flies, so the ribbon leaves the
            // animal exactly where its mouth is drawn.
            let mouth = point(of: character.mouth.anchor, in: stage)
            let mouthCenter = point(of: character.mouth.center, in: stage)
            let mouthOpening = CGRect(
                x: mouthCenter.x - stage.width * character.mouth.opening.width * 0.5,
                y: mouthCenter.y - stage.height * character.mouth.opening.height * 0.5,
                width: stage.width * character.mouth.opening.width,
                height: stage.height * character.mouth.opening.height
            )
            // What this character eats: the level fills with their own food
            // instead of a generic fly, catch and all.
            let foodImageName = FoodCatalog.imageName(for: character.id)
            // Top of the head, where the verdict on a swallowed answer appears,
            // and the spot beside it a tick settles on.
            let headTop = point(of: CGPoint(
                x: character.mouth.center.x + FlyConfig.poopHeadOffset.width,
                y: character.mouth.center.y + FlyConfig.poopHeadOffset.height
            ), in: stage)
            let praiseRest = point(of: CGPoint(
                x: character.mouth.center.x + FlyConfig.praiseRestOffset.width,
                y: character.mouth.center.y + FlyConfig.praiseRestOffset.height
            ), in: stage)

            ZStack {
                CharacterBackdrop(character: character,
                                  stage: stage,
                                  horizon: PlayStage.horizon(in: proxy.size),
                                  reduceMotion: reduceMotion)
                    .equatable()

                FlySwarmLayer(frames: engine.swarm,
                              foodImageName: foodImageName,
                              isPad: isPad,
                              scale: displayScale,
                              onTap: { engine.catchFly(at: $0, mouth: mouth) },
                              onCatch: { engine.catchFly($0, mouth: mouth) })

                // The pose is drawn once and never moved. The mouth the tongue
                // is anchored on is a fixed point measured in the artwork, so
                // any breathing, leaning or squashing of the character would
                // slide the painted lip out from under the ribbon's root on
                // every frame. All of the motion in a strike belongs to the
                // tongue; the animal it comes out of holds perfectly still.
                character.playArtwork
                    .resizable()
                    .scaledToFit()
                    .frame(width: stage.width, height: stage.height)
                    .position(x: stage.midX, y: stage.midY)
                    .allowsHitTesting(false)

                // Drawn after the character: a tongue that emerges from behind
                // the head reads as coming out of the back of the animal.
                TongueLayer(strike: engine.strike,
                            foodImageName: foodImageName,
                            isPad: isPad,
                            headSize: headSize,
                            mouthOpening: mouthOpening,
                            mouth: character.mouth,
                            reduceMotion: reduceMotion)

                // Above the character, so a mark arcing over the head is never
                // cut in half by the artwork it came out of.
                HeadMarkLayer(marks: engine.marks, head: headTop,
                              praiseRest: praiseRest, scale: displayScale)

                if let active = rounds.first {
                    ActiveQuestionView(prompt: active.question.prompt,
                                       character: character,
                                       isPad: isPad,
                                       size: questionFrame.size)
                        .position(x: questionFrame.midX, y: questionFrame.midY)
                }

                // The line from the sum to the answer it is asking for. Drawn
                // above the swarm so the head of the arrow lands on the fly
                // rather than behind it.
                if let tutorialPointer {
                    TutorialArrowLayer(frames: engine.swarm,
                                       target: tutorialPointer,
                                       source: questionFrame,
                                       color: character.deepColor,
                                       isPad: isPad)
                }

                // Its own container, so the message arriving and leaving is the
                // only thing the animation below applies to.
                ZStack {
                    if let tutorialMessage {
                        let band = tutorialRect(in: proxy.size)
                        TutorialMessageCard(text: tutorialMessage,
                                            symbolName: tutorialSymbol ?? "sparkles",
                                            theme: character,
                                            isPad: isPad,
                                            fixedSize: band.size)
                            .position(x: band.midX, y: band.midY)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                            .id(tutorialMessage)
                    }
                }
                .animation(.easeInOut(duration: 0.26), value: tutorialMessage)
                .allowsHitTesting(false)

                if playsLevelCompletion {
                    FlyCelebrationLayer(frames: engine.swarm, color: character.deepColor)
                }
            }
            .clipped()
#if PERF_WATCH
            .onReceive(Timer.publish(every: PerfAuto.interval, on: .main, in: .common)
                .autoconnect()) { _ in
                guard PerfAuto.enabled else { return }
                let candidates = engine.swarm.value.flies.filter { $0.isFlying && $0.isVisible }
                // The right answer, so the session keeps running instead of
                // ending after three mistakes. Its distance from the mouth
                // varies round to round by itself, so the long reaches still
                // get measured — they just do not cost a life.
                guard let target = candidates.first(where: \.isCorrect)
                        ?? candidates.first else { return }
                engine.catchFly(at: target.position, mouth: mouth)
            }
#endif
            .onAppear {
                engine.onHit = onHit
                engine.onImpact = onImpact
                engine.onSwallow = onSwallow
                applyLayout(in: proxy.size)
                engine.sync(rounds: rounds)
                engine.setLive(isLive)
                engine.setRunning(isRunning)
                warmFoodGlyphs(for: rounds)
                if playsFishEntrance { beginEntrance() }
            }
            .onChange(of: proxy.size) { _, size in applyLayout(in: size) }
            // The window's safe area is sampled a frame after the scene appears,
            // so the reserves this view is handed change once, right at the
            // start. Without this the swarm keeps the placeholder ceiling it was
            // laid out with and drifts up under the status bar — and on a phone
            // with a Dynamic Island, behind it.
            .onChange(of: topReserve) { _, _ in applyLayout(in: proxy.size) }
            .onChange(of: bottomReserve) { _, _ in applyLayout(in: proxy.size) }
            // A tutorial message is an obstacle for as long as it is up: the
            // swarm has to steer around it the way it steers around the sum.
            .onChange(of: tutorialMessage == nil) { _, _ in applyLayout(in: proxy.size) }
        }
        // Only the standing sum can deal a swarm, and this view's body is
        // re-run on every published change in the session — so the trigger is
        // the one id that matters rather than a freshly built array of all
        // three on each of those evaluations.
        .onChange(of: rounds.first?.id) { _, _ in
            engine.sync(rounds: rounds)
            // The session generates two sums beyond the one being played, so
            // every answer that will be flown is known a good two rounds before
            // it arrives. Baking their artwork over that time spends it instead
            // of the frame the swarm is dealt on — which is the frame right
            // after an answer, where a child playing quickly can least afford it.
            warmFoodGlyphs(for: rounds)
        }
        .onChange(of: isLive) { _, value in engine.setLive(value) }
        .onChange(of: isRunning) { _, value in engine.setRunning(value) }
        .onChange(of: playsFishEntrance) { _, value in if value { beginEntrance() } }
        .onChange(of: playsLevelCompletion) { _, value in if value { beginCompletion() } }
        .onDisappear { engine.setRunning(false) }
    }

    /// Bakes the food for every answer the session has already generated, well
    /// before the round that will fly it.
    ///
    /// One bake at a time with a gap between them, rather than a burst: baking
    /// is the one piece of work in a round with no deadline whatsoever — the
    /// answers being prepared are two sums away — so it is spread thin enough
    /// that no single frame can notice it, wherever in the round it lands.
    ///
    /// It is deliberately not a `.task(id:)`. That form cancels itself whenever
    /// the sum changes, which would have meant a child answering quickly — the
    /// one this exists for — never getting a single glyph baked ahead, and
    /// paying for all five on the frame the swarm is dealt. Nothing here needs
    /// cancelling: a repeat is a dictionary lookup, and the cache outlives any
    /// one level anyway.
    private func warmFoodGlyphs(for rounds: [GameRound]) {
        let food = FoodCatalog.imageName(for: character.id)
        let size = FlyConfig.flySize(isPad: isPad) * FlyConfig.foodVisualScale
        let scale = displayScale

        // The sum being played is wanted on the very next frame, so it is baked
        // here and now rather than queued. Only the first round of a level ever
        // pays for it, and that lands behind the start card where nothing is
        // moving; from the second round on these were baked two rounds ago and
        // this is five dictionary lookups.
        //
        // Leaving them to the queue below was worth about eighty milliseconds
        // on the frame the first swarm was dealt — the one stall left in a
        // level, and right at its opening.
        if let active = rounds.first {
            FoodGlyphCache.warm(active.options.map(\.text), food: food,
                                size: size, scale: scale)
        }

        let later = rounds.dropFirst().flatMap { $0.options.map(\.text) }
        Task { @MainActor in
            for text in later {
                try? await Task.sleep(nanoseconds: 40_000_000)
                FoodGlyphCache.warm([text], food: food, size: size, scale: scale)
            }
        }
    }

    private func applyLayout(in size: CGSize) {
        var protected = [questionRect(in: size)]
        if tutorialMessage != nil { protected.append(tutorialRect(in: size)) }
        engine.layout(size: size,
                      topReserve: flightCeiling,
                      protectedRects: protected,
                      characterRect: bodyRect(in: size),
                      flightFloor: flightFloor(in: size),
                      isPad: isPad)
    }

    /// The highest a fly's centre may sit: its own top edge stays clear of the
    /// HUD, and with it of the status bar and any Dynamic Island above that.
    private var flightCeiling: CGFloat {
        topReserve + FlyConfig.flySize(isPad: isPad) * 0.5
            + FlyConfig.obstaclePadding(isPad: isPad)
    }

    /// A point given in the artwork's own fractions, resolved into the scene.
    private func point(of unit: CGPoint, in stage: CGRect) -> CGPoint {
        CGPoint(x: stage.minX + stage.width * unit.x,
                y: stage.minY + stage.height * unit.y)
    }

    /// Which way the app reads. The playfield's own coordinates stay
    /// left-to-right whatever the language — a fly sits where the simulation
    /// put it, and the tongue leaves from a mouth painted at a fixed spot — but
    /// the two cards laid over it are interface, and they share the top of the
    /// screen with a HUD that does swap sides. Read rather than observed: the
    /// language cannot change from inside a running game, and this view is
    /// deliberately kept off the sixty-times-a-second path.
    private var isRightToLeft: Bool {
        LanguageManager.shared.effective.layoutDirection == .rightToLeft
    }

    private func questionRect(in size: CGSize) -> CGRect {
        let inset: CGFloat = isPad ? 28 : 16
        let sharesTopRow = size.width >= 700
        let width: CGFloat
        if isPad {
            width = min(410, max(320, size.width * 0.38))
        } else if sharesTopRow {
            width = min(330, max(270, size.width * 0.34))
        } else {
            width = min(310, max(244, size.width - inset * 2))
        }
        let height: CGFloat = isPad ? 82 : 64
        let minY = sharesTopRow
            ? topReserve - (isPad ? 42 : 36)
            : topReserve + (isPad ? 12 : 8)
        let x = isRightToLeft ? inset : size.width - inset - width
        return CGRect(x: x, y: minY, width: width, height: height)
    }

    /// The band a tutorial message occupies: a fixed one, on the leading side
    /// directly under the HUD, whatever the message says. Fixed because the
    /// swarm is told to steer around it — a band that grew and shrank with the
    /// translation would move the airspace under the flies each time the lesson
    /// moved on. The sum keeps the corner opposite it.
    private func tutorialRect(in size: CGSize) -> CGRect {
        let inset: CGFloat = isPad ? 28 : 16
        let width = min(isPad ? 520 : 396,
                        max(230, size.width * (isPad ? 0.46 : 0.47)))
        let height: CGFloat = isPad ? 96 : 74
        let x = isRightToLeft ? size.width - inset - width : inset
        return CGRect(x: x, y: topReserve + (isPad ? 16 : 10),
                      width: width, height: height)
    }

    /// The painted body inside the artwork's frame: the transparent margin
    /// around the lounger is not something a fly should have to steer around.
    private func bodyRect(in size: CGSize) -> CGRect {
        let stage = FlyConfig.characterRect(isPad: isPad, in: size)
        return stage.insetBy(dx: stage.width * 0.04, dy: stage.height * 0.06)
    }

    /// The lowest a fly's centre may sit. The swarm used to be penned in above
    /// the waterline, which left the whole bottom third of the scene unusable
    /// and pushed every answer into the same band of sky. Flies now work the
    /// full height of the pond — down the banks either side of the character
    /// and across the water in front of it — and stay off the character itself
    /// through the safety ring around its body rather than through a ceiling.
    private func flightFloor(in size: CGSize) -> CGFloat {
        size.height - bottomReserve
            - FlyConfig.flySize(isPad: isPad) * 0.5
            - FlyConfig.obstaclePadding(isPad: isPad)
    }

    private func beginEntrance() {
        entranceToken &+= 1
        let token = entranceToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard entranceToken == token else { return }
            onFishEntranceComplete()
        }
    }

    private func beginCompletion() {
        completionToken &+= 1
        let token = completionToken
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.9 : 2.4)) {
            guard completionToken == token else { return }
            onLevelCompletionFinished()
        }
    }
}

/// Gives the engine a lifetime tied to the scene without putting it in the way
/// of one. The engine publishes nothing itself — its three channels do — so
/// `FlyPlayfield` owns it here and is never woken by the simulation.
@MainActor
private final class FlyEngineBox: ObservableObject {
    let engine = FlyEngine()
}

// MARK: - Moving layers
//
// Each of these observes the engine, so a frame of the simulation invalidates
// only the layer whose contents actually changed. The pond, the character
// artwork and the sum card sit outside them and are never rebuilt mid-round.

/// The swarm itself: every answer currently in the air, drawn in a single pass.
///
/// A `ForEach` of ten little views is ten SwiftUI subtrees, each with layers of
/// its own, a tap gesture of its own and an accessibility element of its own —
/// and all of that is built and torn down twice per question, because a swarm
/// change deliberately puts five new answers in the air while five old ones are
/// still leaving. Updating an existing view is cheap; *creating* one is not, and
/// the creations landed one per swoop across exactly the stretch a swarm arrives
/// in. That is the hitch that was left on the fly-in.
///
/// A canvas has no per-fly identity at all: one view, one draw pass, and nothing
/// created or destroyed when the swarm turns over. What the little views used to
/// carry besides their picture is provided here instead — a single tap gesture
/// for the whole layer, resolved against the simulation that owns the positions,
/// and accessibility elements built only when something is actually reading them.
private struct FlySwarmLayer: View {
    @ObservedObject var frames: SwarmChannel
    let foodImageName: String
    let isPad: Bool
    let scale: CGFloat
    /// A tap anywhere on the playing field, in this layer's own coordinates.
    let onTap: (CGPoint) -> Void
    /// One named answer, for assistive technology only.
    let onCatch: (UUID) -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled

    var body: some View {
        let frame = frames.value
        let size = FlyConfig.flySize(isPad: isPad)
        // Baked once and looked up here, on the main actor, so the drawing
        // itself only has to resolve an image it has already been handed.
        let glyphs = glyphs(for: frame.flies, size: size)

        Canvas(rendersAsynchronously: false) { context, _ in
            // Resolving is the step a canvas is meant to have done before it
            // starts drawing, so it happens once per distinct answer rather
            // than once per fly — the outgoing and incoming swarms overlap, and
            // two flies can be carrying the same number.
            var resolved: [String: GraphicsContext.ResolvedImage] = [:]
            resolved.reserveCapacity(glyphs.count)
            for (text, image) in glyphs { resolved[text] = context.resolve(image) }

            for fly in frame.flies where fly.isVisible {
                draw(fly, size: size, clock: frame.clock,
                     glyph: resolved[fly.text], into: context)
            }
        }
        // A canvas paints; it has no shape of its own for a touch to land on, so
        // without this the whole swarm is untappable.
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { onTap($0) }
        .overlay {
            // Nothing but an assistive reader ever visits these, and building
            // them costs the same as the per-fly views this layer exists to
            // avoid — so they are built when there is a reader and not before.
            if voiceOverEnabled || switchControlEnabled {
                assistiveTargets(frame.flies, size: size)
            }
        }
    }

    private func glyphs(for flies: [AnswerFly], size: CGFloat) -> [String: Image] {
        var table: [String: Image] = [:]
        let glyphSize = size * FlyConfig.foodVisualScale
        for fly in flies where fly.isVisible {
            guard table[fly.text] == nil else { continue }
            guard let image = FoodGlyphCache.image(food: foodImageName, text: fly.text,
                                                   size: glyphSize, scale: scale)
            else { continue }
            table[fly.text] = image
        }
        return table
    }

    /// One fly. `GraphicsContext` is a value type, so each nested copy carries
    /// its own transform and none of them leak into the next — the same scoping
    /// the view modifiers used to give, without the views.
    private func draw(_ fly: AnswerFly, size: CGFloat, clock: Double,
                      glyph: GraphicsContext.ResolvedImage?,
                      into context: GraphicsContext) {
        var body = context
        body.translateBy(x: fly.position.x, y: fly.position.y)
        // The swoop lands with a touch of scale behind it and the sweep out
        // pulls back a little into the distance, which keeps a swarm change
        // reading as one movement rather than two sets of flies swapping.
        let growth: CGFloat = fly.isRetiring
            ? 1 - 0.1 * fly.scatterProgress
            : 0.82 + 0.18 * (fly.entry?.progress ?? 1)
        body.scaleBy(x: growth, y: growth)
        body.rotate(by: .degrees(tilt(of: fly)))

        // The fly's own artwork already carries its wings; painting a second
        // pair on top of it would double up. Every other food needs them drawn
        // in, anchored to that food's own silhouette.
        if !foodPaintsOwnWings(foodImageName) {
            let wings = wingLayout(for: foodImageName)
            let flap = sin(clock * 35 + fly.phase)
            let width = size * 0.48 * wings.scale
            let height = size * 0.30 * wings.scale
            let capsule = Path(roundedRect: CGRect(x: -width * 0.5, y: -height * 0.5,
                                                   width: width, height: height),
                               cornerRadius: min(width, height) * 0.5,
                               style: .circular)
            var pair = body
            pair.scaleBy(x: FlyConfig.foodVisualScale, y: FlyConfig.foodVisualScale)
            let beat = 32 - flap * 9
            var left = pair
            left.translateBy(x: size * (wings.dx - wings.spread), y: size * wings.dy)
            left.rotate(by: .degrees(-beat))
            left.fill(capsule, with: .color(.white.opacity(0.78)))
            var right = pair
            right.translateBy(x: size * (wings.dx + wings.spread), y: size * wings.dy)
            right.rotate(by: .degrees(beat))
            right.fill(capsule, with: .color(.white.opacity(0.78)))
        }

        // The enlargement is folded into the size the glyph was baked at rather
        // than applied over it: a raster made at the tap size and then blown up
        // a third would arrive soft.
        if let glyph {
            body.draw(glyph, at: .zero, anchor: .center)
        } else {
            // Only reachable if the bake was refused. The food and its number
            // are drawn straight, without the shadow the baked one carries —
            // a swarm missing its drop shadows beats a swarm of bare wings.
            drawUnbaked(fly, size: size, into: body, resolving: context)
        }
    }

    private func drawUnbaked(_ fly: AnswerFly, size: CGFloat,
                             into context: GraphicsContext,
                             resolving base: GraphicsContext) {
        let side = size * FlyConfig.foodVisualScale
        let box = CGRect(x: -side * 0.5, y: -side * 0.5, width: side, height: side)
        context.draw(base.resolve(Image(foodImageName)), in: box)
        let badge = Text(verbatim: fly.text)
            .font(.system(size: side * 0.22, weight: .black, design: .rounded))
            .foregroundStyle(answerNumberColor(for: foodImageName))
        context.draw(base.resolve(badge), at: .zero, anchor: .center)
    }

    /// A swooping fly arrives leaning into its own approach, and a dismissed one
    /// tumbles as it whirls away. Both are read straight off the fly's own
    /// simulated state, so they stay in step with where it actually is.
    private func tilt(of fly: AnswerFly) -> Double {
        if fly.isRetiring { return fly.spin * fly.exitAge }
        guard let entry = fly.entry, entry.hasStarted else { return 0 }
        let remaining = 1 - Double(entry.progress)
        return Double(entry.heading) * 57.29578 * 0.16 * max(0, remaining)
    }

    private func assistiveTargets(_ flies: [AnswerFly], size: CGFloat) -> some View {
        let tapSize = size * 1.32
        return ZStack {
            ForEach(flies) { fly in
                if fly.isVisible {
                    Color.clear
                        .frame(width: tapSize, height: tapSize)
                        .accessibilityElement()
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onCatch(fly.id) }
                        .position(fly.position)
                }
            }
        }
        // The tap itself belongs to the canvas underneath; these exist to be
        // read and activated, never to swallow a touch.
        .allowsHitTesting(false)
    }
}

/// The tutorial's pointer: a curved arrow from the standing sum to the fly the
/// step is asking for.
///
/// It observes the swarm rather than being told a position, because the fly it
/// points at is flying — a line drawn to where the answer was a moment ago is
/// worse than no line at all. Like the swarm itself it is drawn rather than laid
/// out, so following a fly costs a path per frame and nothing else.
private struct TutorialArrowLayer: View {
    @ObservedObject var frames: SwarmChannel
    let target: TutorialPointer
    /// The sum card the arrow leaves from.
    let source: CGRect
    let color: Color
    let isPad: Bool

    var body: some View {
        let fly = pointedAt(in: frames.value.flies)
        let frame = frames.value
        let width: CGFloat = isPad ? 6 : 4.5
        let head: CGFloat = isPad ? 22 : 17

        Canvas(rendersAsynchronously: false) { context, _ in
            guard let fly else { return }
            let gap = FlyConfig.flySize(isPad: isPad) * 0.5 + (isPad ? 16 : 12)
            // A gentle breathing along its own direction, so the pointer reads
            // as alive without ever leaving the answer it is on.
            let beat = CGFloat(sin(frame.clock * 3.4)) * (isPad ? 5 : 4)
            let start = anchor(on: source, facing: fly.position)
            let heading = atan2(fly.position.y - start.y, fly.position.x - start.x)
            // An answer flying close to the sum leaves no room for a shaft. The
            // head is still drawn, right up against the card: a pointer that
            // vanishes whenever the fly drifts near the question would look
            // like the step had given up on it.
            let reach = max(6, hypot(fly.position.x - start.x,
                                     fly.position.y - start.y) - gap - beat)
            let end = CGPoint(x: start.x + cos(heading) * reach,
                              y: start.y + sin(heading) * reach)
            let drawsShaft = reach > head

            // Bowed a little to one side: a straight line between two rectangles
            // reads as a divider, a curve reads as a gesture.
            let bend = min(reach * 0.16, isPad ? 74 : 52)
            let control = CGPoint(x: (start.x + end.x) * 0.5 - sin(heading) * bend,
                                  y: (start.y + end.y) * 0.5 + cos(heading) * bend)

            var shaft = Path()
            shaft.move(to: start)
            shaft.addQuadCurve(to: end, control: control)

            // The angle the curve actually arrives at, so the head sits square
            // on the end of the shaft rather than on the straight line.
            let approach = drawsShaft ? atan2(end.y - control.y, end.x - control.x)
                                      : heading
            var tip = Path()
            for side in [approach + 2.55, approach - 2.55] {
                tip.move(to: end)
                tip.addLine(to: CGPoint(x: end.x + cos(side) * head,
                                        y: end.y + sin(side) * head))
            }

            // Outlined in white first: the pond, the banks and the flies are all
            // colour, and a bare stroke would be lost against one of them.
            let halo = StrokeStyle(lineWidth: width + 4, lineCap: .round, lineJoin: .round)
            let core = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            if drawsShaft {
                context.stroke(shaft, with: .color(.white.opacity(0.9)), style: halo)
            }
            context.stroke(tip, with: .color(.white.opacity(0.9)), style: halo)
            if drawsShaft {
                context.stroke(shaft, with: .color(color), style: core)
            }
            context.stroke(tip, with: .color(color), style: core)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The answer this step is pointing at.
    ///
    /// Deliberately forgiving about what counts as a candidate. A fly is only
    /// "flying" once it has finished swooping in and while nothing is holding
    /// it, and a strike — including one the tutorial refuses — locks its target
    /// for a third of a second. Requiring that made the arrow blink out every
    /// time the swarm turned over or a fly was tapped, which reads as the hint
    /// giving up. Anything on its way out is still excluded: pointing at a fly
    /// that is leaving the screen would be worse than pointing at nothing.
    ///
    /// The first match wins, so the arrow settles on one fly rather than
    /// hopping between two answers that are equally wrong.
    private func pointedAt(in flies: [AnswerFly]) -> AnswerFly? {
        let wanted = target == .correct
        let candidates = flies.filter {
            !$0.isRetiring && $0.isCorrect == wanted
                && ($0.entry?.hasStarted ?? true)
        }
        return candidates.first { $0.isVisible } ?? candidates.first
    }

    /// Where on the sum card the arrow leaves: the point on its edge nearest the
    /// fly, pulled in slightly so the shaft starts on the card rather than
    /// floating beside it.
    private func anchor(on rect: CGRect, facing point: CGPoint) -> CGPoint {
        let inset = rect.insetBy(dx: 6, dy: 6)
        return CGPoint(x: min(max(point.x, inset.minX), inset.maxX),
                       y: min(max(point.y, inset.minY), inset.maxY))
    }
}

/// The strike: the tongue on its way out and back.
private struct TongueLayer: View {
    @ObservedObject var strike: StrikeChannel
    let foodImageName: String
    let isPad: Bool
    let headSize: CGFloat
    let mouthOpening: CGRect
    let mouth: MouthGeometry
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            if let tongue = strike.value {
                TongueView(catchState: tongue, foodImageName: foodImageName, isPad: isPad,
                           headSize: headSize, mouthOpening: mouthOpening,
                           mouth: mouth,
                           reduceMotion: reduceMotion)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// The verdict on a swallowed answer, played out over the character's head:
/// three droppings for a wrong one, a tick for a right one. Both are measured
/// from the one point given here.
/// Drawn rather than laid out, for the same reason the swarm is: a verdict
/// appears on *every* answer and is gone about a second later, so as views it
/// was a build and a teardown per answer — landing squarely in the stretch the
/// next swarm swoops in on. On a canvas a verdict costs a transform and a blit,
/// and an answer with no mark on screen costs nothing at all.
private struct HeadMarkLayer: View {
    @ObservedObject var marks: MarkChannel
    /// Top of the head, in this layer's own coordinates, and the spot beside it
    /// the tick hops out to.
    let head: CGPoint
    let praiseRest: CGPoint
    let scale: CGFloat

    var body: some View {
        let state = marks.value
        // The tick's artwork never changes for a given character size, so like
        // the food it is baked once instead of being re-drawn — gradient, rim,
        // drop shadow and all — on every frame of the second it is up.
        let tick = state.praise.flatMap {
            PraiseTickCache.image(size: $0.size, scale: scale)
        }
        Canvas(rendersAsynchronously: false) { context, _ in
            if !state.poops.isEmpty {
                let dropping = context.resolve(Image("poop"))
                for poop in state.poops {
                    var g = context
                    g.opacity = poop.opacity
                    g.translateBy(x: head.x + poop.offset.width,
                                  y: head.y + poop.offset.height)
                    g.scaleBy(x: poop.scale, y: poop.scale)
                    g.rotate(by: .degrees(poop.rotation))
                    g.draw(dropping, in: fitted(dropping.size, into: poop.size))
                }
            }

            if let praise = state.praise, let tick {
                let travel = praise.travel
                var g = context
                g.opacity = praise.opacity
                g.translateBy(x: head.x + (praiseRest.x - head.x) * travel,
                              y: head.y + (praiseRest.y - head.y) * travel)
                g.scaleBy(x: praise.scale, y: praise.scale)
                g.draw(context.resolve(tick), at: .zero, anchor: .center)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The artwork's own proportions inside a square box, centred on the origin
    /// — what `scaledToFit` in a fixed frame used to give.
    private func fitted(_ natural: CGSize, into side: CGFloat) -> CGRect {
        guard natural.width > 0, natural.height > 0 else {
            return CGRect(x: -side * 0.5, y: -side * 0.5, width: side, height: side)
        }
        let fit = min(side / natural.width, side / natural.height)
        let width = natural.width * fit
        let height = natural.height * fit
        return CGRect(x: -width * 0.5, y: -height * 0.5, width: width, height: height)
    }
}

/// A tick on a green coin. It has to hold up at the size of a dropping against
/// a pond full of colour, so it carries its own disc and a white rim rather
/// than being a bare glyph laid over whatever happens to be behind it.
private struct PraiseTickView: View {
    let size: CGFloat

    /// Room for the drop shadow to fall into. A shadow does not enlarge the
    /// view it belongs to, so without this the bake would cut it off.
    fileprivate static func margin(for size: CGFloat) -> CGFloat { size * 0.3 }

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.52, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle().fill(
                    LinearGradient(colors: [Color(red: 0.36, green: 0.84, blue: 0.40),
                                            Color(red: 0.13, green: 0.62, blue: 0.24)],
                                   startPoint: .top, endPoint: .bottom)
                )
            )
            .overlay(Circle().stroke(.white.opacity(0.92), lineWidth: size * 0.075))
            .shadow(color: Color(red: 0.06, green: 0.28, blue: 0.10).opacity(0.34),
                    radius: size * 0.13, y: size * 0.07)
            .padding(Self.margin(for: size))
    }
}

/// The baked tick. One character size per session, so this holds a single image
/// in practice — but it is keyed properly so a rotation or a different device
/// cannot hand back a stale one.
@MainActor
private enum PraiseTickCache {
    private struct Key: Hashable {
        let size: CGFloat
        let scale: CGFloat
    }

    private static var images: [Key: Image?] = [:]

    static func image(size: CGFloat, scale: CGFloat) -> Image? {
        let key = Key(size: size, scale: scale)
        if let cached = images[key] { return cached }
        let renderer = ImageRenderer(content: PraiseTickView(size: size))
        renderer.scale = scale
        let image = renderer.uiImage.map { Image(uiImage: $0) }
        images[key] = image
        return image
    }
}

/// The end-of-level bloom, which drifts off the simulation's own clock.
private struct FlyCelebrationLayer: View {
    @ObservedObject var frames: SwarmChannel
    let color: Color

    var body: some View {
        FlyCelebration(clock: frames.value.clock, color: color)
            .allowsHitTesting(false)
    }
}

/// Only the fly's own artwork (`food_1`) is painted with wings already — every
/// other food needs them added around it in code.
private func foodPaintsOwnWings(_ foodImageName: String) -> Bool {
    foodImageName == "food_1"
}

/// No two foods sit on the same colour, so the number painted on top of each
/// one is picked to hold up against that specific artwork rather than
/// leaning on an outline or a backing plate to do the work. Colours are
/// chosen against the artwork itself: pale gold, tan and pink foods take a
/// deep, food-matched shade; the near-black fly and the dark honey pot take
/// a warm off-white instead.
private func answerNumberColor(for foodImageName: String) -> Color {
    switch foodImageName {
    case "food_1": return .white                                        // fly — near-black body
    case "food_2": return Color(red: 0.09, green: 0.22, blue: 0.42)      // fish — deep ocean blue on gold
    case "food_3": return Color(red: 0.11, green: 0.34, blue: 0.14)      // carrot — leaf green on orange
    case "food_4": return Color(red: 0.32, green: 0.19, blue: 0.07)      // kibble — dark biscuit brown on tan
    case "food_5": return .white                                        // meat — red-orange
    case "food_6": return Color(red: 0.30, green: 0.14, blue: 0.24)      // pearl — deep plum on pale pink
    case "food_7": return Color(red: 0.42, green: 0.07, blue: 0.05)      // shrimp — deep shell red on orange
    case "food_8": return Color(red: 0.30, green: 0.17, blue: 0.05)      // peanut — dark shell brown on tan
    case "food_9": return Color(red: 1.0, green: 0.95, blue: 0.83)       // honey — warm cream on dark amber
    case "food_10": return Color(red: 0.34, green: 0.14, blue: 0.04)     // chicken — deep roast brown on tan
    default: return .white
    }
}

/// The math answer, centred on whatever food is carrying it, in that food's
/// own contrasting colour rather than an outline or a plate behind it.
/// Shared between the flying and the just-caught view so a catch never
/// jumps between two different badge styles.
private func answerBadge(text: String, foodImageName: String, size: CGFloat) -> some View {
    Text(verbatim: text)
        .font(.system(size: size * 0.44, weight: .black, design: .rounded))
        .minimumScaleFactor(0.55)
        .lineLimit(1)
        .foregroundStyle(answerNumberColor(for: foodImageName))
        .frame(width: size * 0.78, height: size * 0.78)
}

/// Where a food's own wings attach, and how far apart they sit — read off
/// each artwork's actual silhouette rather than one position tuned for the
/// round fly, so a diagonal carrot or a top-heavy honey pot both keep their
/// wings resting against their body instead of floating above it.
private struct WingLayout {
    /// Offsets as a fraction of the food's frame, from centre.
    let dx: CGFloat
    let dy: CGFloat
    /// How far each wing sits from the pair's centre, and how that scales
    /// the wing shape itself so narrower foods get proportionally smaller
    /// wings rather than ones that overhang their body.
    let spread: CGFloat

    var scale: CGFloat { spread / 0.18 }
}

private func wingLayout(for foodImageName: String) -> WingLayout {
    switch foodImageName {
    case "food_2": return WingLayout(dx: -0.05, dy: -0.20, spread: 0.19)   // fish
    case "food_3": return WingLayout(dx: 0.01, dy: -0.11, spread: 0.18)    // carrot
    case "food_4": return WingLayout(dx: 0, dy: -0.16, spread: 0.18)       // kibble
    case "food_5": return WingLayout(dx: -0.05, dy: -0.09, spread: 0.15)   // meat
    case "food_6": return WingLayout(dx: 0.01, dy: -0.23, spread: 0.15)    // pearl
    case "food_7": return WingLayout(dx: -0.02, dy: -0.18, spread: 0.24)   // shrimp
    case "food_8": return WingLayout(dx: -0.01, dy: -0.12, spread: 0.18)   // peanut
    case "food_9": return WingLayout(dx: 0.01, dy: -0.30, spread: 0.14)    // honey
    case "food_10": return WingLayout(dx: -0.09, dy: -0.09, spread: 0.14)  // chicken
    default: return WingLayout(dx: 0, dy: -0.18, spread: 0.22)             // fallback, unused by food_1
    }
}

/// One food and the answer written on it, as it is drawn.
///
/// The drop shadow under the artwork has no shape to follow — it is cast by the
/// food's own alpha — so drawing this live costs a render pass of its own per
/// fly, and a full swarm is up to ten of them at once. It is therefore never
/// drawn live: `FoodGlyphCache` bakes it into a flat image, once, and the swarm
/// carries copies of that.
private struct FoodGlyphArtwork: View {
    let foodImageName: String
    let text: String
    let size: CGFloat

    /// Room around the artwork for the shadow to fall into. Without it the
    /// raster is cut to the food itself and the shadow is clipped off.
    fileprivate static func margin(for size: CGFloat) -> CGFloat { size * 0.16 }

    var body: some View {
        ZStack {
            // Each food's own artwork leaves room at its centre for the
            // answer, the same spot the plain fly's body used to fill.
            Image(foodImageName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
            answerBadge(text: text, foodImageName: foodImageName, size: size * 0.5)
        }
        .padding(Self.margin(for: size))
    }
}

/// The baked foods, kept for the life of the app.
///
/// A level asks for a small, repeating set of numbers on a single food at a
/// single size, so after the first few rounds this is very nearly all hits —
/// and a hit is a plain image, with no shadow to blur, no text to lay out and
/// no buffer of its own for the compositor to manage. The swarm used to carry
/// ten live `drawingGroup`s, each of which is exactly such a buffer.
///
/// Baking is not free, so it is kept off the frame a swarm arrives on:
/// `warm(_:)` is called for the sums the session has already generated, two
/// rounds before they are ever flown.
@MainActor
private enum FoodGlyphCache {
    private struct Key: Hashable {
        let food: String
        let text: String
        let size: CGFloat
        let scale: CGFloat
    }

    /// A stored `nil` is a refusal that has already been tried. Without it a
    /// glyph that will not bake would be attempted again on every frame it is
    /// on screen, which is far worse than the thing it failed to save.
    private static var images: [Key: Image?] = [:]
    /// Answers are short and repeat, but a long Supermix run meets a lot of
    /// them. Past this the oldest are dropped rather than kept for good.
    private static let limit = 160
    private static var order: [Key] = []

    /// The baked glyph, or nil if this platform declined to render it — in
    /// which case the caller draws the food and its number directly.
    static func image(food: String, text: String,
                      size: CGFloat, scale: CGFloat) -> Image? {
        let key = Key(food: food, text: text, size: size, scale: scale)
        if let cached = images[key] { return cached }
        let renderer = ImageRenderer(
            content: FoodGlyphArtwork(foodImageName: food, text: text, size: size)
        )
        renderer.scale = scale
        let image = renderer.uiImage.map { Image(uiImage: $0) }
        if order.count >= limit {
            images.removeValue(forKey: order.removeFirst())
        }
        images[key] = image
        order.append(key)
        return image
    }

    /// Bakes a set of answers ahead of the round that will fly them.
    static func warm(_ texts: [String], food: String,
                     size: CGFloat, scale: CGFloat) {
        for text in texts {
            _ = image(food: food, text: text, size: size, scale: scale)
        }
    }
}

private struct TongueView: View {
    let catchState: TongueCatch
    let foodImageName: String
    let isPad: Bool
    /// Roughly the width of the character's head. The ribbon's girth and the
    /// stretch it needs to unroll are proportions of the head, not of the
    /// whole reclining body.
    let headSize: CGFloat
    let mouthOpening: CGRect
    /// The painted mouth this ribbon belongs to. A bear's brick-red tongue and
    /// an octopus's pale pink one are both taken from the artwork, so the
    /// tongue never arrives in a colour the character does not own.
    let mouth: MouthGeometry
    let reduceMotion: Bool

    private var deepTongue: Color { mouth.tongueDeepColor }
    private var midTongue: Color { mouth.tongueColor }
    private var lightTongue: Color { mouth.tongueLightColor }

    var body: some View {
        let tip = catchState.tip
        // The ribbon leaves from just inside the throat, so its cut-off root
        // stays hidden behind the lip instead of ending on the frog's chin.
        let root = rootPoint(towards: tip)
        let dx = tip.x - root.x
        let dy = tip.y - root.y
        let distance = hypot(dx, dy)
        let angle = atan2(dy, dx)
        // The ribbon is sized by the mouth it comes out of, not by the head or
        // by a fixed number of points. A bunny's slit and a dog's open jaw are
        // three times apart in width, and a single girth that suits one reads
        // as a tongue far too fat to have fitted through the other. Staying
        // just inside the painted opening is what sells it as coming from
        // inside the animal. The floor only guards the very smallest phone.
        // Both axes of the opening matter, not just its width: an elephant's
        // mouth is a short slot, and a ribbon cut only to its width would be
        // shaved by the lip on the way through at anything but a flat angle.
        let thickness = max(isPad ? 7 : 4.5,
                            min(mouthOpening.width * 0.80, mouthOpening.height * 1.25))
        // Girth ramps in over the first stretch out of the mouth so the tongue
        // unrolls rather than popping to full width on frame one.
        let girth = thickness * min(1, 0.34 + distance / max(1, headSize * 0.9) * 0.66)
        let sideways = min(isPad ? 46 : 32, distance * 0.15) * (dx < 0 ? -1 : 1)
        let bend = sideways + lash(distance: distance)
        let squash = pow(catchState.impact, 1.4)
        let flySize = FlyConfig.flySize(isPad: isPad)
        // The pad grabs a fly, so it is measured against the fly rather than
        // against the mouth — a pad scaled off a bunny's slit would disappear
        // behind the thing it is supposed to be sticking to.
        let pad = max(thickness * 1.62, flySize * 0.30)
        // A caught fly is reeled in and eaten, so it has to end up small enough
        // to have gone through the mouth. It shrinks the whole way back rather
        // than staying full size and dissolving at the lip, which read as the
        // answer being wished away instead of swallowed.
        let swallow = swallowScale(flySize: flySize)

        ZStack {
            // Darkened throat behind the ribbon: without it the tongue looks
            // pasted onto the painted mouth instead of coming out of it.
            Ellipse()
                .fill(mouth.throatColor.opacity(0.55))
                .frame(width: mouthOpening.width, height: mouthOpening.height)
                .position(x: mouthOpening.midX, y: mouthOpening.midY)
                .blur(radius: mouthOpening.height * 0.16)

            // Everything the tongue carries is cut to the lip. Behind the mouth
            // it is visible through the painted opening and nowhere else, so
            // the ribbon's root can sit deep inside the head without painting
            // over the muzzle, and the catch is genuinely swallowed: it passes
            // behind the lip instead of fading out in front of the face.
            Group {
                RolledTongueShape(start: root, end: tip, thickness: girth, bend: bend)
                    .fill(LinearGradient(colors: [deepTongue, midTongue, lightTongue],
                                         startPoint: .bottom, endPoint: .top))
                    .shadow(color: deepTongue.opacity(0.34), radius: 2, y: 2)

                TongueCenterline(start: root, end: tip, bend: bend)
                    .stroke(Color.white.opacity(0.27),
                            style: StrokeStyle(lineWidth: girth * 0.18, lineCap: .round))

                // Mucus strands that stay behind on the fly's position and
                // stretch thin as the pad peels away with its catch.
                if catchState.hasLanded {
                    StickyStrands(anchor: catchState.target, tip: tip,
                                  spread: pad * swallow * 0.42,
                                  fade: strandFade)
                        .stroke(lightTongue.opacity(0.55 * strandFade),
                                style: StrokeStyle(lineWidth: max(1, pad * 0.07),
                                                   lineCap: .round))
                }

                // The sticky pad: a club that flattens across the direction of
                // travel on contact. It also slides back onto the fly's near
                // side, otherwise the splat sits concentric with the fly and is
                // hidden behind the very thing it is splatting onto.
                Ellipse()
                    .fill(LinearGradient(colors: [midTongue, lightTongue],
                                         startPoint: .bottom, endPoint: .top))
                    .frame(width: (pad + flySize * 0.70 * squash) * swallow,
                           height: pad * (0.76 - 0.24 * squash) * swallow)
                    .rotationEffect(.radians(angle + .pi / 2))
                    .position(x: tip.x - cos(angle) * flySize * 0.24 * squash,
                              y: tip.y - sin(angle) * flySize * 0.24 * squash)

                if catchState.hasLanded {
                    StuckFlyView(text: catchState.text, foodImageName: foodImageName, size: flySize,
                                 squash: squash, angle: angle,
                                 struggle: catchState.elapsed, phase: catchState.flyPhase,
                                 muted: reduceMotion)
                        .scaleEffect(swallow)
                        .position(tip)
                }
            }
            // Two overlapping opaque shapes rather than one boolean-combined
            // path: a mask adds up what is drawn into it, so this is the same
            // union without running a path union on every frame of a strike.
            //
            // A mask is the most expensive thing on screen during a strike: its
            // contents are rendered into a buffer of their own before they can
            // be applied. The cone is the only part of it that moves, and it is
            // handed a heading rounded to a degree and a half — small enough
            // that nothing shows (its edges live inside the mouth, and the
            // ribbon itself still swings smoothly), large enough that a whole
            // strike is covered by a handful of distinct masks instead of one
            // per frame.
            .mask {
                ZStack {
                    MouthOutwardClip(opening: mouthOpening,
                                     heading: MouthOutwardClip.settled(angle))
                    MouthLipClip(opening: mouthOpening)
                }
            }

            // The splat stays out in the field where the fly was hit, so it is
            // deliberately outside the mouth mask.
            if catchState.impact > 0 {
                SplatBurst(progress: 1 - catchState.impact, angle: angle,
                           unit: flySize * 0.42, muted: reduceMotion)
                    .position(catchState.target)
            }
        }
        .allowsHitTesting(false)
    }

    /// How large the catch still is, from 1 out at the fly to just small enough
    /// to have fitted through this character's mouth. Measured against the
    /// painted opening, so a crab's wide jaw swallows a bigger fly than a
    /// bunny's slit does — and never below a size that still reads as a fly.
    private func swallowScale(flySize: CGFloat) -> CGFloat {
        let body = max(1, flySize * 0.68)
        let fits = min(1, max(0.18, mouthOpening.width / body))
        return 1 - (1 - fits) * catchState.swallowProgress
    }

    private var strandFade: Double {
        Double(max(0, 1 - catchState.retractionProgress / 0.45))
    }

    private func rootPoint(towards tip: CGPoint) -> CGPoint {
        let dx = tip.x - catchState.start.x
        let dy = tip.y - catchState.start.y
        let length = max(0.001, hypot(dx, dy))
        let inset = headSize * 0.06
        return CGPoint(x: catchState.start.x - dx / length * inset,
                       y: catchState.start.y - dy / length * inset)
    }

    /// A damped lash running through the ribbon once the strike lands. The
    /// tongue is elastic, so it keeps ringing while it reels the fly in.
    private func lash(distance: CGFloat) -> CGFloat {
        guard !reduceMotion else { return 0 }
        let since = catchState.elapsed - FlyConfig.extensionTime
        guard since > 0 else { return 0 }
        return CGFloat(sin(since * 42) * exp(-since * 8.5)) * distance * 0.055
    }
}

/// Everything the tongue may cover on its way out of the head, from the mouth
/// outwards. Masking the ribbon with this is what keeps its root from spilling
/// onto the chin: the stub that lives inside the head shows through the opening
/// the artist drew and is cut off exactly at the lip.
///
/// It is a cone rather than a half-plane. A half-plane cut across the tongue's
/// direction let the ribbon leave at its full girth from the moment it passed
/// the middle of the mouth — and the ribbon is sized to squeeze through a slot,
/// so on a wide, shallow mouth like the frog's that girth is taller than the
/// opening. The overhang showed as a squared-off corner of tongue poking out
/// of the lip, above and below the mouth, whenever the strike ran sideways.
///
/// The cone starts exactly as wide as the opening measured across the tongue's
/// own direction — the aperture the ribbon really has to fit through — and
/// widens from there, so the ribbon emerges from inside the mouth and nowhere
/// else. At the mouth the cone and the lip ellipse are the same width, so the
/// two still meet flush at every angle instead of pinching or leaving a gap.
private struct MouthOutwardClip: Shape {
    let opening: CGRect
    /// Direction the tongue is travelling, in radians.
    let heading: CGFloat

    /// A heading snapped to the nearest step, so consecutive frames of a strike
    /// hand this shape the same value and the mask behind it can be reused
    /// rather than rebuilt and re-rendered. Two structs that compare equal are
    /// what lets SwiftUI skip the work.
    static func settled(_ heading: CGFloat) -> CGFloat {
        let step = CGFloat.pi / 120        // one and a half degrees
        return (heading / step).rounded() * step
    }

    func path(in rect: CGRect) -> Path {
        let lip = mouthLipRect(opening)
        let reach = (rect.width + rect.height) * 2
        // Half the lip's chord through its centre, taken across the heading.
        // For a strike straight out to the side that is half the mouth's
        // height; for one straight up or down, half its width.
        let semiX = max(0.5, lip.width / 2)
        let semiY = max(0.5, lip.height / 2)
        let across = hypot(sin(heading) / semiX, cos(heading) / semiY)
        let aperture = 1 / max(0.0001, across)
        // Just under half a point of flare for every point travelled. Opening
        // faster than that puts the ribbon back at full girth while it is still
        // over the lip, which is the overhang this shape exists to cut; opening
        // slower would start shaving the ribbon's outer edge mid-flight, where
        // the sideways bend and the lash after impact swing it widest.
        let flare: CGFloat = 0.45
        let far = aperture + reach * flare

        var cone = Path()
        cone.move(to: CGPoint(x: 0, y: -aperture))
        cone.addLine(to: CGPoint(x: reach, y: -far))
        cone.addLine(to: CGPoint(x: reach, y: far))
        cone.addLine(to: CGPoint(x: 0, y: aperture))
        cone.closeSubpath()

        cone = cone.applying(CGAffineTransform(rotationAngle: heading))
        return cone.applying(CGAffineTransform(translationX: opening.midX,
                                               y: opening.midY))
    }
}

/// The painted opening itself, with a hair of margin: the measured opening is
/// the visible red, and the ribbon should not be shaved by its own
/// anti-aliased edge.
private struct MouthLipClip: Shape {
    let opening: CGRect

    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: mouthLipRect(opening))
    }
}

/// The painted opening plus that hair of margin. Both halves of the mask work
/// from the same rectangle, so the cone leaves the mouth at exactly the width
/// the lip lets through.
private func mouthLipRect(_ opening: CGRect) -> CGRect {
    opening.insetBy(dx: -opening.width * 0.04, dy: -opening.height * 0.04)
}

/// A soft ribbon following a quadratic curve, broad where it leaves the mouth
/// and tapering towards the pad, so it reads as unrolling out of the throat
/// rather than as a straight bar drawn over the scene.
private struct RolledTongueShape: Shape {
    let start: CGPoint
    let end: CGPoint
    let thickness: CGFloat
    let bend: CGFloat

    func path(in rect: CGRect) -> Path {
        let samples = 28
        let control = tongueControlPoint(start: start, end: end, bend: bend)
        var upper: [CGPoint] = []
        var lower: [CGPoint] = []

        for index in 0...samples {
            let t = CGFloat(index) / CGFloat(samples)
            let point = quadraticPoint(start: start, control: control, end: end, t: t)
            let tangent = quadraticTangent(start: start, control: control, end: end, t: t)
            let length = max(0.001, hypot(tangent.x, tangent.y))
            let normal = CGPoint(x: -tangent.y / length, y: tangent.x / length)
            // Barely tapered. Now that the girth is cut to the mouth it comes
            // out of, the old strong taper left nothing but a thread by the
            // time the ribbon reached the fly.
            let halfWidth = thickness * (0.50 - 0.15 * t)
            upper.append(CGPoint(x: point.x + normal.x * halfWidth,
                                 y: point.y + normal.y * halfWidth))
            lower.append(CGPoint(x: point.x - normal.x * halfWidth,
                                 y: point.y - normal.y * halfWidth))
        }

        var path = Path()
        guard let first = upper.first else { return path }
        path.move(to: first)
        upper.dropFirst().forEach { path.addLine(to: $0) }
        lower.reversed().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }
}

/// Three threads of mucus left hanging between the point of impact and the
/// retreating pad. They sag under their own weight as they stretch.
private struct StickyStrands: Shape {
    let anchor: CGPoint
    let tip: CGPoint
    let spread: CGFloat
    let fade: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard fade > 0.001 else { return path }
        let dx = tip.x - anchor.x
        let dy = tip.y - anchor.y
        let length = max(0.001, hypot(dx, dy))
        let normal = CGPoint(x: -dy / length, y: dx / length)

        for index in -1...1 {
            let offset = CGFloat(index) * spread * 0.5
            let from = CGPoint(x: anchor.x + normal.x * offset,
                               y: anchor.y + normal.y * offset)
            let sag = spread * CGFloat(index == 0 ? 0.7 : 1.1)
            let control = CGPoint(x: (from.x + tip.x) * 0.5 + normal.x * sag,
                                  y: (from.y + tip.y) * 0.5 + normal.y * sag)
            path.move(to: from)
            path.addQuadCurve(to: tip, control: control)
        }
        return path
    }
}

/// The moment of contact: a ring of displaced goo plus a handful of droplets
/// thrown sideways out of the impact.
private struct SplatBurst: View {
    let progress: CGFloat
    let angle: CGFloat
    let unit: CGFloat
    let muted: Bool

    var body: some View {
        let opacity = Double(max(0, 1 - progress))
        // Everything starts just outside the fly's silhouette; a burst that
        // begins at the centre spends its brightest frames hidden behind it.
        ZStack {
            Ellipse()
                .stroke(Color(red: 1.0, green: 0.72, blue: 0.76).opacity(opacity * 0.85),
                        lineWidth: unit * 0.22 * (1 - progress * 0.55))
                .frame(width: unit * (1.75 + progress * 1.9),
                       height: unit * (1.45 + progress * 1.3))
                .rotationEffect(.radians(angle + .pi / 2))

            if !muted {
                ForEach(0..<6, id: \.self) { index in
                    let spray = Double(index) * .pi / 3 + Double(angle)
                    let reach = unit * (0.85 + progress * 1.7)
                    Circle()
                        .fill(Color(red: 1.0, green: 0.66, blue: 0.71).opacity(opacity * 0.9))
                        .frame(width: unit * (0.26 - CGFloat(index % 3) * 0.05))
                        .offset(x: CGFloat(cos(spray)) * reach,
                                y: CGFloat(sin(spray)) * reach)
                }
            }
        }
    }
}

private struct TongueCenterline: Shape {
    let start: CGPoint
    let end: CGPoint
    let bend: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end,
                          control: tongueControlPoint(start: start, end: end, bend: bend))
        return path
    }
}

private func tongueControlPoint(start: CGPoint, end: CGPoint, bend: CGFloat) -> CGPoint {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = max(0.001, hypot(dx, dy))
    return CGPoint(x: start.x + dx * 0.48 - dy / length * bend,
                   y: start.y + dy * 0.48 + dx / length * bend)
}

private func quadraticPoint(start: CGPoint, control: CGPoint, end: CGPoint,
                            t: CGFloat) -> CGPoint {
    let inverse = 1 - t
    return CGPoint(x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
                   y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y)
}

private func quadraticTangent(start: CGPoint, control: CGPoint, end: CGPoint,
                              t: CGFloat) -> CGPoint {
    CGPoint(x: 2 * (1 - t) * (control.x - start.x) + 2 * t * (end.x - control.x),
            y: 2 * (1 - t) * (control.y - start.y) + 2 * t * (end.y - control.y))
}

/// The caught fly, pressed flat against the pad. Its wings splay out and go
/// limp, and it keeps twitching while it is dragged back to the mouth.
private struct StuckFlyView: View {
    let text: String
    let foodImageName: String
    let size: CGFloat
    let squash: CGFloat
    let angle: CGFloat
    let struggle: Double
    let phase: Double
    let muted: Bool

    var body: some View {
        let twitch = muted ? 0 : sin(struggle * 46 + phase) * Double(6 * (0.3 + squash))
        ZStack {
            if !foodPaintsOwnWings(foodImageName) {
                wing(flipped: false)
                wing(flipped: true)
            }
            Image(foodImageName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
            answerBadge(text: text, foodImageName: foodImageName, size: size * 0.5)
        }
        .scaleEffect(FlyConfig.foodVisualScale)
        .rotationEffect(.degrees(twitch))
        // Compress along the direction the pad came from, which is what sells
        // the fly as splatted rather than merely carried.
        .rotationEffect(.radians(Double(-angle)))
        .scaleEffect(x: 1 - 0.34 * squash, y: 1 + 0.26 * squash)
        .rotationEffect(.radians(Double(angle)))
    }

    private func wing(flipped: Bool) -> some View {
        let side: CGFloat = flipped ? 1 : -1
        let wings = wingLayout(for: foodImageName)
        // Splayed wide at the moment of impact, folding back as it settles.
        let splay = 34 + 30 * Double(squash)
        return Capsule()
            .fill(.white.opacity(0.62))
            .frame(width: size * 0.5 * wings.scale, height: size * 0.27 * wings.scale)
            .rotationEffect(.degrees(Double(side) * splay))
            .offset(x: size * (wings.dx + side * wings.spread),
                    y: size * wings.dy + size * 0.16 * squash)
    }
}

private struct ActiveQuestionView: View {
    let prompt: String
    let character: AnimalCharacter
    let isPad: Bool
    let size: CGSize

    var body: some View {
        Text(verbatim: prompt)
            // A sum reads left to right in every language; the bidirectional
            // algorithm would otherwise turn "3 × 1 = ?" around in Arabic.
            .environment(\.layoutDirection, .leftToRight)
            .font(.system(size: isPad ? 40 : 31,
                          weight: .black, design: .rounded))
            .minimumScaleFactor(0.72)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .foregroundStyle(character.deepColor)
            .padding(.horizontal, isPad ? 22 : 16)
            .frame(width: size.width, height: size.height)
            .background(.white.opacity(0.96),
                        in: RoundedRectangle(cornerRadius: isPad ? 23 : 18,
                                             style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: isPad ? 23 : 18,
                                 style: .continuous)
                    .stroke(character.color, lineWidth: isPad ? 5 : 4)
            }
            .shadow(color: character.deepColor.opacity(0.18), radius: 10, y: 5)
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: prompt)
            .accessibilityElement(children: .combine)
    }
}

private struct FlyCelebration: View {
    let clock: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ForEach(0..<16, id: \.self) { index in
                CurrencyIcon(size: CGFloat(18 + index % 4 * 4))
                    .foregroundStyle(color)
                    .position(x: proxy.size.width * CGFloat((index * 37) % 100) / 100,
                              y: proxy.size.height * CGFloat((index * 23) % 100) / 100)
                    .offset(x: CGFloat(sin(clock * 2 + Double(index))) * 18,
                            y: CGFloat(cos(clock * 1.6 + Double(index))) * 14)
            }
        }
    }
}
