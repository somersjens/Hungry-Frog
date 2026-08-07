//
//  Tutorial.swift
//  Hungry Frog
//
//  The guided first run. It teaches the five things a child has to know — read
//  the sum, catch the right fly, what a mistake costs, that five in a row pays a
//  bonus, and where the score ends up — by letting them do each one rather than
//  by describing it.
//
//  Nothing here re-implements a rule. The tutorial only decides *which* answers
//  count while a step is being taught and *what* is being said about it; the sum,
//  the score, the lives and the bonus all come out of `MemoryGame` exactly as
//  they do in a normal session, which is what makes the lesson true.
//

import SwiftUI
import Combine

// MARK: - Steps

/// The five taught beats of a run. The sixth — where the score lands — belongs
/// to the menu the player comes back to, not to the game, so it is not a case
/// here; see `TutorialCenter.pendingMenuStep`.
enum TutorialStep: Int, Equatable, CaseIterable {
    /// Read the sum, catch the fly carrying its answer.
    case findTheAnswer = 1
    /// Catch a wrong one on purpose, and see what it costs.
    case tryAWrongOne
    /// Five in a row for the bonus.
    case fiveInARow
    /// The bonus is running.
    case doublePoints
    /// Handing the game over.
    case goodLuck

    var messageKey: String { "tutorial.step\(rawValue)" }

    /// One glyph per lesson, so a step is recognisable before it is read: the
    /// sum, the mistake it costs, the run, the reward, and the send-off.
    var symbolName: String {
        switch self {
        case .findTheAnswer: return "plus.forwardslash.minus"
        case .tryAWrongOne:  return "heart.slash.fill"
        case .fiveInARow:    return "flame.fill"
        case .doublePoints:  return "sparkles"
        case .goodLuck:      return "hand.thumbsup.fill"
        }
    }
}

/// Which fly the pointer arrow is aimed at while a step runs.
enum TutorialPointer: Equatable {
    case correct
    case wrong
}

// MARK: - Director

/// The state machine behind a guided run. It holds no game state of its own: it
/// is told what happened by `GameViewModel` and answers two questions — what is
/// on screen, and which answers count right now.
@MainActor
final class TutorialDirector {
    private(set) var step: TutorialStep?
    private(set) var pointer: TutorialPointer?

    /// Raised whenever `step` or `pointer` changed, so the view model can mirror
    /// them onto its published properties in one place.
    var onChange: (() -> Void)?

    var isRunning: Bool { step != nil }

    /// How long a step's own reaction — the tick, or the droppings — is given
    /// before the next message replaces it. The first is timed to land just
    /// after the next sum stands; the second lets the burst fall.
    private static let correctHandover = 0.45
    private static let wrongHandover = 1.5
    /// How long the closing message stays up.
    private static let farewell = 3.0

    private var stepWork: DispatchWorkItem?
    /// The bonus can be renewed by another five in a row inside its own window;
    /// only the first one moves the tutorial on.
    private var hasTaughtBonus = false

    // MARK: Lifecycle

    func begin() {
        guard step == nil else { return }
        apply(step: .findTheAnswer, pointer: .correct)
    }

    /// Ends the run without finishing it — the screen is going away, or the
    /// session ended under the tutorial's feet.
    func cancel() {
        stepWork?.cancel()
        stepWork = nil
        guard step != nil || pointer != nil else { return }
        step = nil
        pointer = nil
        onChange?()
    }

    // MARK: What counts

    /// Which answers the step being taught accepts. A tap that is refused here
    /// never reaches the engine: the tongue goes out and comes back empty, so
    /// nothing is scored, nothing is lost, and the lesson stays on its rails.
    ///
    /// This is also what keeps the player alive through the streak: the only
    /// answer that counts while five in a row are being collected is the right
    /// one, so there is no mistake to pay for.
    func accepts(isCorrect: Bool) -> Bool {
        switch step {
        case .tryAWrongOne:
            return !isCorrect
        case .findTheAnswer, .fiveInARow, .doublePoints:
            return isCorrect
        case .goodLuck, .none:
            return true
        }
    }

    // MARK: What happened

