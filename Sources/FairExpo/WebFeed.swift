import Swift
import FairCore
import struct Foundation.Data

/// An RSS web feed document outline with a generic `WebFeedAdditions` parameters allowing extension points for the various elements.
public struct WebFeed<Additions: WebFeedAdditions> {
    public var channels: [Channel]

    /// Additional properties as defined in the item additions
    public var additions: Additions.FeedAdditions?

    public init(channels: [Channel] = [], additions: Additions.FeedAdditions? = nil) throws {
        self.channels = channels
        self.additions = additions
    }

    /// Attempts to initialze the WebFeed with the given RSS data, which must be valid XML.
    public init(xmlData data: Data) throws {
        try self.init(node: XMLNode.parse(data: data, options: [.reportNamespacePrefixes]))
    }

    private init(node: FairCore.XMLNode) throws {
        guard let root = node.elementChildren.first,
              root.elementName == "rss" else {
            throw Errors.noRSSRoot
        }
        let channels = root.elementChildren
        if channels.contains(where: { $0.elementName != "channel" }) {
            throw Errors.rootChannelsInvalid
        }
        self.channels = try channels.map(Channel.init)

        self.additions = try Additions.FeedAdditions(node: node)
    }

    public struct Channel {
        public var title: String?
        public var link: String?
        public var language: String?
        public var description: String?
        public var items: [Item]

        /// Additional properties as defined in the item additions
        public var additions: Additions.ChannelAdditions?

        public init(title: String? = nil, link: String? = nil, language: String? = nil, description: String? = nil, items: [Item] = [], additions: Additions.ChannelAdditions? = nil) {
            self.title = title
            self.link = link
            self.language = language
            self.description = description
            self.items = []
            self.additions = additions
        }

        public init(node: FairCore.XMLNode) throws {
            let elements = node.elementChildren.dictionary(keyedBy: \.elementName)

            self.title = elements["title"]?.childContentTrimmed
            self.link = elements["link"]?.childContentTrimmed
            self.description = elements["description"]?.stringContent // note we don't trim
            self.language = elements["language"]?.childContentTrimmed

            self.items = try node.elementChildren.filter({ $0.elementName == "item" }).map(Item.init)
            self.additions = try Additions.ChannelAdditions(node: node)
        }

        public struct Item {
            public var title: String?
            public var link: String?
            public var pubDate: String?
            public var description: String?
            public var enclosures: [Enclosure]

            /// Additional properties as defined in the item additions
            public var additions: Additions.ItemAdditions?

            public init(title: String? = nil, link: String? = nil, pubDate: String? = nil, description: String? = nil, enclosures: [Enclosure] = [], additions: Additions.ItemAdditions? = nil) {
                self.title = title
                self.link = link
                self.pubDate = pubDate
                self.description = description
                self.enclosures = enclosures
                self.additions = additions
            }

            public init(node: FairCore.XMLNode) throws {
                let elements = node.elementChildren.dictionary(keyedBy: \.elementName)

                self.title = elements["title"]?.childContentTrimmed
                self.link = elements["link"]?.childContentTrimmed
                self.pubDate = elements["pubDate"]?.childContentTrimmed
                self.description = elements["description"]?.stringContent // note we don't trim

                self.enclosures = try node.elementChildren.filter({ $0.elementName == "enclosure" }).map(Enclosure.init)
                self.additions = try Additions.ItemAdditions(node: node)
            }
        }

        // <enclosure url="https://sparkle-project.org/files/Sparkle%20Test%20App.zip" length="107758" type="application/octet-stream" sparkle:edSignature="7cLALFUHSwvEJWSkV8aMreoBe4fhRa4FncC5NoThKxwThL6FDR7hTiPJh1fo2uagnPogisnQsgFgq6mGkt2RBw==" />

        public struct Enclosure {
            public var url: String?
            public var length: String?
            public var type: String?

            public var additions: Additions.EnclosureAdditions?

            public init(url: String? = nil, length: String? = nil, type: String? = nil, additions: Additions.EnclosureAdditions? = nil) {
                self.url = url
                self.length = length
                self.type = type
                self.additions = additions
            }

            public init(node: FairCore.XMLNode) throws {
                let dict = node.elementDictionary(attributes: true, childNodes: false)
                self.url = dict["url"]
                self.length = dict["length"]
                self.type = dict["type"]

                self.additions = try Additions.EnclosureAdditions(node: node)
            }
        }
    }

