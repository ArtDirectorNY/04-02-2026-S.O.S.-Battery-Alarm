// AlarmManager.swift
import Foundation
import UIKit
import CoreHaptics
import AVFoundation
import MediaPlayer
import AudioToolbox

class AlarmManager: NSObject {
    static let shared = AlarmManager()

    private var audioPlayer: AVAudioPlayer? // For default sounds
    private var musicPlayer: AVPlayer?      // For custom music
    private var previewPlayer: AVAudioPlayer? // For one-shot previews
    private var currentSongUrl: URL?        // Store the custom song URL
    private var alarmVolume: Float = 1.0    // App alarm volume (0.0 - 1.0)

    // Track if we have added the KVO observer (safe removal)
    private var observingSystemVolume: Bool = false

    // Track current system/device output volume (observed)
    private var systemVolume: Float = AVAudioSession.sharedInstance().outputVolume

    // Core Haptics engine (lazily created when needed)
    @available(iOS 13.0, *)
    private var hapticEngine: CHHapticEngine?

    private override init() {
        super.init()
        print("🔧 AlarmManager initialized with AVPlayer support")
        setupAudioSession()

        // Restore persisted alarm volume if present
        if let stored = UserDefaults.standard.object(forKey: "alarmVolume") as? Double {
            alarmVolume = Float(max(0.0, min(1.0, stored)))
            print("🔊 AlarmManager: restored alarmVolume = \(alarmVolume)")
        }

        // Start observing device/system output volume
        startObservingSystemVolume()
    }

    deinit {
        stopObservingSystemVolume()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            // Refresh local snapshot
            systemVolume = AVAudioSession.sharedInstance().outputVolume
            print("✅ Audio session configured for playback (systemVolume=\(systemVolume))")
        } catch {
            print("❌ Failed to setup audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - System Volume Observation / Vibration Helpers

    // Prepare a reusable CHHapticEngine if the device supports Core Haptics.
    private func prepareHapticsIfNeeded() {
        if #available(iOS 13.0, *) {
            let caps = CHHapticEngine.capabilitiesForHardware()
            guard caps.supportsHaptics else {
                // Device doesn't support Core Haptics
                return
            }
            // Lazily create and start engine if not already prepared
            if hapticEngine == nil {
                do {
                    hapticEngine = try CHHapticEngine()
                    // Try to start it (best-effort). If start throws, nil it out.
                    try hapticEngine?.start()
                    print("📳 AlarmManager: CHHapticEngine prepared")
                } catch {
                    print("📳 AlarmManager: CHHapticEngine prepare error: \(error.localizedDescription)")
                    hapticEngine = nil
                }
            }
        }
    }

    // Stop and release the CHHapticEngine if we created one
    private func stopHapticsEngineIfNeeded() {
        if #available(iOS 13.0, *) {
            if let engine = hapticEngine {
                // stop(completionHandler:) is the appropriate API
                engine.stop(completionHandler: nil)
                hapticEngine = nil
                print("📳 AlarmManager: CHHapticEngine stopped")
            }
        }
    }

    private func startObservingSystemVolume() {
        guard !observingSystemVolume else { return }
        let session = AVAudioSession.sharedInstance()
        session.addObserver(self, forKeyPath: "outputVolume", options: [.new, .initial], context: nil)
        systemVolume = session.outputVolume
        observingSystemVolume = true
        print("📟 AlarmManager: started observing systemVolume (initial = \(systemVolume))")
    }

