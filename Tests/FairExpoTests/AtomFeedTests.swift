import Swift
import XCTest
import FairCore
@testable import FairExpo

final class AtomFeedTests: XCTestCase {

    func testSampleAtomFeed() async throws {
        let sampleAtom = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/" xml:lang="en-US">
          <id>tag:github.com,2008:https://github.com/appfair/Tune-Out/releases</id>
          <link type="text/html" rel="alternate" href="https://github.com/appfair/Tune-Out/releases"/>
          <link type="application/atom+xml" rel="self" href="https://github.com/appfair/Tune-Out/releases.atom"/>
          <title>Release notes from Tune-Out</title>
          <updated>2025-10-12T21:02:05Z</updated>
          <entry>
            <id>tag:github.com,2008:Repository/1035115287/1.0.5</id>
            <updated>2025-10-13T14:53:13Z</updated>
            <link rel="alternate" type="text/html" href="https://github.com/appfair/Tune-Out/releases/tag/1.0.5"/>
            <title>Release 1.0.5</title>
            <content type="html">&lt;p&gt;&lt;strong&gt;Full Changelog&lt;/strong&gt;: &lt;a class=&quot;commit-link&quot; href=&quot;https://github.com/appfair/Tune-Out/compare/1.0.4...1.0.5&quot;&gt;&lt;tt&gt;1.0.4...1.0.5&lt;/tt&gt;&lt;/a&gt;&lt;/p&gt;</content>
            <author>
              <name>github-actions[bot]</name>
            </author>
            <media:thumbnail height="30" width="30" url="https://avatars.githubusercontent.com/in/15368?s=60&amp;v=4"/>
          </entry>
          <entry>
            <id>tag:github.com,2008:Repository/1035115287/1.0.4</id>
            <updated>2025-10-12T20:57:15Z</updated>
            <link rel="alternate" type="text/html" href="https://github.com/appfair/Tune-Out/releases/tag/1.0.4"/>
            <title>Release 1.0.4</title>
            <content type="html">&lt;p&gt;&lt;strong&gt;Full Changelog&lt;/strong&gt;: &lt;a class=&quot;commit-link&quot; href=&quot;https://github.com/appfair/Tune-Out/compare/1.0.3...1.0.4&quot;&gt;&lt;tt&gt;1.0.3...1.0.4&lt;/tt&gt;&lt;/a&gt;&lt;/p&gt;</content>
            <author>
              <name>github-actions[bot]</name>
            </author>
            <media:thumbnail height="30" width="30" url="https://avatars.githubusercontent.com/in/15368?s=60&amp;v=4"/>
          </entry>
        </feed>
        """

        let webFeed = try AtomFeed(xmlData: sampleAtom.utf8Data)

        XCTAssertEqual(webFeed.id, "tag:github.com,2008:https://github.com/appfair/Tune-Out/releases")
        XCTAssertEqual(webFeed.title, "Release notes from Tune-Out")
        XCTAssertEqual(webFeed.updated, "2025-10-12T21:02:05Z")

        XCTAssertEqual(webFeed.links.first?.type, "text/html")
        XCTAssertEqual(webFeed.links.first?.rel, "alternate")
        XCTAssertEqual(webFeed.links.first?.href, "https://github.com/appfair/Tune-Out/releases")

        XCTAssertEqual(webFeed.links.last?.type, "application/atom+xml")
        XCTAssertEqual(webFeed.links.last?.rel, "self")
        XCTAssertEqual(webFeed.links.last?.href, "https://github.com/appfair/Tune-Out/releases.atom")


        XCTAssertEqual(webFeed.entries.first?.id, "tag:github.com,2008:Repository/1035115287/1.0.5")
        XCTAssertEqual(webFeed.entries.first?.title, "Release 1.0.5")
        XCTAssertEqual(webFeed.entries.first?.updated, "2025-10-13T14:53:13Z")
        XCTAssertEqual(webFeed.entries.first?.authors?.first?.name, "github-actions[bot]")

        XCTAssertEqual(webFeed.entries.first?.links?.first?.type, "text/html")
        XCTAssertEqual(webFeed.entries.first?.links?.first?.rel, "alternate")
        XCTAssertEqual(webFeed.entries.first?.links?.first?.href, "https://github.com/appfair/Tune-Out/releases/tag/1.0.5")


        XCTAssertEqual(webFeed.entries.last?.id, "tag:github.com,2008:Repository/1035115287/1.0.4")
        XCTAssertEqual(webFeed.entries.last?.title, "Release 1.0.4")
        XCTAssertEqual(webFeed.entries.last?.updated, "2025-10-12T20:57:15Z")
        XCTAssertEqual(webFeed.entries.last?.authors?.first?.name, "github-actions[bot]")

        XCTAssertEqual(webFeed.entries.last?.links?.first?.type, "text/html")
        XCTAssertEqual(webFeed.entries.last?.links?.first?.rel, "alternate")
        XCTAssertEqual(webFeed.entries.last?.links?.first?.href, "https://github.com/appfair/Tune-Out/releases/tag/1.0.4")
    }

}