    public enum Errors : Error {
        case noRSSRoot
        case rootChannelsInvalid
        case noChannelTitle
        case noChannelLink
    }
}

/// An instance that can be created from an XML node
public protocol XMLNodeExpressible {
    init?(node: FairCore.XMLNode) throws
}

extension Never : XMLNodeExpressible {
    public init?(node: FairCore.XMLNode) throws {
        nil
    }
}

/// Contains optional structures that can hold additional data in the outline of a `WebFeed`
public protocol WebFeedAdditions {
    associatedtype FeedAdditions: XMLNodeExpressible
    associatedtype ChannelAdditions: XMLNodeExpressible
    associatedtype ItemAdditions: XMLNodeExpressible
    associatedtype EnclosureAdditions: XMLNodeExpressible
}

/// An empty default additions protocol implementation for `WebFeedAdditions`
public enum EmptyFeedAdditions : WebFeedAdditions {
    public typealias FeedAdditions = Never
    public typealias ChannelAdditions = Never
    public typealias ItemAdditions = Never
    public typealias EnclosureAdditions = Never
}

extension WebFeed : Equatable where Additions.FeedAdditions : Equatable, Additions.ChannelAdditions : Equatable, Additions.EnclosureAdditions : Equatable, Additions.ItemAdditions : Equatable { }
extension WebFeed.Channel : Equatable where Additions.ChannelAdditions : Equatable, Additions.EnclosureAdditions : Equatable, Additions.ItemAdditions : Equatable { }
extension WebFeed.Channel.Item : Equatable where Additions.EnclosureAdditions : Equatable, Additions.ItemAdditions : Equatable { }
extension WebFeed.Channel.Enclosure : Equatable where Additions.EnclosureAdditions : Equatable { }

extension WebFeed : Hashable where Additions.FeedAdditions : Hashable, Additions.ChannelAdditions : Hashable, Additions.EnclosureAdditions : Hashable, Additions.ItemAdditions : Hashable { }
extension WebFeed.Channel : Hashable where Additions.ChannelAdditions : Hashable, Additions.EnclosureAdditions : Hashable, Additions.ItemAdditions : Hashable { }
extension WebFeed.Channel.Item : Hashable where Additions.EnclosureAdditions : Hashable, Additions.ItemAdditions : Hashable { }
extension WebFeed.Channel.Enclosure : Hashable where Additions.EnclosureAdditions : Hashable { }

extension WebFeed : Sendable where Additions.FeedAdditions : Sendable, Additions.ChannelAdditions : Sendable, Additions.EnclosureAdditions : Sendable, Additions.ItemAdditions : Sendable { }
extension WebFeed.Channel : Sendable where Additions.ChannelAdditions : Sendable, Additions.EnclosureAdditions : Sendable, Additions.ItemAdditions : Sendable { }
extension WebFeed.Channel.Item : Sendable where Additions.EnclosureAdditions : Sendable, Additions.ItemAdditions : Sendable { }
extension WebFeed.Channel.Enclosure : Sendable where Additions.EnclosureAdditions : Sendable { }



public typealias AppcastFeed = WebFeed<AppcastWebFeedAdditions>

/// Additional properties for various elements of a `WebFeed`.
public enum AppcastWebFeedAdditions : WebFeedAdditions {
    public typealias FeedAdditions = Never
    public typealias ChannelAdditions = Never
    static let sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"