    /// An answer the step was waiting for has landed. The arrow comes down on
    /// the spot, before anything else happens: the fly it was pointing at is
    /// being eaten, and leaving it up for even a moment sends it hunting for
    /// another fly carrying the same kind of answer — which is exactly what
    /// made it appear to jump to a second wrong fly after a mistake.
    func didAnswer(isCorrect: Bool) {
        let answered = step
        if pointer != nil {
            pointer = nil
            onChange?()
        }

        switch answered {
        case .findTheAnswer where isCorrect:
            schedule(after: Self.correctHandover) { [weak self] in
                self?.apply(step: .tryAWrongOne, pointer: .wrong)
            }
        case .tryAWrongOne where !isCorrect:
            schedule(after: Self.wrongHandover) { [weak self] in
                self?.apply(step: .fiveInARow, pointer: .correct)
            }
        default:
            break
        }
    }

    /// A fresh sum is standing, so the answer is pointed out again. The arrow
    /// stays on it until that answer is actually given — a hint that times out
    /// on its own is a hint that vanishes exactly while it is being read.
    ///
    /// The bonus window is deliberately not included: it points the answer out
    /// once, when it opens, and then leaves the player to it.
    func didOpenRound() {
        guard step == .fiveInARow, pointer == nil else { return }
        pointer = .correct
        onChange?()
    }

    /// Five in a row landed and the double-points window opened. The answer is
    /// pointed out one last time here, until that sum is answered.
    func didStartBonus() {
        guard !hasTaughtBonus,
              step == .fiveInARow || step == .doublePoints else { return }
        hasTaughtBonus = true
        apply(step: .doublePoints, pointer: .correct)
    }

    /// The window ran out: one last message, then the game is the player's.
    func bonusDidEnd() {
        guard step == .doublePoints else { return }
        apply(step: .goodLuck, pointer: nil)
        schedule(after: Self.farewell) { [weak self] in
            self?.cancel()
        }
    }

    // MARK: Plumbing

    private func apply(step: TutorialStep?, pointer: TutorialPointer?) {
        self.step = step
        self.pointer = pointer
        onChange?()
    }

    private func schedule(after delay: Double, work: @escaping () -> Void) {
        stepWork?.cancel()
        let item = DispatchWorkItem(block: work)
        stepWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

// MARK: - Hand-overs between screens

/// The one piece of tutorial state that outlives a screen: the welcome flow asks
/// for a level to be opened straight into a guided run, and the guided run asks
/// the menu for the closing step once it is over.
@MainActor
final class TutorialCenter: ObservableObject {
    static let shared = TutorialCenter()

    private static let completedKey = "tutorial.completed"

    /// The level the welcome flow wants opened, guided, the moment the menu
    /// appears. Nil at every other launch.
    @Published private(set) var autoStartLevel: MathLevel?
    /// True from the end of a guided run until the menu has shown its last step.
    @Published private(set) var pendingMenuStep = false

    private init() {}

    /// Whether the player has ever been through a guided run. Only used to keep
    /// the welcome flow from insisting a second time on a replayed onboarding.
    var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: Self.completedKey)
    }

    /// Called as the welcome flow hands over: the first level of whatever the
    /// player just chose is what they will be taught on.
    func requestAutoStart(topic: MathTopic) {
        autoStartLevel = MathLevel(topic: topic, index: 1)
    }

    /// Taken by the menu, once.
    func takeAutoStartLevel() -> MathLevel? {
        defer { autoStartLevel = nil }
        return autoStartLevel
    }

    /// A guided run has begun. The closing step is owed from here rather than
    /// from the end of the run: a full-screen cover calls its `onDismiss` —
    /// which is where the menu picks this up — before the screen it was
    /// covering the menu with ever disappears, so anything raised on the way
    /// out arrives one beat too late to be seen.
    func guidedRunStarted() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        pendingMenuStep = true
    }

    /// Taken by the menu when the player comes back, once.
    func takeMenuStep() -> Bool {
        defer { pendingMenuStep = false }
        return pendingMenuStep
    }
}

// MARK: - The message card

