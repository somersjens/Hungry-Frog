//
//  HomeView.swift
//  Math Memory
//
//  Home screen: a wide landscape toolbar with the player and streak on the
//  left, the session choices on the right, and a four-column level grid below.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct LevelSelection: Identifiable {
    let level: MathLevel
    var id: String { level.id }
}

/// What the player had before the session they just finished, so the level
/// score and the header total both visibly grow from there.
private struct ScoreCelebration: Identifiable {
    let levelID: String
    let levelStart: Int
    let topicStart: Int
    let totalStart: Int
    /// True only when this session turned an unfinished board into a maxed one.
    /// That inserts the fern-and-crown reveal before its bubble flies away.
    let revealsMaximum: Bool
    let id = UUID()
    /// Stamped when the celebration actually becomes visible, not when it was
    /// built — a stale timestamp makes every time-driven view skip straight to
    /// its finished state.
    var startedAt = Date()
}

struct HomeView: View {
    var onRestartOnboarding: (() -> Void)?

    @AppStorage(GameSettings.characterKey) private var characterID = CharacterCatalog.freeCharacterID
    @AppStorage(GameSettings.playerNameKey) private var playerName = ""
    @AppStorage(GameSettings.onboardingCompleteKey) private var onboardingComplete = false
    @AppStorage(GameSettings.totalCardsKey) private var totalCards = 0
    @AppStorage(GameSettings.topicKey) private var topicRaw = MathTopic.allCases[0].rawValue
    @AppStorage(GameSettings.mixedVariantKey) private var mixedVariantRaw = MixedVariant.allCases[0].rawValue
    @AppStorage(GameSettings.practiceModeKey) private var practiceModeRaw = PracticeMode.fallback.rawValue

    @ObservedObject private var premium = PremiumStore.shared
    @ObservedObject private var progressSync = ProgressSync.shared
    @ObservedObject private var language = LanguageManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: LevelSelection?
    @State private var showPremium = false
    @State private var premiumInitialCharacterID: String?
    @State private var celebratedUnlockID: String?
    @State private var pendingUnlockIDs: [String] = []
    @State private var showGoalPicker = false
    @State private var showNameEditor = false
    @State private var nameDraft = ""
    @State private var infoPopup: InfoPopup?
    @State private var controlAnchors: [String: CGRect] = [:]
    @State private var viewportWidth: CGFloat = 0
    @State private var suppressTopicTap = false
    /// The brief return-to-menu celebration after a session earned cards.
    @State private var celebration: ScoreCelebration?
    @State private var cardGlyphAnchors: [String: CGRect] = [:]
    @State private var flights: [CardFlight] = []
    @State private var lastPlayedLevelID: String?
    @State private var lastPlayedLevelBest = 0
    @State private var lastPlayedTopic = 0
    @State private var lastPlayedTotal = 0
    /// True from opening a level until the celebration for it is in place. The
    /// session banks its cards while the cover is still up and `@AppStorage`
    /// mirrors that write at once, so without this the menu behind the closing
    /// cover would show the new totals for a frame, snap back to the old ones
    /// and only then count up.
    @State private var holdsPreSessionValues = false
    /// Stamped the moment the flying card reaches the topic counter. Both the
    /// topic total and the grand total start counting up from it, together.
    @State private var cardArrival: Date?
    @State private var highlightsHeaderCards = false
    /// The stable value shown in the summary line under the name. It only
    /// changes once the return celebration has settled, so the remaining count
    /// is replaced in a single pop instead of ticking down with the total.
    @State private var unlockPrompt: NextCharacterPrompt?
    @State private var unlockPreviewTrigger = 0

    private var character: AnimalCharacter { CharacterCatalog.current(isPremium: premium.isPremium) }
    private var topic: MathTopic { MathTopic(rawValue: topicRaw) ?? MathTopic.allCases[0] }
    private var mixedVariant: MixedVariant {
        MixedVariant(rawValue: mixedVariantRaw) ?? MixedVariant.allCases[0]
    }
    private var practiceMode: PracticeMode { PracticeMode.from(rawValue: practiceModeRaw) }
    private var isPad: Bool { AppLayout.isPad }

    private var displayName: String {
        playerName.isEmpty ? CharacterCatalog.defaultPlayerName : playerName
    }

    // MARK: - Metrics

    private var menuScale: CGFloat { isPad ? 1.4 : 1 }
    private var menuControlSpacing: CGFloat { isPad ? 14 : 10 }
    private var topicButtonDiameter: CGFloat { isPad ? 58 : 38 }
    private var levelGridSpacing: CGFloat { isPad ? 16 : 10 }
    private var levelCardHeight: CGFloat { isPad ? 124 : 88 }

