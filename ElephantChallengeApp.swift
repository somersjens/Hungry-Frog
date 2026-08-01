//
//  ElephantChallengeApp.swift
//  Elephant Challenge: Math Memory
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
/// The game is portrait-only. iPad has to *declare* every orientation, so the
/// lock is applied here at runtime instead — `UIRequiresFullScreen`, the old
/// way of saying this, is deprecated and will stop being honoured.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?)
    -> UIInterfaceOrientationMask {
        .portrait
    }
}
#endif

@main
struct ElephantChallengeApp: App {
#if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
#endif
    @AppStorage(GameSettings.onboardingCompleteKey) private var onboardingComplete = false
    @StateObject private var language = LanguageManager.shared
    @StateObject private var promotedPurchase = PromotedPurchaseCoordinator.shared

    init() {
        // Bring stored progress up to the current version before anything can
        // read it: data written by Jumping Fox must never reach the new game.
        Progress.store.migrateIfNeeded()
        // Decimal answers are printed with the separator of the language the
        // player is reading — a comma in Dutch, a point in English — rather
        // than the device's. The in-app language switch must win here too.
        DecimalAnswer.separatorProvider = {
            LanguageManager.shared.locale.decimalSeparator ?? "."
        }
        // Capture the first launch date independently of when the player first
        // finishes a game; later review phases use age since installation.
        _ = ReviewRequestCoordinator.shared
        PromotedPurchaseCoordinator.shared.startListening()
        // Bring iCloud sync online at launch, not just once the home screen
        // appears — on a fresh reinstall the app opens on onboarding, which
        // never touches ProgressSync, and the saved name would stay missing.
        _ = ProgressSync.shared
        // Install the notification delegate and rebuild the reminder schedule
        // for players who granted permission in an earlier session.
        NotificationManager.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if onboardingComplete {
                    HomeView()
                        // Both screens fade through each other rather than one
                        // replacing the other, so the hand-over reads as a
                        // single settling motion instead of a cut.
                        .transition(.opacity.combined(with: .scale(scale: 1.015)))
                } else {
                    OnboardingView()
                        .transition(.opacity.combined(with: .scale(scale: 0.99)))
                }
            }
            .animation(.easeInOut(duration: 0.42), value: onboardingComplete)
            // Re-renders every `Text` (and formats numbers) when the language
            // changes; combined with the bundle redirection this makes the
            // switch instant, no restart required.
            .environment(\.locale, language.locale)
            .sheet(isPresented: Binding(
                get: { promotedPurchase.isAwaitingParentApproval },
                set: { isPresented in
                    if !isPresented { promotedPurchase.cancelDeferredPurchase() }
                }
            ),
                   onDismiss: { promotedPurchase.cancelDeferredPurchase() }) {
                let character = CharacterCatalog.current(isPremium: PremiumStore.shared.isPremium)
                ParentApprovalGate(
                    accent: character.color,
                    deepColor: character.deepColor,
                    onApproved: { promotedPurchase.approveDeferredPurchase() }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

/// Shared layout helper, used to give iPad more breathing room without
/// changing the visual hierarchy.
enum AppLayout {
    static var isPad: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
#else
        false
#endif
    }
}
