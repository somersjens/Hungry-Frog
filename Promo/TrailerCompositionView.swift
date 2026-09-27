#if TRAILER_EXPORT
import SwiftUI
import UIKit
import AVFoundation
import CoreVideo
import Combine

// MARK: - Format and timeline

struct TrailerFormat: Hashable {
    let name: String
    let pixels: CGSize
    let points: CGSize
    let isPad: Bool

    static let iphone = TrailerFormat(name: "frog-app-store-teaser-1920x886",
                                      pixels: CGSize(width: 1920, height: 886),
                                      points: CGSize(width: 960, height: 443),
                                      isPad: false)
    static let ipad = TrailerFormat(name: "frog-app-store-teaser-1600x1200",
                                    pixels: CGSize(width: 1600, height: 1200),
                                    points: CGSize(width: 800, height: 600),
                                    isPad: true)
}

enum TrailerTimeline {
    static let duration = 20.0
    static let frameRate: Int32 = 30
    static let strikeDuration = 0.42

    static let firstStrikeStart = 2.00
    static let firstSwarmExit = firstStrikeStart + strikeDuration
    static let firstSwarmEntry = firstSwarmExit + 0.10
    static let firstSwarmSettled = firstSwarmEntry + 1.02
    static let wrongStrikeStart = 5.20
    static let reactionStart = wrongStrikeStart + strikeDuration

    // The zoom is fully restored at this exact frame; the character showcase
    // starts immediately instead of leaving a dead beat between scenes.
    static let animalStart = 7.39
    static let animalDuration = 5.40
    static let frogReturn = animalStart + animalDuration

    static let streakStep = 0.74
    static let streakStart = frogReturn + 0.50

    struct Strike {
        let start: Double
        let fly: Int
        let correct: Bool
        let scoreAfter: Int
    }

    static let strikes: [Strike] = [
        Strike(start: firstStrikeStart, fly: 0, correct: true,  scoreAfter: 1),
        Strike(start: wrongStrikeStart, fly: 2, correct: false, scoreAfter: 1),
        Strike(start: streakStart,                  fly: 1, correct: true, scoreAfter: 2),
        Strike(start: streakStart + streakStep,     fly: 3, correct: true, scoreAfter: 3),
        Strike(start: streakStart + streakStep * 2, fly: 4, correct: true, scoreAfter: 4),
        Strike(start: streakStart + streakStep * 3, fly: 0, correct: true, scoreAfter: 6),
        Strike(start: streakStart + streakStep * 4, fly: 2, correct: true, scoreAfter: 8)
    ]

    // The production tongue reaches the fly at 0.13 s and begins retracting
    // after its 0.10 s contact hold.
    static let tongueContact = 0.13
    static let tongueRetraction = 0.23
    static let boostStart = streakStart + streakStep * 2 + strikeDuration
    static let completionStart = streakStart + streakStep * 4 + tongueContact
    // The final catch gets a clean confetti beat before the two-second icon
    // ending. Keeping these tied together prevents a long tail after play.
    static let iconStart = duration - 2.00

    static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

    static func smooth(_ value: Double) -> Double {
        let x = clamp(value)
        return x * x * (3 - 2 * x)
    }

    static func ramp(_ time: Double, from: Double, to: Double) -> Double {
        guard to > from else { return time >= to ? 1 : 0 }
        return smooth((time - from) / (to - from))
    }

    static func window(_ time: Double, start: Double, end: Double,
                       fade: Double = 0.24) -> Double {
        min(ramp(time, from: start, to: start + fade),
            1 - ramp(time, from: end - fade, to: end))
    }
}

// MARK: - Composition

struct TrailerCompositionView: View {
    let time: Double
    let format: TrailerFormat

    private var frog: AnimalCharacter { CharacterCatalog.character(id: "frog") }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let stage = TrailerStageGeometry.characterRect(isPad: format.isPad, in: size)
            let question = questionRect(in: size)
            let zoom = cameraZoom
            let endBlur = TrailerTimeline.ramp(time,
                                               from: TrailerTimeline.iconStart - 0.35,
                                               to: TrailerTimeline.iconStart + 0.35)
            let anchor = UnitPoint(x: stage.midX / max(1, size.width),
                                   y: stage.midY / max(1, size.height))

