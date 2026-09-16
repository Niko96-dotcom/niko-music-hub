import SwiftUI

/// Routes Help-menu choices into the single Help window (scroll target).
@MainActor
final class HubHelpRouting: ObservableObject {
    static let shared = HubHelpRouting()

    @Published private(set) var requestedTopic: HubHelpTopic?
    @Published private(set) var requestID: UInt64 = 0

    func showHelp(topic: HubHelpTopic?) {
        requestedTopic = topic
        requestID &+= 1
    }
}

/// In-app Help page. One window, four sections from `HubHelpTopics`.
struct HubHelpWindow: View {
    @ObservedObject var routing: HubHelpRouting

    init(routing: HubHelpRouting = .shared) {
        self.routing = routing
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(HubHelpTopics.all) { topic in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(topic.heading)
                                .font(.title2.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                            Text(topic.body)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(topic.anchor)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { scroll(using: proxy) }
            .onChange(of: routing.requestID) { _, _ in
                scroll(using: proxy)
            }
        }
        .navigationTitle(HubHelpTopics.windowTitle)
        .frame(minWidth: 480, minHeight: 420)
    }

    private func scroll(using proxy: ScrollViewProxy) {
        let destination = routing.requestedTopic?.anchor ?? HubHelpTopics.all.first?.anchor
        guard let destination else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(destination, anchor: .top)
        }
    }
}