    private func stopObservingSystemVolume() {
        guard observingSystemVolume else { return }
        let session = AVAudioSession.sharedInstance()
        session.removeObserver(self, forKeyPath: "outputVolume")
        observingSystemVolume = false
        print("📟 AlarmManager: stopped observing systemVolume")
    }

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        if keyPath == "outputVolume" {
            if let newVal = (change?[.newKey] as? NSNumber)?.floatValue {
                systemVolume = newVal
                print("📟 AlarmManager: observed systemVolume change -> \(systemVolume)")

                // If an alarm is currently active (native), re-evaluate vibration
                let nativeAlarmPlaying = (audioPlayer?.isPlaying == true) || (musicPlayer?.rate != 0)
                if nativeAlarmPlaying {
                    triggerVibrationIfNeeded()
                }
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    // Decide if vibration should occur: when either app alarmVolume OR systemVolume is below threshold
    private func shouldVibrateForCurrentVolumes(threshold: Float = 0.5) -> Bool {
        return alarmVolume < threshold || systemVolume < threshold
    }

    // Trigger a short vibration if criteria met (prefer CoreHaptics, then UIFeedbackGenerator, then AudioServices)
    private func triggerVibrationIfNeeded() {
        guard shouldVibrateForCurrentVolumes() else { return }

        // Always run haptics on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 1) Try Core Haptics (iOS 13+). Prefer a prepared engine if available.
            if #available(iOS 13.0, *) {
                let caps = CHHapticEngine.capabilitiesForHardware()
                if caps.supportsHaptics {
                    // Ensure engine exists (prepare if needed)
                    self.prepareHapticsIfNeeded()

                    if let engine = self.hapticEngine {
                        do {
                            // Create a short transient pattern and play it on the prepared engine
                            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9)
                            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
                            let pattern = try CHHapticPattern(events: [event], parameters: [])
                            let player = try engine.makePlayer(with: pattern)
                            try player.start(atTime: 0)
                            // Stop the player after the transient finishes (use stop(atTime:) with a 0 argument)
                            DispatchQueue.global().asyncAfter(deadline: .now() + 0.35) {
                                try? player.stop(atTime: 0)
                            }
                            print("📳 AlarmManager: CHHapticEngine vibration triggered (alarmVolume=\(self.alarmVolume), systemVolume=\(self.systemVolume))")
                            return
                        } catch {
                            print("📳 AlarmManager: CHHapticEngine play error: \(error.localizedDescription) — falling back")
                            // fall through to next option
                        }
                    }
                }
            }

            // 2) Try UIFeedbackGenerator (iOS 10+). Use a quick double pulse to increase noticeability on faint devices.
            if #available(iOS 10.0, *) {
                let generator = UINotificationFeedbackGenerator()
                generator.prepare()
                generator.notificationOccurred(.warning)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    generator.notificationOccurred(.warning)
                }
                print("📳 AlarmManager: UIFeedbackGenerator vibration triggered (alarmVolume=\(self.alarmVolume), systemVolume=\(self.systemVolume))")
                return
            }

            // 3) Fallback to classic vibration for very old devices / OS — do two quick pulses
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
            print("📳 AlarmManager: AudioServicesPlaySystemSound vibration triggered (alarmVolume=\(self.alarmVolume), systemVolume=\(self.systemVolume))")
        }
    }

    // MARK: - Custom Music Management
    func setCustomAlarmSong(url: URL) {
        currentSongUrl = url
        print("🎵 Custom alarm song URL stored: \(url)")
    }

    // Set the in-app alarm volume (0.0 - 1.0)
    func setAlarmVolume(_ normalized: Double) {
        let v = Float(max(0.0, min(1.0, normalized)))
        alarmVolume = v

        // Persist the chosen volume
        UserDefaults.standard.set(Double(v), forKey: "alarmVolume")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let ap = self.audioPlayer {
                ap.volume = v
            }
            if let mp = self.musicPlayer {
                mp.volume = v
            }
            print("🔊 AlarmManager: alarmVolume set to \(v)")

            // If native alarm is playing, re-evaluate vibration now that app volume changed
            let nativeAlarmPlaying = (self.audioPlayer?.isPlaying == true) || (self.musicPlayer?.rate != 0)
            if nativeAlarmPlaying {
                self.triggerVibrationIfNeeded()
            }
        }
    }

    // Public accessor so other modules (PromoWebView) can query the current app alarm volume (0.0 - 1.0)
    func currentAlarmVolume() -> Double {
        return Double(alarmVolume)
    }

    // Play a bundled default sound by logical name via native playback (honors alarmVolume)
    // Returns true if native playback started, false if resource missing or playback failed.
    func playDefault(named: String) -> Bool {
        // Map logical name -> resource filename (without extension)
        let mapping: [String: String] = [
            "default": "beep_short",    // use bundled beep_short.mp3 as the default short beep
            "slide_whistle": "slide_whistle",
            "alarm_clock": "alarm_clock",
            "boing": "cartoon_boing"
        ]

        guard let resource = mapping[named] else {
            print("❌ playDefault: no mapping for name '\(named)'")
            return false
        }

        guard let url = Bundle.main.url(forResource: resource, withExtension: "mp3") else {
            print("❌ playDefault: resource '\(resource).mp3' not found in bundle")
            return false
        }

        // Stop any current playback first
        stopAlarm()

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.volume = alarmVolume
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            // Vibrate only when volumes indicate it (app OR device below threshold)
            if shouldVibrateForCurrentVolumes() {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }

            print("✅ playDefault: playing '\(named)' as '\(resource).mp3' at volume \(alarmVolume)")
            return true
        } catch {
            print("❌ playDefault: failed to play '\(resource).mp3' - \(error.localizedDescription)")
            return false
        }
    }

    /// Play a short (one-shot) preview of the named bundled sound at current app alarmVolume.
    /// Returns true if native preview started, false if native resource missing (caller can fallback to page audio).
    func previewDefault(named: String) -> Bool {
        // Map logical name -> resource filename (without extension)
        let mapping: [String: String] = [
            "default": "beep_short",    // use bundled beep_short.mp3 as the default short beep
            "slide_whistle": "slide_whistle",
            "alarm_clock": "alarm_clock",
            "boing": "cartoon_boing"
        ]

        guard let resource = mapping[named] else {
            print("❌ previewDefault: no mapping for name '\(named)'")
            return false
        }

        guard let url = Bundle.main.url(forResource: resource, withExtension: "mp3") else {
            print("❌ previewDefault: resource '\(resource).mp3' not found in bundle")
            return false
        }

        // Stop any preview already running
        previewPlayer?.stop()
        previewPlayer = nil

        do {
            previewPlayer = try AVAudioPlayer(contentsOf: url)
            previewPlayer?.numberOfLoops = 0
            previewPlayer?.volume = alarmVolume
            previewPlayer?.prepareToPlay()
            previewPlayer?.play()
            print("▶️ previewDefault: playing '\(named)' once at volume \(alarmVolume)")

            // Stop and release after ~3 seconds (preview duration)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self else { return }
                self.previewPlayer?.stop()
                self.previewPlayer = nil
                print("⏹️ previewDefault: stopped preview for '\(named)'")
            }
            return true
        } catch {
            print("❌ previewDefault: failed to play '\(resource).mp3' - \(error.localizedDescription)")
            previewPlayer = nil
            return false
        }
    }

    func startAlarm() {
        print("🔊 Starting alarm - checking for custom music")

        // If custom music is already playing, don't restart it
        if let mp = musicPlayer, mp.rate != 0 {
            print("🎵 Custom music already playing - skipping restart")
            return
        }

        // If default alarm is already playing, don't restart it
        if let player = audioPlayer, player.isPlaying {
            print("🔊 Default alarm already playing - skipping restart")
            return
        }

        // First, try to play custom music if available
        if let songUrl = currentSongUrl {
            print("🎵 Attempting to play custom music: \(songUrl)")
            playCustomMusic(url: songUrl)
            return
        }

        // Fall back to the default alarm sound
        print("🔊 No custom music, playing default alarm")
        _ = playDefault(named: "default")
    }

    private func playCustomMusic(url: URL) {
        print("🎵 Playing custom music from: \(url)")

        // Stop any currently playing sounds first
        stopAlarm()

        // Create a new AVPlayer with the song URL
        let playerItem = AVPlayerItem(url: url)
        musicPlayer = AVPlayer(playerItem: playerItem)
        musicPlayer?.volume = alarmVolume

        // Enable endless looping
        musicPlayer?.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                               object: playerItem,
                                               queue: .main) { [weak self] _ in
            print("🎵 Custom music looped")
            self?.musicPlayer?.seek(to: .zero)
            self?.musicPlayer?.play()
        }

        // Start playback
        musicPlayer?.play()

        // Vibrate conditionally
        if shouldVibrateForCurrentVolumes() {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }

        print("✅ Custom music alarm started" + (shouldVibrateForCurrentVolumes() ? " with vibration" : ""))
    }

    private func playDefaultAlarmSound() {
        // kept for backward compatibility; prefer playDefault(named:)
        guard let url = Bundle.main.url(forResource: "alarm_sound", withExtension: "mp3") else {
            print("❌ alarm_sound.mp3 not found in bundle")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1 // Loop indefinitely
            audioPlayer?.volume = alarmVolume
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            if shouldVibrateForCurrentVolumes() {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }

            print("✅ Default alarm started" + (shouldVibrateForCurrentVolumes() ? " and vibration triggered" : "") + " (volume: \(alarmVolume))")
        } catch {
            print("❌ Failed to play default alarm: \(error.localizedDescription)")
        }
    }

    func stopAlarm() {
        print("🛑 Stop alarm requested")

        // Only stop if actually playing
        if let player = musicPlayer, player.rate != 0 {
            player.pause()
            print("🛑 Custom music alarm stopped")
        }

        if let player = audioPlayer, player.isPlaying {
            player.stop()
            print("🛑 Default alarm stopped")
        }

        // Don't nil out the players, just pause them
        // This allows us to resume without reloading

        // Remove notification observer only if we have a music player
        if musicPlayer != nil {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        }
    }
}