            ZStack {
                gameplay(size: size, stage: stage, question: question)
                    .scaleEffect(zoom, anchor: anchor)
                    .offset(x: cameraDrift.width, y: cameraDrift.height)
                    .compositingGroup()
                    .blur(radius: CGFloat(endBlur * 4.0))

                promotionalText(size: size)

                iconEnding(size: size)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .environment(\.layoutDirection, .leftToRight)
        }
        .frame(width: format.points.width, height: format.points.height)
        .background(frog.skyColor)
    }

    private func gameplay(size: CGSize, stage: CGRect, question: CGRect) -> some View {
        ZStack {
            ForEach(characterWeights, id: \.character.id) { item in
                characterWorld(character: item.character,
                               opacity: item.opacity,
                               size: size,
                               stage: stage,
                               question: question)
            }

            hud(size: size)
                .offset(y: -CGFloat(hudExitProgress) * (format.isPad ? 150 : 116))

            if time < TrailerTimeline.firstStrikeStart - 0.04 {
                TrailerTutorialArrow(target: flyPosition(index: 0, at: time, in: size),
                                     source: question,
                                     color: frog.deepColor,
                                     isPad: format.isPad,
                                     clock: time)
                    .transition(.opacity)
            }

            selectionRipple(size: size)

            if let strike = activeStrike {
                let local = time - strike.strike.start
                TrailerTongueStrike(character: activeCharacter,
                                    isPad: format.isPad,
                                    stage: stage,
                                    target: flyPosition(index: strike.strike.fly,
                                                        at: strike.strike.start,
                                                        in: size),
                                    answer: answer(for: strike.strike.fly),
                                    elapsed: local,
                                    isCorrect: strike.strike.correct)
            }

            if time >= TrailerTimeline.completionStart {
                let rise = TrailerTimeline.ramp(time,
                                                from: TrailerTimeline.completionStart,
                                                to: TrailerTimeline.completionStart + 0.92)
                TrailerCompletionFlies(clock: time * 1.35, color: frog.deepColor)
                    .currencyIcon(for: frog)
                    // Keep the production fly bloom wide enough that it still
                    // surrounds the icon instead of zooming down to two giant
                    // flies at the end of the push-in.
                    .scaleEffect(1 + rise * 0.28)
                    .opacity(TrailerTimeline.window(time,
                                                    start: TrailerTimeline.completionStart,
                                                    end: TrailerTimeline.duration + 0.28,
                                                    fade: 0.28))
            }
        }
    }

    private func characterWorld(character: AnimalCharacter,
                                opacity: Double,
                                size: CGSize,
                                stage: CGRect,
                                question: CGRect) -> some View {
        ZStack {
            CharacterBackdrop(character: character,
                              stage: stage,
                              horizon: PlayStage.horizon(in: size),
                              reduceMotion: false)

            flies(character: character, size: size, stage: stage)

            if character.id == "frog",
               time >= TrailerTimeline.reactionStart,
               time < TrailerTimeline.reactionStart + 1.05 {
                TrailerWrongReaction(stage: stage,
                                     elapsed: time - TrailerTimeline.reactionStart,
                                     displayScale: 2)
            } else {
                character.playArtwork
                    .resizable()
                    .scaledToFit()
                    .frame(width: stage.width, height: stage.height)
                    .position(x: stage.midX, y: stage.midY)
            }

            TrailerQuestionCard(prompt: questionPrompt,
                                character: character,
                                isPad: format.isPad,
                                size: question.size)
                .position(x: question.midX, y: question.midY)
                .offset(y: -CGFloat(hudExitProgress) * (format.isPad ? 150 : 116))
        }
        .opacity(opacity)
        .currencyIcon(for: character)
    }

    @ViewBuilder
    private func flies(character: AnimalCharacter, size: CGSize, stage: CGRect) -> some View {
        if time >= TrailerTimeline.firstSwarmExit,
           time < TrailerTimeline.firstSwarmSettled {
            // The caught answer stays on the tongue. The other four flies use
            // the live game's scatter profile, while a complete replacement
            // swarm swoops in from beyond the nearest screen edges.
            ForEach(1..<5, id: \.self) { index in
                TrailerFoodGlyph(characterID: character.id,
                                 answer: firstRoundAnswer(for: index),
                                 isPad: format.isPad)
                    .rotationEffect(.degrees(scatterRotation(index: index)))
                    .scaleEffect(scatterScale)
                    .position(firstSwarmScatterPosition(index: index,
                                                        size: size,
                                                        stage: stage))
            }

            ForEach(0..<5, id: \.self) { index in
                let entry = firstReplacementEntry(index: index, size: size)
                TrailerFoodGlyph(characterID: character.id,
                                 answer: answer(for: index),
                                 isPad: format.isPad)
                    .rotationEffect(.degrees(entry.rotation))
                    .opacity(entry.opacity)
                    .position(entry.position)
            }
        } else {
            ForEach(0..<5, id: \.self) { index in
                let hidden = activeStrike.map {
                    $0.strike.fly == index && $0.local >= 0.13
                } ?? false
                TrailerFoodGlyph(characterID: character.id,
                                 answer: answer(for: index),
                                 isPad: format.isPad)
                    .rotationEffect(.degrees(sin(time * 2.1 + Double(index)) * 5.5))
                    .scaleEffect(hidden ? 0.01 : flyEntryScale(index: index))
                    .opacity(hidden ? 0 : flyEntryOpacity(index: index))
                    .position(flyPosition(index: index, at: time, in: size))
            }
        }
    }

    // MARK: Layout and deterministic motion

    private func questionRect(in size: CGSize) -> CGRect {
        let inset: CGFloat = format.isPad ? 28 : 16
        let width: CGFloat = format.isPad ? min(320, size.width * 0.40)
                                            : min(280, size.width * 0.30)
        let height: CGFloat = format.isPad ? 82 : 64
        return CGRect(x: size.width - inset - width,
                      y: format.isPad ? 36 : 20,
                      width: width,
                      height: height)
    }

    private func flyPosition(index: Int, at moment: Double, in size: CGSize) -> CGPoint {
        let basesPhone: [CGPoint] = [
            CGPoint(x: 0.72, y: 0.42), CGPoint(x: 0.48, y: 0.27),
            CGPoint(x: 0.30, y: 0.47), CGPoint(x: 0.82, y: 0.70),
            CGPoint(x: 0.16, y: 0.72)
        ]
        let basesPad: [CGPoint] = [
            CGPoint(x: 0.70, y: 0.42), CGPoint(x: 0.45, y: 0.29),
            CGPoint(x: 0.25, y: 0.48), CGPoint(x: 0.78, y: 0.70),
            CGPoint(x: 0.16, y: 0.68)
        ]
        let base = (format.isPad ? basesPad : basesPhone)[index]
        let phase = Double(index) * 1.37
        let x = base.x * size.width
            + CGFloat(sin(moment * (0.92 + Double(index) * 0.035) + phase))
                * (format.isPad ? 32 : 39)
        let y = base.y * size.height
            + CGFloat(cos(moment * (1.15 + Double(index) * 0.04) + phase * 0.73))
                * (format.isPad ? 25 : 19)
        return CGPoint(x: x, y: y)
    }

    private func firstRoundAnswer(for index: Int) -> String {
        index == 0 ? "6" : ["4", "8", "9", "12", "5"][index]
    }

    private func firstSwarmScatterPosition(index: Int,
                                           size: CGSize,
                                           stage: CGRect) -> CGPoint {
        let start = flyPosition(index: index,
                                at: TrailerTimeline.firstSwarmExit,
                                in: size)
        let origin = CGPoint(x: stage.midX, y: stage.midY)
        let angleNudges: [Double] = [0, -0.16, 0.13, -0.11, 0.17]
        let baseAngle = Double(atan2(start.y - origin.y, start.x - origin.x))
            + angleNudges[index]
        let age = max(0, time - TrailerTimeline.firstSwarmExit)
        let launch = format.isPad ? 150.0 : 120.0
        let top = format.isPad ? 2_000.0 : 1_600.0
        let ramp = 0.26
        let distance: Double
        if age < ramp {
            let x = age / ramp
            distance = launch * age
                + (top - launch) * ramp * (x * x * x - 0.5 * x * x * x * x)
        } else {
            distance = ramp * (launch + 0.5 * (top - launch))
                + top * (age - ramp)
        }
        return CGPoint(x: start.x + CGFloat(cos(baseAngle) * distance),
                       y: start.y + CGFloat(sin(baseAngle) * distance))
    }

    private var scatterScale: CGFloat {
        let age = max(0, time - TrailerTimeline.firstSwarmExit)
        return CGFloat(1 - min(1, age / 0.26) * 0.10)
    }

    private func scatterRotation(index: Int) -> Double {
        let spins: [Double] = [0, -226, 278, -312, 244]
        return spins[index] * max(0, time - TrailerTimeline.firstSwarmExit)
    }

    private func firstReplacementEntry(index: Int,
                                       size: CGSize) -> (position: CGPoint,
                                                        rotation: Double,
                                                        opacity: Double) {
        let target = flyPosition(index: index,
                                 at: TrailerTimeline.firstSwarmSettled,
                                 in: size)
        let margin: CGFloat = format.isPad ? 82 : 62
        let origins: [CGPoint] = [
            CGPoint(x: size.width + margin, y: target.y - size.height * 0.08),
            CGPoint(x: target.x + size.width * 0.06, y: -margin),
            CGPoint(x: -margin, y: target.y - size.height * 0.04),
            CGPoint(x: size.width + margin, y: target.y + size.height * 0.05),
            CGPoint(x: -margin, y: target.y + size.height * 0.07)
        ]
        let durations: [Double] = [0.62, 0.72, 0.66, 0.78, 0.70]
        let local = time - TrailerTimeline.firstSwarmEntry - Double(index) * 0.06
        guard local > 0 else {
            return (origins[index], 0, 0)
        }
        let t = TrailerTimeline.clamp(local / durations[index])
        // Same cubic overshoot used by FlyEntry in the production swarm.
        let overshoot = 0.42
        let p = 1 + (overshoot + 1) * pow(t - 1, 3)
            + overshoot * pow(t - 1, 2)
        let origin = origins[index]
        let point = CGPoint(x: origin.x + (target.x - origin.x) * CGFloat(p),
                            y: origin.y + (target.y - origin.y) * CGFloat(p))
        let heading = Double(atan2(target.y - origin.y, target.x - origin.x)) * 180 / .pi
        return (point,
                heading * (1 - t) * 0.08 + sin(time * 2.1 + Double(index)) * 5.5,
                TrailerTimeline.ramp(local, from: 0, to: 0.10))
    }

    private func flyEntryScale(index: Int) -> CGFloat {
        let generation = TrailerTimeline.strikes.filter {
            $0.correct && time >= $0.start + TrailerTimeline.strikeDuration
        }.count
        guard generation > 0,
              let last = TrailerTimeline.strikes.last(where: {
                  $0.correct && time >= $0.start + TrailerTimeline.strikeDuration
              }) else { return 1 }
        let stagger = Double(index) * 0.045
        let p = TrailerTimeline.ramp(time,
                                     from: last.start + TrailerTimeline.strikeDuration + stagger,
                                     to: last.start + TrailerTimeline.strikeDuration + 0.34 + stagger)
        return CGFloat(0.62 + p * 0.38)
    }

    private func flyEntryOpacity(index: Int) -> Double {
        guard let last = TrailerTimeline.strikes.last(where: {
            $0.correct && time >= $0.start + TrailerTimeline.strikeDuration
        }) else { return 1 }
        let stagger = Double(index) * 0.045
        return 0.22 + 0.78 * TrailerTimeline.ramp(
            time,
            from: last.start + TrailerTimeline.strikeDuration + stagger,
            to: last.start + TrailerTimeline.strikeDuration + 0.24 + stagger
        )
    }

    private var questionPrompt: String {
        if time < TrailerTimeline.firstStrikeStart + TrailerTimeline.strikeDuration {
            return "2 + 4 = ?"
        }
        if time < TrailerTimeline.streakStart { return "3 + 3 = ?" }
        let step = TrailerTimeline.strikes.filter {
            $0.start < time && $0.start >= TrailerTimeline.streakStart
        }.count
        return ["4 + 2 = ?", "1 + 5 = ?", "8 − 2 = ?", "3 × 2 = ?"][step % 4]
    }

    private func answer(for index: Int) -> String {
        let target = currentCorrectFly
        let distractors = ["4", "8", "9", "12", "5"]
        return index == target ? "6" : distractors[index]
    }

    private var currentCorrectFly: Int {
        if time < TrailerTimeline.firstStrikeStart + TrailerTimeline.strikeDuration { return 0 }
        if time < TrailerTimeline.streakStart { return 4 }
        return TrailerTimeline.strikes.last(where: {
            $0.start <= time && $0.start >= TrailerTimeline.streakStart
        })?.fly ?? 1
    }

    private var activeStrike: (strike: TrailerTimeline.Strike, local: Double)? {
        guard let strike = TrailerTimeline.strikes.first(where: {
            time >= $0.start && time < $0.start + TrailerTimeline.strikeDuration
        }) else { return nil }
        return (strike, time - strike.start)
    }

    private var activeCharacter: AnimalCharacter {
        characterWeights.max(by: { $0.opacity < $1.opacity })?.character ?? frog
    }

    private var characterWeights: [(character: AnimalCharacter, opacity: Double)] {
        let bunny = CharacterCatalog.character(id: "bunny")
        let dog = CharacterCatalog.character(id: "dog")
        let crab = CharacterCatalog.character(id: "crab")
        let start = TrailerTimeline.animalStart
        let fade = 0.495
        let hold = 1.14
        let bunnyIn = start + fade
        let dogIn = bunnyIn + hold
        let dogFull = dogIn + fade
        let crabIn = dogFull + hold
        let crabFull = crabIn + fade
        let frogIn = crabFull + hold
        if time < start { return [(frog, 1)] }
        if time < bunnyIn {
            let p = TrailerTimeline.ramp(time, from: start, to: bunnyIn)
            return [(frog, 1), (bunny, p)]
        }
        if time < dogIn { return [(bunny, 1)] }
        if time < dogFull {
            let p = TrailerTimeline.ramp(time, from: dogIn, to: dogFull)
            return [(bunny, 1), (dog, p)]
        }
        if time < crabIn { return [(dog, 1)] }
        if time < crabFull {
            let p = TrailerTimeline.ramp(time, from: crabIn, to: crabFull)
            return [(dog, 1), (crab, p)]
        }
        if time < frogIn { return [(crab, 1)] }
        if time < TrailerTimeline.frogReturn {
            let p = TrailerTimeline.ramp(time,
                                         from: frogIn,
                                         to: TrailerTimeline.frogReturn)
            return [(crab, 1), (frog, p)]
        }
        return [(frog, 1)]
    }

    private var cameraZoom: CGFloat {
        let zoomIn = TrailerTimeline.ramp(time,
                                          from: TrailerTimeline.wrongStrikeStart
                                                + TrailerTimeline.tongueRetraction,
                                          to: TrailerTimeline.reactionStart + 0.28)
        let zoomOut = TrailerTimeline.ramp(time,
                                           from: TrailerTimeline.reactionStart + 0.88,
                                           to: TrailerTimeline.animalStart)
        return CGFloat(1 + 0.38 * zoomIn * (1 - zoomOut))
    }

    private var hudExitProgress: Double {
        TrailerTimeline.ramp(time,
                             from: TrailerTimeline.completionStart,
                             to: TrailerTimeline.completionStart + 0.36)
    }

    private var cameraDrift: CGSize {
        CGSize(width: CGFloat(sin(time * 0.62)) * 1.6,
               height: CGFloat(cos(time * 0.54)) * 1.1)
    }

    // MARK: HUD, messages, interactions, ending

    private func hud(size: CGSize) -> some View {
        let character = activeCharacter
        let isPad = format.isPad
        let control: CGFloat = isPad ? 52 : 44
        let score = TrailerTimeline.strikes.last(where: {
            time >= $0.start + TrailerTimeline.strikeDuration
        })?.scoreAfter ?? 0

        return ZStack(alignment: .top) {
            HStack(spacing: isPad ? 10 : 8) {
                Circle()
                    .fill(character.deepColor)
                    .frame(width: control, height: control)
                    .overlay(Image(systemName: "pause.fill")
                        .font(.system(size: isPad ? 24 : 20, weight: .bold))
                        .foregroundStyle(.white))
                    .overlay(Circle().stroke(.white.opacity(0.92), lineWidth: 3))

                HStack(spacing: isPad ? 7 : 5) {
                    Text(verbatim: "\(score)")
                        .font(.system(size: isPad ? 30 : 23,
                                      weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    CurrencyIcon(size: isPad ? 34 : 26)
                }
                .foregroundStyle(character.deepColor)
                .padding(.horizontal, isPad ? 13 : 11)
                .frame(height: control)

                LivesView(lives: time >= TrailerTimeline.reactionStart ? 2 : 3,
                          character: character,
                          isPad: isPad,
                          glyphSize: isPad ? 30 : 24,
                          rowHeight: control)
                    .padding(.horizontal, isPad ? 12 : 10)

                Spacer()
            }
            .padding(.leading, isPad ? 28 : 16)
            .padding(.top, isPad ? 24 : 14)

            if time >= TrailerTimeline.boostStart {
                TrailerDoublePointsChip(
                    remaining: max(0, GameConfig.streakBoostDuration
                                      - (time - TrailerTimeline.boostStart)),
                    character: character,
                    isPad: isPad
                )
                .frame(maxWidth: size.width * (isPad ? 0.30 : 0.24))
                .padding(.top, isPad ? 24 : 14)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .currencyIcon(for: character)
    }

    private func promotionalText(size: CGSize) -> some View {
        let item: (text: String, opacity: Double)
        let firstSwitch = TrailerTimeline.firstStrikeStart + TrailerTimeline.strikeDuration
        if time < firstSwitch {
            item = ("Help out the hungry frog",
                    TrailerTimeline.window(time, start: 0.06,
                                           end: firstSwitch + 0.02, fade: 0.14))
        } else if time < TrailerTimeline.animalStart {
            item = ("Don't eat the wrong flies",
                    TrailerTimeline.window(time, start: firstSwitch - 0.04,
                                           end: TrailerTimeline.animalStart + 0.02,
                                           fade: 0.14))
        } else if time < TrailerTimeline.streakStart {
            item = ("Unlock new characters",
                    TrailerTimeline.window(time,
                                           start: TrailerTimeline.animalStart - 0.04,
                                           end: TrailerTimeline.streakStart + 0.02,
                                           fade: 0.14))
        } else {
            item = ("Get double points for streaks",
                    TrailerTimeline.window(time,
                                           start: TrailerTimeline.streakStart - 0.04,
                                           end: TrailerTimeline.completionStart + 0.02,
                                           fade: 0.14))
        }
        let isPad = format.isPad
        return Text(verbatim: item.text)
            .font(.system(size: isPad ? 24 : 19, weight: .heavy, design: .rounded))
            .foregroundStyle(frog.deepColor)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, isPad ? 20 : 16)
            .frame(height: isPad ? 48 : 40)
            .background(.white.opacity(0.94), in: Capsule())
            .overlay(Capsule().stroke(frog.color, lineWidth: isPad ? 4 : 3))
            .shadow(color: frog.deepColor.opacity(0.18), radius: 8, y: 4)
            .opacity(item.opacity)
            .position(x: size.width * 0.52,
                      y: isPad ? 128 : 102)
    }

    @ViewBuilder
    private func selectionRipple(size: CGSize) -> some View {
        ForEach(Array(TrailerTimeline.strikes.enumerated()), id: \.offset) { _, strike in
            let p = TrailerTimeline.clamp((time - (strike.start - 0.18)) / 0.34)
            if p > 0 && p < 1 {
                Circle()
                    .stroke(.white.opacity(1 - p), lineWidth: format.isPad ? 6 : 4)
                    .frame(width: CGFloat(30 + p * 72), height: CGFloat(30 + p * 72))
                    .shadow(color: frog.deepColor.opacity(0.42 * (1 - p)), radius: 4)
                    .position(flyPosition(index: strike.fly, at: strike.start, in: size))
            }
        }
    }

    private func iconEnding(size: CGSize) -> some View {
        let reveal = TrailerTimeline.ramp(time,
                                          from: TrailerTimeline.iconStart,
                                          to: TrailerTimeline.iconStart + 0.54)
        let settle = TrailerTimeline.ramp(time,
                                          from: TrailerTimeline.iconStart + 0.54,
                                          to: TrailerTimeline.iconStart + 1.02)
        let side = min(size.width, size.height) * (format.isPad ? 0.55 : 0.64)
        return Image("app_icon_good")
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.24), radius: 22, y: 12)
            .scaleEffect(CGFloat(0.66 + reveal * 0.42 - settle * 0.08))
            .rotationEffect(.degrees(-11 + reveal * 15 - settle * 4))
            .offset(y: CGFloat((1 - reveal) * 20))
            .opacity(reveal)
    }
}

