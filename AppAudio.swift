//
//  AppAudio.swift
//  Elephant Challenge: Math Memory
//
//  All of the app's sound in one place:
//   - looping background music while a game is being played,
//   - the correct / wrong answer sound effects,
//   - the sums read aloud in every app language with a system voice, and
//   - small Apple-native tap sounds for the menus.
//
//  The start/pause card exposes music/effects and spoken sums as two independent
//  controls. Speech is offered only when the device has a matching system voice
//  for the language selected inside the app.
//

import Foundation
import Combine
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

enum AppAudioMode: String {
    case all
    case musicAndEffects
    case speechOnly
    case off
}

final class AppAudio: NSObject, ObservableObject {
    static let shared = AppAudio()

    /// Sound effects, background music and spoken sums each have their own
    /// preference. Effects can stay on with the music off, which is what most
    /// players want, and speech remains usable as reading support either way.
    @Published private(set) var gameSoundsEnabled: Bool {
        didSet {
            guard oldValue != gameSoundsEnabled else { return }
            GameSettings.gameSoundsEnabled = gameSoundsEnabled
            if gameSoundsEnabled {
                prepare()
                activateSession()
            } else {
                stopEngine()
                deactivateSessionIfUnused()
            }
        }
    }

    /// The endless background loop, independent of the effects.
    @Published private(set) var musicEnabled: Bool {
        didSet {
            guard oldValue != musicEnabled else { return }
            GameSettings.musicEnabled = musicEnabled
            // Re-apply the session category right away: with the music off,
            // effects/speech should mix with whatever the player is listening
            // to elsewhere rather than silencing it.
            configureSessionIfNeeded()
            if musicEnabled {
                startMusic()
            } else {
                stopMusic()
                deactivateSessionIfUnused()
            }
        }
    }

    @Published private(set) var spokenSumsEnabled: Bool {
        didSet {
            guard oldValue != spokenSumsEnabled else { return }
            GameSettings.spokenSumsEnabled = spokenSumsEnabled
            if spokenSumsEnabled {
                prepare()
                activateSession()
                // Enabling mid-session: warm the synthesizer now (idempotent) so
                // the first spoken sum doesn't cold-start it. A no-op if prepare
                // hasn't resolved voices yet — that path warms up on its own.
                if speechVoicesResolved {
                    let languageCode = LanguageManager.shared.effective.code
                    warmUpSpeechSynthesizer(preferred: voicesByLanguage[languageCode])
                }
            } else {
                cancelPendingSpeech()
                stopSpeechPlayback()
                deactivateSessionIfUnused()
            }
        }
    }

    var hasAnyAudioEnabled: Bool { gameSoundsEnabled || musicEnabled || spokenSumsEnabled }

    /// True only when both localized math wording and a matching installed
    /// system voice exist for the language currently selected in the app.
    var isSpokenMathAvailable: Bool {
        let languageCode = LanguageManager.shared.effective.code
        guard SpokenMath.lexicons[languageCode] != nil else { return false }
        // Voice discovery is deliberately asynchronous. Until it completes,
        // keep the three-state audio control available; resolving the installed
        // voices must never happen inside a SwiftUI render or button tap.
        return !speechVoicesResolved || voicesByLanguage[languageCode] != nil
    }

    var areSpokenSumsEnabled: Bool {
        let languageCode = LanguageManager.shared.effective.code
        return spokenSumsEnabled && voicesByLanguage[languageCode] != nil
    }

    // MARK: Players

    private var musicPlayer: AVAudioPlayer?
    private var speechPlayer: AVAudioPlayer?
    private var speechFileURL: URL?
    private let synthesizer = AVSpeechSynthesizer()

    /// Sound effects play through one long-lived `AVAudioEngine` instead of a
    /// pool of `AVAudioPlayer`s. The render graph stays up for the whole
    /// session, so firing an effect is just "schedule a preloaded PCM buffer on
    /// a node" — no per-play decode, no audio-session touch and no graph rebuild
    /// to land in the same frame as SpriteKit. Because the graph never tears
    /// down, a speech start or an audio-route change can no longer stall them.
    private let engine = AVAudioEngine()
    /// One player node per effect, kept in its always-on "playing" state so a
    /// trigger is a single cheap `scheduleBuffer(.interrupts)` on the node.
    private var effectNodes: [String: AVAudioPlayerNode] = [:]
    /// Preloaded, lead-trimmed PCM buffer per effect, ready to schedule.
    private var effectBuffers: [String: AVAudioPCMBuffer] = [:]

