//
//  PremiumView.swift
//  Elephant Challenge: Math Memory
//
//  Character collection and one-time Premium purchase sheet. The first half of
//  the catalog is earned by collecting cards; the second half is Premium-only,
//  which also opens levels 13–99 of every topic.
//

import SwiftUI
import StoreKit
#if canImport(UIKit)
import UIKit
#endif

/// Every size on the sheet is derived from the height the device actually
/// offers, so the hero, the offer and the whole cast fit on one screen instead
/// of pushing the buy button below the fold. The base numbers are tuned for an
/// iPhone in landscape; `unit` stretches them for the taller iPads.
private struct PremiumMetrics {
    let unit: CGFloat

    init(height: CGFloat, isPad: Bool) {
        let designHeight: CGFloat = isPad ? 515 : 455
        let raw = height / designHeight
        unit = min(isPad ? 1.75 : 1.2, max(0.72, raw))
    }

    private func s(_ value: CGFloat) -> CGFloat { value * unit }

    // Frame
    var cardPadding: CGFloat { s(13) }
    var stackSpacing: CGFloat { s(11) }
    var columnSpacing: CGFloat { s(14) }

    // Hero
    var heroSize: CGFloat { s(170) }
    var nameSize: CGFloat { s(27) }
    var badgeSize: CGFloat { s(14) }

    // Offer
    var panelPadding: CGFloat { s(14) }
    var panelSpacing: CGFloat { s(9) }
    var headerSize: CGFloat { s(18) }
    var featureSpacing: CGFloat { s(10) }
    var featureTitle: CGFloat { s(15) }
    var featureSubtitle: CGFloat { s(12.5) }
    var buttonFont: CGFloat { s(17) }
    var buttonPadding: CGFloat { s(11) }
    var footnote: CGFloat { s(12) }

    // Character strip
    var stripPadding: CGFloat { s(8) }
    var tileSpacing: CGFloat { s(5) }
    var tileArt: CGFloat { s(42) }
    var tilePadding: CGFloat { s(6) }
    var tileBadge: CGFloat { s(10.5) }
}

