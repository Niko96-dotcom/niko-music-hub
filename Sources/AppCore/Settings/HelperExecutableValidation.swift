import Foundation

public enum HelperExecutableValidation {
    public static func validate(url: URL) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return "That path does not exist."
        }
        guard !isDirectory.boolValue else {
            return "Choose a file, not a folder."
        }
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            return "That file is not executable."
        }
        return nil
    }
}