    /// The catalog of one-shot sound effects. The per-file `volume` values were
    /// measured (each file's RMS) and chosen so every effect lands at the same
    /// loudness as the "return to menu" trophy sound (~-38 dBFS) — the level
    /// that felt right — rather than each raw file playing at its own recorded
    /// level. `key` is what the `play…` methods reference.
    private struct Effect {
        let key: String
        let file: String
        let ext: String
        let volume: Float
        /// Seconds of leading silence in the file, skipped at playback so the
        /// sound fires immediately (measured per file; no re-encoding needed).
        let lead: TimeInterval
    }
    // Most of these are shipped as uncompressed CAF/PCM, converted from the
    // originals without touching their sample rate, channels or timing — which
    // is why their `volume`/`lead` have never had to change. The three `wav`
    // files were already PCM.
    //
    // The newer files (`splash`, `wrong_answer`, `score_increase_main`) are AAC
    // inside the same CAF container, which is a quarter of the download for no
    // cost at all: every effect is decoded into a PCM buffer once in `prepare()`
    // and only ever scheduled from memory afterwards, so nothing here is ever
    // decoded on a busy frame whatever the file holds. Their leading silence was
    // trimmed out of the files themselves rather than skipped at load, so their
    // `lead` is 0.
    private static let effects: [Effect] = [
        Effect(key: "correct",       file: "sfx_correct",        ext: "caf", volume: 0.14, lead: 0.0),
        Effect(key: "wrong",         file: "sfx_wrong",          ext: "caf", volume: 0.11, lead: 0.065),
        // The strike landing on a piece of food, right or wrong, and the
        // wrong answer arriving in the mouth behind it.
        Effect(key: "splash",        file: "splash",             ext: "caf", volume: 0.24, lead: 0.0),
        Effect(key: "wrongAnswer",   file: "wrong_answer",       ext: "caf", volume: 0.087, lead: 0.0),
        // The card flip that opens a round.
        Effect(key: "cardFlip",      file: "sfx_card_flip",      ext: "caf", volume: 0.10, lead: 0.015),
        // The question card turning face up.
        Effect(key: "cardReveal",    file: "sfx_card_reveal",    ext: "caf", volume: 0.19, lead: 0.010),
        // The thick double card appearing, and the doubled score landing.
        Effect(key: "doubleCard",    file: "sfx_double_card",    ext: "caf", volume: 0.18, lead: 0.0),
        Effect(key: "doubleScore",   file: "sfx_double_score",   ext: "caf", volume: 0.15, lead: 0.0),
        // Half a life leaving the HUD when the flamethrower is fired.
        Effect(key: "halfLife",      file: "sfx_half_life",      ext: "caf", volume: 0.12, lead: 0.0),
        Effect(key: "lifeLost",      file: "sfx_life_lost",      ext: "caf", volume: 0.24, lead: 0.045),
        Effect(key: "flamethrower",  file: "sfx_flamethrower",   ext: "caf", volume: 0.31, lead: 0.045),
        Effect(key: "sessionStart",  file: "sfx_session_start",  ext: "caf", volume: 0.16, lead: 0.225),
        Effect(key: "sessionComplete", file: "sfx_level_complete", ext: "caf", volume: 0.10, lead: 0.010),
        Effect(key: "highScore",     file: "sfx_high_score",     ext: "caf", volume: 0.14, lead: 0.025),
        Effect(key: "characterUnlock", file: "sfx_character_unlock", ext: "caf", volume: 0.12, lead: 0.050),
        // The card counters on the result screen and the home header.
        Effect(key: "cardCount",     file: "sfx_card_count",     ext: "caf", volume: 1.0,  lead: 0.065),
        Effect(key: "cardFlight",    file: "sfx_card_flight",    ext: "caf", volume: 0.812, lead: 0.35),
        // The header totals climbing on the menu. The sound runs for as long as
        // the counters do, where the old blip was over before they had started.
        Effect(key: "cardTotal",     file: "score_increase_main", ext: "caf", volume: 0.094, lead: 0.0),
        Effect(key: "select",        file: "sfx_select",         ext: "caf", volume: 0.17, lead: 0.0),
        Effect(key: "switchOn",      file: "sfx_switch_on",      ext: "caf", volume: 0.89, lead: 0.200),
        Effect(key: "switchOff",     file: "sfx_switch_off",     ext: "caf", volume: 1.0,  lead: 0.170)
    ]

    /// True while a level is actually being played (not the menu, the intro/
    /// pause card or the result screen). The music loops everywhere, but plays
    /// louder here; the sums are only spoken while this is true.
    private(set) var isGameplayActive = false

    /// The category options actually applied to the shared session, so
    /// `configureSessionIfNeeded()` only calls `setCategory` when the desired
    /// mix behavior has actually changed.
    private var appliedCategoryOptions: AVAudioSession.CategoryOptions?
    private var sessionActive = false
    /// The music loops continuously: softly in the background on the menus and
    /// cards, a little louder during play, and briefly ducked while a sum is
    /// read so the words stay clearly audible over it. Keep these values in dB
    /// so the intended perceived loudness is explicit; AVAudioPlayer itself
    /// expects a linear gain.
    private let menuMusicVolume: Float = pow(10, -26.0 / 20.0)
    private let gameMusicVolume: Float = pow(10, -16.0 / 20.0)
    private let duckedMusicVolume: Float = pow(10, -31.0 / 20.0)

