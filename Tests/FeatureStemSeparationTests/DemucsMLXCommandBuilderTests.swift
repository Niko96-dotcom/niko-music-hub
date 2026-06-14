import AppCore
import FeatureStemSeparation
import Foundation
import Testing

struct DemucsMLXCommandBuilderTests {

    private let builder = DemucsMLXCommandBuilder()

    @Test
    func buildRequest_usesConfiguredExecutableURL() throws {
        let executable = URL(fileURLWithPath: "/opt/homebrew/bin/demucs-mlx")
        let settings = HelperToolSettings(demucsMlx: executable)
        let request = makeRequest(preset: .fast4)

        let processRequest = try builder.buildRequest(backendRequest: request, settings: settings)

        #expect(processRequest.executableURL == executable)
    }

    @Test
    func buildRequest_includesModelArgumentPerPreset() throws {
        let executable = URL(fileURLWithPath: "/usr/local/bin/demucs-mlx")
        let settings = HelperToolSettings(demucsMlx: executable)

        for preset in StemSeparationPreset.allCases {
            let request = makeRequest(preset: preset)
            let processRequest = try builder.buildRequest(backendRequest: request, settings: settings)
            let args = processRequest.arguments
            if let modelIndex = args.firstIndex(of: "-n") {
                #expect(args[modelIndex + 1] == preset.demucsModelID)
            } else {
                Issue.record("Missing -n model argument for \(preset)")
            }
            #expect(args.contains("--prefetch-tracks"))
            #expect(args.contains("--write-workers"))
            #expect(argsContainsSequence(args, preset.demucsQualityArguments))
        }
    }

    @Test
    func buildRequest_bestPresetUsesQualityInferenceArguments() throws {
        let executable = URL(fileURLWithPath: "/usr/local/bin/demucs-mlx")
        let settings = HelperToolSettings(demucsMlx: executable)
        let request = makeRequest(preset: .best4)

        let processRequest = try builder.buildRequest(backendRequest: request, settings: settings)

        #expect(argsContainsSequence(processRequest.arguments, ["--overlap", "0.50"]))
        #expect(argsContainsSequence(processRequest.arguments, ["--shifts", "2"]))
    }

    @Test
    func buildRequest_autoDetectsKnownExecutableWhenUnconfigured() throws {
        let detectedPath = "/opt/homebrew/bin/demucs-mlx"
        let healthChecker = DemucsMLXHealthChecker(fileExists: { $0 == detectedPath })
        let builder = DemucsMLXCommandBuilder(healthChecker: healthChecker)
        let request = makeRequest(preset: .fast4)

        let processRequest = try builder.buildRequest(backendRequest: request, settings: HelperToolSettings())

        #expect(processRequest.executableURL == URL(fileURLWithPath: detectedPath))
    }

    @Test
    func buildRequest_doesNotUseShellCommandString() throws {
        let executable = URL(fileURLWithPath: "/usr/local/bin/demucs-mlx")
        let settings = HelperToolSettings(demucsMlx: executable)
        let request = makeRequest(preset: .experimental6)

        let processRequest = try builder.buildRequest(backendRequest: request, settings: settings)

        // Each argument must be a discrete token; no spaces inside an argument.
        for arg in processRequest.arguments {
            #expect(!arg.contains(" "), "Argument contains shell-unsafe space: \(arg)")
        }
        #expect(!processRequest.arguments.contains("&&"))
        #expect(!processRequest.arguments.contains(";"))
        #expect(!processRequest.arguments.contains("|"))
    }

    @Test
    func buildRequest_throwsWhenExecutableMissing() {
        let healthChecker = DemucsMLXHealthChecker(fileExists: { _ in false })
        let builder = DemucsMLXCommandBuilder(healthChecker: healthChecker)
        let settings = HelperToolSettings()
        let request = makeRequest(preset: .fast4)

        #expect(throws: DemucsMLXCommandBuilderError.missingExecutable) {
            try builder.buildRequest(backendRequest: request, settings: settings)
        }
    }
}

private func makeRequest(preset: StemSeparationPreset) -> StemSeparationBackendRequest {
    StemSeparationBackendRequest(
        inputURL: URL(fileURLWithPath: "/Users/music/input.wav"),
        outputFolderURL: URL(fileURLWithPath: "/Users/music/output"),
        preset: preset
    )
}

private func argsContainsSequence(_ arguments: [String], _ expected: [String]) -> Bool {
    guard !expected.isEmpty, expected.count <= arguments.count else { return false }
    return arguments.indices.contains { index in
        let end = index + expected.count
        guard end <= arguments.count else { return false }
        return Array(arguments[index..<end]) == expected
    }
}