    /// Appcast-specific attributes for `<item>` nodes
    ///
    /// ```
    /// SUAppcastElementVersion = SUAppcastAttributeVersion;
    /// SUAppcastElementShortVersionString = SUAppcastAttributeShortVersionString;
    /// SUAppcastElementCriticalUpdate = @"sparkle:criticalUpdate";
    /// SUAppcastElementDeltas = @"sparkle:deltas";
    /// SUAppcastElementMinimumAutoupdateVersion = @"sparkle:minimumAutoupdateVersion";
    /// SUAppcastElementMinimumSystemVersion = @"sparkle:minimumSystemVersion";
    /// SUAppcastElementMaximumSystemVersion = @"sparkle:maximumSystemVersion";
    /// SUAppcastElementReleaseNotesLink = @"sparkle:releaseNotesLink";
    /// SUAppcastElementFullReleaseNotesLink = @"sparkle:fullReleaseNotesLink";
    /// SUAppcastElementTags = @"sparkle:tags";
    /// SUAppcastElementPhasedRolloutInterval = @"sparkle:phasedRolloutInterval";
    /// SUAppcastElementInformationalUpdate = @"sparkle:informationalUpdate";
    /// SUAppcastElementChannel = @"sparkle:channel";
    /// SUAppcastElementBelowVersion = @"sparkle:belowVersion";
    /// SUAppcastElementIgnoreSkippedUpgradesBelowVersion = @"sparkle:ignoreSkippedUpgradesBelowVersion";
    /// ```
    public struct ItemAdditions : XMLNodeExpressible, Hashable {
        var version: String?
        var shortVersionString: String?
        var criticalUpdate: String?
        var minimumAutoupdateVersion: String?
        var minimumSystemVersion: String?
        var maximumSystemVersion: String?
        var releaseNotesLink: String?
        var fullReleaseNotesLink: String?
        var phasedRolloutInterval: String?
        var informationalUpdate: String?
        var channel: String?
        var belowVersion: String?
        var ignoreSkippedUpgradesBelowVersion: String?
        var tags: [FairCore.XMLNode]?
        var deltas: [AppcastFeed.Channel.Enclosure]?

        public init?(node: FairCore.XMLNode) throws {
            let element = { node.childElements(named: $0, namespaceURI: sparkle).first?.childContentTrimmed }

            self.version = element("version")
            self.shortVersionString = element("shortVersionString")
            self.criticalUpdate = element("criticalUpdate")
            self.minimumAutoupdateVersion = element("minimumAutoupdateVersion")
            self.minimumSystemVersion = element("minimumSystemVersion")
            self.maximumSystemVersion = element("maximumSystemVersion")
            self.releaseNotesLink = element("releaseNotesLink")
            self.fullReleaseNotesLink = element("fullReleaseNotesLink")
            self.phasedRolloutInterval = element("phasedRolloutInterval")
            self.informationalUpdate = element("informationalUpdate")
            self.channel = element("channel")
            self.belowVersion = element("belowVersion")
            self.ignoreSkippedUpgradesBelowVersion = element("ignoreSkippedUpgradesBelowVersion")

            self.tags = node.childElements(named: "tags", namespaceURI: sparkle).flatMap(\.elementChildren).array()
            self.deltas = try node.childElements(named: "deltas", namespaceURI: sparkle).flatMap(\.elementChildren).compactMap(AppcastFeed.Channel.Enclosure.init)
        }
    }

    /// Appcast-specific attributes for `<enclosure>` nodes:
    ///
    /// ```
    /// SUAppcastAttributeDeltaFrom = @"sparkle:deltaFrom";
    /// SUAppcastAttributeDSASignature = @"sparkle:dsaSignature";
    /// SUAppcastAttributeEDSignature = @"sparkle:edSignature";
    /// SUAppcastAttributeShortVersionString = @"sparkle:shortVersionString";
    /// SUAppcastAttributeVersion = @"sparkle:version";
    /// SUAppcastAttributeOsType = @"sparkle:os";
    /// SUAppcastAttributeInstallationType = @"sparkle:installationType";
    /// ```
    public struct EnclosureAdditions : XMLNodeExpressible, Hashable {
        var version: String?
        var shortVersionString: String?
        var edSignature: String?
        var dsaSignature: String?
        var deltaFrom: String?
        var installationType: String?
        var os: String?

        public init?(node: FairCore.XMLNode) throws {
            let attr = { node.attributeValue(key: $0, namespaceURI: sparkle) }
            self.version = attr("version")
            self.shortVersionString = attr("shortVersionString")
            self.edSignature = attr("edSignature")
            self.dsaSignature = attr("dsaSignature")
            self.deltaFrom = attr("deltaFrom")
            self.installationType = attr("installationType")
            self.os = attr("os")
        }
    }
}

extension WebFeed.Channel.Item where Additions == AppcastWebFeedAdditions {

    /// https://sparkle-project.org/documentation/api-reference/Classes/SUAppcastItem.html#/c:objc(cs)SUAppcastItem(py)displayVersionString
    var displayVersionString: String? {

        enclosures.compactMap(\.shortVersionString).first
    }
}

extension WebFeed.Channel.Enclosure where Additions == AppcastWebFeedAdditions {
    var version: String? { additions?.version }
    var shortVersionString: String? { additions?.shortVersionString }
    var edSignature: String? { additions?.edSignature }
    var dsaSignature: String? { additions?.dsaSignature }
}