/// What a tutorial says, wherever it says it. Deliberately the same card the
/// standing sum is drawn on — white, the character's own colour around it — so a
/// tutorial message reads as part of the game rather than as an overlay on it.
struct TutorialMessageCard: View {
    let text: String
    /// The glyph for this particular lesson — see `TutorialStep.symbolName`.
    let symbolName: String
    let theme: AnimalCharacter
    var isPad: Bool = AppLayout.isPad
    /// The playing field hands over a fixed band so the swarm can steer around
    /// it; the menu lets the card size itself.
    var fixedSize: CGSize?

    var body: some View {
        HStack(alignment: .center, spacing: isPad ? 14 : 10) {
            Image(systemName: symbolName)
                .font(.system(size: isPad ? 26 : 20, weight: .bold))
                .foregroundStyle(theme.color)

            Text(verbatim: text)
                .font(.system(size: isPad ? 20 : 15.5, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.deepColor)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .minimumScaleFactor(0.62)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, isPad ? 20 : 14)
        .padding(.vertical, isPad ? 14 : 10)
        .frame(width: fixedSize?.width, height: fixedSize?.height)
        .background(.white.opacity(0.96),
                    in: RoundedRectangle(cornerRadius: isPad ? 23 : 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isPad ? 23 : 18, style: .continuous)
                .stroke(theme.color, lineWidth: isPad ? 5 : 4)
        }
        .shadow(color: theme.deepColor.opacity(0.18), radius: 10, y: 5)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - "Not now" notice

/// Shown when the tutorial is asked for in the middle of a run. It is the same
/// card the level intro is built from — white sheet, one heavy heading, one line
/// of explanation and a single filled button in the character's deep colour.
struct TutorialNoticeCard: View {
    let theme: AnimalCharacter
    let onDismiss: () -> Void

    private var isPad: Bool { AppLayout.isPad }
    private var scale: CGFloat { isPad ? 1.2 : 1 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 14 * scale) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 30 * scale, weight: .bold))
                    .foregroundStyle(theme.color)

                Text("tutorial.notice.title")
                    .font(.system(size: 22 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.deepColor)
                    .multilineTextAlignment(.center)

                Text("tutorial.notice.message")
                    .font(.system(size: 15 * scale, weight: .regular))
                    .foregroundStyle(theme.deepColor.opacity(0.84))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onDismiss) {
                    Text("common.ok")
                        .font(.system(size: 17 * scale, weight: .heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13 * scale)
                        .foregroundStyle(.white)
                        .background(theme.deepColor,
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tutorial-notice-ok")
                .padding(.top, 2 * scale)
            }
            .padding(24 * scale)
            .frame(width: isPad ? 420 : 340)
            .background(.background.opacity(0.96),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(theme.deepColor.opacity(0.14), lineWidth: 1))
            .shadow(color: theme.deepColor.opacity(0.3), radius: 18, y: 8)
        }
        .transition(.opacity)
    }
}

// MARK: - The menu's closing step

/// Dims the menu around the level that was just played, so the one card the
/// score landed on is the only thing lit. The hole is punched out of the wash
/// rather than drawn over the card, which keeps the card itself untouched — it
/// is still the live view, mid-celebration, underneath.
struct TutorialSpotlight: View {
    /// The card to leave lit, in the shared "home" space. Nil dims the lot.
    let hole: CGRect?
    var cornerRadius: CGFloat = 18
    var padding: CGFloat = 6

    var body: some View {
        // One path with an even-odd fill rather than a blend mode: a
        // `destinationOut` hole needs a compositing group, and a group is
        // clipped to its own bounds — which would leave the safe-area edges of
        // a landscape screen undimmed. Here the wash is simply drawn well past
        // every edge, and the coordinates stay the menu's own.
        GeometryReader { proxy in
            Path { path in
                let overhang: CGFloat = 240
                path.addRect(CGRect(x: -overhang, y: -overhang,
                                    width: proxy.size.width + overhang * 2,
                                    height: proxy.size.height + overhang * 2))
                if let hole {
                    path.addRoundedRect(
                        in: hole.insetBy(dx: -padding, dy: -padding),
                        cornerSize: CGSize(width: cornerRadius + padding,
                                           height: cornerRadius + padding),
                        style: .continuous
                    )
                }
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
