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

    /// A fly that has not begun its swoop must not be drawn hanging off screen.
    var isVisible: Bool {
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

private struct CatchFeedback: Identifiable {
    let id = UUID()
    let position: CGPoint
    let isCorrect: Bool
    var elapsed: Double = 0
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

@MainActor
private final class FlyEngine: ObservableObject {
    @Published private(set) var flies: [AnswerFly] = []
    @Published private(set) var tongue: TongueCatch?
    @Published private(set) var feedback: CatchFeedback?
    @Published private(set) var clock: Double = 0

    var onHit: ((UUID) -> Bool)?

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
            scatter { _ in true }
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
        pendingSpecs = specs
        dealPendingSwarm()
    }

    func setLive(_ live: Bool) {
        isLive = live
        if live { dealPendingSwarm() }
    }

    func setRunning(_ running: Bool) {
        isRunning = running
        if running {
            guard displayLink == nil else { return }
            lastFrameTime = 0
            stepAccumulator = 0
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
        let elapsed = lastFrameTime == 0 ? FlyConfig.tick : timestamp - lastFrameTime
        lastFrameTime = timestamp
        stepAccumulator += min(max(0, elapsed), FlyConfig.tick * 3)
        while stepAccumulator >= FlyConfig.tick {
            stepAccumulator -= FlyConfig.tick
            tick()
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
    }

    // MARK: - Simulation

    private func tick() {
        guard isRunning else { return }
        clock += FlyConfig.tick
        moveFlies()
        advanceTongue()
        advanceFeedback()
    }

    private func moveFlies() {
        // Stepped on a copy and published once. Writing straight into the
        // `@Published` array would announce a change per fly per property —
        // dozens of notifications a frame for one visible update.
        var swarm = flies
        for index in swarm.indices {
            if swarm[index].isRetiring {
                advanceScatter(&swarm[index])
            } else if swarm[index].entry != nil {
                advanceEntry(&swarm[index])
            } else if !swarm[index].isLocked {
                advanceFlight(&swarm[index])
            }
        }
        swarm.removeAll {
            $0.isRetiring
                && ($0.exitAge >= FlyConfig.scatterLifetime
                    || !outerRouteBounds.contains($0.position))
        }
        flies = swarm
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
            catchState.wasAccepted = onHit?(catchState.optionID) ?? false
            if catchState.wasAccepted == true {
                feedback = CatchFeedback(position: catchState.target,
                                         isCorrect: catchState.isCorrect)
            }
        }
        if catchState.elapsed >= catchState.total {
            if catchState.wasAccepted == true {
                retiredOptionIDs.insert(catchState.optionID)
                flies.removeAll { $0.id == catchState.flyID }
                if catchState.isCorrect {
                    pendingSpecs.removeAll { $0.roundID == catchState.roundID }
                }
            } else if let index = flies.firstIndex(where: { $0.id == catchState.flyID }) {
                // Input can close while the tongue is already travelling. The
                // fly was never eaten: it resumes if its sum still stands, and
                // otherwise leaves after the swarm it belonged to.
                flies[index].isLocked = false
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
        }
        self.tongue = nil
    }

    private func advanceFeedback() {
        guard var current = feedback else { return }
        current.elapsed += FlyConfig.tick
        feedback = current.elapsed >= 0.72 ? nil : current
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
    let onHit: (UUID) -> Bool
    let onFishEntranceComplete: () -> Void
    let onLevelCompletionFinished: () -> Void

    /// The engine is held through a box that never publishes anything, so this
    /// view is *not* re-run sixty times a second. Only the layers that actually
    /// move observe the engine directly (see `FlySwarmLayer` and friends);
    /// everything else here — the pond, the character, the sum — is laid out
    /// once and left alone.
    @StateObject private var box = FlyEngineBox()
    @State private var entranceToken = 0
    @State private var completionToken = 0

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

            ZStack {
                PondBackdrop(tint: character.color, isPad: isPad)

                FlySwarmLayer(engine: engine,
                              foodImageName: foodImageName,
                              isPad: isPad,
                              isLive: isLive,
                              mouth: mouth)

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
                TongueLayer(engine: engine,
                            foodImageName: foodImageName,
                            isPad: isPad,
                            headSize: headSize,
                            mouthOpening: mouthOpening,
                            mouth: character.mouth,
                            reduceMotion: reduceMotion)

                if let active = rounds.first {
                    ActiveQuestionView(prompt: active.question.prompt,
                                       character: character,
                                       isPad: isPad,
                                       size: questionFrame.size)
                        .position(x: questionFrame.midX, y: questionFrame.midY)
                }

                if playsLevelCompletion {
                    FlyCelebrationLayer(engine: engine, color: character.deepColor)
                }
            }
            .clipped()
            .onAppear {
                engine.onHit = onHit
                applyLayout(in: proxy.size)
                engine.sync(rounds: rounds)
                engine.setLive(isLive)
                engine.setRunning(isRunning)
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
        }
        .onChange(of: rounds.map(\.id)) { _, _ in engine.sync(rounds: rounds) }
        .onChange(of: isLive) { _, value in engine.setLive(value) }
        .onChange(of: isRunning) { _, value in engine.setRunning(value) }
        .onChange(of: playsFishEntrance) { _, value in if value { beginEntrance() } }
        .onChange(of: playsLevelCompletion) { _, value in if value { beginCompletion() } }
        .onDisappear { engine.setRunning(false) }
    }

    private func applyLayout(in size: CGSize) {
        engine.layout(size: size,
                      topReserve: flightCeiling,
                      protectedRects: [questionRect(in: size)],
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
        return CGRect(x: size.width - inset - width, y: minY,
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

/// Holds the engine without ever announcing anything itself. `@StateObject` on
/// the engine directly would subscribe `FlyPlayfield` to every frame of the
/// simulation, whether or not it reads a single moving value.
@MainActor
private final class FlyEngineBox: ObservableObject {
    let engine = FlyEngine()
}

// MARK: - Moving layers
//
// Each of these observes the engine, so a frame of the simulation invalidates
// only the layer whose contents actually changed. The pond, the character
// artwork and the sum card sit outside them and are never rebuilt mid-round.

/// The swarm itself: every answer currently in the air.
private struct FlySwarmLayer: View {
    @ObservedObject var engine: FlyEngine
    let foodImageName: String
    let isPad: Bool
    let isLive: Bool
    /// Where a strike leaves from, in this layer's own coordinates.
    let mouth: CGPoint

    var body: some View {
        let tapSize = FlyConfig.flySize(isPad: isPad) * 1.32
        ZStack {
            ForEach(engine.flies) { fly in
                // The struck fly keeps flying until the pad actually
                // reaches it. Hiding it on tap made it blink away well
                // before the tongue arrived.
                if fly.isVisible,
                   engine.tongue?.flyID != fly.id
                    || engine.tongue?.hasLanded == false {
                    AnswerFlyView(fly: fly, foodImageName: foodImageName,
                                  isPad: isPad, clock: engine.clock)
                        .frame(width: tapSize, height: tapSize)
                        // A plain tap rather than a `Button`: the swarm is
                        // rebuilt every frame, and a button carries a press
                        // state and gesture of its own to be rebuilt with it.
                        .contentShape(Circle())
                        .onTapGesture { engine.catchFly(fly.id, mouth: mouth) }
                        .allowsHitTesting(isLive && fly.isFlying)
                        .accessibilityElement(children: .combine)
                        .accessibilityAction { engine.catchFly(fly.id, mouth: mouth) }
                        .position(fly.position)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The strike: the tongue on its way out and back, and the tick or cross it
/// leaves behind at the point of impact.
private struct TongueLayer: View {
    @ObservedObject var engine: FlyEngine
    let foodImageName: String
    let isPad: Bool
    let headSize: CGFloat
    let mouthOpening: CGRect
    let mouth: MouthGeometry
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            if let tongue = engine.tongue {
                TongueView(catchState: tongue, foodImageName: foodImageName, isPad: isPad,
                           headSize: headSize, mouthOpening: mouthOpening,
                           mouth: mouth,
                           reduceMotion: reduceMotion)
            }

            if let feedback = engine.feedback {
                CatchFeedbackView(feedback: feedback, isPad: isPad)
                    .id(feedback.id)
                    .position(feedback.position)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// The end-of-level bloom, which drifts off the simulation's own clock.
private struct FlyCelebrationLayer: View {
    @ObservedObject var engine: FlyEngine
    let color: Color

    var body: some View {
        FlyCelebration(clock: engine.clock, color: color)
            .allowsHitTesting(false)
    }
}

private struct PondBackdrop: View {
    let tint: Color
    let isPad: Bool

    var body: some View {
        GeometryReader { proxy in
            let waterline = proxy.size.height * FlyConfig.waterlineShare
            ZStack {
                LinearGradient(colors: [Color(red: 0.62, green: 0.87, blue: 0.98),
                                        Color(red: 0.86, green: 0.95, blue: 0.83)],
                               startPoint: .top, endPoint: .bottom)

                Circle()
                    .fill(Color(red: 1.0, green: 0.91, blue: 0.48).opacity(0.78))
                    .frame(width: isPad ? 112 : 76)
                    .blur(radius: 1)
                    .position(x: proxy.size.width * 0.18, y: proxy.size.height * 0.17)

                PondCloud(scale: isPad ? 1.35 : 0.9)
                    .position(x: proxy.size.width * 0.72, y: proxy.size.height * 0.17)
                PondCloud(scale: isPad ? 1.0 : 0.68)
                    .opacity(0.72)
                    .position(x: proxy.size.width * 0.30, y: proxy.size.height * 0.32)

                Ellipse()
                    .fill(Color(red: 0.25, green: 0.58, blue: 0.25))
                    .frame(width: proxy.size.width * 1.35, height: isPad ? 190 : 120)
                    .position(x: proxy.size.width * 0.5, y: waterline + (isPad ? 35 : 24))

                Rectangle()
                    .fill(LinearGradient(colors: [Color(red: 0.27, green: 0.72, blue: 0.78),
                                                   Color(red: 0.08, green: 0.47, blue: 0.64)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: proxy.size.height - waterline)
                    .position(x: proxy.size.width * 0.5,
                              y: waterline + (proxy.size.height - waterline) * 0.5)

                Ellipse()
                    .fill(Color(red: 0.47, green: 0.86, blue: 0.88).opacity(0.72))
                    .frame(width: proxy.size.width * 1.16, height: isPad ? 72 : 46)
                    .position(x: proxy.size.width * 0.5, y: waterline)

                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: isPad ? 100 : 62, height: isPad ? 7 : 5)
                        .position(x: proxy.size.width * CGFloat(0.12 + Double(index) * 0.19),
                                  y: waterline + CGFloat(index % 2) * (isPad ? 54 : 34))
                }

                LilyPad(color: tint)
                    .frame(width: isPad ? 150 : 96, height: isPad ? 64 : 42)
                    .position(x: proxy.size.width * 0.20, y: waterline + (isPad ? 82 : 54))
                LilyPad(color: tint)
                    .frame(width: isPad ? 120 : 78, height: isPad ? 52 : 34)
                    .position(x: proxy.size.width * 0.82, y: waterline + (isPad ? 42 : 29))

                PondReeds()
                    .frame(width: isPad ? 125 : 82, height: isPad ? 190 : 128)
                    .position(x: isPad ? 60 : 40, y: waterline - (isPad ? 48 : 31))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct PondCloud: View {
    let scale: CGFloat

    var body: some View {
        ZStack {
            Capsule().frame(width: 116, height: 35).offset(y: 11)
            Circle().frame(width: 54).offset(x: -27)
            Circle().frame(width: 68).offset(x: 14, y: -7)
            Circle().frame(width: 44).offset(x: 44, y: 6)
        }
        .foregroundStyle(.white.opacity(0.72))
        .scaleEffect(scale)
        .shadow(color: .white.opacity(0.28), radius: 9)
    }
}

private struct LilyPad: View {
    let color: Color

    var body: some View {
        Ellipse()
            .fill(LinearGradient(colors: [Color(red: 0.28, green: 0.66, blue: 0.25),
                                          color.opacity(0.88)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .topTrailing) {
                Circle().fill(Color.white.opacity(0.34)).frame(width: 12, height: 7)
                    .padding(.trailing, 18).padding(.top, 8)
            }
            .rotationEffect(.degrees(-5))
            .shadow(color: .black.opacity(0.13), radius: 3, y: 3)
    }
}

private struct PondReeds: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(0..<6, id: \.self) { index in
                Capsule()
                    .fill(Color(red: 0.17, green: 0.48, blue: 0.16))
                    .frame(width: 6, height: CGFloat(62 + index * 12))
                    .rotationEffect(.degrees(Double(index - 3) * 5))
                    .offset(x: CGFloat(index - 3) * 10)
            }
            ForEach([1, 3, 5], id: \.self) { index in
                Capsule()
                    .fill(Color(red: 0.34, green: 0.18, blue: 0.08))
                    .frame(width: 13, height: 32)
                    .offset(x: CGFloat(index - 3) * 10,
                            y: -CGFloat(52 + index * 12))
            }
        }
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

private struct AnswerFlyView: View {
    let fly: AnswerFly
    /// This character's own food, so a bunny's level fills with carrots while
    /// a penguin's fills with fish — the answer number always rides on top of
    /// whatever is currently flying.
    let foodImageName: String
    let isPad: Bool
    let clock: Double

    /// A swooping fly arrives leaning into its own approach, and a dismissed
    /// one tumbles as it whirls away. Both are read straight off the fly's own
    /// simulated state, so they stay in step with where it actually is.
    private var tilt: Double {
        if fly.isRetiring { return fly.spin * fly.exitAge }
        guard let entry = fly.entry, entry.hasStarted else { return 0 }
        let remaining = 1 - Double(entry.progress)
        return Double(entry.heading) * 57.29578 * 0.16 * max(0, remaining)
    }

    var body: some View {
        let size = FlyConfig.flySize(isPad: isPad)
        let scatter = Double(fly.scatterProgress)
        return ZStack {
            // The fly's own artwork already carries its wings; painting a
            // second pair on top of it would double up. Every other food
            // needs them drawn in, anchored to that food's own silhouette.
            if !foodPaintsOwnWings(foodImageName) {
                FoodWings(foodImageName: foodImageName, size: size,
                          flap: sin(clock * 35 + fly.phase))
            }
            // The artwork and the number on it never change while the fly is
            // in the air, so they live in a view of their own: the swarm is
            // rebuilt every frame, and this way only the flap and the
            // transforms below are actually recomputed.
            FoodGlyph(foodImageName: foodImageName, text: fly.text, size: size)
        }
        // Rendered a third larger than the tap target it sits in: the food
        // needs to be big enough that the number still has room to breathe
        // at its centre, without also growing the hitbox or the spacing the
        // swarm is laid out with.
        .scaleEffect(FlyConfig.foodVisualScale)
        .frame(width: size, height: size)
        .rotationEffect(.degrees(tilt))
        // The swoop lands with a touch of scale behind it and the sweep out
        // pulls back a little into the distance, which keeps a swarm change
        // reading as one movement rather than two sets of flies swapping.
        // Neither end fades: they fly on and off at full strength.
        .scaleEffect(fly.isRetiring
                     ? 1 - 0.1 * scatter
                     : 0.82 + 0.18 * Double(fly.entry?.progress ?? 1))
        .accessibilityLabel(Text(verbatim: fly.text))
        .accessibilityAddTraits(.isButton)
    }
}

/// One food and the answer written on it. Everything here is fixed for the
/// life of a fly, so SwiftUI can skip it entirely on the frames where only the
/// fly's position changed.
private struct FoodGlyph: View {
    let foodImageName: String
    let text: String
    let size: CGFloat

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
    }
}

/// The pair of beating wings on the foods that are not already drawn with
/// them. `flap` is the only thing that moves, once per frame.
private struct FoodWings: View {
    let foodImageName: String
    let size: CGFloat
    /// −1…1, straight off the fly's own wingbeat.
    let flap: Double

    var body: some View {
        let wings = wingLayout(for: foodImageName)
        ZStack {
            Capsule()
                .fill(.white.opacity(0.78))
                .frame(width: size * 0.48 * wings.scale, height: size * 0.30 * wings.scale)
                .rotationEffect(.degrees(-32 + flap * 9))
                .offset(x: size * (wings.dx - wings.spread), y: size * wings.dy)
            Capsule()
                .fill(.white.opacity(0.78))
                .frame(width: size * 0.48 * wings.scale, height: size * 0.30 * wings.scale)
                .rotationEffect(.degrees(32 - flap * 9))
                .offset(x: size * (wings.dx + wings.spread), y: size * wings.dy)
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
            .mask {
                ZStack {
                    MouthOutwardClip(opening: mouthOpening, heading: angle)
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

/// Everything outside the head, plus the painted mouth itself — and nothing
/// else. Masking the ribbon with this is what keeps its root from spilling onto
/// the chin: the stub that lives inside the head shows through the opening the
/// artist drew and is cut off exactly at the lip. The cut runs across the
/// tongue's own direction, so the ribbon meets the lip flush at every angle
/// instead of leaving a gap on one side.
private struct MouthOutwardClip: Shape {
    let opening: CGRect
    /// Direction the tongue is travelling, in radians.
    let heading: CGFloat

    func path(in rect: CGRect) -> Path {
        // A half-plane starting at the mouth and running outwards forever.
        let reach = (rect.width + rect.height) * 2
        var outward = Path(CGRect(x: 0, y: -reach, width: reach, height: reach * 2))
        outward = outward.applying(CGAffineTransform(rotationAngle: heading))
        outward = outward.applying(CGAffineTransform(translationX: opening.midX,
                                                    y: opening.midY))
        return outward
    }
}

/// The painted opening itself, with a hair of margin: the measured opening is
/// the visible red, and the ribbon should not be shaved by its own
/// anti-aliased edge.
private struct MouthLipClip: Shape {
    let opening: CGRect

    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: opening.insetBy(dx: -opening.width * 0.04,
                                        dy: -opening.height * 0.04))
    }
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

private struct CatchFeedbackView: View {
    let feedback: CatchFeedback
    let isPad: Bool

    var body: some View {
        let progress = CGFloat(min(1, feedback.elapsed / 0.72))
        let color = feedback.isCorrect
            ? Color(red: 0.18, green: 0.72, blue: 0.31)
            : Color(red: 0.90, green: 0.20, blue: 0.22)
        let base = isPad ? CGFloat(70) : 52

        ZStack {
            Circle()
                .stroke(color.opacity(Double(1 - progress)), lineWidth: isPad ? 7 : 5)
                .frame(width: base * (0.55 + progress),
                       height: base * (0.55 + progress))

            ForEach(0..<8, id: \.self) { index in
                Circle()
                    .fill(color.opacity(Double(1 - progress)))
                    .frame(width: isPad ? 8 : 6, height: isPad ? 8 : 6)
                    .offset(x: CGFloat(cos(Double(index) * .pi / 4)) * base * progress * 0.72,
                            y: CGFloat(sin(Double(index) * .pi / 4)) * base * progress * 0.72)
            }

            Image(systemName: feedback.isCorrect ? "checkmark" : "xmark")
                .font(.system(size: isPad ? 31 : 23, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: isPad ? 54 : 42, height: isPad ? 54 : 42)
                .background(color, in: Circle())
                .shadow(color: color.opacity(0.35), radius: 7, y: 4)
                .scaleEffect(1 + progress * 0.12)
                .opacity(Double(1 - max(0, progress - 0.62) / 0.38))
        }
        .offset(y: -progress * (isPad ? 30 : 22))
        .accessibilityHidden(true)
    }
}

private struct ActiveQuestionView: View {
    let prompt: String
    let character: AnimalCharacter
    let isPad: Bool
    let size: CGSize

    var body: some View {
        Text(verbatim: prompt)
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
            .accessibilityLabel(Text(verbatim: prompt))
    }
}

struct FlyCurrencyIcon: View {
    let size: CGFloat

    var body: some View {
        CurrencyIcon(size: size)
    }
}

private struct FlyCelebration: View {
    let clock: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ForEach(0..<16, id: \.self) { index in
                FlyCurrencyIcon(size: CGFloat(18 + index % 4 * 4))
                    .foregroundStyle(color)
                    .position(x: proxy.size.width * CGFloat((index * 37) % 100) / 100,
                              y: proxy.size.height * CGFloat((index * 23) % 100) / 100)
                    .offset(x: CGFloat(sin(clock * 2 + Double(index))) * 18,
                            y: CGFloat(cos(clock * 1.6 + Double(index))) * 14)
            }
        }
    }
}
