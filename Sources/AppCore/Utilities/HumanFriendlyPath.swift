import Foundation

/// Paths for on-screen display — avoids `~` and highlights the Music library when relevant.
public enum HumanFriendlyPath {
  public static func display(
    _ url: URL,
    homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
  ) -> String {
    let path = url.standardizedFileURL.path
    if path == homeDirectory {
      return String(localized: "Home", comment: "Path gloss for the user’s home folder")
    }
    let musicPrefix = homeDirectory + "/Music"
    if path == musicPrefix {
      return String(localized: "Music", comment: "Path gloss for ~/Music")
    }
    if path.hasPrefix(musicPrefix + "/") {
      return String(localized: "Music", comment: "Path gloss for ~/Music") + path.dropFirst(musicPrefix.count)
    }
    if path.hasPrefix(homeDirectory + "/") {
      return String(path.dropFirst(homeDirectory.count + 1))
    }
    return path
  }

  /// Short secondary label for archive roots (e.g. under the folder name).
  public static func archiveRootSubtitle(
    _ url: URL,
    homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
  ) -> String {
    let path = url.standardizedFileURL.path
    let musicPrefix = homeDirectory + "/Music"
    if path == musicPrefix || path.hasPrefix(musicPrefix + "/") {
      return String(localized: "In Music", comment: "Archive root subtitle when the folder is inside ~/Music")
    }
    if path.hasPrefix(homeDirectory + "/") {
      return String(localized: "On this Mac", comment: "Archive root subtitle when the folder is under the home directory")
    }
    return display(url, homeDirectory: homeDirectory)
  }
}
