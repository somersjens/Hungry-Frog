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
                ScrollView {
                    let available = min(AppLayout.landscapeContentWidth,
                                        proxy.size.width - AppLayout.landscapeGutter * 2)
                    HStack(alignment: .top, spacing: isPad ? 24 : 12) {
                        VStack(spacing: isPad ? 18 : 10) {
                            hero
                            purchaseSection
                        }
                        .frame(width: isPad ? 310 : 218)

                        collectionPanel
                            .frame(maxWidth: .infinity)
                    }
                    .padding(isPad ? 20 : 12)
                    .background(.white.opacity(0.52),
                                in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: character.deepColor.opacity(0.1), radius: 16, y: 7)
                    .padding(AppLayout.landscapeGutter)
                    .frame(width: available + AppLayout.landscapeGutter * 2)
                    .frame(maxWidth: .infinity)
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

    @ViewBuilder
    private var collectionPanel: some View {
        HStack(alignment: .top, spacing: isPad ? 18 : 8) {
            characterList(
                title: L(key: "premium.unlockWithCards"),
                icon: Currency.icon,
                animals: CharacterCatalog.cardCharacters
            )
                .padding(.vertical, isPad ? 12 : 8)
                .frame(width: isPad ? 205 : 145)
            premiumBlock
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
        }
    }

    private var hero: some View {
        VStack(spacing: isPad ? 6 : 3) {
            HStack(alignment: .center) {
                if activeUnlockCharacterID == nil { closeButton }
                Spacer()
                if activeUnlockCharacterID == nil {
                    LanguagePicker(
                        tint: character.deepColor.opacity(0.7),
                        scale: isPad ? 1.12 : 0.9
                    )
                }
            }
            .padding(.bottom, isPad ? 14 : 10)

            let heroSize: CGFloat = isPad ? 195 : 118
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [character.color.opacity(0.35), character.color.opacity(0.05)],
                        center: .center, startRadius: 6, endRadius: 150
                    ))
                    .frame(width: heroSize, height: heroSize)
                Circle()
                    .stroke(character.color.opacity(0.30), lineWidth: 2)
                    .frame(width: heroSize * 0.92, height: heroSize * 0.92)
                character.artwork
                    .resizable()
                    .scaledToFit()
                    .frame(width: heroSize * 0.88, height: heroSize * 0.88)
                    .shadow(color: character.deepColor.opacity(0.25), radius: 14, y: 8)
                    .id(previewCharacterID)
                    .transition(.scale.combined(with: .opacity))
            }
            .frame(maxWidth: .infinity)

            Text(character.localizedName)
                .font(.system(size: (isPad ? 28 : 26) * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(character.deepColor)

            availabilityBadge(for: character)
        }
    }

    @ViewBuilder
    private func availabilityBadge(for animal: AnimalCharacter) -> some View {
        if animal.id == CharacterCatalog.freeCharacterID {
            badge(text: L(key: "premium.availableFromStart"), icon: nil)
        } else if let cards = CharacterUnlockStore.requirement(for: animal.id) {
            if totalCards >= cards {
                badge(text: localizedInteger("premium.earnedCards %lld", cards),
                      icon: "checkmark.circle.fill")
            } else if premium.isPremium {
                badge(text: L(key: "premium.unlockedWithPremium"), icon: "crown.fill")
            } else {
                badge(text: localizedInteger("premium.availableAt %lld", cards),
                      icon: Currency.icon)
            }
        } else {
            badge(
                text: L(key: premium.isPremium ? "premium.unlockedWithPremium" : "premium.exclusiveBadge"),
                icon: "crown.fill"
            )
        }
    }

    private func badge(text: String, icon: String?) -> some View {
        HStack(spacing: 6) {
            if let icon {
                if icon == Currency.icon {
                    CurrencyIcon(size: 13 * scale)
                } else {
                    Image(systemName: icon)
                }
            }
            Text(text)
        }
        .font(.system(size: 13 * scale, weight: .bold, design: .rounded))
        .foregroundStyle(character.deepColor)
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 6 * scale)
        .background(.white.opacity(0.58), in: Capsule())
        .overlay(Capsule().stroke(character.color.opacity(0.38), lineWidth: 1))
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: isPad ? 16 : 12) {
            featureRow(icon: "square.grid.3x3.fill",
                       title: L("premium.feature.levels.title"),
                       subtitle: L("premium.feature.levels.subtitle"))
            featureRow(icon: "pawprint.fill",
                       title: L("premium.feature.animals.title"),
                       subtitle: L("premium.feature.animals.subtitle"))
            featureRow(icon: "nosign",
                       title: L("premium.feature.noAds.title"),
                       subtitle: L("premium.feature.noAds.subtitle"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var premiumBlock: some View {
        VStack(alignment: .leading, spacing: isPad ? 9 : 6) {
            sectionHeader(title: L(key: "premium.exclusiveWithPremium"), icon: "crown.fill")
            HStack(alignment: .top, spacing: isPad ? 18 : 10) {
                characterRows(CharacterCatalog.premiumCharacters, showsAccessory: false)
                    .frame(width: isPad ? 100 : 66)
                featureList
                    .padding(.top, isPad ? 6 : 4)
                    .layoutPriority(1)
            }
        }
        .padding(isPad ? 12 : 8)
        .background(.white.opacity(0.3),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func characterList(title: String, icon: String,
                               animals: [AnimalCharacter]) -> some View {
        VStack(spacing: isPad ? 9 : 6) {
            sectionHeader(title: title, icon: icon)
            characterRows(animals, showsAccessory: true)
        }
    }

    private func characterRows(_ animals: [AnimalCharacter],
                               showsAccessory: Bool) -> some View {
        VStack(spacing: isPad ? 9 : 6) {
            ForEach(animals) { animal in
                characterRow(for: animal, showsAccessory: showsAccessory)
            }
        }
    }

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            if icon == Currency.icon {
                CurrencyIcon(size: 15 * scale)
            } else {
                Image(systemName: icon)
            }
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Spacer(minLength: 0)
        }
        .font(.system(size: 14 * scale, weight: .heavy, design: .rounded))
        .foregroundStyle(character.deepColor)
        .frame(height: 24 * scale, alignment: .leading)
    }

    private func characterRow(for animal: AnimalCharacter,
                              showsAccessory: Bool) -> some View {
        let isSelected = previewCharacterID == animal.id
        let isAccessible = canUse(animal)
        return Button {
            AppAudio.shared.playMenuTap()
            previewCharacterID = animal.id
            if isAccessible { characterID = animal.id }
        } label: {
            HStack(spacing: isPad ? 10 : 6) {
                if !showsAccessory { Spacer(minLength: 0) }
                animal.artwork
                    .resizable()
                    .scaledToFit()
                    .frame(width: 38 * scale * animal.selectorArtworkScale,
                           height: 38 * scale * animal.selectorArtworkScale)
                    .frame(width: 44 * scale, height: 44 * scale)

                Spacer(minLength: 2)
                if showsAccessory {
                    characterRowAccessory(for: animal)
                }
            }
            .padding(.horizontal, 8 * scale)
            .frame(minHeight: 50 * scale)
            .background(isSelected ? character.color.opacity(0.18) : .white.opacity(0.34),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
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

    @ViewBuilder
    private func characterRowAccessory(for animal: AnimalCharacter) -> some View {
        if animal.id == CharacterCatalog.freeCharacterID {
            Text(verbatim: L(key: "premium.start"))
                .characterRowBadgeStyle(character: character)
        } else if canUse(animal) {
            Image(systemName: "checkmark.circle.fill")
                .characterRowBadgeStyle(character: character)
        } else if let cards = CharacterUnlockStore.requirement(for: animal.id) {
            HStack(spacing: 3) {
                Text(verbatim: "\(cards)")
                CurrencyIcon(size: 11 * scale)
            }
            .characterRowBadgeStyle(character: character)
        } else {
            Image(systemName: "crown.fill")
                .characterRowBadgeStyle(character: character)
        }
    }

    private func canUse(_ animal: AnimalCharacter) -> Bool {
        CharacterUnlockStore.canUse(characterID: animal.id, isPremium: premium.isPremium)
    }

    @ViewBuilder
    private var purchaseSection: some View {
        if premium.isPremium {
            Button { dismiss() } label: {
                Text("common.done")
                    .font(isPad ? .system(size: 24, weight: .bold) : .headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14 * scale)
                    .background(character.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        } else {
            VStack(spacing: isPad ? 12 : 8) {
                Button { showsParentApproval = true } label: {
                    HStack {
                        if premium.isPurchasing {
                            ProgressView().tint(.white)
                        } else {
                            Text(purchaseButtonTitle)
                                .font(isPad ? .system(size: 24, weight: .bold) : .headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, (isPad ? 16 : 12) * scale)
                    .background(
                        LinearGradient(colors: [character.color, character.deepColor],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .foregroundStyle(.white)
                    .shadow(color: character.deepColor.opacity(0.3), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
                .disabled(premium.isPurchasing)

                Text("premium.oneTime")
                    .font(isPad ? .system(size: 20) : .subheadline)
                    .foregroundStyle(character.deepColor.opacity(0.7))

                Button("premium.restore") {
                    Task { await premium.restorePurchases() }
                }
                .font(isPad ? .system(size: 18) : .footnote)
                .foregroundStyle(character.deepColor.opacity(0.7))

                if let error = premium.lastError {
                    Text(error)
                        .font(isPad ? .system(size: 18) : .footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
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

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 12 * scale) {
            Image(systemName: icon)
                .font(isPad ? .system(size: 28) : .title3)
                .foregroundStyle(character.color)
                .frame(width: 28 * scale)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(isPad ? .system(size: 24, weight: .bold) : .subheadline.weight(.bold))
                    .foregroundStyle(character.deepColor)
                Text(subtitle)
                    .font(isPad ? .system(size: 20) : .footnote)
                    .foregroundStyle(character.deepColor.opacity(0.7))
            }
        }
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
    func characterRowBadgeStyle(character: AnimalCharacter) -> some View {
        self
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(character.deepColor)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background(character.color.opacity(0.16), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
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
