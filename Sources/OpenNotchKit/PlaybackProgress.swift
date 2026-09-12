import Foundation

/// Extrapolates the display position of the progress bar between adapter
/// snapshots — the adapter only streams on state changes, so while a track
/// plays the UI advances `elapsed` by wall-clock locally (no polling).
public enum PlaybackProgress {
    public static func position(info: NowPlayingInfo, at now: Date) -> TimeInterval? {
        guard let elapsed = info.elapsed else { return nil }
        guard info.isPlaying, let timestamp = info.timestamp else { return elapsed }
        let position = elapsed + now.timeIntervalSince(timestamp)
        if let duration = info.duration { return min(max(position, 0), duration) }
        return max(position, 0)
    }
}
