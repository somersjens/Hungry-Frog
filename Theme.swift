//
//  Theme.swift
//  Elephant Challenge: Math Memory
//
//  Character catalog: 10 animals, each with a clearly different colour and a
//  matching visual theme for the whole app. Characters are earned by collecting
//  cards; the requirements live in `GameConfig.characterUnlockRequirements`.
//

import SwiftUI

/// The game's currency. A player collects bubbles: in the reef, on the menu
/// totals, on the level cards and in the shop. One glyph, used everywhere, so
/// the same thing is never drawn two ways.
enum Currency {
    static let icon = "bubble"
}

/// The artwork used anywhere a bubble count is shown. The source PNG is
/// rendered as a template so it keeps following each character's theme color.
struct CurrencyIcon: View {
    let size: CGFloat

    var body: some View {
        Image(Currency.icon)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

struct AnimalCharacter: Identifiable, Equatable {
    let id: String
    let name: String
    let emoji: String
    /// Name of the artwork in the asset catalog.
    let imageName: String

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

    /// Penguin and octopus artwork already fills more of its source canvas, so
    /// every other asset is scaled up slightly to match.
    var selectorArtworkScale: CGFloat {
        id == "penguin" || id == "octopus" ? 1 : 1.1
    }

    /// Localized display name, resolved per language from the string catalog
    /// ("character.fox", "character.frog", …).
    var localizedName: String {
        L(key: "character.\(id)")
    }
}

enum CharacterCatalog {
    /// The character available from the very first card.
    static let freeCharacterID = CharacterUnlocks.starterCharacterID

    /// The localized fallback used when the player leaves their name empty.
    /// Resolve it through the character catalog so it can never drift from the
    /// name shown for Octopus in the active language.
    static var defaultPlayerName: String {
        character(id: "octopus").localizedName
    }

    /// Order must match `CharacterUnlocks.orderedCharacterIDs`; a test asserts it.
    static let all: [AnimalCharacter] = [
        AnimalCharacter(id: "fox", name: "Fox", emoji: "🦊", imageName: "no_background",
                        primaryRGB: (0.96, 0.55, 0.14), deepRGB: (0.80, 0.33, 0.04),
                        skyRGB: (1.00, 0.94, 0.86), tintRGB: (1.00, 0.90, 0.78)),
        AnimalCharacter(id: "frog", name: "Frog", emoji: "🐸", imageName: "frog_no_background",
                        primaryRGB: (0.36, 0.70, 0.29), deepRGB: (0.16, 0.47, 0.18),
                        skyRGB: (0.92, 0.98, 0.89), tintRGB: (0.84, 0.95, 0.80)),
        AnimalCharacter(id: "penguin", name: "Penguin", emoji: "🐧", imageName: "pinquin_no_background",
                        primaryRGB: (0.35, 0.68, 0.88), deepRGB: (0.13, 0.42, 0.65),
                        skyRGB: (0.90, 0.96, 1.00), tintRGB: (0.80, 0.91, 1.00)),
        AnimalCharacter(id: "bunny", name: "Bunny", emoji: "🐰", imageName: "bunny_no_background",
                        primaryRGB: (0.95, 0.58, 0.71), deepRGB: (0.78, 0.32, 0.48),
                        skyRGB: (1.00, 0.94, 0.96), tintRGB: (1.00, 0.88, 0.93)),
        AnimalCharacter(id: "dog", name: "Dog", emoji: "🐶", imageName: "dog_no_background",
                        primaryRGB: (0.16, 0.72, 0.72), deepRGB: (0.06, 0.48, 0.49),
                        skyRGB: (0.89, 0.98, 0.98), tintRGB: (0.79, 0.95, 0.95)),
        AnimalCharacter(id: "lion", name: "Lion", emoji: "🦁", imageName: "lion_no_background",
                        primaryRGB: (0.93, 0.75, 0.18), deepRGB: (0.72, 0.52, 0.05),
                        skyRGB: (1.00, 0.97, 0.85), tintRGB: (1.00, 0.93, 0.72)),
        AnimalCharacter(id: "octopus", name: "Octopus", emoji: "🐙", imageName: "octupus_no_background",
                        primaryRGB: (0.62, 0.40, 0.80), deepRGB: (0.42, 0.22, 0.60),
                        skyRGB: (0.96, 0.92, 1.00), tintRGB: (0.91, 0.84, 1.00)),
        AnimalCharacter(id: "crab", name: "Crab", emoji: "🦀", imageName: "crab_no_background",
                        primaryRGB: (0.88, 0.30, 0.25), deepRGB: (0.65, 0.15, 0.12),
                        skyRGB: (1.00, 0.92, 0.90), tintRGB: (1.00, 0.85, 0.82)),
        AnimalCharacter(id: "elephant", name: "Elephant", emoji: "🐘", imageName: "elephant_no_background",
                        primaryRGB: (0.48, 0.58, 0.74), deepRGB: (0.29, 0.39, 0.56),
                        skyRGB: (0.93, 0.95, 0.99), tintRGB: (0.86, 0.90, 0.97)),
        AnimalCharacter(id: "bear", name: "Bear", emoji: "🐻", imageName: "bear_no_background",
                        primaryRGB: (0.62, 0.44, 0.28), deepRGB: (0.42, 0.28, 0.16),
                        skyRGB: (0.97, 0.93, 0.88), tintRGB: (0.93, 0.87, 0.79))
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