struct PremiumView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var premium = PremiumStore.shared
    @ObservedObject private var language = LanguageManager.shared
    @AppStorage(GameSettings.characterKey) private var characterID = CharacterCatalog.freeCharacterID
    @AppStorage(GameSettings.totalCardsKey) private var totalCards = 0

    /// Set when the sheet was opened to celebrate a character the player just
    /// earned; the celebration plays once on appear.
    let celebratedUnlockCharacterID: String?

    @State private var previewCharacterID: String
    @State private var showsParentApproval = false
    @State private var showsUnlockCelebration = false
    @State private var unlockGlow = false
    @State private var unlockCharacterScale: CGFloat = 0.18
    @State private var unlockCharacterRotation = -18.0
    @State private var unlockBurstRotation = -14.0
    @State private var unlockTitleScale: CGFloat = 0.72
    @State private var unlockPulse = false
    @State private var unlockCharacterFloating = false
    @State private var activeUnlockCharacterID: String?
    @State private var pendingUnlockCharacterIDs: [String] = []
    @State private var unlockCelebrationGeneration = 0

    init(initialCharacterID: String? = nil,
         celebratedUnlockCharacterID: String? = nil) {
        self.celebratedUnlockCharacterID = celebratedUnlockCharacterID
        _previewCharacterID = State(initialValue: initialCharacterID ?? GameSettings.characterID)
    }

    private var character: AnimalCharacter { CharacterCatalog.character(id: previewCharacterID) }
    private var unlockedCharacter: AnimalCharacter? {
        activeUnlockCharacterID.map { CharacterCatalog.character(id: $0) }
    }
    private var isPad: Bool { AppLayout.isPad }
    private var scale: CGFloat { isPad ? 1.4 : 1 }

    var body: some View {
        let _ = totalCards
        ZStack(alignment: .top) {
            LinearGradient(colors: [character.skyColor, character.tintColor],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            GeometryReader { proxy in
                let available = min(AppLayout.landscapeContentWidth,
                                    proxy.size.width - AppLayout.landscapeGutter * 2)
                // Side-by-side only when there is genuinely room for two
                // columns; portrait stacks the hero above the offer.
                let isSplit = available >= 620
                let metrics = PremiumMetrics(height: proxy.size.height, isPad: isPad)

                ScrollView {
                    VStack(spacing: metrics.stackSpacing) {
                        if isSplit {
                            HStack(alignment: .top, spacing: metrics.columnSpacing) {
                                heroPanel(metrics)
                                    .frame(width: heroWidth(available: available,
                                                            metrics: metrics))
                                offerPanel(metrics)
                                    .frame(maxWidth: .infinity)
                                    .frame(maxHeight: .infinity)
                            }
                        } else {
                            heroPanel(metrics)
                            offerPanel(metrics)
                        }

                        characterStrip(metrics,
                                       columns: isSplit ? CharacterCatalog.all.count : 5)
                    }
                    .padding(metrics.cardPadding)
                    .background(.white.opacity(0.52),
                                in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: character.deepColor.opacity(0.1), radius: 16, y: 7)
                    .padding(AppLayout.landscapeGutter)
                    .frame(width: available + AppLayout.landscapeGutter * 2)
                    .frame(maxWidth: .infinity)
                    // Centre the card when it fits, scroll only when it cannot.
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.visible)
            }

            if showsUnlockCelebration, let unlockedCharacter {
                unlockCelebration(animal: unlockedCharacter)
                    .transition(.opacity)
                    .zIndex(10)
            } else if activeUnlockCharacterID != nil {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: previewCharacterID)
        .animation(.spring(response: 0.42, dampingFraction: 0.7), value: premium.isPremium)
        .onAppear {
            if let celebratedUnlockCharacterID {
                previewCharacterID = celebratedUnlockCharacterID
                playUnlockCelebration(characterID: celebratedUnlockCharacterID)
            }
        }
        .task { await premium.refresh() }
        .sheet(isPresented: $showsParentApproval) {
            ParentApprovalGate(
                accent: character.color,
                deepColor: character.deepColor,
                onApproved: {
                    showsParentApproval = false
                    startPurchase()
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    /// The hero column ends exactly where the first Premium-only animal starts
    /// in the strip below, so the offer block visually claims that half of the
    /// cast. Derived from the same tile maths the strip uses.
    private func heroWidth(available: CGFloat, metrics: PremiumMetrics) -> CGFloat {
        let contentWidth = available - metrics.cardPadding * 2
        let columns = CGFloat(CharacterCatalog.all.count)
        let tileWidth = (contentWidth
                         - metrics.stripPadding * 2
                         - metrics.tileSpacing * (columns - 1)) / columns
        let earnable = CGFloat(CharacterCatalog.cardCharacters.count)
        let width = metrics.stripPadding
            + earnable * (tileWidth + metrics.tileSpacing)
            - metrics.columnSpacing
        // Never let an unusual catalog split starve either column.
        return min(max(width, contentWidth * 0.3), contentWidth * 0.6)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 17 * scale, weight: .bold))
                .foregroundStyle(character.deepColor)
                .frame(width: 38 * scale, height: 38 * scale)
                .background(.white.opacity(0.7), in: Circle())
                .shadow(color: character.deepColor.opacity(0.15), radius: 6, y: 3)
        }
    }

    /// Left half: the character the player is previewing, shown as large as the
    /// panel allows, with the close button tucked into its top corner.
    private func heroPanel(_ metrics: PremiumMetrics) -> some View {
        VStack(spacing: metrics.stackSpacing * 0.5) {
            HStack(alignment: .center) {
                if activeUnlockCharacterID == nil {
                    closeButton
                    Spacer()
                    LanguagePicker(
                        tint: character.deepColor.opacity(0.7),
                        scale: isPad ? 1.12 : 0.8
                    )
                } else {
                    Spacer()
                }
            }

            Spacer(minLength: 0)

            let heroSize = metrics.heroSize
            ZStack {
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
                    .id(previewCharacterID)
                    .transition(.scale.combined(with: .opacity))
            }
            .frame(maxWidth: .infinity)

            Text(character.localizedName)
                .font(.system(size: metrics.nameSize, weight: .heavy, design: .rounded))
                .foregroundStyle(character.deepColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            availabilityBadge(for: character, metrics: metrics)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.cardPadding * 0.5)
        .padding(.vertical, metrics.cardPadding * 0.4)
    }

    /// Right half: what Premium gives you, and the button that buys it. The
    /// language picker rides in the header row so it sits in the far corner of
    /// the sheet, opposite the close button.
    private func offerPanel(_ metrics: PremiumMetrics) -> some View {
        VStack(alignment: .center, spacing: metrics.panelSpacing) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: metrics.headerSize * 0.9, weight: .bold))
                Text(premium.isPremium ? "premium.youHavePremium" : "premium.advantages")
                    .font(.system(size: metrics.headerSize, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(character.deepColor)
            .frame(maxWidth: .infinity)

            // Two spacers keep the leftover height split above and below the
            // list instead of piling it all up over the buy button.
            Spacer(minLength: 0)

            featureList(metrics)

            Spacer(minLength: 0)

            purchaseSection(metrics)
        }
        .padding(metrics.panelPadding)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.42),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private func availabilityBadge(for animal: AnimalCharacter,
                                   metrics: PremiumMetrics) -> some View {
        if animal.id == CharacterCatalog.freeCharacterID {
            badge(text: L(key: "premium.availableFromStart"), icon: nil, metrics: metrics)
        } else if let cards = CharacterUnlockStore.requirement(for: animal.id) {
            if totalCards >= cards {
                badge(text: localizedInteger("premium.earnedCards %lld", cards),
                      icon: "checkmark.circle.fill", metrics: metrics)
            } else if premium.isPremium {
                badge(text: L(key: "premium.unlockedWithPremium"),
                      icon: "crown.fill", metrics: metrics)
            } else {
                badge(text: localizedInteger("premium.availableAt %lld", cards),
                      icon: Currency.icon, metrics: metrics)
            }
        } else {
            badge(
                text: L(key: premium.isPremium ? "premium.unlockedWithPremium" : "premium.exclusiveBadge"),
                icon: "crown.fill", metrics: metrics
            )
        }
    }

    private func badge(text: String, icon: String?, metrics: PremiumMetrics) -> some View {
        HStack(spacing: 6) {
            if let icon {
                if icon == Currency.icon {
                    CurrencyIcon(size: metrics.badgeSize)
                } else {
                    Image(systemName: icon)
                }
            }
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .font(.system(size: metrics.badgeSize, weight: .bold, design: .rounded))
        .foregroundStyle(character.deepColor)
        .padding(.horizontal, metrics.badgeSize)
        .padding(.vertical, metrics.badgeSize * 0.5)
        .background(.white.opacity(0.58), in: Capsule())
        .overlay(Capsule().stroke(character.color.opacity(0.38), lineWidth: 1))
    }

    private func featureList(_ metrics: PremiumMetrics) -> some View {
        VStack(alignment: .center, spacing: metrics.featureSpacing) {
            featureRow(title: L("premium.feature.levels.title"),
                       subtitle: L("premium.feature.levels.subtitle"),
                       metrics: metrics)
            featureRow(title: L("premium.feature.animals.title"),
                       subtitle: L("premium.feature.animals.subtitle"),
                       metrics: metrics)
            featureRow(title: L("premium.feature.noAds.title"),
                       subtitle: L("premium.feature.noAds.subtitle"),
                       metrics: metrics)
        }
        .frame(maxWidth: .infinity)
    }

    /// The whole cast in one row along the bottom, each animal captioned with
    /// what it costs: free, a fly total, or Premium.
    private func characterStrip(_ metrics: PremiumMetrics, columns: Int) -> some View {
        let animals = CharacterCatalog.all
        let rows = stride(from: 0, to: animals.count, by: columns).map { start in
            Array(animals[start..<min(start + columns, animals.count)])
        }
        return VStack(spacing: metrics.tileSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: metrics.tileSpacing) {
                    ForEach(row) { animal in
                        characterTile(for: animal, metrics: metrics)
                    }
                    // Keep a short final row aligned with the one above it.
                    if row.count < columns {
                        ForEach(0..<(columns - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(metrics.stripPadding)
        .background(.white.opacity(0.34),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func characterTile(for animal: AnimalCharacter,
                               metrics: PremiumMetrics) -> some View {
        let isSelected = previewCharacterID == animal.id
        let isAccessible = canUse(animal)
        let artSide = metrics.tileArt
        return Button {
            AppAudio.shared.playMenuTap()
            previewCharacterID = animal.id
            if isAccessible { characterID = animal.id }
        } label: {
            VStack(spacing: metrics.tileSpacing) {
                animal.artwork
                    .resizable()
                    .scaledToFit()
                    .frame(width: artSide, height: artSide)
                    .frame(height: artSide * 1.1)
                    .opacity(isAccessible ? 1 : 0.9)

                characterTileBadge(for: animal, metrics: metrics)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, metrics.tilePadding * 0.7)
            .padding(.vertical, metrics.tilePadding)
            .background(isSelected ? character.color.opacity(0.20) : .white.opacity(0.42),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? character.color : .clear,
                            lineWidth: isSelected ? 2 : 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("character-cell")
        .accessibilityLabel(animal.localizedName)
        .accessibilityValue(isAccessible ? "unlocked" : "locked")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The caption under an animal: its requirement, ticked once it is earned.
    /// The caption under an animal. Earned animals drop their price for a solid
    /// tick; the starter keeps its "Start" label only until the player has
    /// earned a second animal, so the row never mixes the two ideas.
    @ViewBuilder
    private func characterTileBadge(for animal: AnimalCharacter,
                                    metrics: PremiumMetrics) -> some View {
        let isStarter = animal.id == CharacterCatalog.freeCharacterID
        let showsTick = canUse(animal) && (!isStarter || hasEarnedBeyondStarter)

        if showsTick {
            Image(systemName: "checkmark")
                .font(.system(size: metrics.tileBadge * 0.72, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: metrics.tileBadge * 1.25,
                       height: metrics.tileBadge * 1.25)
                .background(character.color, in: Circle())
                .characterTileBadgeStyle(character: character,
                                         isUnlocked: true,
                                         size: metrics.tileBadge)
        } else if isStarter {
            Text(verbatim: L(key: "premium.start"))
                .characterTileBadgeStyle(character: character,
                                         isUnlocked: true,
                                         size: metrics.tileBadge)
        } else if let cards = CharacterUnlockStore.requirement(for: animal.id) {
            Text(verbatim: "\(cards)")
                .characterTileBadgeStyle(character: character,
                                         isUnlocked: false,
                                         size: metrics.tileBadge)
        } else {
            Image(systemName: "crown.fill")
                .characterTileBadgeStyle(character: character,
                                         isUnlocked: false,
                                         size: metrics.tileBadge)
        }
    }

    /// True once any animal beyond the starter is available.
    private var hasEarnedBeyondStarter: Bool {
        CharacterCatalog.all.contains {
            $0.id != CharacterCatalog.freeCharacterID && canUse($0)
        }
    }

    private func canUse(_ animal: AnimalCharacter) -> Bool {
        CharacterUnlockStore.canUse(characterID: animal.id, isPremium: premium.isPremium)
    }

    @ViewBuilder
    private func purchaseSection(_ metrics: PremiumMetrics) -> some View {
        if premium.isPremium {
            Button { dismiss() } label: {
                Text("common.done")
                    .font(.system(size: metrics.buttonFont, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, metrics.buttonPadding)
                    .background(character.color, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        } else {
            VStack(spacing: metrics.panelSpacing * 0.55) {
                Button { showsParentApproval = true } label: {
                    HStack(spacing: 10) {
                        if premium.isPurchasing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "crown.fill")
                                .font(.system(size: metrics.buttonFont, weight: .bold))
                            Text(purchaseButtonTitle)
                                .font(.system(size: metrics.buttonFont, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, metrics.buttonPadding)
                    .background(
                        LinearGradient(colors: [character.color, character.deepColor],
                                       startPoint: .top, endPoint: .bottom),
                        in: Capsule()
                    )
                    .foregroundStyle(.white)
                    .shadow(color: character.deepColor.opacity(0.3), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
                .disabled(premium.isPurchasing)

                Text("premium.oneTime")
                    .font(.system(size: metrics.footnote))
                    .foregroundStyle(character.deepColor.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                Button("premium.restore") {
                    Task { await premium.restorePurchases() }
                }
                .font(.system(size: metrics.footnote * 0.92))
                .foregroundStyle(character.deepColor.opacity(0.7))
                .frame(maxWidth: .infinity)

                if let error = premium.lastError {
                    Text(error)
                        .font(.system(size: metrics.footnote * 0.92))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var purchaseButtonTitle: String {
        if let price = premium.product?.displayPrice {
            return L("premium.unlockWithPrice \(price)")
        }
        return L("premium.unlock")
    }

    private func startPurchase() {
        let lockedCharacterIDs = CharacterCatalog.all
            .filter {
                !CharacterUnlockStore.canUse(characterID: $0.id, isPremium: false)
            }
            .map(\.id)

        Task {
            await premium.purchase()
            guard premium.isPremium else { return }

            if let firstCharacterID = lockedCharacterIDs.first {
                pendingUnlockCharacterIDs = Array(lockedCharacterIDs.dropFirst())
                playUnlockCelebration(characterID: firstCharacterID)
            } else {
                characterID = previewCharacterID
            }
        }
    }

    private func featureRow(title: String, subtitle: String,
                            metrics: PremiumMetrics) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(title)
                .font(.system(size: metrics.featureTitle, weight: .bold))
                .foregroundStyle(character.deepColor)
            Text(subtitle)
                .font(.system(size: metrics.featureSubtitle))
                .foregroundStyle(character.deepColor.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private func unlockCelebration(animal: AnimalCharacter) -> some View {
        GeometryReader { proxy in
            let horizontalMargin: CGFloat = isPad ? 80 : 32
            let maximumWidth: CGFloat = isPad ? 500 : 340
            let cardWidth = min(maximumWidth, max(280, proxy.size.width - horizontalMargin))
            let stageSize = cardWidth
            let particleRadius = stageSize * 0.39

            ZStack {
                Color.black.opacity(0.28)

                VStack(spacing: 0) {
                    ZStack {
                        Rectangle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        .white.opacity(unlockPulse ? 0.46 : 0.32),
                                        animal.tintColor.opacity(unlockPulse ? 0.42 : 0.28),
                                        animal.color.opacity(unlockPulse ? 0.12 : 0.07),
                                        .clear
                                    ],
                                    center: .center,
                                    startRadius: 8,
                                    endRadius: stageSize * 0.52
                                )
                            )

                        ZStack {
                            ForEach(0..<16, id: \.self) { index in
                                let angle = Double(index) * (.pi * 2 / 16)
                                let radiusVariation: CGFloat = index.isMultiple(of: 2) ? 0.92 : 1.04
                                Group {
                                    if index.isMultiple(of: 4) {
                                        CurrencyIcon(size: CGFloat(11 + (index % 3) * 3) * scale)
                                    } else {
                                        Image(systemName: "sparkle")
                                            .font(.system(
                                                size: CGFloat(11 + (index % 3) * 3) * scale,
                                                weight: .bold
                                            ))
                                    }
                                }
                                    .foregroundStyle(
                                        index.isMultiple(of: 4) ? animal.deepColor : animal.color
                                    )
                                    // Cancel the ring's rotation on each glyph so
                                    // the cards and sparkles keep orbiting but stay
                                    // upright rather than tumbling.
                                    .rotationEffect(.degrees(-unlockBurstRotation))
                                    .offset(
                                        x: CGFloat(cos(angle)) * particleRadius * radiusVariation,
                                        y: CGFloat(sin(angle)) * particleRadius * radiusVariation
                                    )
                                    .scaleEffect(unlockGlow ? (unlockPulse ? 1.08 : 0.78) : 0.12)
                                    .opacity(unlockGlow ? (unlockPulse ? 1 : 0.68) : 0)
                            }
                        }
                        .rotationEffect(.degrees(unlockBurstRotation))

                        animal.artwork
                            .resizable()
                            .scaledToFit()
                            .frame(width: stageSize * 0.72, height: stageSize * 0.72)
                            .scaleEffect(unlockCharacterScale)
                            .rotationEffect(.degrees(unlockCharacterRotation))
                            .offset(y: unlockCharacterFloating ? -7 * scale : 7 * scale)
                            .shadow(color: animal.deepColor.opacity(0.35), radius: 18, y: 9)
                    }
                    .frame(width: stageSize, height: stageSize)
                    .clipped()

                    Text(verbatim: L(key: "premium.characterUnlocked"))
                        .font(.system(size: 19 * scale, weight: .black, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(animal.deepColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                        .scaleEffect(unlockTitleScale)
                        .opacity(unlockGlow ? 1 : 0)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 22 * scale)
                        .padding(.vertical, 24 * scale)
                }
                .frame(width: cardWidth)
                .background(animal.skyColor)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(animal.color.opacity(0.6), lineWidth: 4)
                )
                .shadow(color: animal.deepColor.opacity(0.28), radius: 28, y: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { finishUnlockCelebration() }
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(localizedString("premium.characterUnlocked %@", animal.localizedName))
    }

    private func playUnlockCelebration(characterID unlockedCharacterID: String) {
        unlockCelebrationGeneration += 1
        let generation = unlockCelebrationGeneration

        activeUnlockCharacterID = unlockedCharacterID
        previewCharacterID = unlockedCharacterID
        unlockGlow = false
        unlockCharacterScale = 0.18
        unlockCharacterRotation = -18
        unlockBurstRotation = -14
        unlockTitleScale = 0.72
        unlockPulse = false
        unlockCharacterFloating = false

        withAnimation(.easeIn(duration: 0.18)) { showsUnlockCelebration = true }
        // Keep audio owned by the celebration itself. This covers characters
        // earned with cards as well as every character unlocked by Premium,
        // without duplicate or prematurely timed playback.
        AppAudio.shared.playCharacterUnlock()
#if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
        withAnimation(.spring(response: 0.72, dampingFraction: 0.55)) {
            unlockGlow = true
            unlockCharacterScale = 1
            unlockCharacterRotation = 0
            unlockTitleScale = 1
        }
        withAnimation(.easeOut(duration: 0.8)) {
            unlockBurstRotation = 18
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            guard generation == unlockCelebrationGeneration,
                  showsUnlockCelebration else { return }
#if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.85)
#endif
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            guard generation == unlockCelebrationGeneration,
                  showsUnlockCelebration else { return }
#if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
#endif
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard generation == unlockCelebrationGeneration,
                  showsUnlockCelebration else { return }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                unlockBurstRotation = 378
            }
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                unlockPulse = true
                unlockCharacterFloating = true
            }
        }
    }

    private func finishUnlockCelebration() {
        guard showsUnlockCelebration,
              let completedCharacterID = activeUnlockCharacterID else { return }

        unlockCelebrationGeneration += 1
        withAnimation(.easeOut(duration: 0.3)) { showsUnlockCelebration = false }

        let completedCharacter = CharacterCatalog.character(id: completedCharacterID)
        if canUse(completedCharacter) {
            characterID = completedCharacterID
        }

        if let nextCharacterID = pendingUnlockCharacterIDs.first {
            pendingUnlockCharacterIDs.removeFirst()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                playUnlockCelebration(characterID: nextCharacterID)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                guard !showsUnlockCelebration else { return }
                activeUnlockCharacterID = nil
            }
        }
    }

    /// Formats a count into a localized template. Dynamic lookup keeps these
    /// strings out of the compile-time catalog checks while still routing
    /// through the app's language switch.
    private func localizedInteger(_ key: String, _ value: Int) -> String {
        String(format: L(key: key), locale: language.locale, Int64(value))
    }

    private func localizedString(_ key: String, _ value: String) -> String {
        String(format: L(key: key), locale: language.locale, value)
    }
}

private extension View {
    /// One pill for every caption under an animal, so a tick and a fly total
    /// share the same shape and height whatever they contain.
    func characterTileBadgeStyle(character: AnimalCharacter,
                                 isUnlocked: Bool,
                                 size: CGFloat) -> some View {
        self
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .foregroundStyle(character.deepColor.opacity(isUnlocked ? 1 : 0.75))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .allowsTightening(true)
            .frame(minWidth: size * 1.5, minHeight: size * 1.25)
            .padding(.horizontal, size * 0.6)
            .padding(.vertical, size * 0.35)
            .background(character.color.opacity(isUnlocked ? 0.22 : 0.10), in: Capsule())
    }
}

extension View {
    @ViewBuilder
    func premiumSheetPresentation() -> some View {
        if #available(iOS 18.0, *) {
            self
                .presentationSizing(.page)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        } else {
            self
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

#Preview {
    PremiumView(initialCharacterID: "frog", celebratedUnlockCharacterID: "frog")
}
