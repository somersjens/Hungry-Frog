//
//  Theme.swift
//  Elephant Challenge: Math Memory
//
//  Character catalog: 10 animals, each with a clearly different colour and a
//  matching visual theme for the whole app. Characters are earned by collecting
//  cards; the requirements live in `GameConfig.characterUnlockRequirements`.
//

import SwiftUI

/// The game's currency. Players collect flies throughout the game. Keep the
/// asset name in one place so every counter and reward uses the same artwork.
enum Currency {
    static let icon = "fly_currency"
}

/// The artwork used anywhere a currency count is shown. It is rendered as a
/// template so existing character-theme colors continue to apply.
struct CurrencyIcon: View {
    let size: CGFloat

    var body: some View {
        Image(Currency.icon)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Where a character's painted mouth sits inside its playing artwork, and what
/// colour it is painted in. Every animal reclines on the same beach lounger,
/// but each muzzle lands somewhere else on the canvas and is drawn in its own
/// shade, so both are measured off the artwork once per character. Positions
/// are fractions of the artwork's frame; colours are components (0–1) sampled
/// from the painted mouth itself, which is what keeps the tongue looking like
/// it belongs to the animal it comes out of.
struct MouthGeometry: Equatable {
    /// Centre of the mouth opening.
    let center: CGPoint
    /// Size of that opening, used for the darkened throat behind the tongue.
    let opening: CGSize
    /// The painted tongue: the ribbon's mid tone.
    let tongueRGB: (Double, Double, Double)
    /// The shadowed inside of the mouth, behind the ribbon.
    let throatRGB: (Double, Double, Double)

    static func == (lhs: MouthGeometry, rhs: MouthGeometry) -> Bool {
        lhs.center == rhs.center && lhs.opening == rhs.opening
            && lhs.tongueRGB == rhs.tongueRGB && lhs.throatRGB == rhs.throatRGB
    }

    /// The tongue's root: just below the centre of the opening, so the ribbon
    /// climbs out of the throat instead of appearing on the lip.
    var anchor: CGPoint {
        CGPoint(x: center.x, y: center.y + opening.height * 0.16)
    }

    /// The ribbon's mid tone, taken straight from the artwork.
    var tongueColor: Color {
        Color(red: tongueRGB.0, green: tongueRGB.1, blue: tongueRGB.2)
    }

    /// The shaded root, where the ribbon is still inside the mouth. Darkening
    /// the painted tongue keeps the whole gradient in the character's own hue
    /// instead of falling back on one generic pink for all ten animals.
    var tongueDeepColor: Color {
        Color(red: tongueRGB.0 * 0.52, green: tongueRGB.1 * 0.34, blue: tongueRGB.2 * 0.42)
    }

    /// The lit top of the ribbon and the sticky pad.
    var tongueLightColor: Color {
        Color(red: tongueRGB.0 + (1 - tongueRGB.0) * 0.46,
              green: tongueRGB.1 + (1 - tongueRGB.1) * 0.52,
              blue: tongueRGB.2 + (1 - tongueRGB.2) * 0.50)
    }

    var throatColor: Color {
        Color(red: throatRGB.0, green: throatRGB.1, blue: throatRGB.2)
    }
}

struct AnimalCharacter: Identifiable, Equatable {
    let id: String
    let name: String
    let emoji: String
    /// Front-facing portrait: menus, the intro card, the collection, results.
    let imageName: String
    /// The reclining pose the character is played in.
    let sideImageName: String
    /// Mouth of `sideImageName`, in that artwork's own coordinates.
    let mouth: MouthGeometry

    // Colour components (0–1).
    let primaryRGB: (Double, Double, Double)
    let deepRGB: (Double, Double, Double)
    let skyRGB: (Double, Double, Double)
    let tintRGB: (Double, Double, Double)

    static func == (lhs: AnimalCharacter, rhs: AnimalCharacter) -> Bool {
        lhs.id == rhs.id
    }

    var color: Color { Color(red: primaryRGB.0, green: primaryRGB.1, blue: primaryRGB.2) }
    var deepColor: Color { Color(red: deepRGB.0, green: deepRGB.1, blue: deepRGB.2) }
    var skyColor: Color { Color(red: skyRGB.0, green: skyRGB.1, blue: skyRGB.2) }
    var tintColor: Color { Color(red: tintRGB.0, green: tintRGB.1, blue: tintRGB.2) }

    var artwork: Image { Image(imageName) }
    var playArtwork: Image { Image(sideImageName) }

    /// Every playing pose is drawn on the same wide canvas around the same
    /// lounger, so a single ratio sizes all ten of them.
    static let playAspectRatio: CGFloat = 1152.0 / 705.0

    /// Roughly how much of the playing artwork's width the head takes up. The
    /// tongue's girth and the length it needs to unroll are measured off the
    /// head, not off the whole reclining body.
    static let playHeadWidthShare: CGFloat = 0.30

    /// Localized display name, resolved per language from the string catalog
    /// ("character.frog", "character.penguin", …).
    var localizedName: String {
        L(key: "character.\(id)")
    }
}

enum CharacterCatalog {
    /// The character available from the very first card.
    static let freeCharacterID = CharacterUnlocks.starterCharacterID

    /// The localized fallback used when the player leaves their name empty.
    /// The current game character is Frog, so this resolves to Frog/Kikker and
    /// automatically follows every language added to the string catalog.
    static var defaultPlayerName: String {
        character(id: "frog").localizedName
    }

    /// Order must match `CharacterUnlocks.orderedCharacterIDs`. Frog leads the
    /// catalog: it is the game's own character and the one every player starts
    /// with. Fox closes it. Each palette is taken from the artwork itself —
    /// the dog and the crab are themed on their headband rather than their
    /// fur, which is what keeps them apart from the fox and the bear.
    static let all: [AnimalCharacter] = [
        AnimalCharacter(id: "frog", name: "Frog", emoji: "🐸",
                        imageName: "front_1", sideImageName: "side_1",
                        mouth: MouthGeometry(center: CGPoint(x: 0.212, y: 0.454),
                                             opening: CGSize(width: 0.046, height: 0.038),
                                             tongueRGB: (0.68, 0.15, 0.16),
                                             throatRGB: (0.31, 0.01, 0.00)),
                        primaryRGB: (0.29, 0.72, 0.22), deepRGB: (0.15, 0.43, 0.11),
                        skyRGB: (0.92, 0.99, 0.91), tintRGB: (0.82, 0.97, 0.79)),
        AnimalCharacter(id: "penguin", name: "Penguin", emoji: "🐧",
                        imageName: "front_2", sideImageName: "side_2",
                        mouth: MouthGeometry(center: CGPoint(x: 0.285, y: 0.462),
                                             opening: CGSize(width: 0.040, height: 0.035),
                                             tongueRGB: (0.82, 0.20, 0.19),
                                             throatRGB: (0.34, 0.08, 0.03)),
                        primaryRGB: (0.24, 0.48, 0.85), deepRGB: (0.11, 0.27, 0.51),
                        skyRGB: (0.91, 0.94, 0.99), tintRGB: (0.79, 0.86, 0.97)),
        AnimalCharacter(id: "bunny", name: "Bunny", emoji: "🐰",
                        imageName: "front_3", sideImageName: "side_3",
                        mouth: MouthGeometry(center: CGPoint(x: 0.312, y: 0.481),
                                             opening: CGSize(width: 0.032, height: 0.036),
                                             tongueRGB: (0.90, 0.35, 0.34),
                                             throatRGB: (0.30, 0.01, 0.01)),
                        primaryRGB: (0.96, 0.55, 0.64), deepRGB: (0.58, 0.31, 0.37),
                        skyRGB: (0.99, 0.94, 0.96), tintRGB: (0.97, 0.86, 0.89)),
        AnimalCharacter(id: "dog", name: "Dog", emoji: "🐶",
                        imageName: "front_4", sideImageName: "side_4",
                        mouth: MouthGeometry(center: CGPoint(x: 0.380, y: 0.465),
                                             opening: CGSize(width: 0.048, height: 0.055),
                                             tongueRGB: (0.78, 0.23, 0.15),
                                             throatRGB: (0.18, 0.02, 0.00)),
                        primaryRGB: (0.13, 0.70, 0.71), deepRGB: (0.05, 0.42, 0.43),
                        skyRGB: (0.90, 0.99, 0.99), tintRGB: (0.76, 0.97, 0.97)),
        AnimalCharacter(id: "lion", name: "Lion", emoji: "🦁",
                        imageName: "front_5", sideImageName: "side_5",
                        mouth: MouthGeometry(center: CGPoint(x: 0.312, y: 0.479),
                                             opening: CGSize(width: 0.045, height: 0.054),
                                             tongueRGB: (0.82, 0.21, 0.12),
                                             throatRGB: (0.18, 0.03, 0.00)),
                        primaryRGB: (0.97, 0.73, 0.10), deepRGB: (0.58, 0.43, 0.02),
                        skyRGB: (0.99, 0.97, 0.89), tintRGB: (0.97, 0.91, 0.74)),
        AnimalCharacter(id: "octopus", name: "Octopus", emoji: "🐙",
                        imageName: "front_6", sideImageName: "side_6",
                        mouth: MouthGeometry(center: CGPoint(x: 0.316, y: 0.519),
                                             opening: CGSize(width: 0.032, height: 0.044),
                                             tongueRGB: (0.91, 0.40, 0.40),
                                             throatRGB: (0.16, 0.01, 0.04)),
                        primaryRGB: (0.66, 0.38, 0.90), deepRGB: (0.38, 0.20, 0.54),
                        skyRGB: (0.96, 0.93, 0.99), tintRGB: (0.90, 0.82, 0.97)),
        AnimalCharacter(id: "crab", name: "Crab", emoji: "🦀",
                        imageName: "front_7", sideImageName: "side_7",
                        mouth: MouthGeometry(center: CGPoint(x: 0.342, y: 0.488),
                                             opening: CGSize(width: 0.035, height: 0.044),
                                             tongueRGB: (0.92, 0.23, 0.15),
                                             throatRGB: (0.31, 0.00, 0.00)),
                        primaryRGB: (0.91, 0.24, 0.16), deepRGB: (0.55, 0.11, 0.06),
                        skyRGB: (0.99, 0.91, 0.90), tintRGB: (0.97, 0.78, 0.76)),
        AnimalCharacter(id: "elephant", name: "Elephant", emoji: "🐘",
                        imageName: "front_8", sideImageName: "side_8",
                        mouth: MouthGeometry(center: CGPoint(x: 0.335, y: 0.530),
                                             opening: CGSize(width: 0.031, height: 0.031),
                                             tongueRGB: (0.82, 0.31, 0.35),
                                             throatRGB: (0.33, 0.08, 0.10)),
                        primaryRGB: (0.44, 0.59, 0.80), deepRGB: (0.25, 0.34, 0.48),
                        skyRGB: (0.94, 0.96, 0.99), tintRGB: (0.86, 0.91, 0.97)),
        AnimalCharacter(id: "bear", name: "Bear", emoji: "🐻",
                        imageName: "front_9", sideImageName: "side_9",
                        mouth: MouthGeometry(center: CGPoint(x: 0.305, y: 0.522),
                                             opening: CGSize(width: 0.038, height: 0.042),
                                             tongueRGB: (0.84, 0.22, 0.15),
                                             throatRGB: (0.44, 0.04, 0.01)),
                        primaryRGB: (0.65, 0.42, 0.22), deepRGB: (0.39, 0.24, 0.11),
                        skyRGB: (0.99, 0.95, 0.92), tintRGB: (0.97, 0.88, 0.80)),
        AnimalCharacter(id: "fox", name: "Fox", emoji: "🦊",
                        imageName: "front_10", sideImageName: "side_10",
                        mouth: MouthGeometry(center: CGPoint(x: 0.322, y: 0.543),
                                             opening: CGSize(width: 0.043, height: 0.048),
                                             tongueRGB: (0.81, 0.20, 0.08),
                                             throatRGB: (0.18, 0.03, 0.00)),
                        primaryRGB: (0.97, 0.48, 0.08), deepRGB: (0.58, 0.26, 0.01),
                        skyRGB: (0.99, 0.93, 0.89), tintRGB: (0.97, 0.84, 0.73))
    ]

    static func character(id: String) -> AnimalCharacter {
        all.first { $0.id == id } ?? all[0]
    }

    /// The first half of the catalog: earned purely by collecting cards.
    static var cardCharacters: [AnimalCharacter] {
        all.filter { !CharacterUnlocks.premiumCharacterIDs.contains($0.id) }
    }

    /// The second half: still earnable with cards, but Premium grants them at once.
    static var premiumCharacters: [AnimalCharacter] {
        all.filter { CharacterUnlocks.premiumCharacterIDs.contains($0.id) }
    }

    /// The selected character, falling back to the starter when the selected
    /// one is not available (yet).
    static func current(isPremium: Bool) -> AnimalCharacter {
        let selected = character(id: GameSettings.characterID)
        if !CharacterUnlockStore.canUse(characterID: selected.id, isPremium: isPremium) {
            return character(id: freeCharacterID)
        }
        return selected
    }
}

/// Character access, derived from the player's card total so an unlock can
/// never be lost through a missed animation. Only the one-time celebration
/// receipt is stored separately.
enum CharacterUnlockStore {
    static var totalCards: Int {
        get { Progress.store.totalCards }
        set { Progress.store.totalCards = newValue }
    }

    /// Cards required for a character, or nil when it is not card-unlockable.
    static func requirement(for characterID: String) -> Int? {
        CharacterUnlocks.cardsRequired(for: characterID)
    }

    static func canUse(characterID: String, isPremium: Bool) -> Bool {
        CharacterUnlocks.isUnlocked(characterID: characterID,
                                    totalCards: totalCards,
                                    isPremium: isPremium)
    }

    /// The next animal still to be earned, for the home screen and reminders.
    static func nextMilestone() -> (character: AnimalCharacter, remaining: Int)? {
        guard let next = CharacterUnlocks.nextMilestone(totalCards: totalCards) else { return nil }
        return (CharacterCatalog.character(id: next.characterID), next.remaining)
    }

    /// Characters that crossed their requirement but have not been celebrated.
    static func unannouncedUnlocks(at total: Int) -> [AnimalCharacter] {
        let announced = Progress.store.announcedUnlocks
        return CharacterUnlocks.unlockedCharacterIDs(totalCards: total)
            .filter { $0 != CharacterCatalog.freeCharacterID && !announced.contains($0) }
            .map { CharacterCatalog.character(id: $0) }
    }

    static func markAnnounced(_ characterID: String) {
        var announced = Progress.store.announcedUnlocks
        announced.insert(characterID)
        Progress.store.announcedUnlocks = announced
    }
}