// MARK: - Export UI and orchestration

@MainActor
final class TrailerExportProgress: ObservableObject {
    @Published var message = "Preparing native trailer render…"
    @Published var fraction = 0.0
    @Published var finished = false
    @Published var failed: String?
}

struct TrailerExportStatusView: View {
    @StateObject private var progress = TrailerExportProgress()
    @State private var started = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.92, green: 0.99, blue: 0.91),
                                    Color(red: 0.74, green: 0.95, blue: 0.70)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Image("front_1")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 180)
                Text(progress.failed ?? progress.message)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(red: 0.15, green: 0.43, blue: 0.11))
                ProgressView(value: progress.fraction)
                    .frame(width: 420)
            }
            .padding(36)
        }
        .task {
            guard !started else { return }
            started = true
            do {
                try await TrailerExporter.exportAll(progress: progress)
                progress.finished = true
                progress.message = "Trailer exports complete"
            } catch {
                progress.failed = error.localizedDescription
                TrailerExporter.writeFailure(error)
            }
        }
    }
}

enum TrailerExporter {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--export-app-store-teaser")
    }

    @MainActor
    static func exportAll(progress: TrailerExportProgress) async throws {
        let folder = try outputFolder()
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder,
                                                withIntermediateDirectories: true)

        let formats: [TrailerFormat] = [.iphone, .ipad]
        for (formatIndex, format) in formats.enumerated() {
            progress.message = "Rendering \(format.name)…"
            let silent = folder.appendingPathComponent("\(format.name)-silent.mp4")
            let output = folder.appendingPathComponent("\(format.name).mp4")
            try await renderVideo(format: format, to: silent) { share in
                progress.fraction = (Double(formatIndex) + share * 0.88) / Double(formats.count)
            }
            progress.message = "Mixing production audio into \(format.name)…"
            try await mixAudio(video: silent, output: output)
            try? FileManager.default.removeItem(at: silent)
            progress.message = "Extracting QA checkpoints for \(format.name)…"
            try extractPreviews(from: output, format: format, folder: folder)
            try await validateDecode(of: output)
            progress.fraction = Double(formatIndex + 1) / Double(formats.count)
        }

        let payload: [String: Any] = [
            "duration": TrailerTimeline.duration,
            "frameRate": TrailerTimeline.frameRate,
            "exports": formats.map { "\($0.name).mp4" }
        ]
        let data = try JSONSerialization.data(withJSONObject: payload,
                                              options: [.prettyPrinted, .sortedKeys])
        try data.write(to: folder.appendingPathComponent("export-complete.json"),
                       options: .atomic)
    }

    static func writeFailure(_ error: Error) {
        guard let folder = try? outputFolder() else { return }
        try? FileManager.default.createDirectory(at: folder,
                                                 withIntermediateDirectories: true)
        try? error.localizedDescription.write(
            to: folder.appendingPathComponent("export-failed.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func outputFolder() throws -> URL {
        let documents = try FileManager.default.url(for: .documentDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil,
                                                    create: true)
        return documents.appendingPathComponent("AppStoreTeaser", isDirectory: true)
    }

    @MainActor
    private static func renderVideo(format: TrailerFormat,
                                    to url: URL,
                                    progress: @escaping (Double) -> Void) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let width = Int(format.pixels.width)
        let height = Int(format.pixels.height)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: format.isPad ? 18_000_000 : 16_000_000,
                    AVVideoExpectedSourceFrameRateKey: TrailerTimeline.frameRate,
                    AVVideoMaxKeyFrameIntervalKey: Int(TrailerTimeline.frameRate * 2),
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferCGImageCompatibilityKey as String: true
            ]
        )
        guard writer.canAdd(input) else { throw TrailerExportError.cannotAddVideoInput }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? TrailerExportError.writerFailed
        }
        writer.startSession(atSourceTime: .zero)

        let frames = Int(TrailerTimeline.duration * Double(TrailerTimeline.frameRate))
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            let seconds = Double(frame) / Double(TrailerTimeline.frameRate)
            let view = TrailerCompositionView(time: seconds, format: format)
                .frame(width: format.points.width, height: format.points.height)
                .environment(\.displayScale, 2)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(format.points)
            renderer.scale = 2
            renderer.isOpaque = true
            guard let image = renderer.uiImage,
                  let cgImage = image.cgImage,
                  let pool = adaptor.pixelBufferPool else {
                throw TrailerExportError.frameRenderFailed(frame)
            }
            var optionalBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess,
                  let buffer = optionalBuffer else {
                throw TrailerExportError.pixelBufferFailed(frame)
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            guard let base = CVPixelBufferGetBaseAddress(buffer),
                  let context = CGContext(data: base,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                                            | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
                throw TrailerExportError.pixelBufferFailed(frame)
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            let presentation = CMTime(value: Int64(frame),
                                      timescale: TrailerTimeline.frameRate)
            guard adaptor.append(buffer, withPresentationTime: presentation) else {
                throw writer.error ?? TrailerExportError.writerFailed
            }
            if frame.isMultiple(of: 5) {
                progress(Double(frame + 1) / Double(frames))
                await Task.yield()
            }
        }
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw writer.error ?? TrailerExportError.writerFailed
        }
    }

    private struct SoundCue {
        let file: String
        let ext: String
        let time: Double
        let volume: Float
    }

    private static let soundCues: [SoundCue] = [
        SoundCue(file: "splash", ext: "caf", time: 2.13, volume: 0.24),
        SoundCue(file: "sfx_correct", ext: "caf", time: 2.41, volume: 0.14),
        SoundCue(file: "splash", ext: "caf", time: 5.33, volume: 0.24),
        SoundCue(file: "wrong_answer", ext: "caf", time: 5.62, volume: 0.10),
        SoundCue(file: "sfx_character_unlock", ext: "caf", time: 7.64, volume: 0.12),
        SoundCue(file: "sfx_correct", ext: "caf", time: 13.68, volume: 0.14),
        SoundCue(file: "sfx_correct", ext: "caf", time: 14.42, volume: 0.14),
        SoundCue(file: "sfx_correct", ext: "caf", time: 15.16, volume: 0.14),
        SoundCue(file: "sfx_double_score", ext: "caf", time: 15.20, volume: 0.15),
        SoundCue(file: "sfx_correct", ext: "caf", time: 15.90, volume: 0.14),
        SoundCue(file: "sfx_correct", ext: "caf", time: 16.64, volume: 0.14),
        SoundCue(file: "sfx_level_complete", ext: "caf", time: 16.40, volume: 0.10)
    ]

    private static func mixAudio(video: URL, output: URL) async throws {
        try? FileManager.default.removeItem(at: output)
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)
        guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video,
                                                           preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw TrailerExportError.missingVideoTrack }
        let duration = CMTime(seconds: TrailerTimeline.duration, preferredTimescale: 600)
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                       of: sourceVideo,
                                       at: .zero)

        var parameters: [AVAudioMixInputParameters] = []
        if let musicURL = Bundle.main.url(forResource: "frog_music", withExtension: "m4a") {
            let musicAsset = AVURLAsset(url: musicURL)
            if let source = try await musicAsset.loadTracks(withMediaType: .audio).first {
                let assetDuration = try await musicAsset.load(.duration)
                var cursor = CMTime.zero
                while cursor < duration {
                    guard let track = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    ) else { break }
                    let remaining = duration - cursor
                    let piece = min(assetDuration, remaining)
                    try track.insertTimeRange(CMTimeRange(start: .zero, duration: piece),
                                              of: source,
                                              at: cursor)
                    let mix = AVMutableAudioMixInputParameters(track: track)
                    mix.setVolume(0.34, at: cursor)
                    parameters.append(mix)
                    cursor = cursor + piece
                }
            }
        }

        for cue in soundCues {
            guard let url = Bundle.main.url(forResource: cue.file, withExtension: cue.ext) else {
                continue
            }
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first,
                  let track = composition.addMutableTrack(withMediaType: .audio,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            let cueDuration = try await asset.load(.duration)
            let start = CMTime(seconds: cue.time, preferredTimescale: 600)
            let usable = min(cueDuration, max(.zero, duration - start))
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: usable),
                                      of: source,
                                      at: start)
            let mix = AVMutableAudioMixInputParameters(track: track)
            mix.setVolume(cue.volume, at: start)
            parameters.append(mix)
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = parameters
        guard let session = AVAssetExportSession(asset: composition,
                                                 presetName: AVAssetExportPresetHighestQuality)
        else { throw TrailerExportError.audioExportFailed }
        session.outputURL = output
        session.outputFileType = .mp4
        session.audioMix = audioMix
        session.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else {
            throw session.error ?? TrailerExportError.audioExportFailed
        }
    }

    private static let previewTimes: [Double] = [
        0.00, 1.00, 1.90, 2.13, 2.42, 2.62, 2.90, 3.30,
        3.54, 4.20, 5.20, 5.43, 5.65, 6.50, 7.39, 7.64,
        8.40, 9.27, 10.91, 12.54, 12.79, 13.04, 13.29,
        13.68, 14.42, 15.16, 15.90, 16.38, 17.20, 17.80,
        18.00, 18.40, 19.00, 19.90
    ]

    private static func extractPreviews(from video: URL,
                                        format: TrailerFormat,
                                        folder: URL) throws {
        let directory = folder.appendingPathComponent("previews", isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for seconds in previewTimes {
            var actual = CMTime.zero
            let image = try generator.copyCGImage(
                at: CMTime(seconds: seconds, preferredTimescale: 600),
                actualTime: &actual
            )
            guard let data = UIImage(cgImage: image).pngData() else {
                throw TrailerExportError.previewFailed(seconds)
            }
            let stamp = String(format: "%05.2f", seconds).replacingOccurrences(of: ".", with: "_")
            try data.write(to: directory.appendingPathComponent(
                "\(format.name)-\(stamp)s.png"
            ), options: .atomic)
        }
    }

    private static func validateDecode(of url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard videoTracks.count == 1, audioTracks.count == 1 else {
            throw TrailerExportError.unexpectedStreams(videoTracks.count, audioTracks.count)
        }
        for track in [videoTracks[0], audioTracks[0]] {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            guard reader.canAdd(output) else { throw TrailerExportError.decodeFailed }
            reader.add(output)
            guard reader.startReading() else {
                throw reader.error ?? TrailerExportError.decodeFailed
            }
            while output.copyNextSampleBuffer() != nil {}
            guard reader.status == .completed else {
                throw reader.error ?? TrailerExportError.decodeFailed
            }
        }
    }
}

enum TrailerExportError: LocalizedError {
    case cannotAddVideoInput
    case writerFailed
    case frameRenderFailed(Int)
    case pixelBufferFailed(Int)
    case missingVideoTrack
    case audioExportFailed
    case previewFailed(Double)
    case unexpectedStreams(Int, Int)
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .cannotAddVideoInput: return "The native writer rejected the H.264 input."
        case .writerFailed: return "The native H.264 writer failed."
        case .frameRenderFailed(let frame): return "SwiftUI could not render frame \(frame)."
        case .pixelBufferFailed(let frame): return "Could not allocate frame \(frame)."
        case .missingVideoTrack: return "The silent trailer has no video track."
        case .audioExportFailed: return "The production audio mix could not be exported."
        case .previewFailed(let second): return "Could not extract the \(second)s QA frame."
        case .unexpectedStreams(let video, let audio):
            return "Expected one video and one audio stream, found \(video) video and \(audio) audio."
        case .decodeFailed: return "A final trailer stream did not decode to completion."
        }
    }
}
#endif
