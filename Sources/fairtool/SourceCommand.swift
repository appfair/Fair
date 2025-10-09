import Foundation
import FairCore
import FairExpo
import ArgumentParser

public struct SourceCommand : AsyncParsableCommand {
    public static let experimental = false
    public static var configuration = CommandConfiguration(commandName: "source",
                                                           abstract: "App source catalog management commands",
                                                           shouldDisplay: !experimental,
                                                           subcommands: [
                                                            CreateCommand.self,
                                                            //VerifyCommand.self,
                                                            //PostReleaseCommand.self,
                                                           ])

    public init() {
    }

    public struct CreateCommand: FairParsableCommand {
        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var outputOptions: OutputOptions
        @OptionGroup public var sourceOptions: SourceOptions

        public static var configuration = CommandConfiguration(commandName: "create",
                                                               abstract: "Create a catalog source for the current app",
                                                               shouldDisplay: !experimental)

        public static let experimental = false
        public typealias Output = AltCatalog


        public init() {
        }

        public mutating func run() async throws {
            //let date = Date() // Calendar.current.startOfDay(for: Date())

            warnExperimental(Self.experimental)
            msg(.info, "creating catalog")
            var catalog = AltCatalog(apps: [])
            catalog.name = sourceOptions.catalogName

            let json = try outputOptions.writeCatalog(catalog)
            let _ = json
        }
    }

// Second, in the past when I've developed a source, I was stymied by the requirement that the ADP's manifest be served with the same file structure as the zip that was delivered, which precluded the possibility of serving the files from a GitHub release (since GH releases only have a "flat" hierarchy). I was excited to read about https://faq.altstore.io/developers/make-a-source#asseturls-dictionary-of-strings, which ought to let me create a mapping into the ADP's contents. But I'm wondering if there are any sources that have actually utilized this that I can examine to make sure I understand it correctly?


//    public struct CreateCommand: FairStructuredCommand {
//        public static let experimental = false
//        public typealias Output = AltCatalogItem
//
//        public static var configuration = CommandConfiguration(commandName: "create",
//                                                               abstract: "Create a source from the specified .ipa or .zip",
//                                                               shouldDisplay: !experimental)
//        @OptionGroup public var msgOptions: MsgOptions
//
//        @OptionGroup public var sourceOptions: SourceOptions
//
//        @Argument(help: ArgumentHelp("Path(s) or URL(s) for app folders or ipa archives", valueName: "apps", visibility: .default))
//        public var apps: [String]
//
//        public init() { }
//
//        public func executeCommand() -> AsyncThrowingStream<Output, Error> {
//            return executeStream(apps) { app in
//                msg(.info, "creating app catalog:", app)
//                let url = URL(fileOrScheme: app)
//                return try await AppCatalogAPI.shared.catalogApp(url: url, options: sourceOptions, clearDownload: true)
//            }
//        }
//
//        public func writeCommandStart() throws {
//            if msgOptions.promoteJSON == true {
//                return // skip generating enclosure
//            }
//            var catalog = AppCatalog(name: sourceOptions.catalogName ?? "CATALOG_NAME", identifier: sourceOptions.catalogIdentifier ?? "CATALOG_IDENTIFIER", apps: [])
//
//            if let catalogPlatform = sourceOptions.catalogPlatform {
//                catalog.platform = .init(rawValue: catalogPlatform) // TODO: validate platform name?
//            }
//
//            if let catalogSource = sourceOptions.catalogSourceURL,
//               let catalogSourceURL = URL(string: catalogSource) {
//                catalog.sourceURL = catalogSourceURL
//            }
//
//            if let catalogIcon = sourceOptions.catalogIconURL,
//               let catalogIconURL = URL(string: catalogIcon) {
//                catalog.iconURL = catalogIconURL
//            }
//
//            if let catalogLocalizedDescription = sourceOptions.catalogLocalizedDescription {
//                catalog.localizedDescription = catalogLocalizedDescription
//            }
//
//            if let catalogTintColor = sourceOptions.catalogTintColor {
//                catalog.tintColor = catalogTintColor
//            }
//
//
//            // trim out the "apps" array and tack it onto the end of the output so we
//            // can stream the apps afterwards
//            if let json = try catalog.toJSON(outputFormatting: [.sortedKeys, .withoutEscapingSlashes], dateEncodingStrategy: .iso8601).utf8String?.replacingOccurrences(of: #""apps":[],"#, with: "").dropLast() {
//                // since we want to retain the streaming apps array behavior, we just hardwire the JSON we spit out initially
//                // it will be followed by the async array of apps
//                msgOptions.write(json + #","apps":"#)
//            }
//        }
//
//        public func writeCommandEnd() {
//            if msgOptions.promoteJSON == true {
//                return // skip generating enclosure
//            }
//            msgOptions.write("}")
//        }
//    }

//    public struct VerifyCommand: FairStructuredCommand {
//        public static let experimental = false
//        public typealias Output = AppCatalogAPI.AppCatalogVerifyResult
//
//        public static var configuration = CommandConfiguration(commandName: "verify",
//                                                               abstract: "Verify the files in the specified catalog JSON",
//                                                               shouldDisplay: !experimental)
//        @OptionGroup public var msgOptions: MsgOptions
//        @OptionGroup public var downloadOptions: DownloadOptions
//
//        @Option(name: [.long], help: ArgumentHelp("Verify only the specified bundle ID(s)", valueName: "id"))
//        public var bundleID: Array<String> = []
//
//        @Argument(help: ArgumentHelp("Path or url for catalog", valueName: "path", visibility: .default))
//        public var catalogs: [String]
//
//        public init() { }
//
//        public func executeCommand() -> AsyncThrowingStream<Output, Error> {
//            return msgOptions.executeStreamJoined(catalogs) { catalog in
//                msg(.debug, "verifying catalog:", catalog)
//                let url = URL(string: catalog)
//
//                let catalogURL = url == nil || url?.scheme == nil ? URL(fileURLWithPath: catalog) : url!
//                let (data, _) = try await URLSession.shared.fetch(request: URLRequest(url: catalogURL))
//                let catalog = try AppCatalog.parse(jsonData: data)
//                var apps = catalog.apps
//
//                // if we are filtering by bundle IDs, find ones that match
//                if !bundleID.isEmpty {
//                    let bundleIDs = bundleID.set()
//                    apps = apps.filter({ $0.bundleIdentifier.map(bundleIDs.contains) == true })
//                }
//
//                return apps.asyncMap({ try await AppCatalogAPI.shared.verifyAppItem(app: $0, catalogURL: catalogURL, msg: { msg($0, $1) }) })
//            }
//        }
//    }

//    public struct PostReleaseCommand: FairParsableCommand {
//        public static let experimental = true
//        public typealias Output = AppNewsPost
//
//        public static var configuration = CommandConfiguration(commandName: "postrelease",
//                                                               abstract: "Compare sources and post app version changes",
//                                                               shouldDisplay: !experimental)
//        @OptionGroup public var msgOptions: MsgOptions
//        @OptionGroup public var outputOptions: OutputOptions
//        @OptionGroup public var indexOptions: IndexingOptions
//        @OptionGroup public var newsOptions: NewsOptions
//        @OptionGroup public var tweetOptions: TweetOptions
//
//        @Option(name: [.long], help: ArgumentHelp("The source catalog", valueName: "src"))
//        public var fromCatalog: String
//
//        @Option(name: [.long], help: ArgumentHelp("The destination catalog", valueName: "dest"))
//        public var toCatalog: String
//
//        @Option(name: [.long], help: ArgumentHelp("Limit number of news items", valueName: "limit"))
//        public var newsItems: Int?
//
//        @Flag(name: [.long], help: ArgumentHelp("Update version date for new versions", valueName: "update"))
//        public var updateVersionDate: Bool = false
//
//        public init() { }
//
//        public mutating func run() async throws {
//            let date = Date() // Calendar.current.startOfDay(for: Date())
//
//            warnExperimental(Self.experimental)
//            msg(.info, "posting changes from: \(fromCatalog) to \(toCatalog)")
////            let srcCatalog = try AppCatalog.parse(jsonData: Data(contentsOf: URL(fileURLWithPath: fromCatalog)))
////
////            var dstCatalog = try AppCatalog.parse(jsonData: Data(contentsOf: URL(fileURLWithPath: toCatalog)))
////            dstCatalog.news = srcCatalog.news
////            if updateVersionDate {
////                dstCatalog.importVersionDates(from: srcCatalog)
////            }
////
////            // copy over the news from the previous catalog…
////            let diffs = AppCatalog.newReleases(from: srcCatalog, to: dstCatalog)
////
////            // if we want to tweet the changes, make sure we have the necessary auth info
////            let twitterAuth = self.newsOptions.tweetBody == nil ? nil : try self.tweetOptions.createAuth()
////
////            // … then add items for each of the new releases, purging duplicates as needed
////            let tweets = try await newsOptions.postUpdates(to: &dstCatalog, with: diffs, twitterAuth: twitterAuth, newsLimit: newsItems, tweetLimit: nil)
////            if !tweets.isEmpty {
////                msg(.info, "posted tweets:", try tweets.map({ try $0.debugJSON }))
////            }
////
////            if updateVersionDate {
////                dstCatalog.updateVersionDates(for: diffs, with: date)
////            }
////
////            let json = try outputOptions.writeCatalog(dstCatalog)
////            msg(.info, "posted", diffs.count, "changes to catalog", json.count, "old items:", srcCatalog.news?.count ?? 0, "new items:", dstCatalog.news?.count ?? 0)
////
////            try indexOptions.writeCatalogIndex(dstCatalog)
//        }
//
//
//    }

//    public struct IndexingOptions: ParsableArguments {
//        @Option(name: [.long], help: ArgumentHelp("Catalog index markdown file to generate"))
//        public var markdownIndex: String?
//
//        public init() { }
//
//        func writeCatalogIndex(_ catalog: AltCatalog) throws {
//            guard let indexFlag = self.markdownIndex else {
//                return
//            }
//
//            // #warning("TODO: outputOptions.write(data)")
//            func output(_ data: Data, to path: String) throws {
//                if path == "-" {
//                    print(data.utf8String!)
//                } else {
//                    let file = URL(fileURLWithPath: path)
//                    try data.write(to: file)
//                }
//            }
//
////            let md = try catalog.buildAppCatalogMarkdown()
////            try output(md.utf8Data, to: indexFlag)
//            //msg(.info, "Wrote index to", indexFlag, md.count)
//        }
//    }

