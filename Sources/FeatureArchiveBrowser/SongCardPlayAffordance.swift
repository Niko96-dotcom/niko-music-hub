enum SongCardPlayAffordance {
    enum Kind: Equatable {
        case play(enabled: Bool)
        case noPreview
        case pausedForCapture
    }

    static func kind(hasPreview: Bool, captureActive: Bool) -> Kind {
        if captureActive { return hasPreview ? .pausedForCapture : .noPreview }
        return hasPreview ? .play(enabled: true) : .noPreview
    }
}
