// Copyright (c) 2022 - 2026 The App Fair Project <info@appfair.org>
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-or-later
import Swift
import FairCore
import Universal
import struct Foundation.Data

/// An Atom web feed
public struct AtomFeed {
    public var id: String?
    public var title: String?
    public var updated: String?
    public var links: [Link]
    public var entries: [Entry]

    /// Attempts to initialze the AtomFeed with the given atom data, which must be valid XML.
    public init(xmlData data: Data) throws {
        try self.init(node: XMLNode.parse(data: data, options: [.reportNamespacePrefixes]))
    }

    private init(node: XMLNode) throws {
        guard let root = node.elementChildren.first,
              root.elementName == "feed" else {
            throw Errors.noAtomRoot
        }

        let entries = root.elementChildren

        let elements = entries.dictionary(keyedBy: \.elementName)
        self.id = elements["id"]?.childContentTrimmed
        self.title = elements["title"]?.childContentTrimmed
        self.updated = elements["updated"]?.childContentTrimmed

        self.entries = try entries.filter({ $0.elementName == "entry" }).map(Entry.init)
        self.links = try entries.filter({ $0.elementName == "link" }).map(Link.init)
    }

    public struct Link {
        public var type: String?
        public var rel: String?
        public var href: String?

        public init(node: XMLNode) throws {
            let dict = node.elementDictionary(attributes: true, childNodes: false)
            self.type = dict["type"]
            self.rel = dict["rel"]
            self.href = dict["href"]
        }
    }

    public struct Author {
        public var name: String?

        public init(node: XMLNode) throws {
            let entries = node.elementChildren
            self.name = entries.filter({ $0.elementName == "name" }).first?.stringContent
        }
    }

    public struct Content {
        public var type: String?
        public var contents: String?

        public init(node: XMLNode) throws {
            let dict = node.elementDictionary(attributes: true, childNodes: false)
            self.type = dict["type"]
            self.contents = node.stringContent
        }
    }

    public struct Entry {
        public var id: String?
        public var title: String?
        public var updated: String?
        public var links: [Link]?
        public var authors: [Author]?
        public var contents: [Content]?

        public init(node: XMLNode) throws {
            let elements = node.elementChildren.dictionary(keyedBy: \.elementName)

            self.id = elements["id"]?.childContentTrimmed
            self.title = elements["title"]?.childContentTrimmed
            self.updated = elements["updated"]?.childContentTrimmed

            self.links = try node.elementChildren.filter({ $0.elementName == "link" }).map(Link.init)
            self.authors = try node.elementChildren.filter({ $0.elementName == "author" }).map(Author.init)
            self.contents = try node.elementChildren.filter({ $0.elementName == "content" }).map(Content.init)
        }
    }

    public enum Errors : Error {
        case noAtomRoot
        case rootEntriesInvalid
        case noChannelTitle
        case noChannelLink
    }
}