    public struct NewsOptions: ParsableArguments, NewsItemFormat {
        @Option(name: [.long], help: ArgumentHelp("The post title format", valueName: "format"))
        public var postTitle: String?

        @Option(name: [.long], help: ArgumentHelp("The post title format for updates", valueName: "format"))
        public var postTitleUpdate: String?

        @Option(name: [.long], help: ArgumentHelp("The post caption format for new releases", valueName: "format"))
        public var postCaption: String?

        @Option(name: [.long], help: ArgumentHelp("The post caption format for updates", valueName: "format"))
        public var postCaptionUpdate: String?

        @Option(name: [.long], help: ArgumentHelp("The post body format", valueName: "format"))
        public var postBody: String?

        @Option(name: [.long], help: ArgumentHelp("The tweet body format", valueName: "format"))
        public var tweetBody: String?

        @Option(name: [.long], help: ArgumentHelp("The app id for the post", valueName: "appid"))
        public var postAppID: String?

        @Option(name: [.long], help: ArgumentHelp("The post URL format", valueName: "format"))
        public var postURL: String?

        public init() { }

    }


}

public protocol NewsItemFormat {
    var postTitle: String? { get }
    var postTitleUpdate: String? { get }
    var postCaption: String? { get }
    var postCaptionUpdate: String? { get }
    var postBody: String? { get }
    var postAppID: String? { get }
    var postURL: String? { get }
    var tweetBody: String? { get }
}

