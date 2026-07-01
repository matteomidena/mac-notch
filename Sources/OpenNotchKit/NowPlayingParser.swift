import Foundation

public enum NowPlayingParser {
    public static func parse(line: String) -> NowPlayingInfo? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var info = NowPlayingInfo()
        info.title = obj["title"] as? String
        info.artist = obj["artist"] as? String
        info.album = obj["album"] as? String
        info.elapsed = (obj["elapsedTime"] as? NSNumber)?.doubleValue
        info.duration = (obj["duration"] as? NSNumber)?.doubleValue
        info.isPlaying = (obj["playing"] as? NSNumber)?.boolValue ?? false
        info.artworkMimeType = obj["artworkMimeType"] as? String
        if let b64 = obj["artworkData"] as? String { info.artworkData = Data(base64Encoded: b64) }
        return info
    }
}
