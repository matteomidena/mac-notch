import Foundation

public struct NowPlayingInfo: Equatable, Sendable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var isPlaying: Bool
    public var elapsed: TimeInterval?
    public var duration: TimeInterval?
    public var artworkData: Data?
    public var artworkMimeType: String?

    public init(title: String? = nil, artist: String? = nil, album: String? = nil,
                isPlaying: Bool = false, elapsed: TimeInterval? = nil,
                duration: TimeInterval? = nil, artworkData: Data? = nil,
                artworkMimeType: String? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.elapsed = elapsed
        self.duration = duration
        self.artworkData = artworkData
        self.artworkMimeType = artworkMimeType
    }
}
