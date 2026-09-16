public struct BPMReadoutAnnouncement: Equatable, Sendable {
    public let label: String
    public let value: String

    public init(displayedBPMText: String) {
        self.label = "Current BPM"
        self.value = displayedBPMText == "--" ? "Not recorded" : displayedBPMText
    }
}
