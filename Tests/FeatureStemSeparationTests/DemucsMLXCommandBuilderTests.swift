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
            if let modelIndex = args.firstIndex(of: "--model") {
                #expect(args[modelIndex + 1] == preset.demucsModelID)
            } else {
                Issue.record("Missing --model argument for \(preset)")
            }
        }
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
