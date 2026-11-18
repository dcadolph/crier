import Foundation

// Story is one headline from one feed.
public struct Story: Sendable, Hashable, Identifiable {
    // title is the headline with any trailing outlet name removed.
    public let title: String
    // link opens the story.
    public let link: URL
    // outlet is the publisher's name.
    public let outlet: String
    // published is when the feed says the story went out, if it says.
    public let published: Date?
    // sourceID names the feed the story came from.
    public let sourceID: String
    // rank is the story's position in an editor-ranked feed, or nil for other feeds.
    public let rank: Int?

    // init builds a story.
    public init(title: String, link: URL, outlet: String, published: Date?, sourceID: String, rank: Int? = nil) {
        self.title = title
        self.link = link
        self.outlet = outlet
        self.published = published
        self.sourceID = sourceID
        self.rank = rank
    }

    // id is the story's link, which is unique per story.
    public var id: String {
        link.absoluteString
    }
}
