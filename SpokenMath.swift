//
//  SpokenMath.swift
//  Elephant Challenge: Math Memory
//
//  Compact, language-native wording for the sums read by AppAudio.
//

import Foundation

/// Converts the language-neutral question shown by the game into a short
/// utterance. Numerals deliberately remain numerals: the selected system voice
/// already knows how to pronounce them in its own language.
enum SpokenMath {
    struct Lexicon {
        let plus: String
        let minus: String
        let times: String
        let dividedBy: String
        let percentPattern: String
        let percentOfPattern: String
        let equals: String
        let unknown: String

        init(_ plus: String, _ minus: String, _ times: String, _ dividedBy: String,
             _ percentPattern: String, _ percentOfPattern: String,
             _ equals: String, _ unknown: String) {
            self.plus = plus
            self.minus = minus
            self.times = times
            self.dividedBy = dividedBy
            self.percentPattern = percentPattern
            self.percentOfPattern = percentOfPattern
            self.equals = equals
            self.unknown = unknown
        }

        func percent(_ value: String) -> String {
            percentPattern.replacingOccurrences(of: "%p", with: value)
        }

        func percentOf(_ value: String, whole: String) -> String {
            percentOfPattern
                .replacingOccurrences(of: "%p", with: value)
                .replacingOccurrences(of: "%w", with: whole)
        }
    }

    /// Languages for which Apple currently supplies an AVSpeech voice on its
    /// platforms and which are also present in the app. A runtime voice check
    /// still decides whether speech is enabled on the particular device.
    static let lexicons: [String: Lexicon] = [
        "en": .init("plus", "minus", "times", "divided by", "%p percent", "%p percent of %w", "is", "how many"),
        "nl": .init("plus", "min", "keer", "gedeeld door", "%p procent", "%p procent van %w", "is", "hoeveel")
    ]

    /// A fraction is a part of a whole, not a division instruction. These
    /// pattern deliberately avoids language-specific ordinal inflection while
    /// still sounding natural. `%n` is the numerator and `%d` the denominator.
    /// Dutch is handled separately below because its short school form
    /// (“1 twintigste”) is both clear and productive.
    private static let fractionPatterns: [String: String] = [
        "en": "%n of %d parts"
    ]

    static var fractionPatternLanguageCodes: Set<String> {
        Set(fractionPatterns.keys)
    }

    static func text(for prompt: String, languageCode: String) -> String? {
        guard let lexicon = lexicons[languageCode] else { return nil }
        let sides = prompt.components(separatedBy: "=")
        if sides.count == 2 {
            let lhs = expression(sides[0], languageCode: languageCode, lexicon: lexicon)
            let rhs = sides[1].trimmingCharacters(in: .whitespaces)
            if rhs == "?" {
                return lhs
            }
            return "\(lhs) \(lexicon.equals) \(expression(rhs, languageCode: languageCode, lexicon: lexicon))"
        }
        return expression(prompt, languageCode: languageCode, lexicon: lexicon)
    }

    private static func expression(_ expression: String, languageCode: String,
                                   lexicon: Lexicon) -> String {
        let tokens = expression.split(separator: " ").map(String.init)

        // Percent questions are said in the natural order of the language,
        // rather than literally reading “percent times”.
        if tokens.count == 3,
           tokens[0].hasSuffix("%"),
           tokens[1] == "×" {
            let percent = String(tokens[0].dropLast())
            return lexicon.percentOf(number(percent, lexicon: lexicon),
                                     whole: term(tokens[2], languageCode: languageCode,
                                                 lexicon: lexicon))
        }

        return tokens.map { token in
            switch token {
            case "+": return lexicon.plus
            case "−", "-": return lexicon.minus
            case "×": return lexicon.times
            case "÷": return lexicon.dividedBy
            case "=": return lexicon.equals
            default: return term(token, languageCode: languageCode, lexicon: lexicon)
            }
        }.joined(separator: " ")
    }

    private static func term(_ token: String, languageCode: String,
                             lexicon: Lexicon) -> String {
        if token.hasSuffix("%") {
            return lexicon.percent(number(String(token.dropLast()), lexicon: lexicon))
        }
        if token.contains("/") {
            let parts = token.components(separatedBy: "/")
            if parts.count == 2 {
                return fraction(numerator: number(parts[0], lexicon: lexicon),
                                denominator: number(parts[1], lexicon: lexicon),
                                languageCode: languageCode)
            }
        }
        return number(token, lexicon: lexicon)
    }

    private static func fraction(numerator: String, denominator: String,
                                 languageCode: String) -> String {
        if languageCode == "nl" {
            if numerator == lexicons["nl"]?.unknown {
                return "\(numerator) \(dutchOrdinal(denominator))n"
            }
            return "\(numerator) \(dutchOrdinal(denominator))"
        }
        let pattern = fractionPatterns[languageCode] ?? "%n/%d"
        return pattern
            .replacingOccurrences(of: "%n", with: numerator)
            .replacingOccurrences(of: "%d", with: denominator)
    }

    /// Numeric ordinal spelling keeps even advanced denominators such as 128
    /// short while prompting the Dutch voice to say “honderdachtentwintigste”.
    private static func dutchOrdinal(_ denominator: String) -> String {
        guard denominator != "hoeveel", let value = Int(denominator) else {
            return denominator
        }
        let suffix = value == 8 || value >= 20 ? "ste" : "de"
        return "\(value)\(suffix)"
    }

    private static func number(_ text: String, lexicon: Lexicon) -> String {
        text == "?" ? lexicon.unknown : text
    }
}
