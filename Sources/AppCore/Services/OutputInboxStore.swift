import Foundation

public protocol OutputInboxStore: Sendable {
    func listItems() throws -> [OutputInboxItem]
    func addItem(_ item: OutputInboxItem) throws
    func updateItem(_ item: OutputInboxItem) throws
    func refreshAvailability() throws
}
