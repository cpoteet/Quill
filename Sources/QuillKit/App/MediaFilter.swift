import Foundation

public enum MediaFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case images
    case documents
    case audio
    case video

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All Media"
        case .images: return "Images"
        case .documents: return "Documents"
        case .audio: return "Audio"
        case .video: return "Video"
        }
    }

    public var icon: String {
        switch self {
        case .all: return "photo.on.rectangle.angled"
        case .images: return "photo"
        case .documents: return "doc"
        case .audio: return "waveform"
        case .video: return "film"
        }
    }

    /// nil means the request sends no media_type parameter at all.
    public var mediaTypeParameter: String? {
        switch self {
        case .all: return nil
        case .images: return "image"
        case .documents: return "application"
        case .audio: return "audio"
        case .video: return "video"
        }
    }

    /// Mirrors `mediaTypeParameter`, so a local insert lands in the set a reload would return.
    public func matches(_ media: WPMedia) -> Bool {
        guard let mediaTypeParameter else { return true }
        return media.mediaType == mediaTypeParameter
    }
}
