//
//  ElephantChallengeApp.swift
//  Elephant Challenge: Math Memory
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
/// The complete app is played in landscape. Keeping the runtime mask aligned
/// with the generated Info.plist prevents sheets and full-screen covers from
/// briefly rotating through portrait during presentation.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?)
    -> UIInterfaceOrientationMask {
        .landscape
    }
}
#endif

@main
struct ElephantChallengeApp: App {
#if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
#endif
    @AppStorage(GameSettings.onboardingCompleteKey) private var onboardingComplete = false
    @State private var showsOnboardingReplay = false
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
                if onboardingComplete && !showsOnboardingReplay {
                    HomeView {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            showsOnboardingReplay = true
                        }
                    }
                        // Both screens fade through each other rather than one
                        // replacing the other, so the hand-over reads as a
                        // single settling motion instead of a cut.
                        .transition(.opacity.combined(with: .scale(scale: 1.015)))
                } else {
                    OnboardingView {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            showsOnboardingReplay = false
                        }
                    }
                        .transition(.opacity.combined(with: .scale(scale: 0.99)))
                }
            }
            .animation(.easeInOut(duration: 0.42), value: onboardingComplete)
            .animation(.easeInOut(duration: 0.42), value: showsOnboardingReplay)
            // Re-renders every `Text` (and formats numbers) when the language
            // changes; combined with the bundle redirection this makes the
            // switch instant, no restart required.
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.effective.layoutDirection)
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


    /// Shared landscape canvas widths. iPad uses the extra room without
    /// stretching controls into long, hard-to-scan rows.
    static var landscapeContentWidth: CGFloat { isPad ? 1180 : 980 }
    static var landscapeGutter: CGFloat { isPad ? 28 : 16 }
}
