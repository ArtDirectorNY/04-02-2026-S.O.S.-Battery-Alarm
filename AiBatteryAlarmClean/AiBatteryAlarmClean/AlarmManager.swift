// AlarmManager.swift
import Foundation
import UIKit
import CoreHaptics
import AVFoundation
import MediaPlayer
import AudioToolbox
import UserNotifications

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

    // Haptics availability tracking: when an attempt to start the engine fails we avoid
    // retrying continuously and will wait 'hapticRetryInterval' seconds before retrying.
    private var hapticsUnavailableUntil: Date?
    private let hapticRetryInterval: TimeInterval = 10.0

    // A cancelable work item used to delay stopping the CHHapticEngine so short cycles
    // of start/stop don't thrash the haptics service.
    private var hapticStopWorkItem: DispatchWorkItem?

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
    // Uses a short retry cooldown to avoid repeating failing attempts rapidly.
    private func prepareHapticsIfNeeded() {
        if #available(iOS 13.0, *) {
            let caps = CHHapticEngine.capabilitiesForHardware()
            guard caps.supportsHaptics else {
                // Device doesn't support Core Haptics
                return
            }

            // If we've recently seen a failing attempt, skip until cooldown expires
            if let until = hapticsUnavailableUntil, Date() < until {
                // Silently skip attempting to re-create the engine until cooldown expires.
                return
            }

            // Lazily create and start engine if not already prepared
            if hapticEngine == nil {
                do {
                    hapticEngine = try CHHapticEngine()
                    // Try to start it (best-effort). If start throws, nil it out.
                    try hapticEngine?.start()
                    // Cancel any previously scheduled stop — we successfully started
                    hapticStopWorkItem?.cancel()
                    hapticStopWorkItem = nil
                    hapticsUnavailableUntil = nil
                    print("📳 AlarmManager: CHHapticEngine prepared")
                } catch {
                    // Record a cooldown so we don't hammer the haptics service repeatedly.
                    hapticEngine = nil
                    hapticsUnavailableUntil = Date().addingTimeInterval(hapticRetryInterval)
                    print("📳 AlarmManager: CHHapticEngine prepare failed — will retry in \(Int(hapticRetryInterval))s")
                }
            }
        }
    }

    // Stop and release the CHHapticEngine if we created one (delayed/cancelable to reduce churn)
    private func stopHapticsEngineIfNeeded() {
        if #available(iOS 13.0, *) {
            // Cancel any previously-scheduled stop (we'll reschedule)
            hapticStopWorkItem?.cancel()

            // Schedule a delayed stop so quick restart cycles avoid tearing down the engine.
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if let engine = self.hapticEngine {
                    engine.stop(completionHandler: nil)
                    self.hapticEngine = nil
                    print("📳 AlarmManager: CHHapticEngine stopped (delayed)")
                }
            }
            hapticStopWorkItem = work
            // 4 seconds is a compromise: short enough not to leak resources, long enough to avoid rapid thrash.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
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
    // Uses hapticsUnavailableUntil to avoid repeated failing attempts.
    private func triggerVibrationIfNeeded() {
        guard shouldVibrateForCurrentVolumes() else { return }

        // Always run haptics on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 1) Try Core Haptics (iOS 13+). Prefer a prepared engine if available and not in cooldown.
            if #available(iOS 13.0, *) {
                let caps = CHHapticEngine.capabilitiesForHardware()
                if caps.supportsHaptics {
                    // Ensure engine exists (prepare if needed)
                    self.prepareHapticsIfNeeded()

                    // If engine unavailable (due to cooldown), fall through quietly to other options
                    if let engine = self.hapticEngine {
                        do {
                            // Create a short transient pattern and play it on the prepared engine
                            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9)
                            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
                            let pattern = try CHHapticPattern(events: [event], parameters: [])
                            let player = try engine.makePlayer(with: pattern)
                            try player.start(atTime: 0)
                            // Stop the player after the transient finishes
                            DispatchQueue.global().asyncAfter(deadline: .now() + 0.35) {
                                try? player.stop(atTime: 0)
                            }
                            // Successful play - do a minimal log
                            print("📳 AlarmManager: CHHapticEngine vibration triggered")
                            return
                        } catch {
                            // Mark a short cooldown to avoid repeated failing attempts and fall back
                            self.hapticEngine = nil
                            self.hapticsUnavailableUntil = Date().addingTimeInterval(self.hapticRetryInterval)
                            print("📳 AlarmManager: CHHapticEngine play failed — using fallback haptics (retry in \(Int(self.hapticRetryInterval))s)")
                            // fall through to UIFeedbackGenerator fallback
                        }
                    }
                }
            }

            // 2) UIFeedbackGenerator fallback (iOS 10+)
            if #available(iOS 10.0, *) {
                let generator = UINotificationFeedbackGenerator()
                generator.prepare()
                generator.notificationOccurred(.warning)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    generator.notificationOccurred(.warning)
                }
                print("📳 AlarmManager: UIFeedbackGenerator vibration triggered")
                return
            }

            // 3) Classic vibration fallback
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
            print("📳 AlarmManager: classic vibration triggered")
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
        // Safety: if the device is charging and the battery is at-or-below the configured low threshold,
        // suppress playing the native alarm sound/vibration. This prevents alarm noise while the device is charging.
        let deviceLevel = UIDevice.current.batteryLevel
        let deviceState = UIDevice.current.batteryState
        let storedLow = Float(UserDefaults.standard.object(forKey: "lowThreshold") as? Double ?? 0.20)
        if deviceLevel >= 0 && (deviceState == .charging || deviceState == .full) && deviceLevel <= storedLow {
            print("⛔ playDefault suppressed: device charging and battery \(Int(deviceLevel * 100))% <= lowThreshold \(Int(storedLow * 100))%")
            // Ensure any existing audio/haptics are stopped
            stopAlarm()
            return false
        }

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

    // MARK: - Local Notifications for Background Alarms
    private let repeatingNotificationIdentifier = "alarm.repeating"

    private func scheduleRepeatingLocalNotification(batteryLevel: Int, message: String? = nil) {
        // Diagnostic origin log so we can trace repeating notifications to AlarmManager
        print("AlarmManager: scheduleRepeatingLocalNotification called (origin=AlarmManager) for battery:\(batteryLevel)%")

        let center = UNUserNotificationCenter.current()
        // Check authorization status first (best-effort)
        center.getNotificationSettings { settings in
            // Diagnostic: print full settings so we can verify whether alerts/sound/banners are allowed
            print("ℹ️ UNNotificationSettings - auth:\(settings.authorizationStatus.rawValue) alert:\(settings.alertSetting.rawValue) sound:\(settings.soundSetting.rawValue) badge:\(settings.badgeSetting.rawValue) lockScreen:\(settings.lockScreenSetting.rawValue) notificationCenter:\(settings.notificationCenterSetting.rawValue) criticalAlert:\(settings.criticalAlertSetting.rawValue) showPreviews:\(settings.showPreviewsSetting.rawValue)")
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                // Not authorized — nothing to do
                print("❗ scheduleRepeatingLocalNotification: notifications not authorized")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "🔋 Battery High!"
            // Use explicit message when provided; otherwise fallback to battery percent
            content.body = message ?? "Battery is at \(batteryLevel)%"
            content.sound = UNNotificationSound.default

            // 1) Long-term repeating trigger at 60s (system repeats require >= 60s)
            let repeatingTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: true)
            let repeatingRequest = UNNotificationRequest(identifier: self.repeatingNotificationIdentifier, content: content, trigger: repeatingTrigger)

            center.add(repeatingRequest) { error in
                if let error = error {
                    print("❌ scheduleRepeatingLocalNotification repeating add error: \(error.localizedDescription)")
                } else {
                    print("✅ Background notification scheduled (repeating every 60s) for battery: \(batteryLevel)%")
                }
            }

            // 2) Immediate one-shot notification to force a banner right away (~1s)
            let immediateContent = UNMutableNotificationContent()
            immediateContent.title = content.title
            immediateContent.body = content.body
            immediateContent.sound = content.sound

            let immediateTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
            let immediateRequest = UNNotificationRequest(identifier: self.repeatingNotificationIdentifier + ".now", content: immediateContent, trigger: immediateTrigger)

            center.add(immediateRequest) { err in
                if let err = err {
                    print("❌ scheduleRepeatingLocalNotification immediate add error: \(err.localizedDescription)")
                } else {
                    print("✅ Immediate background notification scheduled for battery: \(batteryLevel)%")
                }
            }

            // 3) Schedule a small set of fallback one-shot notifications at 60s intervals (next 5 occurrences).
            // These use distinct identifiers so they are not removed by the simple repeating-identifier removal.
            let occurrences = 5
            for i in 1...occurrences {
                let delay = TimeInterval(60 * i)
                let id = "\(self.repeatingNotificationIdentifier).once.\(i)"
                let oneShotTrigger = UNTimeIntervalNotificationTrigger(timeInterval: max(2.0, delay), repeats: false)
                let oneShotRequest = UNNotificationRequest(identifier: id, content: immediateContent, trigger: oneShotTrigger)
                center.add(oneShotRequest) { err in
                    if let err = err {
                        print("❌ scheduleRepeatingLocalNotification one-shot add error (i=\(i)): \(err.localizedDescription)")
                    } else {
                        print("✅ One-shot background notification scheduled at +\(Int(delay))s for battery: \(batteryLevel)% (id=\(id))")
                    }
                }
            }
        }
    }

    private func cancelRepeatingLocalNotification() {
        let center = UNUserNotificationCenter.current()

        // Build the list of identifiers we may have added so we can remove them all.
        var ids: [String] = [repeatingNotificationIdentifier,
                             repeatingNotificationIdentifier + ".now"]

        // Add the one-shot ids we schedule (once.1 .. once.5)
        for i in 1...5 {
            ids.append("\(repeatingNotificationIdentifier).once.\(i)")
        }

        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        print("🛑 Repeating background notification cancelled (ids removed: \(ids.count))")
    }

    func startAlarm() {
        // If device is charging and battery <= low threshold, suppress starting the alarm.
        let deviceLevel = UIDevice.current.batteryLevel
        let deviceState = UIDevice.current.batteryState
        let storedLow = Float(UserDefaults.standard.object(forKey: "lowThreshold") as? Double ?? 0.20)
        if deviceLevel >= 0 && (deviceState == .charging || deviceState == .full) && deviceLevel <= storedLow {
            print("⛔ startAlarm suppressed: device charging and battery \(Int(deviceLevel * 100))% <= lowThreshold \(Int(storedLow * 100))%")
            // Ensure we are not currently playing
            stopAlarm()
            return
        }

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

        // Fall back to the preferred default alarm sound (persisted from JS selection)
        let preferred = UserDefaults.standard.string(forKey: "preferredAlarmSound") ?? "default"
        let soundToPlay = (preferred == "custom") ? "default" : preferred

        print("🔊 No custom music, playing preferred alarm: \(soundToPlay)")
        let started = playDefault(named: soundToPlay)
        if started {
            // Schedule repeating native notifications while alarm is active.
            // We schedule an immediate one-shot and a 60s repeating trigger. Message set for HIGH.
            let percent = Int(deviceLevel * 100)
            let highMessage = "Sufficiently charged (per your settings). Unplug the device. (Battery: \(percent)%)"
            scheduleRepeatingLocalNotification(batteryLevel: percent, message: highMessage)
        }
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

        // Stop custom music if playing
        if let player = musicPlayer, player.rate != 0 {
            player.pause()
            print("🛑 Custom music alarm stopped")
        }

        // Stop default/native audio if playing
        if let player = audioPlayer, player.isPlaying {
            player.stop()
            print("🛑 Default alarm stopped")
        }

        // Stop any preview playback
        if let pp = previewPlayer, pp.isPlaying {
            pp.stop()
            previewPlayer = nil
            print("⏹️ Preview stopped")
        }

        // Stop and release haptics engine if we created one
        stopHapticsEngineIfNeeded()

        // Cancel any repeating background notifications scheduled for this alarm
        cancelRepeatingLocalNotification()

        // Remove AVPlayer loop observer (safe to call even if none)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)

        // Note: keep player objects around (not nil'ing) so UI/resume behavior remains fast.
    }
}


