//
//  AudioPlayerService.swift
//  Ramble
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioPlayerService: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(url: URL) {
        stop()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        self.player = player
        player.delegate = self
        player.prepareToPlay()
        duration = player.duration
        currentTime = 0
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            pause()
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
        updateCurrentTime()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        stopTimer()
        currentTime = 0
        duration = 0
    }

    func seek(to fraction: Double) {
        guard let player else { return }
        let time = fraction * player.duration
        player.currentTime = time
        currentTime = time
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCurrentTime()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateCurrentTime() {
        currentTime = player?.currentTime ?? 0
    }
}

extension AudioPlayerService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.stopTimer()
            self.currentTime = 0
            player.currentTime = 0
        }
    }
}
