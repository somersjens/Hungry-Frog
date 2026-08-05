//
//  FoodCatalog.swift
//  Elephant Challenge: Math Memory
//
//  What each character eats. One food per character, in the same order as
//  `CharacterUnlocks.orderedCharacterIDs`, backed by the `food_1`…`food_10`
//  artwork. The currency (flies collected as "cards") is a separate concept
//  and keeps its own fly artwork and wording everywhere — this catalog only
//  covers what visibly flies around in a level and how that is described.
//

import Foundation

public struct FoodItem: Identifiable, Equatable, Sendable {
    /// Short identifier used to key the localized singular/plural strings
    /// ("food.<id>.singular", "food.<id>.plural").
    public let id: String
    /// Asset catalog name of the artwork ("food_1" … "food_10").
    public let imageName: String

    public init(id: String, imageName: String) {
        self.id = id
        self.imageName = imageName
    }
}

public enum FoodCatalog {
    /// Order must match `CharacterUnlocks.orderedCharacterIDs`, which in turn
    /// matches `CharacterCatalog.all` — frog through fox, so `food_1` is the
    /// frog's fly and `food_10` is the fox's chicken.
    private static let items: [FoodItem] = [
        FoodItem(id: "fly", imageName: "food_1"),
        FoodItem(id: "fish", imageName: "food_2"),
        FoodItem(id: "carrot", imageName: "food_3"),
        FoodItem(id: "kibble", imageName: "food_4"),
        FoodItem(id: "meat", imageName: "food_5"),
        FoodItem(id: "pearl", imageName: "food_6"),
        FoodItem(id: "shrimp", imageName: "food_7"),
        FoodItem(id: "peanut", imageName: "food_8"),
        FoodItem(id: "honey", imageName: "food_9"),
        FoodItem(id: "chicken", imageName: "food_10")
    ]

    /// The food a character eats, falling back to the starter's (the fly) for
    /// an unrecognized ID rather than crashing.
    public static func food(for characterID: String) -> FoodItem {
        let index = CharacterUnlocks.orderedCharacterIDs.firstIndex(of: characterID) ?? 0
        guard items.indices.contains(index) else { return items[0] }
        return items[index]
    }

    /// The artwork a character's food flies around as.
    public static func imageName(for characterID: String) -> String {
        food(for: characterID).imageName
    }

    /// The food's name, in the singular or plural form the count calls for.
    /// Resolved through `L(key:)`, so it follows the in-app language switch
    /// and falls back to English for any language missing a translation.
    public static func word(for characterID: String, count: Int) -> String {
        let id = food(for: characterID).id
        let key = count == 1 ? "food.\(id).singular" : "food.\(id).plural"
        return L(key: key)
    }
}