extension NewsItemFormat {
    /// Takes the differences from two catalogs and adds them to the postings with the given formats and limits.
    /// Also sends out updates to various channels, such as Twitter (experimental) and ATOM (planned)
//    public func postUpdates(to catalog: inout AppCatalog, with diffs: [AltCatalogItem.Diff], twitterAuth: OAuth1.Info? = nil, newsLimit: Int? = nil, tweetLimit: Int? = nil) async throws -> [Tweeter.PostResponse] {
//        var tweetLimit = tweetLimit ?? .max
//        var responses: [Tweeter.PostResponse] = []
//
//        var news: [AppNewsPost] = catalog.news ?? []
//        for diff in diffs {
//            guard let bundleID = diff.new.bundleIdentifier else {
//                dbg("skipping missing id:", diff.new)
//                continue
//            }
//
//            let fmt = { (str: String?) in
//                str?.replacing(variables: [
//                    "appname": diff.new.name,
//                    "appname_hyphenated": diff.new.appNameHyphenated,
//                    "appbundleid": bundleID,
//                    "apptoken": bundleID, // currently stored in "bundleID", but should it be moved?
//                    "appversion": diff.new.version,
//                    "oldappversion": diff.old?.version,
//                ].compactMapValues({ $0 }))
//            }
//
//            let updatesExistingApp = diff.old != nil
//
//            // a unique identifier for the item
//            let identifier = "release-" + bundleID + "-" + (diff.new.version ?? "new")
//            let title = fmt(updatesExistingApp ? self.postTitleUpdate : self.postTitle)
//            let caption = fmt(updatesExistingApp ? self.postCaptionUpdate : self.postCaption)
//            let tweet = fmt(updatesExistingApp ? self.tweetBody : self.tweetBody) // TODO: different update
//
//            let postTitle = (title ?? "New Release: \(diff.new.name) \(diff.new.version ?? "")").trimmed()
//
//            let date = ISO8601DateFormatter().string(from: Date())
//            var post = AppNewsPost(identifier: identifier, date: date, title: postTitle, caption: caption ?? "")
//
//            post.appID = bundleID
//            // clear out any older news postings with the same bundle id
//            news = news.filter({ $0.appID != bundleID })
//            news.append(post)
//
//            if let tweet = tweet, let twitterAuth = twitterAuth {
//                tweetLimit = tweetLimit - 1
//                if tweetLimit >= 0 {
//                    // TODO: convert error to warning (will need a msg handler)
//                    responses.append(try await Tweeter.post(text: tweet, auth: twitterAuth))
//                }
//            }
//        }
//
//        // trim down the news count until we are at the limit
//        if let newsLimit = newsLimit {
//            news = news.suffix(newsLimit)
//        }
//        catalog.news = news.isEmpty ? nil : news
//
//        return responses
//    }
}

