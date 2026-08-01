//
//  Localization.swift
//  Elephant Challenge: Math Memory
//
//  Runtime language switching + the little flag-and-chevron picker shown on
//  the welcome screens and the premium menu.
//
//  SwiftUI's `Text` resolves its strings from the *main bundle*, not from the
//  environment locale, so changing `\.locale` alone is not enough to swap the
//  language while the app is running. We install a tiny Bundle subclass that
//  redirects `localizedString(...)` to a chosen `.lproj`. Changing the
//  environment locale at the root then re-renders every `Text`, which now
//  reads the redirected strings — a live, no-restart language change.
//

import SwiftUI
import Combine
import ObjectiveC

// MARK: - Supported languages

/// A language the app can present, identified by its ISO code and shown in the
/// picker with a flag and its own-language name (endonym). This is a plain data
/// model rather than an enum with per-case switches, so the full language list
/// below is the single place to add a language — no code branches to touch.
///
/// The string catalog carries the actual translations for each `code`; until a
/// language is fully translated the runtime falls back to English (see the
/// bundle redirection further down).
struct AppLanguage: Identifiable, Hashable, Sendable {
    /// ISO 639 code, matching the language's `.lproj` and its column in the
    /// string catalog.
    let code: String
    /// Flag shown in the picker.
    let flag: String
    /// The language's name in its own language — the convention for a picker.
    let displayName: String

    var id: String { code }

    /// The two languages the app ships in. Adding a row here (plus its column
    /// in the string catalog) is all it takes to offer another one.
    static let all: [AppLanguage] = [
        AppLanguage(code: "en", flag: "\u{1F1EC}\u{1F1E7}", displayName: "English"),
        AppLanguage(code: "nl", flag: "\u{1F1F3}\u{1F1F1}", displayName: "Nederlands")
    ]

    /// Look up a language by its ISO code.
    static func named(_ code: String) -> AppLanguage? {
        all.first { $0.code == code }
    }

    /// Convenience handles on the two supported languages.
    static let english = named("en")!
    static let dutch = named("nl")!
}

// MARK: - Language manager

/// Holds the user's language choice. `nil` means "follow the device", which is
/// the default at first launch; picking a flag pins the app to that language.
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    private static let overrideKey = "settings.languageOverride"

    @Published var override: AppLanguage? {
        didSet {
            let defaults = UserDefaults.standard
            if let override {
                defaults.set(override.code, forKey: Self.overrideKey)
            } else {
                defaults.removeObject(forKey: Self.overrideKey)
            }
            Bundle.setLanguage(override?.code)
        }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.overrideKey) {
            override = AppLanguage.named(raw)
        }
        Bundle.setLanguage(override?.code)
    }

    /// The language actually shown: the pinned choice, or the device's best
    /// match among the languages we support. Matching is generic over
    /// `AppLanguage.all`, so adding a language to the roster (and the string
    /// catalog) is all it takes to have the device follow it automatically.
    var effective: AppLanguage {
        if let override { return override }
        for code in Bundle.main.preferredLocalizations {
            let base = code.split(separator: "-").first.map(String.init) ?? code
            if let match = AppLanguage.named(base) { return match }
        }
        return .english
    }

    /// Drives the environment locale, which both formats numbers correctly and
    /// forces every `Text` to re-render when the language changes.
    var locale: Locale { Locale(identifier: effective.code) }

    /// The `.lproj` bundle for the language currently shown. `String(localized:)`
    /// ignores the runtime bundle redirection used for `Text`, so any string
    /// resolved in code must be pointed at this bundle explicitly (see `L`).
    var bundle: Bundle { Self.lprojBundle(for: effective.code) ?? .main }

    /// The English `.lproj`, used as the last-resort fallback for any key a
    /// language has not translated yet.
    static let englishBundle: Bundle? = lprojBundle(for: "en")

    private static func lprojBundle(for code: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    func select(_ language: AppLanguage) {
        withAnimation(.easeInOut(duration: 0.2)) { override = language }
    }
}

/// Resolve a localized string in the language the user has chosen. Use this
/// everywhere instead of `String(localized:)`, which always follows the system
/// language regardless of the in-app switch.
func L(_ key: String.LocalizationValue) -> String {
    let manager = LanguageManager.shared
    return String(localized: key, bundle: manager.bundle, locale: manager.locale)
}

