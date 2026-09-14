import AVFoundation
import Foundation

/// T1.13: audio announcement at each km boundary (product-spec.md §4.13) — a protocol so `RunViewModel` can
/// inject a spy in tests instead of driving a real `AVSpeechSynthesizer`.
protocol AudioCueAnnouncing {
    func announce(kmNumber: Int, paceSecPerKm: Double)
}

/// Speaks "Kilometer N, pace M:SS per kilometer" via `AVSpeechSynthesizer` — content is exact (km number AND
/// current pace, product-spec §4.13 AC1), not just a chime. `.playback` + `.duckOthers` (not `.ambient`,
/// tech-spec.md §5.3 — `.ambient` cannot play in background at all), configured once on first use so an
/// announcement still speaks with the screen locked (`UIBackgroundModes` gained `audio`, alongside `location`).
final class AudioCueService: AudioCueAnnouncing {
    /// Persisted globally (not per-run) — toggling off must suppress this run AND every subsequent run until
    /// re-enabled (T1.13 DoD), so this can't live on a `RunViewModel` instance, which doesn't survive a run.
    static let enabledDefaultsKey = "audioCuesEnabled"

    private let userDefaults: UserDefaults
    private let speak: (String) -> Void
    /// Held here, not created per-call — a synthesizer deallocated mid-utterance would cut the speech off.
    private let synthesizer = AVSpeechSynthesizer()
    private var audioSessionConfigured = false

    init(userDefaults: UserDefaults = .standard, speak: ((String) -> Void)? = nil) {
        self.userDefaults = userDefaults
        if let speak {
            self.speak = speak
        } else {
            let synthesizer = synthesizer
            self.speak = { text in synthesizer.speak(AVSpeechUtterance(string: text)) }
        }
    }

    /// Defaults to `true` (on by first run) — `object(forKey:)` distinguishes "never set" from an explicit
    /// `false`, unlike `bool(forKey:)` which can't tell the two apart.
    var isEnabled: Bool {
        get { userDefaults.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true }
        set { userDefaults.set(newValue, forKey: Self.enabledDefaultsKey) }
    }

    func announce(kmNumber: Int, paceSecPerKm: Double) {
        guard isEnabled else { return }
        configureAudioSessionIfNeeded()
        speak(Self.announcementText(kmNumber: kmNumber, paceSecPerKm: paceSecPerKm))
    }

    static func announcementText(kmNumber: Int, paceSecPerKm: Double) -> String {
        let totalSeconds = Int(paceSecPerKm.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "Kilometer \(kmNumber). Pace \(minutes) minute \(seconds) second per kilometer."
    }

    private func configureAudioSessionIfNeeded() {
        guard !audioSessionConfigured else { return }
        audioSessionConfigured = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}
