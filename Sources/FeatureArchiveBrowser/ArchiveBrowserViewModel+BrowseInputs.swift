import AppCore
import Foundation
import NikoMusicCore

// MARK: - Sidebar browse input mutators (filter, hidden, sort, collaborator)

extension ArchiveBrowserViewModel {
    func toggleBrowseFilter(_ filter: ArchiveBrowseFilter) {
        mutateBrowseInputs {
            var next = browseFilter
            if next.contains(filter) {
                next.remove(filter)
            } else {
                next.insert(filter)
            }
            browseFilter = next
        }
    }

    func toggleShowHiddenSongs() {
        mutateBrowseInputs {
            showHiddenSongs.toggle()
        }
    }

    func setSortMode(_ mode: ArchiveBrowseSortMode) {
        mutateBrowseInputs {
            sortMode = mode
        }
    }

    func setSelectedCollaboratorID(_ id: String?) {
        mutateBrowseInputs {
            selectedCollaboratorID = id
        }
    }
}