/// Resolve a localized string from a key that is only known at runtime (for
/// example an indexed key like `game.encouragement.3`). Routes through the same
/// bundle as `L(_:)` so the in-app language switch applies consistently instead
/// of relying on `Bundle.main`'s redirection.
func L(key: String) -> String {
    let manager = LanguageManager.shared
    let value = manager.bundle.localizedString(forKey: key, value: key, table: nil)
    // A key that resolves to itself was not found in the chosen language; fall
    // back to English so an untranslated key never surfaces as a raw identifier.
    if value == key, let english = LanguageManager.englishBundle {
        return english.localizedString(forKey: key, value: key, table: nil)
    }
    return value
}

// MARK: - Bundle redirection (the mechanism behind a live switch)

private var languageBundleKey: UInt8 = 0

/// A Bundle that, when asked for a localized string, forwards the request to a
/// specific `.lproj` bundle if one has been set.
private final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let redirected = objc_getAssociatedObject(self, &languageBundleKey) as? Bundle {
            let result = redirected.localizedString(forKey: key, value: key, table: tableName)
            // Fall back to English for any key the chosen language is missing,
            // so a partial translation never leaves a raw key on screen.
            if result == key,
               let english = LanguageManager.englishBundle,
               english !== redirected {
                return english.localizedString(forKey: key, value: value, table: tableName)
            }
            return result
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// Swap `Bundle.main`'s class exactly once so it can redirect lookups.
    private static let installLanguageBundle: Void = {
        object_setClass(Bundle.main, LanguageBundle.self)
    }()

    /// Point `Bundle.main` at a language's `.lproj`, or pass `nil` to fall back
    /// to the device's normal resolution.
    static func setLanguage(_ language: String?) {
        _ = installLanguageBundle
        let target: Bundle?
        if let language,
           let path = Bundle.main.path(forResource: language, ofType: "lproj") {
            target = Bundle(path: path)
        } else {
            target = nil
        }
        objc_setAssociatedObject(Bundle.main, &languageBundleKey, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

// MARK: - Liquid glass styling with an iOS 16 fallback

private struct LiquidGlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        }
    }
}

extension View {
    /// Liquid-glass capsule background (with an iOS 16 material fallback),
    /// shared by the language picker and the onboarding back button so they
    /// match exactly.
    func liquidGlassCapsule() -> some View { modifier(LiquidGlassCapsule()) }
}

// MARK: - Re-applying the language environment across modal boundaries

/// Re-applies the app's locale. Modal presentations (`sheet`,
/// `fullScreenCover`) begin a fresh environment and do not inherit the values
/// set at the app root, so any full-screen surface presented that way (the game
/// and result screens) must opt back in.
private struct GameEnvironment: ViewModifier {
    @ObservedObject private var language = LanguageManager.shared
    func body(content: Content) -> some View {
        content
            .environment(\.locale, language.locale)
    }
}

extension View {
    /// Carry the chosen language's locale into a modally presented surface.
    func gameEnvironment() -> some View { modifier(GameEnvironment()) }
}

// MARK: - The picker

/// A flag with a chevron. Tap to choose a language; the current one is ticked.
struct LanguagePicker: View {
    @ObservedObject private var language = LanguageManager.shared

    /// Colour for the chevron so it can sit on light or dark backgrounds.
    var tint: Color = .secondary
    /// Callers can opt into the larger, touch-friendly iPad treatment while
    /// preserving the compact control on iPhone.
    var scale: CGFloat = 1

    var body: some View {
        Menu {
            ForEach(AppLanguage.all) { option in
                Button {
                    language.select(option)
                } label: {
                    // Flag + endonym are already runtime strings and must not
                    // be treated as a localizable key, so compose them verbatim.
                    let title = Text(verbatim: "\(option.flag)  \(option.displayName)")
                    if language.effective == option {
                        Label { title } icon: { Image(systemName: "checkmark") }
                    } else {
                        title
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(language.effective.flag)
                    .font(.system(size: 20 * scale))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10 * scale, weight: .bold))
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 12 * scale)
            .padding(.vertical, 8 * scale)
            .liquidGlassCapsule()
            .contentShape(Capsule())
        }
        .accessibilityLabel(Text("language.select"))
    }
}
