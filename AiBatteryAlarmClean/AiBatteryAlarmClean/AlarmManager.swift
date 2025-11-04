import Foundation
import AVFoundation
import MediaPlayer
import AudioToolbox

class AlarmManager {
    static let shared = AlarmManager()

    private var audioPlayer: AVAudioPlayer? // For default sounds
    private var musicPlayer: AVPlayer?      // For custom music
    private var currentSongUrl: URL?        // Store the custom song URL

    private init() {
        print("🔧 AlarmManager initialized with AVPlayer support")
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            print("✅ Audio session configured for playback")
        } catch {
            print("❌ Failed to setup audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Custom Music Management
    func setCustomAlarmSong(url: URL) {
        currentSongUrl = url
        print("🎵 Custom alarm song URL stored: \(url)")
    }

    func startAlarm() {
        print("🔊 Starting alarm - checking for custom music")
        
        // If custom music is already playing, don't restart it
        if musicPlayer != nil && musicPlayer?.rate != 0 {
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
        playDefaultAlarmSound()
    }

    private func playCustomMusic(url: URL) {
        print("🎵 Playing custom music from: \(url)")
        
        // Stop any currently playing sounds first
        stopAlarm()
        
        // Create a new AVPlayer with the song URL
        let playerItem = AVPlayerItem(url: url)
        musicPlayer = AVPlayer(playerItem: playerItem)
        
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
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        print("✅ Custom music alarm started with vibration")
    }

    private func playDefaultAlarmSound() {
        guard let url = Bundle.main.url(forResource: "alarm_sound", withExtension: "mp3") else {
            print("❌ alarm_sound.mp3 not found in bundle")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1 // Loop indefinitely
            audioPlayer?.volume = 0.8
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            print("✅ Default alarm started and vibration triggered")
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