private extension AltCatalog {
//    func buildAppCatalogMarkdown() throws -> String {
//        let catalog = self
//
//        // a hack to distinguish between fairapps and appcasks
//        //let isFairApp = catalog.sourceURL?.contains("appcasks") != true
//
//        let format = ISO8601DateFormatter()
//        func fmt(_ date: Date?) -> String? {
//            guard let date = date else { return nil }
//            //return date.localizedDate(dateStyle: .short, timeStyle: .short)
//            return format.string(from: date)
//        }
//
//        func pre(_ string: String?, limit: Int = .max) -> String {
//            guard let string = string, !string.isEmpty else { return "" }
//            return "`" + string.prefix(limit - 1) + (string.count > limit ? "…" : "") + "`"
//        }
//
//        var md = """
//            ---
//            layout: catalog
//            ---
//
//            <style>
//            table {
//                border-collapse: collapse;
//            }
//
//            td, th {
//                border: 1px solid black;
//                white-space: nowrap;
//            }
//
//            th, td {
//                padding: 5px;
//            }
//
//            tr:nth-child(even) {
//                background-color: Lightgreen;
//            }
//            </style>
//
//            | name | version | dls | date | size | imps | views | stars | issues | category |
//            | ---: | :------ | --: | ---- | :--- | ---: | ----: | -----:| -----: | :------- |
//
//            """
//
//        for app in catalog.apps {
//            let landingPage = "https://\(app.name.rehyphenated()).github.io/App/"
//
//            let v = app.version ?? ""
//            var version = v
//            if app.beta == true {
//                version += "β"
//            }
//
//            md += "| "
//            md += "[`\(pre(app.name, limit: 25))`](\(app.homepage?.absoluteString ?? landingPage))"
//
//            md += " | "
//            if version.isEmpty {
//                // no output
//                //            } else if let relURL = URL(string: v, relativeTo: app.releasesURL), isFairApp == true {
//                //                md += "[`\(pre(version, limit: 25))`](\(relURL.absoluteString))"
//            } else {
//                md += "`\(pre(version, limit: 25))`"
//            }
//
//            md += " | "
//            md += pre(app.stats?.downloadCount?.description)
//
//            md += " | "
//            md += pre(fmt(app.versionDate))
//
//            md += " | "
//            md += pre(app.size?.localizedByteCount())
//
//            md += " | "
//            md += pre(app.stats?.impressionCount?.description)
//
//            md += " | "
//            md += pre(app.stats?.viewCount?.description)
//
//            md += " | "
//            md += pre(app.stats?.starCount?.description)
//
//            md += " | "
//            let issueCount = (app.stats?.issueCount ?? 0)
//            if issueCount > 0, let issuesURL = app.issuesURL {
//                md += "[`\(pre(issueCount.description))`](\(issuesURL.absoluteString))"
//            } else {
//                md += pre(issueCount.description)
//            }
//
//            md += " | "
//            if let category = app.categories?.first {
//                //                if isFairApp {
//                //                    md += "[\(pre(category.baseValue))](https://github.com/topics/appfair-\(category.baseValue)) "
//                //                } else {
//                md += pre(category.rawValue)
//                //                }
//            }
//
//            md += " |\n"
//        }
//
//        md += """
//
//            <center><small><code>{{ site.time | date_to_xmlschema }}</code></small></center>
//
//            """
//
//        return md
//    }
}
