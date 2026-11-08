import AVFoundation
import Observation

/// Plays one radio clip at a time. Starting another clip, reaching the end, or a failed download stops the
/// current one, so the feed never has two drivers talking over each other.
@MainActor @Observable
final class TeamRadioPlayer {
    private(set) var playingID: String?
    /// 0...1 through the playing clip.
    private(set) var progress = 0.0
    private(set) var failedID: String?
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var audioSessionActive = false

    func toggle(_ radio: TeamRadio) {
        if playingID == radio.id { stop(); return }
        guard let url = radio.playbackURL else { return }
        stop()
        failedID = nil
        #if os(iOS)
        // Radio is spoken audio the user asked for, so it plays even with the silent switch on.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        audioSessionActive = (try? AVAudioSession.sharedInstance().setActive(true)) != nil
        #endif
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        playingID = radio.id
        progress = 0
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, let duration = self.player?.currentItem?.duration.seconds, duration.isFinite, duration > 0 else { return }
                self.progress = min(max(time.seconds / duration, 0), 1)
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                guard let self, self.playingID == radio.id else { return }
                self.stop()
                self.failedID = radio.id
            }
        }
        player.play()
    }

    func stop() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        statusObservation = nil
        timeObserver = nil
        endObserver = nil
        player?.pause()
        player = nil
        playingID = nil
        progress = 0
        #if os(iOS)
        // Let the user's music or podcast resume once the clip is over.
        if audioSessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioSessionActive = false
        }
        #endif
    }
}
