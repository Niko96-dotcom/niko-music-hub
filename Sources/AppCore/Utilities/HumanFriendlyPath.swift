import Foundation

/// Paths for on-screen display — avoids `~` and highlights the Music library when relevant.
public enum HumanFriendlyPath {
  public static func display(
    _ url: URL,
    homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
  ) -> String {
    let path = url.standardizedFileURL.path
    if path == homeDirectory {
      return "Home"
    }
    let musicPrefix = homeDirectory + "/Music"
    if path == musicPrefix {
      return "Music"
    }
    if path.hasPrefix(musicPrefix + "/") {
      return "Music" + path.dropFirst(musicPrefix.count)
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
      return "In Music"
    }
    if path.hasPrefix(homeDirectory + "/") {
      return "On this Mac"
    }
    return display(url, homeDirectory: homeDirectory)
  }
}