    var body: some View {
        // Reading the revision redraws the personal bests when iCloud updates.
        let _ = progressSync.revision

        ZStack {
            MenuMeadowBackground(accent: character.color)

            GeometryReader { proxy in
                ScrollView {
                    let available = min(AppLayout.landscapeContentWidth,
                                        proxy.size.width - AppLayout.landscapeGutter * 2)

                    VStack(alignment: .leading, spacing: isPad ? 22 : 14) {
                        menuCard
                            .zIndex(1)
                        levelGrid
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .zIndex(0)
                    }
                    .padding(AppLayout.landscapeGutter)
                    .frame(width: available + AppLayout.landscapeGutter * 2)
                    .frame(maxWidth: .infinity)
                }
                .onAppear { viewportWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { _, width in viewportWidth = width }
                .onPreferenceChange(ControlAnchorKey.self) { controlAnchors = $0 }
                .onPreferenceChange(CardGlyphAnchorKey.self) { cardGlyphAnchors = $0 }
                .overlay(alignment: .topLeading) { infoPopoutOverlay }
                .overlay {
                    ForEach(flights) { flight in
                        CardFlightView(flight: flight)
                    }
                }
            }
        }
        .coordinateSpace(name: "home")
        .fullScreenCover(item: $selection, onDismiss: handleSessionDismissed) { item in
            GameView(request: GameSessionRequest(level: item.level,
                                                 mixedVariant: mixedVariant,
                                                 mode: practiceMode))
                .gameEnvironment()
        }
        .sheet(isPresented: $showPremium, onDismiss: {
            premiumInitialCharacterID = nil
            celebratedUnlockID = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                presentNextUnlockIfAny()
            }
        }) {
            PremiumView(initialCharacterID: premiumInitialCharacterID,
                        celebratedUnlockCharacterID: celebratedUnlockID)
                .premiumSheetPresentation()
        }
        .sheet(isPresented: $showNameEditor) {
            NameEditorSheet(theme: character, name: $nameDraft) {
                let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                playerName = trimmed
            }
            // A short sheet that rises over the menu, tinted to the character.
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
            .presentationBackground {
                LinearGradient(colors: [character.skyColor, character.tintColor],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .task {
            premium.startInitialRefresh()
            totalCards = Progress.store.totalCards
            synchronizeUnlockPrompt(animated: false)
        }
        .onChange(of: totalCards) { _, _ in
            // A returning session banks its cards before any of the celebration
            // is visible. Hold the old prompt until that flow releases it;
            // iCloud or restored progress may update it right away.
            guard celebration == nil, !holdsPreSessionValues else { return }
            synchronizeUnlockPrompt(animated: unlockPrompt != nil)
        }
        .onAppear {
            AppAudio.shared.prepare()
            AppAudio.shared.startMusic()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            AppAudio.shared.startMusic()
        }
    }

    // MARK: - Menu card

    /// Everything above the level grid lives in one card, so the boundary
    /// between "settings for the next run" and "pick a level" stays obvious.
    private var menuCard: some View {
        HStack(alignment: .top, spacing: isPad ? 24 : 14) {
            playerPanel
                .frame(width: isPad ? 500 : 350)

            Rectangle()
                .fill(character.deepColor.opacity(0.2))
                .frame(width: 1)
                .padding(.vertical, 2)

            // The session choices form one long control block beside the
            // player. In landscape this is faster to scan than a tall sidebar
            // and leaves the entire next row available to the levels.
            VStack(spacing: menuControlSpacing) {
                topicPicker
                if topic.usesSupermixGrid {
                    supermixPicker
                } else {
                    modePicker
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(isPad ? 20 : 13)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white.opacity(0.76))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 1)
                }
        }
        .shadow(color: character.deepColor.opacity(0.12), radius: 14, y: 7)
    }

    private var playerPanel: some View {
        VStack(alignment: .leading, spacing: isPad ? 10 : 7) {
            HStack(alignment: .center, spacing: isPad ? 16 : 10) {
                characterButton

                Button {
                    nameDraft = playerName
                    showNameEditor = true
                } label: {
                    Text(verbatim: displayName)
                        .font(.system(size: isPad ? 28 : 18, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                }
                .buttonStyle(.plain)
                .foregroundStyle(character.deepColor)
                .frame(maxWidth: .infinity, alignment: .leading)

                CompactStreakView(accent: character.deepColor) {
                    NotificationManager.shared.requestAuthorizationOnStreakTap {
                        showGoalPicker = true
                    }
                }
                .frame(maxWidth: .infinity)
                .popover(isPresented: $showGoalPicker, arrowEdge: .top) {
                    DailyGoalPicker(theme: character)
                        .padding()
                        .presentationCompactAdaptation(.popover)
                }
                .frame(width: isPad ? 142 : 96)
            }

            totalCounter
            topicHeader
        }
    }

    // MARK: Character

    private var characterButton: some View {
        let box: CGFloat = isPad ? 96 : 62
        return ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [character.skyColor, character.tintColor],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 2)
                }
            character.artwork
                .resizable()
                .scaledToFit()
                .padding(box * 0.08)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .frame(width: box, height: box)
        .shadow(color: character.deepColor.opacity(0.18), radius: 7, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // One exclusive recognizer decides between the two actions. A
        // successful hold can therefore never fall through into the tap that
        // opens the character collection.
        .gesture(characterGesture)
        .accessibilityIdentifier("home-character")
        .accessibilityLabel(Text(verbatim: character.localizedName))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openCharacterCollectionFromCharacter() }
    }

    private var characterGesture: some Gesture {
        LongPressGesture(minimumDuration: 2, maximumDistance: 24)
            .exclusively(before: TapGesture())
            .onEnded { result in
                switch result {
                case .first(let completed) where completed:
                    restartOnboarding()
                case .second:
                    openCharacterCollectionFromCharacter()
                default:
                    break
                }
            }
    }

    private func openCharacterCollectionFromCharacter() {
        AppAudio.shared.playMenuTap()
        openCharacterCollection()
    }

    /// Grand total and selected-category total intentionally share the exact
    /// same icon-number-label grammar and typography.
    private var totalCounter: some View {
        let total = headerCount(start: celebration?.totalStart,
                                heldStart: lastPlayedTotal,
                                current: totalCards)
        return HStack(spacing: isPad ? 7 : 5) {
            CurrencyIcon(size: isPad ? 20 : 14)
                .scaleEffect(highlightsHeaderCards ? 1.32 : 1)
                .rotationEffect(.degrees(highlightsHeaderCards ? -10 : 0))
            CountingNumber(from: total.from,
                           to: total.to,
                           startedAt: total.at,
                           duration: Self.headerCountDuration)
            Text("home.totalLabel")
        }
        .font(.system(size: isPad ? 20 : 14, weight: .bold, design: .rounded))
        .foregroundStyle(character.deepColor)
        .lineLimit(1)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: totalCards)
    }

    /// Recomputes the next animal to earn. The prompt is a stored value rather
    /// than a derived one so it can be held steady while a return celebration is
    /// still counting the total up, then swapped in one movement afterwards.
    private func synchronizeUnlockPrompt(animated: Bool) {
        let next: NextCharacterPrompt?
        if totalCards > 0,
           let milestone = CharacterUnlocks.nextMilestone(totalCards: totalCards) {
            next = NextCharacterPrompt(characterID: milestone.characterID,
                                       remaining: milestone.remaining)
        } else {
            // Before the first card, and once the last card character has been
            // earned, the line is simply the total.
            next = nil
        }

        guard next != unlockPrompt else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.28)) { unlockPrompt = next }
        } else {
            withTransaction(Transaction(animation: nil)) { unlockPrompt = next }
        }
    }

    // MARK: Topic

    private var topicHeader: some View {
        let count = headerCount(start: celebration?.topicStart,
                                heldStart: lastPlayedTopic,
                                current: topicCards)
        return HStack(spacing: isPad ? 7 : 5) {
            // The card that flies up from the level card aims here, so the
            // reward visibly joins this topic before the totals move.
            CurrencyIcon(size: isPad ? 20 : 14)
                .scaleEffect(highlightsHeaderCards ? 1.32 : 1)
                .rotationEffect(.degrees(highlightsHeaderCards ? -10 : 0))
                .reportAnchor("topicTotal")
            CountingNumber(from: count.from,
                           to: count.to,
                           startedAt: count.at,
                           duration: Self.headerCountDuration)
            Text(verbatim: L(key: topic.titleKey))
        }
        .font(.system(size: isPad ? 20 : 14, weight: .bold, design: .rounded))
        .foregroundStyle(character.deepColor)
        .lineLimit(1)
    }

    /// Cards earned across every level of the selected topic.
    private var topicCards: Int {
        topicCards(for: topic)
    }

    /// Every board counts: a level's scores on two, three and four cards — and
    /// on each Supermix combination — all contribute to its topic, so switching
    /// never appears to wipe progress off the topic total.
    private func topicCards(for topic: MathTopic) -> Int {
        LevelCatalog.levels(for: topic)
            .reduce(0) { $0 + Progress.store.bestScoreAcrossBoards(level: $1) }
    }

    /// The scoreboard the menu is currently showing for a level.
    private func board(for level: MathLevel) -> LevelBoard {
        LevelBoard(level: level, mixedVariant: mixedVariant, mode: practiceMode)
    }

    /// The score a level card shows. The level just played keeps its old score
    /// until the celebration is ready to count it up.
    private func heldBest(for level: MathLevel, board: LevelBoard) -> Int {
        if holdsPreSessionValues, level.id == lastPlayedLevelID { return lastPlayedLevelBest }
        return Progress.store.bestScore(board)
    }

    /// The six topics share the full width, matching the level cards below.
    private var topicPicker: some View {
        HStack(spacing: 0) {
            ForEach(Array(MathTopic.allCases.enumerated()), id: \.element.id) { index, option in
                topicButton(option)
                    .frame(width: topicButtonDiameter, height: topicButtonDiameter)

                if index < MathTopic.allCases.count - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func topicButton(_ option: MathTopic) -> some View {
        let isSelected = option == topic
        return Button {
            // A long press may also end as a button tap; consume that trailing
            // action instead of switching topic.
            guard !suppressTopicTap else {
                suppressTopicTap = false
                return
            }
            AppAudio.shared.playMenuTap()
            // Tapping the already-selected topic reveals its description
            // instead of re-selecting it (which would do nothing).
            if isSelected {
                showInfoPopup(header: L("info.topic.header"),
                              message: L(key: option.detailKey),
                              anchorKey: "topic.\(option.rawValue)")
            } else {
                infoPopup = nil
                topicRaw = option.rawValue
            }
        } label: {
            topicIcon(option, isSelected: isSelected)
                .frame(maxWidth: .infinity)
                .frame(height: topicButtonDiameter)
                .background(isSelected ? character.deepColor : .white.opacity(0.7), in: Circle())
                .overlay(Circle().stroke(character.deepColor.opacity(isSelected ? 0 : 0.25), lineWidth: 1))
                .reportAnchor("topic.\(option.rawValue)")
                .animation(.snappy(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("topic-\(option.rawValue)")
        .accessibilityLabel(Text(verbatim: L(key: option.titleKey)))
        // Holding the star runs the return celebration end to end, which is the
        // only practical way to check the whole chain — card count-up, flight,
        // both totals and the unlock sheet — without playing two full levels.
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 2).onEnded { _ in
                suppressTopicTap = true
                runReturnCelebrationSelfTest()
            },
            including: option == .mixed ? .all : .none
        )
    }

    private func topicIcon(_ option: MathTopic, isSelected: Bool) -> some View {
        // Bare glyphs, not the `.circle.fill` variants: the button already
        // provides the circle, so the only solid is the selected one. Per-symbol
        // point sizes even out their differing optical heights.
        let size = option.symbolPointSize * menuScale
        return Image(systemName: option.symbolName)
            .font(.system(size: size, weight: .bold))
            .frame(height: 24 * menuScale)
            .foregroundStyle(isSelected ? .white : character.deepColor)
    }

    // MARK: Practice mode

    /// Order · Random · Mixed: three equally wide buttons that decide the order
    /// and the spread of the sums, not what they are about. On Fractions and
    /// Percentages the same three buttons carry different labels, because there
    /// they change the kind of sum instead — see `MathTopic.modeOverride`.
    ///
    /// The label stays on one line and shrinks to fit, so a longer word in
    /// another language still sits three abreast without shrinking the base
    /// size of the shorter labels.
    private var modePicker: some View {
        HStack(spacing: isPad ? 12 : 8) {
            ForEach(PracticeMode.allCases) { mode in
                let isSelected = mode == practiceMode
                Button {
                    AppAudio.shared.playMenuTap()
                    // Tapping the one already chosen explains it instead of
                    // re-selecting it, which would do nothing.
                    if isSelected {
                        showInfoPopup(header: L(key: mode.infoHeaderKey(for: topic)),
                                      message: L(key: mode.infoKey(for: topic)),
                                      anchorKey: "mode.\(mode.rawValue)")
                    } else {
                        infoPopup = nil
                        practiceModeRaw = mode.rawValue
                    }
                } label: {
                    Text(verbatim: L(key: mode.titleKey(for: topic)))
                        .font(.system(size: isPad ? 20 : 14.5, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                        .frame(height: isPad ? 48 : 37)
                        .padding(.horizontal, isPad ? 8 : 2)
                        .background(isSelected ? character.deepColor : .white.opacity(0.7),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(character.deepColor.opacity(isSelected ? 0 : 0.25), lineWidth: 1)
                        )
                        .foregroundStyle(isSelected ? .white : character.deepColor)
                        .reportAnchor("mode.\(mode.rawValue)")
                        .animation(.snappy(duration: 0.2), value: isSelected)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mode-\(mode.rawValue)")
                .accessibilityLabel(Text(verbatim: L(key: mode.titleKey(for: topic))))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    /// The four Supermix combinations, shown only while Supermix is selected.
    /// Each button spells out the operations it practises.
    private var supermixPicker: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: isPad ? 12 : 8),
                            GridItem(.flexible(), spacing: isPad ? 12 : 8)],
                  spacing: isPad ? 12 : 8) {
            ForEach(MixedVariant.allCases) { variant in
                let isSelected = variant == mixedVariant
                Button {
                    AppAudio.shared.playMenuTap()
                    // Tapping the one already chosen explains it instead.
                    if isSelected {
                        showInfoPopup(header: L("info.topic.header"),
                                      message: L(key: variant.detailKey),
                                      anchorKey: "super.\(variant.rawValue)")
                    } else {
                        infoPopup = nil
                        mixedVariantRaw = variant.rawValue
                    }
                } label: {
                    supermixLabel(variant)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(isSelected ? .white : character.deepColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: isPad ? 48 : 37)
                    .background(isSelected ? character.deepColor : .white.opacity(0.62),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(character.deepColor.opacity(isSelected ? 0 : 0.28), lineWidth: 1))
                    .reportAnchor("super.\(variant.rawValue)")
                    .animation(.snappy(duration: 0.2), value: isSelected)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("supermix-\(variant.rawValue)")
                .accessibilityLabel(Text(verbatim: variant.operators.joined(separator: " ")))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    /// Every column reserves as many slots as its longest button needs — four
    /// on the left (`+ − × ÷`), five on the right (`+ − × ÷ %`) — and a shorter
    /// button centres itself inside them. That is what puts the operators the
    /// two buttons in a column share directly underneath one another, instead
    /// of letting each row pack tight against its own content.
    ///
    /// `%` reads optically heavier than the rest at the same point size, so it
    /// gets its own smaller size and a narrower slot.
    private func supermixLabel(_ variant: MixedVariant) -> some View {
        let font = Font.system(size: isPad ? 26 : 19, weight: .heavy, design: .rounded)
        let heavyFont = Font.system(size: isPad ? 21 : 15, weight: .heavy, design: .rounded)
        let slotWidth: CGFloat = isPad ? 30 : 20
        let active = variant.operators
        let totalSlots = MixedVariant.slotCount(forColumnOf: variant)
        // A shorter button sits in the middle of the reserved slots: "+ −"
        // lands in slots 2 and 3 of 4, not at the front.
        let offset = (totalSlots - active.count) / 2

        return HStack(spacing: 2) {
            ForEach(0..<totalSlots, id: \.self) { slot in
                let index = slot - offset
                let symbol = (index >= 0 && index < active.count) ? active[index] : ""
                let heavy = MixedVariant.heavyOperatorGlyphs[symbol]
                Text(verbatim: symbol)
                    .font(heavy == nil ? font : heavyFont)
                    .frame(width: slotWidth * (heavy ?? 1))
            }
        }
    }

    // MARK: - Info pop-out

    private func showInfoPopup(header: String, message: String, anchorKey: String) {
        guard let anchor = controlAnchors[anchorKey] else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            infoPopup = InfoPopup(header: header, message: message, anchor: anchor)
        }
        // Self-dismissing, so it never gets in the way of the next choice.
        let shown = infoPopup?.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
            guard infoPopup?.id == shown else { return }
            withAnimation(.easeOut(duration: 0.22)) { infoPopup = nil }
        }
    }

    @ViewBuilder
    private var infoPopoutOverlay: some View {
        if let popup = infoPopup, viewportWidth > 0 {
            let horizontalInset: CGFloat = isPad ? 26 : 16
            let maximumWidth = viewportWidth - horizontalInset * 2
            let width = InfoPopoutCard.preferredWidth(header: popup.header,
                                                      message: popup.message,
                                                      isPad: isPad,
                                                      maximum: maximumWidth)
            // Centre the card under its control, then keep it fully on screen.
            let desiredX = popup.anchor.midX - width / 2
            let clampedX = min(max(horizontalInset, desiredX),
                               max(horizontalInset, viewportWidth - horizontalInset - width))
            let caretOffset = popup.anchor.midX - (clampedX + width / 2)

            InfoPopoutCard(header: popup.header,
                           message: popup.message,
                           caretOffset: caretOffset,
                           theme: character)
                .frame(width: width)
                .offset(x: clampedX, y: popup.anchor.maxY + 4)
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
                .allowsHitTesting(false)
        }
    }

    // MARK: - Level grid

    private var levelGrid: some View {
        let levels = LevelCatalog.levels(for: topic)
        let regular = levels.filter { !$0.requiresPremium }
        let premiumLevels = levels.filter { $0.requiresPremium }
        let hasProgress = levels.contains {
            Progress.store.bestScoreAcrossBoards(level: $0) > 0
        }
        let recommendedID = hasProgress ? nil : regular.first?.id

        return VStack(alignment: .leading, spacing: 14) {
            AdaptiveLevelGrid(spacing: levelGridSpacing,
                              minimumCardWidth: isPad ? 210 : 118,
                              maximumColumns: 4,
                              cardHeight: levelCardHeight) {
                ForEach(regular) { level in
                    levelCard(level, recommendedID: recommendedID)
                }
            }

            if !premiumLevels.isEmpty {
                premiumSection(premiumLevels)
            }
        }
    }

    private func levelCard(_ level: MathLevel, recommendedID: String?) -> some View {
        let board = board(for: level)
        return LevelCardView(
            level: level,
            status: status(for: level, recommendedID: recommendedID),
            best: heldBest(for: level, board: board),
            maximum: board.maximum,
            maxCompletions: Progress.store.maxCompletionCount(board),
            pausedCards: PausedSessionStore.shared.session(board)?.cards,
            celebrationStart: celebration?.levelID == level.id
                ? celebration?.levelStart : nil,
            celebrationStartedAt: celebration?.levelID == level.id
                ? celebration?.startedAt : nil,
            cardHeight: levelCardHeight,
            theme: character
        ) {
            infoPopup = nil
            // Snapshot what this level and the total are worth *now*. This has
            // to happen on the tap: the cover's content builder re-runs while
            // the session is live, so anything captured there would be
            // overwritten with post-session values.
            rememberBeforePlaying(level)
            selection = LevelSelection(level: level)
        }
    }

    private func status(for level: MathLevel, recommendedID: String?) -> LevelCardStatus {
        if level.requiresPremium && !premium.isPremium { return .locked }
        // Completion is per board: the crown belongs to the scoreboard the
        // player is looking at, not to the level as a whole.
        let board = board(for: level)
        if Progress.store.bestScore(board) >= board.maximum { return .completed }
        if level.id == recommendedID { return .recommended }
        return .available
    }

    @ViewBuilder
    private func premiumSection(_ levels: [MathLevel]) -> some View {
        if premium.isPremium {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(character.deepColor.opacity(0.28))
                        .frame(height: 1.5)
                    HStack(spacing: 5) {
                        Text("menu.premiumLevels")
                            .font(.subheadline.weight(.bold))
                        Image(systemName: "crown.fill")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(character.deepColor)
                    .fixedSize()
                    Rectangle()
                        .fill(character.deepColor.opacity(0.28))
                        .frame(height: 1.5)
                }

                AdaptiveLevelGrid(spacing: levelGridSpacing,
                                  minimumCardWidth: isPad ? 210 : 118,
                                  maximumColumns: 4,
                                  cardHeight: levelCardHeight) {
                    ForEach(levels) { level in
                        levelCard(level, recommendedID: nil)
                    }
                }
            }
        } else {
            Button {
                AppAudio.shared.playMenuTap()
                openCharacterCollection()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: isPad ? 24 : 17, weight: .bold))
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("menu.moreLevels")
                            .font(.system(size: isPad ? 20 : 15, weight: .bold))
                            .foregroundStyle(.white)
                        Text("menu.unlockWithPremium")
                            .font(.system(size: isPad ? 16 : 12, weight: .regular))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.system(size: isPad ? 20 : 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.trailing, isPad ? 22 : 11)
                }
                .padding(isPad ? 20 : 14)
                .background(
                    LinearGradient(colors: [character.color, character.deepColor],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("premium-levels")
        }
    }

    // MARK: - Actions

    /// Records what the level and the running total were worth before play, so
    /// the return can count up from there. The session banks its cards while
    /// the cover is still up and `@AppStorage` mirrors that write immediately,
    /// so reading these on dismissal would only ever see the new values.
    private func rememberBeforePlaying(_ level: MathLevel) {
        lastPlayedLevelID = level.id
        lastPlayedLevelBest = Progress.store.bestScore(board(for: level))
        lastPlayedTopic = topicCards(for: level.topic)
        lastPlayedTotal = Progress.store.totalCards
        holdsPreSessionValues = true
    }

    private func openCharacterCollection(initialCharacterID: String? = nil) {
        premiumInitialCharacterID = initialCharacterID
        showPremium = true
    }

    private func restartOnboarding() {
        AppAudio.shared.playMenuTap()
        if let onRestartOnboarding {
            onRestartOnboarding()
        } else {
            withAnimation(.easeInOut(duration: 0.35)) {
                onboardingComplete = false
            }
        }
    }

    // MARK: Return celebration

    /// How long the two header counters take to reach their new value.
    private static let headerCountDuration = 0.95
    /// The moment the level card's own score has finished counting up, which is
    /// when the reward leaves the card.
    private static var cardSettleDelay: Double {
        LevelCardView.scoreCountDelay + LevelCardView.scoreCountDuration + 0.1
    }
    /// Gives the springing max card, ferns and crown a clear beat on screen
    /// before the reward bubble starts its flight to the topic total.
    private static let maximumRevealPause = 0.9
    private static let flightDuration = 0.62

    /// The `(from, to, startedAt)` a header counter should use. It holds the
    /// pre-session value while the reward is still on the level card and in
    /// flight, then counts up the moment the card lands. Without a celebration
    /// it simply shows the live value.
    private func headerCount(start: Int?,
                             heldStart: Int,
                             current: Int) -> (from: Int, to: Int, at: Date?) {
        if let start, celebration != nil {
            // Both counters read this, so they always move as one.
            if let cardArrival { return (start, current, cardArrival) }
            return (start, start, nil)
        }
        // The session is still on screen, or its cover is closing: keep showing
        // what the player left with until the celebration takes over.
        if holdsPreSessionValues { return (heldStart, heldStart, nil) }
        return (current, current, nil)
    }

    /// Back from a session: bank the totals and celebrate anything earned. The
    /// before-values are captured first, so the level score and the headers
    /// count up from what the player had rather than snapping to the new value.
    private func handleSessionDismissed() {
        let levelID = lastPlayedLevelID
        let levelStart = lastPlayedLevelBest
        let topicStart = lastPlayedTopic
        let totalStart = lastPlayedTotal

        totalCards = Progress.store.totalCards
        let levelNow = levelID
            .flatMap { LevelCatalog.level(id: $0) }
            .map { Progress.store.bestScore(board(for: $0)) } ?? 0

        if let levelID, levelNow > levelStart || totalCards > totalStart {
            let level = LevelCatalog.level(id: levelID)
            let revealsMaximum = level.map {
                levelStart < board(for: $0).maximum && levelNow >= board(for: $0).maximum
            } ?? false
            let celebration = ScoreCelebration(levelID: levelID,
                                               levelStart: levelStart,
                                               topicStart: topicStart,
                                               totalStart: totalStart,
                                               revealsMaximum: revealsMaximum)
            self.celebration = celebration
            cardArrival = nil
            // The celebration now owns these values, and it starts from the
            // very same ones the hold was showing.
            holdsPreSessionValues = false
            AppAudio.shared.playCardCount()
            // The level card counts up on its own first; the reward only leaves
            // it once that has landed.
            let departureDelay = Self.cardSettleDelay
                + (celebration.revealsMaximum ? Self.maximumRevealPause : 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + departureDelay) {
                guard self.celebration?.id == celebration.id else { return }
                self.launchCardFlight(for: celebration)
            }
            // Clear it once every part of the celebration has played out.
            let lifetime = departureDelay + Self.flightDuration
                + Self.headerCountDuration + 0.12
            DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) {
                guard self.celebration?.id == celebration.id else { return }
                self.celebration = nil
                self.cardArrival = nil
                // Card count, flight and totals are all finished now: preview
                // the new remaining count once, straight away.
                self.unlockPreviewTrigger &+= 1
                self.synchronizeUnlockPrompt(animated: true)
            }
            pendingUnlockIDs = CharacterUnlockStore.unannouncedUnlocks(at: totalCards).map(\.id)
            // Let the whole celebration play before a character sheet takes over.
            DispatchQueue.main.asyncAfter(deadline: .now() + lifetime + 0.25) {
                presentNextUnlockIfAny()
            }
        } else {
            holdsPreSessionValues = false
            synchronizeUnlockPrompt(animated: unlockPrompt != nil)
            pendingUnlockIDs = CharacterUnlockStore.unannouncedUnlocks(at: totalCards).map(\.id)
            presentNextUnlockIfAny()
        }
    }

    /// Sends one card arcing from the level card's glyph up to the topic
    /// counter, which is what makes the score feel like it was carried there.
    /// If either endpoint is unknown the reward simply lands straight away.
    private func launchCardFlight(for celebration: ScoreCelebration) {
        guard let source = cardGlyphAnchors[celebration.levelID],
              let destination = controlAnchors["topicTotal"] else {
            landHeaderCards(for: celebration)
            return
        }
        let flight = CardFlight(celebrationID: celebration.id,
                                source: source,
                                destination: destination,
                                sourcePointSize: isPad ? 13 : 9,
                                destinationPointSize: isPad ? 22 : 15,
                                arcHeight: isPad ? 64 : 44,
                                color: celebration.revealsMaximum
                                    ? LevelCardView.completedPalette(for: character).hero
                                    : character.color,
                                startedAt: Date(),
                                duration: Self.flightDuration)
        flights.append(flight)
        AppAudio.shared.playCardFlight()
        DispatchQueue.main.asyncAfter(deadline: .now() + flight.duration) {
            flights.removeAll { $0.id == flight.id }
            landHeaderCards(for: celebration)
        }
    }

    /// The reward merges into the header: the topic total and the grand total
    /// start counting at the same instant, and the topic glyph gives a small
    /// welcoming pulse.
    private func landHeaderCards(for celebration: ScoreCelebration) {
        guard self.celebration?.id == celebration.id else { return }
        cardArrival = Date()
        AppAudio.shared.playCardTotal()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.56)) {
            highlightsHeaderCards = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.66) {
            withAnimation(.easeOut(duration: 0.24)) {
                highlightsHeaderCards = false
            }
        }
    }

    // MARK: Self-test

    /// Drives the complete return sequence twice from the menu, then hands over
    /// to a real character unlock. Everything runs through the same code a
    /// finished session uses, so what it shows is what a player would see.
    ///
    /// This writes real progress: both levels are pushed to their maximum and
    /// the total is topped up to the next milestone.
    private func runReturnCelebrationSelfTest() {
        let levels = LevelCatalog.levels(for: topic).filter { !$0.requiresPremium }
        guard levels.count >= 2 else { return }

        let full = board(for: levels[0]).maximum
        // One celebration from start to the moment the unlock sheet may appear.
        let step = Self.cardSettleDelay + Self.maximumRevealPause + Self.flightDuration
            + Self.headerCountDuration + 0.6

        awardForSelfTest(levels[0], cards: full)
        DispatchQueue.main.asyncAfter(deadline: .now() + step) {
            // Top the running total up to the next milestone, so the second
            // return ends on a genuine unlock rather than a simulated one.
            if let milestone = CharacterUnlocks.nextMilestone(totalCards: Progress.store.totalCards) {
                var announced = Progress.store.announcedUnlocks
                announced.remove(milestone.characterID)
                Progress.store.announcedUnlocks = announced
            }
            awardForSelfTest(levels[1], cards: full, reachNextMilestone: true)
        }
    }

    /// Banks a score exactly the way a finished session does, then runs the
    /// ordinary return handler so the whole celebration plays.
    private func awardForSelfTest(_ level: MathLevel,
                                  cards: Int,
                                  reachNextMilestone: Bool = false) {
        rememberBeforePlaying(level)
        let store = Progress.store
        let board = board(for: level)
        let gained = max(0, min(cards, board.maximum) - store.bestScore(board))
        _ = store.recordScore(cards, board: board)
        store.recordMaxCompletion(board)
        _ = store.addCards(gained)
        if reachNextMilestone,
           let milestone = CharacterUnlocks.nextMilestone(totalCards: store.totalCards) {
            _ = store.addCards(milestone.remaining)
        }
        handleSessionDismissed()
    }

    private func presentNextUnlockIfAny() {
        guard !showPremium, !pendingUnlockIDs.isEmpty else { return }
        let next = pendingUnlockIDs.removeFirst()
        CharacterUnlockStore.markAnnounced(next)
        celebratedUnlockID = next
        premiumInitialCharacterID = next
        showPremium = true
    }
}
