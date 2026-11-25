//
//  NowPlayingController.swift
//  Tempo
//

import MediaPlayer
import UIKit

/// Lock screen / Control Center integration: play and pause from the lock
/// screen, and show the current tempo on the Now Playing card.
final class NowPlayingController {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onToggle: (() -> Void)?

    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()

    init() {
        configureCommands()
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    func update(isPlaying: Bool, bpm: Double, timeSignature: String, title: String) {
        guard isPlaying else {
            infoCenter.nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "\(Int(bpm.rounded())) BPM · \(timeSignature)",
            // A metronome is a live stream: there is no track to scrub.
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPMediaItemPropertyArtwork: artwork,
        ]
        info[MPNowPlayingInfoPropertyExternalContentIdentifier] = "tempo.metronome"
        infoCenter.nowPlayingInfo = info
    }

    // MARK: - Private

    private func configureCommands() {
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.onPlay?()
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.onPause?()
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onToggle?()
            return .success
        }

        // Nothing to skip, scrub or seek in a metronome.
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false
    }

    private lazy var artwork: MPMediaItemArtwork = {
        let size = CGSize(width: 512, height: 512)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            UIColor(red: 1.0, green: 0.62, blue: 0.16, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 96, y: 96, width: 320, height: 320))

            let configuration = UIImage.SymbolConfiguration(pointSize: 190, weight: .semibold)
            if let symbol = UIImage(systemName: "metronome.fill", withConfiguration: configuration)?
                .withTintColor(UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1), renderingMode: .alwaysOriginal) {
                let origin = CGPoint(
                    x: (size.width - symbol.size.width) / 2,
                    y: (size.height - symbol.size.height) / 2
                )
                symbol.draw(at: origin)
            }
        }
        return MPMediaItemArtwork(boundsSize: size) { _ in image }
    }()
}