    /// The volume the music should currently sit at, given where the player is.
    private var currentMusicTarget: Float { isGameplayActive ? gameMusicVolume : menuMusicVolume }

    /// One-time, off-the-main-thread setup so nothing has to be allocated,
    /// decoded or session-activated during play — that first-touch work was
    /// what stuttered the game the first time a sound played.
    private var preparationStarted = false
    private var audioResourcesReady = false
    private var wantsMusicPlayback = false
    /// Audio output waits very briefly after activating the hardware session.
    /// Starting the engine and MP3 decoder in the same instant as that hardware
    /// transition is what can produce a one-off crack on a cold app launch.
    private var sessionOutputReady = false
    private var musicOutputReady = false
    private var sessionStartupToken = 0
    private let sessionSettleDelay: TimeInterval = 0.15
    private let engineToMusicDelay: TimeInterval = 0.10
    private let prepareQueue = DispatchQueue(label: "com.elephantchallenge.audio.prepare", qos: .userInitiated)
    /// Speech is rendered to PCM here. The synthesizer never touches the live
    /// audio output, so enabling spoken sums cannot reconfigure the game route.
    private let speechQueue = DispatchQueue(label: "com.elephantchallenge.audio.speech", qos: .utility)

    // MARK: Voices

    /// Best installed voice per spoken-math language, resolved once. Voice
    /// availability differs by OS version and by voices downloaded in Settings.
    private var voicesByLanguage: [String: AVSpeechSynthesisVoice] = [:]
    @Published private(set) var speechVoicesResolved = false
    private var speechRenderInProgress = false
    /// The very first `AVSpeechSynthesizer.write(_:)` is done once at prepare
    /// time to move its heavy first-use cost off the first level start.
    private var speechWarmedUp = false

    private override init() {
        self.gameSoundsEnabled = GameSettings.gameSoundsEnabled
        self.musicEnabled = GameSettings.musicEnabled
        self.spokenSumsEnabled = GameSettings.spokenSumsEnabled
        super.init()
        registerForInterruptions()
    }

    func toggleGameSounds() {
        gameSoundsEnabled.toggle()
    }

    func toggleMusic() {
        musicEnabled.toggle()
    }

    func toggleSpokenSums() {
        guard isSpokenMathAvailable else { return }
        spokenSumsEnabled.toggle()
    }

    // MARK: - Preparation (called once, up front)

    /// Loads every player and resolves installed voices on a background queue.
    /// Cheap to call repeatedly; only the first call works.
    /// The heavy, blocking bits — file decode, `prepareToPlay`, session
    /// activation — happen here, at a calm moment, not mid-game.
    func prepare() {
        guard !preparationStarted else { return }
        preparationStarted = true
        prepareQueue.async { [weak self] in
            guard let self else { return }
            // AVAudioPlayer's endless loop keeps this single compressed music
            // asset in memory without repeatedly loading or creating players.
            let music = Self.makePlayer(named: "frog_music", loops: -1, volume: 0,
                                        enableRate: true)
            // Decode + lead-trim every effect into a ready-to-schedule PCM buffer
            // here, off the main thread, so play time does no file work at all.
            var buffers: [String: AVAudioPCMBuffer] = [:]
            for effect in Self.effects {
                buffers[effect.key] = Self.makeBuffer(named: effect.file, ext: effect.ext,
                                                      trimLeading: effect.lead)
            }
            // `speechVoices()` can load system voice metadata and take long
            // enough to freeze a live game. Resolve it alongside file decoding.
            let voices = Self.bestVoicesByLanguage()
            DispatchQueue.main.async {
                if self.musicPlayer == nil { self.musicPlayer = music }
                self.installEffectBuffers(buffers)
                self.voicesByLanguage = voices
                self.speechVoicesResolved = true
                self.audioResourcesReady = true
                // Spin the speech synthesizer up now, at this calm menu moment,
                // rather than on the first level start where its first-use cost
                // otherwise lands mid-play (see the method).
                if self.spokenSumsEnabled {
                    let languageCode = LanguageManager.shared.effective.code
                    self.warmUpSpeechSynthesizer(preferred: voices[languageCode])
                }
                self.renderPendingSpeechIfPossible()
                // Only touch the audio session when sound is on, so a muted app
                // never interrupts the user's own audio.
                if self.hasAnyAudioEnabled {
                    self.activateSession()
                    self.startMusicIfReady()
                }
            }
        }
    }

