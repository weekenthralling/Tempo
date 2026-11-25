//
//  AudioSessionController.swift
//  Tempo
//

import AVFoundation

/// Owns the `AVAudioSession` configuration and translates the system
/// notifications a metronome has to survive (phone calls, headphones unplugged,
/// media services reset) into simple callbacks.
final class AudioSessionController {
    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((_ shouldResume: Bool) -> Void)?
    var onOutputRouteLost: (() -> Void)?
    var onMediaServicesReset: (() -> Void)?

    private let session = AVAudioSession.sharedInstance()
    private var mixWithOthers = true
    private var isConfigured = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                self?.handleInterruption(notification)
            }
        )
        observers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                self?.handleRouteChange(notification)
            }
        )
        observers.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                self?.onMediaServicesReset?()
            }
        )
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Configures the session when needed and makes it active.
    ///
    /// `.playback` is what keeps the click audible with the silent switch on,
    /// and it is also a prerequisite for background audio.
    func activate(mixWithOthers: Bool) throws {
        if !isConfigured || self.mixWithOthers != mixWithOthers {
            let options: AVAudioSession.CategoryOptions = mixWithOthers ? [.mixWithOthers] : []
            try session.setCategory(.playback, mode: .default, options: options)
            self.mixWithOthers = mixWithOthers
            isConfigured = true
        }
        try session.setActive(true)
    }

    /// Lets other apps (music, podcasts) come back after we stop.
    func deactivate() {
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Notifications

    private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else {
            return
        }

        switch type {
        case .began:
            onInterruptionBegan?()
        case .ended:
            let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            onInterruptionEnded?(options.contains(.shouldResume))
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let rawReason = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason),
            reason == .oldDeviceUnavailable
        else {
            return
        }
        // Headphones were unplugged. Pause rather than suddenly clicking
        // through the speaker (Apple's recommended behaviour).
        onOutputRouteLost?()
    }
}
