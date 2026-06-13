import AppCore
import FeatureStemSeparation
import Testing

struct StemSeparationFeatureTests {

    @Test
    func metadata_matchesExpectations() {
        let feature = StemSeparationFeature()
        #expect(feature.metadata.id == "stem-separation")
        #expect(feature.metadata.displayName == "Stem Separation")
        #expect(feature.metadata.shortLabel == "Stems")
        #expect(feature.metadata.capabilities.contains(.producesFiles))
        #expect(feature.metadata.capabilities.contains(.runsJobs))
    }
}