    /// Attaches one player node per effect and wires it to the engine's mixer at
    /// the buffer's own format (the mixer resamples as needed, so effects keep
    /// their native rates). Runs once, on the main thread, after the background
    /// decode; the engine itself is only started when sound is on.
    private func installEffectBuffers(_ buffers: [String: AVAudioPCMBuffer]) {
        for effect in Self.effects where effectBuffers[effect.key] == nil {
            guard let buffer = buffers[effect.key] else { continue }
            effectBuffers[effect.key] = buffer
            let node = AVAudioPlayerNode()
            node.volume = effect.volume
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
            effectNodes[effect.key] = node
        }
        // The session can go active before this background decode finishes — the
        // tutorial starts gameplay immediately, with no start card, so
        // `activateSession()` runs while `effectNodes` is still empty and
        // `startEngineIfNeeded()` skips (nothing to play). Once activated,
        // `activateSession()` short-circuits and never retries, so the engine
        // would stay down and every effect would be silent. Now that the nodes
        // exist, bring the engine up here.
        if sessionOutputReady { startEngineIfNeeded() }
    }

    /// Builds a fully prepared player. Runs the decode/`prepareToPlay` cost on
    /// whatever (background) queue calls it.
    private static func makePlayer(named name: String, ext: String = "m4a",
                                   loops: Int, volume: Float,
                                   enableRate: Bool = false) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.numberOfLoops = loops
        player.volume = volume
        // Rate has to be enabled before the player is prepared, otherwise the
        // decoder is set up without the time-stretch stage and the streak
        // speed-up has to reconfigure it mid-playback.
        player.enableRate = enableRate
        player.prepareToPlay()
        return player
    }

    /// Decodes a sound file into a PCM buffer, dropping `trimLeading` seconds of
    /// leading silence so a scheduled buffer sounds immediately. (The old players
    /// did this by seeking on every play; baking it into the buffer once makes
    /// each trigger free.) Runs on whatever background queue calls it.
    private static func makeBuffer(named name: String, ext: String,
                                   trimLeading: TimeInterval) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let skip = AVAudioFramePosition((trimLeading * format.sampleRate).rounded())
        let start = min(max(0, skip), file.length)
        file.framePosition = start
        let frames = AVAudioFrameCount(file.length - start)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              (try? file.read(into: buffer)) != nil else { return nil }
        return buffer
    }

    /// Starts the effects engine (once) and puts every effect node into its
    /// always-on "playing" state, so a later trigger is a single scheduleBuffer
    /// with nothing to spin up. Requires the session active; a no-op when sound
    /// is off, the engine is already running, or the nodes aren't attached yet.
    private func startEngineIfNeeded() {
        guard gameSoundsEnabled, sessionOutputReady,
              !engine.isRunning, !effectNodes.isEmpty else { return }
        engine.prepare()
        guard (try? engine.start()) != nil else { return }
        for node in effectNodes.values { node.play() }
    }

    /// Stops the effect nodes and the engine (used when going silent or
    /// backgrounding); the attached graph is kept for a later restart.
    private func stopEngine() {
        guard engine.isRunning else { return }
        for node in effectNodes.values { node.stop() }
        engine.stop()
    }

    // MARK: - Audio session

    /// While the game's own background music is off, effects and spoken sums
    /// should not stop music the player has running in another app; while the
    /// game's music is on, it takes over the same way it always has.
    private var desiredCategoryOptions: AVAudioSession.CategoryOptions {
        musicEnabled ? [] : [.mixWithOthers]
    }

    private func configureSessionIfNeeded() {
        let options = desiredCategoryOptions
        guard appliedCategoryOptions != options else { return }
        let session = AVAudioSession.sharedInstance()
        // `.playback` keeps the game audible even with the ring/silent switch
        // set to silent — expected for a game the child is actively playing,
        // and the single in-app switch is the real mute control. `.mixWithOthers`
        // is added only when the game's own music is off, so another app's
        // music keeps playing underneath the game's effects/speech.
        try? session.setCategory(.playback, mode: .default, options: options)
        appliedCategoryOptions = options
    }

    private func activateSession() {
        guard hasAnyAudioEnabled else { return }
        guard audioResourcesReady else {
            prepare()
            return
        }
        guard !sessionActive else {
            if sessionOutputReady {
                startEngineIfNeeded()
                startMusicIfReady()
                playPreparedSpeechIfPossible()
            }
            return
        }
        configureSessionIfNeeded()
        try? AVAudioSession.sharedInstance().setActive(true)
        sessionActive = true
        sessionOutputReady = false
        musicOutputReady = false
        sessionStartupToken += 1
        let token = sessionStartupToken
        DispatchQueue.main.asyncAfter(deadline: .now() + sessionSettleDelay) { [weak self] in
            guard let self, token == self.sessionStartupToken,
                  self.sessionActive, self.hasAnyAudioEnabled else { return }
            self.sessionOutputReady = true
            self.startEngineIfNeeded()
            // Stagger the MP3 decoder behind the now-silent effects engine.
            // This avoids piling two cold output paths onto the first render.
            DispatchQueue.main.asyncAfter(deadline: .now() + self.engineToMusicDelay) {
                guard token == self.sessionStartupToken,
                      self.sessionActive, self.hasAnyAudioEnabled else { return }
                self.musicOutputReady = true
                self.startMusicIfReady()
                self.playPreparedSpeechIfPossible()
            }
        }
    }

    private func deactivateSession() {
        guard sessionActive else { return }
        sessionStartupToken += 1
        sessionOutputReady = false
        musicOutputReady = false
        stopEngine()
        // Let any paused apps (music, podcasts) resume once we go quiet.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionActive = false
    }

    private func deactivateSessionIfUnused() {
        guard !hasAnyAudioEnabled else { return }
        deactivateSession()
    }

    // MARK: - Gameplay lifecycle

    /// Called by the game view as the play field becomes (in)active. The music
    /// keeps looping either way; this only raises it for play and lowers it
    /// back to the soft menu level afterwards, and reads the current sum aloud
    /// on the transition into play.
    func setGameplayActive(_ active: Bool, questionText: String?) {
        let wasActive = isGameplayActive
        isGameplayActive = active
        if active {
            if musicEnabled {
                startMusic()
                setMusicVolume(gameMusicVolume)
            } else if spokenSumsEnabled {
                prepare()
                activateSession()
            }
            // Read the sum the player is looking at the moment play begins.
            if !wasActive, let questionText { speakQuestion(questionText) }
        } else {
            cancelPendingSpeech()
            stopSpeechPlayback()
            setMusicVolume(menuMusicVolume) // keep the loop, just soften it
        }
    }

    // MARK: - Background music

    /// Starts (or resumes) the endless background loop at the volume that suits
    /// the current screen. Safe to call repeatedly.
    func startMusic() {
        guard musicEnabled else { return }
        wantsMusicPlayback = true
        prepare()
        activateSession()
        startMusicIfReady()
    }

    /// Starts only after background decoding and the short session-settle
    /// window. There is intentionally no synchronous cold-load fallback here.
    private func startMusicIfReady() {
        guard musicEnabled, wantsMusicPlayback,
              audioResourcesReady, musicOutputReady else { return }
        guard let player = musicPlayer else { return }
        if !player.isPlaying {
            player.volume = 0
            player.play()
            // A longer cold-start fade is especially important on the home
            // screen: the mastered track must never arrive as a sudden hit.
            player.setVolume(currentMusicTarget, fadeDuration: 2.0)
        } else {
            setMusicVolume(currentMusicTarget)
        }
    }

    private func setMusicVolume(_ volume: Float, fade: TimeInterval = 0.7) {
        musicPlayer?.setVolume(volume, fadeDuration: fade)
    }

    /// The playback rate currently applied to the loop, so a repeated request
    /// for the rate already running is not passed on to the player.
    private var appliedGameplayRate: Float = 1

    /// Keeps the soundtrack in step with the temporary fast streak mode.
    ///
    /// This is called on every state sync — several times per answered sum —
    /// and almost always asks for the rate that is already playing. Writing
    /// `rate` re-times the running decoder, so the guard is what keeps a fast
    /// run of correct answers from re-rating the music on every one of them.
    func setGameplayRate(_ rate: Float) {
        guard let player = musicPlayer else { return }
        let clamped = min(max(rate, 0.5), 2)
        guard clamped != appliedGameplayRate else { return }
        appliedGameplayRate = clamped
        player.rate = clamped
    }

    /// Fades the music out and stops it — used only when sound is switched off
    /// (or paused for backgrounding, via `pause`).
    private func stopMusic() {
        wantsMusicPlayback = false
        guard let player = musicPlayer, player.isPlaying else {
            musicPlayer?.stop()
            deactivateSessionIfUnused()
            return
        }
        player.setVolume(0, fadeDuration: 0.35)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.musicEnabled else { return }
            self.musicPlayer?.stop()
            self.musicPlayer?.currentTime = 0
            self.deactivateSessionIfUnused()
        }
    }

    /// Lower / restore the music around a spoken sum (speech only happens in
    /// play, so it restores to the gameplay level).
    private func duckMusic(_ ducked: Bool) {
        guard let player = musicPlayer, player.isPlaying else { return }
        player.setVolume(ducked ? duckedMusicVolume : currentMusicTarget, fadeDuration: 0.18)
    }

    // MARK: - Sound effects

    // Answers.
    func playCorrect()          { playEffect("correct") }
    func playWrong()            { playEffect("wrong") }
    func playSplash()           { playEffect("splash") }        // the tongue lands on food
    func playWrongAnswer()      { playEffect("wrongAnswer") }   // a wrong answer is swallowed
    func playCardFlip()         { playEffect("cardFlip") }         // a card turns over
    func playCardReveal()       { playEffect("cardReveal") }       // the question becomes visible
    func playDoubleCardAppear() { playEffect("doubleCard") }       // the thick special card
    func playDoubleScore()      { playEffect("doubleScore") }      // a double card paid out
    func playFlamethrower()     { playEffect("flamethrower") }     // the helper fires
    func playHalfLife()         { playEffect("halfLife") }         // half a life spent
    func playLifeLost()         { playEffect("lifeLost") }         // a whole life lost
    func playLifeRestored()     { playEffect("characterUnlock") }  // heart fish caught
    func playSessionStart()     { playEffect("sessionStart") }
    func playSessionComplete()  { playEffect("sessionComplete") }
    func playHighScore()        { playEffect("highScore") }        // new personal best
    func playCharacterUnlock()  { playEffect("characterUnlock") }
    func playCardCount()        { playEffect("cardCount") }        // cards counting up
    func playCardFlight()       { playEffect("cardFlight") }       // cards flying to the total
    func playCardTotal()        { playEffect("cardTotal") }        // grand total ticks up

    func playMenuTap()          { playEffect("select") }
    func playSwitch(on: Bool)   { playEffect(on ? "switchOn" : "switchOff") }

    private func playEffect(_ key: String) {
        guard gameSoundsEnabled else { return }
        prepare()
        activateSession()
        // Preloaded by `prepare()`. If a sound is somehow needed before that
        // finished (rare — play happens well after launch) it's simply skipped;
        // no synchronous file work is ever done on this hot path.
        guard sessionOutputReady,
              let node = effectNodes[key], let buffer = effectBuffers[key] else { return }
        // The node is already running (see `startEngineIfNeeded`); `.interrupts`
        // restarts it from the top with nothing to allocate — the whole trigger
        // is one buffer schedule on the audio render thread, invisible to the
        // frame. The lead trim and volume are already baked in at load time.
        if !node.isPlaying { node.play() }
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    // MARK: - Spoken sums

    /// Bumped on every request so a superseded (debounced) one can bow out.
    private var speechRequestToken = 0
    private struct PendingSpeech {
        let token: Int
        let text: String
        let voice: AVSpeechSynthesisVoice?
        let languageCode: String
    }
    private struct PreparedSpeech {
        let request: PendingSpeech
        let player: AVAudioPlayer
        let fileURL: URL
    }
    private var pendingSpeech: PendingSpeech?
    private var preparedSpeech: PreparedSpeech?
    /// How long to wait after a new sum appears before speaking it. This keeps
    /// the synthesizer's start-up work out of the exact frames where the jump
    /// lands and SpriteKit rebuilds the answer board — the collision that made
    /// the game stutter — and debounces fast consecutive answers to the latest.
    private let speechStartDelay: TimeInterval = 0.3

    /// Requests that a sum such as "3 + 4 = ?" be read in the interface
    /// language. No-op unless that language has both localized math wording and
    /// an installed system voice. Speech is deferred (see `speechStartDelay`).
    func speakQuestion(_ prompt: String) {
        guard spokenSumsEnabled, isGameplayActive else { return }
        let languageCode = LanguageManager.shared.effective.code
        guard let text = Self.spokenText(for: prompt, languageCode: languageCode) else { return }
        guard !text.isEmpty else { return }

        speechRequestToken += 1
        let token = speechRequestToken
        let request = PendingSpeech(token: token, text: text,
                                    voice: voicesByLanguage[languageCode],
                                    languageCode: languageCode)
        // Preparation may still be resolving installed voices. Preserve the
        // latest visible sum until its voice metadata becomes available.
        guard request.voice != nil else {
            if !speechVoicesResolved {
                pendingSpeech = request
                prepare()
            }
            return
        }
        pendingSpeech = request
        scheduleSpeechRender(request)
    }

    /// The first ever `AVSpeechSynthesizer.write(_:)` spins up the synthesizer's
    /// internal audio unit and loads the selected voice — heavy one-off work.
    /// On some iOS versions that first use nudges the shared audio session and
    /// knocks the always-on effects engine over (an
    /// `AVAudioEngineConfigurationChange`), which restarts it with an audible
    /// pop. Doing one throwaway, silent render here — at the menu, before the
    /// first sum is ever spoken — moves that glitch out of the first level start.
    /// Output never reaches the speakers: `write` only fills PCM buffers, which
    /// are discarded. Serialized with real renders on `speechQueue`.
    private func warmUpSpeechSynthesizer(preferred voice: AVSpeechSynthesisVoice?) {
        guard !speechWarmedUp else { return }
        speechWarmedUp = true
        speechQueue.async { [weak self] in
            guard let self else { return }
            let utterance = AVSpeechUtterance(string: "0")
            utterance.voice = voice
            utterance.volume = 0
            self.synthesizer.write(utterance) { _ in }
        }
    }

    private func scheduleSpeechRender(_ request: PendingSpeech) {
        DispatchQueue.main.asyncAfter(deadline: .now() + speechStartDelay) { [weak self] in
            guard let self, request.token == self.speechRequestToken else { return }
            self.renderPendingSpeechIfPossible()
        }
    }

    /// Renders the latest sum to a temporary linear-PCM CAF without using an
    /// audio session. Only the prepared AVAudioPlayer later touches the already
    /// stable game output.
    private func renderPendingSpeechIfPossible() {
        guard spokenSumsEnabled, isGameplayActive,
              !speechRenderInProgress,
              speechPlayer?.isPlaying != true,
              preparedSpeech == nil,
              let pending = pendingSpeech else { return }

        let voice = pending.voice ?? voicesByLanguage[pending.languageCode]
        guard let voice else {
            if speechVoicesResolved { pendingSpeech = nil }
            return
        }

        let request = PendingSpeech(token: pending.token, text: pending.text,
                                    voice: voice, languageCode: pending.languageCode)
        pendingSpeech = request
        speechRenderInProgress = true
        let utterance = AVSpeechUtterance(string: request.text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.pitchMultiplier = 1.05
        utterance.postUtteranceDelay = 0.05

        speechQueue.async { [weak self] in
            self?.renderSpeech(utterance, for: request)
        }
    }

    private func renderSpeech(_ utterance: AVSpeechUtterance, for request: PendingSpeech) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jumping-fox-speech-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        var outputFile: AVAudioFile?
        var renderFailed = false
        var renderCompleted = false

        synthesizer.write(utterance) { [weak self] buffer in
            guard let self else { return }
            guard !renderCompleted else { return }
            guard let pcm = buffer as? AVAudioPCMBuffer else {
                renderFailed = true
                return
            }
            if pcm.frameLength > 0 {
                do {
                    if outputFile == nil {
                        outputFile = try AVAudioFile(forWriting: url,
                                                     settings: pcm.format.settings)
                    }
                    try outputFile?.write(from: pcm)
                } catch {
                    renderFailed = true
                }
                return
            }

            // A zero-frame buffer marks completion. Close the file before the
            // player opens it, then pay decode/prepare costs on this queue too.
            renderCompleted = true
            outputFile = nil
            let player: AVAudioPlayer?
            if renderFailed {
                player = nil
            } else {
                player = try? AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
            }
            DispatchQueue.main.async {
                self.finishSpeechRender(player: player, fileURL: url, request: request)
            }
        }
    }

    private func finishSpeechRender(player: AVAudioPlayer?, fileURL: URL,
                                    request: PendingSpeech) {
        speechRenderInProgress = false
        guard request.token == speechRequestToken,
              spokenSumsEnabled, isGameplayActive,
              let player else {
            removeSpeechFile(fileURL)
            renderPendingSpeechIfPossible()
            return
        }
        preparedSpeech = PreparedSpeech(request: request, player: player, fileURL: fileURL)
        playPreparedSpeechIfPossible()
    }

    private func playPreparedSpeechIfPossible() {
        guard musicOutputReady, spokenSumsEnabled, isGameplayActive,
              speechPlayer?.isPlaying != true,
              let prepared = preparedSpeech else { return }
        guard prepared.request.token == speechRequestToken else {
            preparedSpeech = nil
            removeSpeechFile(prepared.fileURL)
            renderPendingSpeechIfPossible()
            return
        }

        preparedSpeech = nil
        pendingSpeech = nil
        speechPlayer = prepared.player
        speechFileURL = prepared.fileURL
        prepared.player.delegate = self
        // A synthesized CAF can begin with a non-zero waveform. Opening that
        // directly at full scale creates the very audible click that occurred
        // both on the first sum and whenever speech was enabled mid-game.
        // Start at digital silence and ramp across the first few milliseconds.
        prepared.player.volume = 0
        duckMusic(true)
        if prepared.player.play() {
            prepared.player.setVolume(1, fadeDuration: 0.045)
        } else {
            duckMusic(false)
            cleanupSpeechPlayback()
        }
    }

    private func cancelPendingSpeech() {
        speechRequestToken += 1
        pendingSpeech = nil
        if let prepared = preparedSpeech {
            preparedSpeech = nil
            removeSpeechFile(prepared.fileURL)
        }
    }

    private func stopSpeechPlayback() {
        speechPlayer?.stop()
        duckMusic(false)
        cleanupSpeechPlayback()
    }

    private func cleanupSpeechPlayback() {
        speechPlayer = nil
        if let url = speechFileURL {
            speechFileURL = nil
            removeSpeechFile(url)
        }
    }

    private func removeSpeechFile(_ url: URL) {
        speechQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Turns a written sum into speech — just the essential sum, without a
    /// sentence such as “what is”. Kept as an English-compatible overload for
    /// existing callers and focused unit tests.
    ///
    /// Handles every sum the game produces:
    ///   "3 + 4 = ?"        -> "3 plus 4"
    ///   "12 − 5 = ?"       -> "12 minus 5"
    ///   "6 × 7 = ?"        -> "6 times 7"
    ///   "3/4 × 8 = ?"      -> "3 over 4 times 8"
    ///   "1/4 + 1/4 = ?"    -> "1 over 4 plus 1 over 4"
    ///   "25% × 40 = ?"     -> "25 percent of 40"
    ///   "1/2 = ?"          -> "1 over 2"
    ///   "1/2 = ?/4"        -> "1 over 2 is how many over 4"  (unknown on right)
    static func spokenText(for prompt: String) -> String {
        SpokenMath.text(for: prompt, languageCode: "en") ?? ""
    }

    static func spokenText(for prompt: String, languageCode: String) -> String? {
        SpokenMath.text(for: prompt, languageCode: languageCode)
    }

    /// Retained for callers that specifically need the legacy English choice.
    static func bestEnglishVoice() -> AVSpeechSynthesisVoice? {
        bestVoicesByLanguage()["en"] ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Picks the clearest installed voice for each supported language. Apple
    /// identifies Norwegian Bokmål as `nb`, while the app uses the broader
    /// language code `no`, so that one is mapped explicitly. Dutch is pinned
    /// to the Netherlands locale so a higher-quality Belgian voice cannot win.
    private static func bestVoicesByLanguage() -> [String: AVSpeechSynthesisVoice] {
        let novelty: Set<String> = ["Albert", "Bad News", "Bahh", "Bells", "Boing",
                                    "Bubbles", "Cellos", "Wobble", "Fred", "Good News",
                                    "Jester", "Organ", "Superstar", "Trinoids",
                                    "Whisper", "Zarvox", "Junior", "Ralph", "Kathy"]

        func score(_ v: AVSpeechSynthesisVoice) -> Int {
            var s = 0
            switch v.quality {
            case .premium:  s += 300
            case .enhanced: s += 200
            default:        s += 100
            }
            return s
        }

        let installed = AVSpeechSynthesisVoice.speechVoices()
            .filter { !novelty.contains($0.name) }
        var result: [String: AVSpeechSynthesisVoice] = [:]
        for languageCode in SpokenMath.lexicons.keys {
            let voiceCode = languageCode == "no" ? "nb" : languageCode
            let candidates = installed.filter {
                $0.language.split(separator: "-").first.map(String.init) == voiceCode
            }
            let localeCandidates: [AVSpeechSynthesisVoice]
            if languageCode == "nl" {
                localeCandidates = candidates.filter { $0.language == "nl-NL" }
            } else {
                localeCandidates = candidates
            }
            if let best = localeCandidates.max(by: { score($0) < score($1) }) {
                result[languageCode] = best
            }
        }
        return result
    }

    // MARK: - Interruptions & backgrounding

    private func registerForInterruptions() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleInterruption(_:)),
                           name: AVAudioSession.interruptionNotification, object: nil)
        // A route change (headphones plugged/unplugged, etc.) stops the engine;
        // this brings it back so effects keep working afterwards.
        center.addObserver(self, selector: #selector(handleEngineConfigurationChange),
                           name: .AVAudioEngineConfigurationChange, object: engine)
#if canImport(UIKit)
        center.addObserver(self, selector: #selector(appWillResignActive),
                           name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidBecomeActive),
                           name: UIApplication.didBecomeActiveNotification, object: nil)
#endif
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            musicPlayer?.pause()
            stopSpeechPlayback()
            // The system deactivates our session and stops the engine; mirror
            // that so `ended` can cleanly reactivate and bring the effects back.
            sessionStartupToken += 1
            sessionOutputReady = false
            musicOutputReady = false
            sessionActive = false
            stopEngine()
        case .ended:
            if let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                prepare()
                activateSession()
                startMusic()
            }
        @unknown default:
            break
        }
    }

    /// The route/config changed and stopped the engine; restart it in place.
    @objc private func handleEngineConfigurationChange() {
        DispatchQueue.main.async { [weak self] in self?.startEngineIfNeeded() }
    }

    @objc private func appWillResignActive() {
        musicPlayer?.pause()
        stopSpeechPlayback()
        sessionStartupToken += 1
        sessionOutputReady = false
        musicOutputReady = false
        sessionActive = false
        stopEngine()
    }

    @objc private func appDidBecomeActive() {
        // Restore the shared output even in speech-only mode. Music/effects
        // remain independently governed by `gameSoundsEnabled`.
        prepare()
        activateSession()
        startMusic()
        startEngineIfNeeded()
    }
}

// MARK: - Rendered speech playback delegate

extension AppAudio: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self, weak player] in
            guard let self, let player, player === self.speechPlayer else { return }
            self.duckMusic(false)
            self.cleanupSpeechPlayback()
            self.renderPendingSpeechIfPossible()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { [weak self, weak player] in
            guard let self, let player, player === self.speechPlayer else { return }
            self.duckMusic(false)
            self.cleanupSpeechPlayback()
            self.renderPendingSpeechIfPossible()
        }
    }
}
