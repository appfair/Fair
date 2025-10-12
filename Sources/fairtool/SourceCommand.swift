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

        @Argument(help: ArgumentHelp("Path or url for app release", valueName: "source", visibility: .default))
        public var sources: [String]

        public static var configuration = CommandConfiguration(commandName: "create",
                                                               abstract: "Create a catalog source for the current app",
                                                               shouldDisplay: !experimental)

        public static let experimental = false
        public typealias Output = AltCatalog


        public init() {
        }

        public mutating func run() async throws {
            warnExperimental(Self.experimental)
            msg(.info, "creating catalog")
            var catalog = AltCatalog()
            catalog.name = sourceOptions.catalogName
            catalog.subtitle = sourceOptions.catalogSubtitle
            catalog.description = sourceOptions.catalogDescription
            catalog.website = sourceOptions.catalogWebsite
            catalog.iconURL = sourceOptions.catalogIconURL
            catalog.tintColor = sourceOptions.catalogTintColor

            var apps: [AltCatalogAppItem] = []
            for source in sources {
                msg(.info, "analyzing source: \(source)")
                let item = try await createAppItem(path: source)
                apps.append(item)
            }
            catalog.apps = apps
            let json = try outputOptions.writeCatalog(catalog)
            let _ = json
        }

        func createAppItem(path: String) async throws -> AltCatalogAppItem {
            let url = URL(fileOrScheme: path)
            msg(.info, "checking url: \(url.absoluteString)")
            let dataSource: any DataWrapper
            let pathPrefix: String
            let appToken: String
            let relativePaths: [String] // the paths that will be relative to the pathPrefix
            if url.isFileURL {
                // e.g.: /opt/src/github/appfair/Tune-Out
                dataSource = try FileSystemDataWrapper(root: url)
                pathPrefix = ""
                appToken = url.lastPathComponent // e.g., "Tune-Out"
                relativePaths = dataSource.paths.map(\.pathName)
            } else {
                // e.g.: https://github.com/appfair/Tune-Out/archive/refs/tags/1.0.2.zip
                msg(.info, "downloading url: \(url.absoluteString)")
                let (localURL, response) = try await prf("download: \(url.absoluteURL)") {
                    try await URLSession.shared.downloadFile(for: URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad))
                }
                try response.validateHTTPCode()
                dataSource = try ZipArchiveDataWrapper(archive: ZipArchive(url: localURL, accessMode: .read))
                pathPrefix = (dataSource.paths.first?.pathName ?? "") + "/" // e.g.: "Tune-Out-1.0.2/"
                relativePaths = dataSource.paths.map(\.pathName).map({ $0.dropFirst(pathPrefix.count).description })

                appToken = url.pathComponents.filter({ !$0.isEmpty }).dropFirst(2).first ?? "Unknown" // e.g. "https://github.com/appfair/Tune-Out" -> "Tune-Out"
            }

            let envFileData = try dataSource.data(atPath: pathPrefix + "Skip.env")
            let envFile = try EnvFile(data: envFileData)

            func env(key: String) throws -> String {
                guard let value = envFile[key] else {
                    throw AppError("Could not load \(key) from Skip.env")
                }
                return value
            }

            //msg(.info, "env file contents: \(envFile.contents)")
            let productName = try env(key: "PRODUCT_NAME")
            let marketingVersion = try env(key: "MARKETING_VERSION")
            let projectVersion = try env(key: "CURRENT_PROJECT_VERSION")
            let bundleIdentifier = try env(key: "PRODUCT_BUNDLE_IDENTIFIER")
            //let packageName = try env(key: "ANDROID_PACKAGE_NAME")

            // The last part of the bundle ID usually, but not always, is the app token (e.g., org.appfair.app.SkipNotes vs. Skip-Notes)
            //guard let appToken = bundleIdentifier.split(separator: ".").last.map(String.init) else {
            //    throw AppError("Could not load app token from from bundleIdentifier in Skip.env")
            //}

            guard let repoURL = URL(string: "\(sourceOptions.hubRepository)/\(sourceOptions.fairgroundName)/\(appToken)") else {
                throw AppError("Could not create repo URL from: \(appToken)")
            }
            guard let rawContentURL = URL(string: "\(sourceOptions.hubContent)/\(sourceOptions.fairgroundName)/\(appToken)/refs/tags/\(marketingVersion)") else {
                throw AppError("Could not create raw content URL from: \(appToken)")
            }

            let releaseBaseURL = repoURL.appending(components: "releases", "download", marketingVersion)

            //msg(.info, "productName: \(productName)")

            let releaseDate = Calendar.current.startOfDay(for: Date()).ISO8601Format() // FIXME: use the date of the release

            func loadFastlaneMetadata(_ path: String, locale: String = "en-US") throws -> String? {
                String(data: try dataSource.data(atPath: pathPrefix + "Darwin/fastlane/metadata/\(locale)/\(path)"), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let localizedDescription = try loadFastlaneMetadata("description.txt")
            let subtitle = try loadFastlaneMetadata("subtitle.txt")

            let manifestURL = releaseBaseURL.appending(path: "manifest.json")
            let manifestData = try await URLSession.shared.fetch(request: URLRequest(url: manifestURL)).data
            let manifest = try JSONDecoder().decode(ADPManifest.self, from: manifestData)
            let marketplaceID = manifest.appleItemId

            if manifest.bundleId != bundleIdentifier {
                throw AppError("Bundle identifier mismatch with manifest.json: \(manifest.bundleId) vs. \(bundleIdentifier)")
            }
            if manifest.shortVersionString != marketingVersion {
                throw AppError("Bundle version mismatch with manifest.json: \(manifest.shortVersionString) vs. \(marketingVersion)")
            }

            // build the mapping from delta/variant asset to the flattened form stored at the GitHub release
            var assetURLs: [String: String] = [:]
            assetURLs["manifest"] = manifestURL.absoluteString
            assetURLs["signature"] = releaseBaseURL.appending(path: "signature").absoluteString
            // all the other assets are either deltas/ or variants/
            for assetPath in manifest.deltas.map(\.assetPath) + manifest.variants.map(\.assetPath) {
                guard let lastAssetPath = assetPath.split(separator: "/").last else { continue }
                let lastAssetBase = lastAssetPath.split(separator: ".").dropLast().joined(separator: ".")
                assetURLs[lastAssetBase] = releaseBaseURL.appending(path: lastAssetPath).absoluteString
            }
            let minOSVersion: String? = nil // TODO: get from Info.plist
            let maxOSVersion: String? = nil // TODO: get from Info.plist

            let releaseNotes: String? = nil // TODO: get release notes somehow

            let appVersion = AltCatalogAppItemVersion(version: marketingVersion, buildVersion: projectVersion, date: releaseDate, localizedDescription: releaseNotes, downloadURL: manifestURL.absoluteString, assetURLs: assetURLs, minOSVersion: minOSVersion, maxOSVersion: maxOSVersion)

            var appPermissions = AltCatalogAppItemPermissions()

            let infoPlist = try Plist(data: dataSource.data(atPath: pathPrefix + "Darwin/Info.plist"))
            var permissions: [AltCatalogAppItemPermissions.PermissionPrivacy] = []
            for (key, value) in infoPlist.rawValue {
                guard let key = key as? String else { continue }
                guard let value = value as? String else { continue }
                guard key.hasSuffix("UsageDescription") else { continue }
                permissions.append(AltCatalogAppItemPermissions.PermissionPrivacy(name: key, usageDescription: value))
            }
            if !permissions.isEmpty {
                appPermissions.privacy = .init(permissions)
            }

            let entitlementsPlist = try Plist(data: dataSource.data(atPath: pathPrefix + "Darwin/Entitlements.plist"))
            var entitlements: [AltCatalogAppItemPermissions.PermissionEntitlement] = []
            for (key, value) in entitlementsPlist.rawValue {
                if let key = key as? String {
                    entitlements.append(.init(name: key))
                }
            }
            if !entitlements.isEmpty {
                appPermissions.entitlements = entitlements.map({ .init($0) })
            }

            var category: String? // TODO: parse category from Info.plist and map it into https://faq.altstore.io/developers/make-a-source#category-string options: (developer, entertainment, games, lifestyle, other, photo-video, social, utilities)

            // the convention for the path of the app icon
            //let iconURL = rawContentURL.appending(path: "Darwin/Assets.xcassets/AppIcon.appiconset/AppIcon@3x.png")
            let iconURL = relativePaths
                .filter({ $0.hasPrefix("Darwin/Assets.xcassets/AppIcon.appiconset/") })
                .filter({ $0.hasSuffix("@3x.png") })
                .sorting(by: \.count) // e.g., prefer "AppIcon@3x.png" over "AppIcon-29@3x.png"
                .map({ rawContentURL.appending(path: $0) })
                .first

            let tintColor: String? = nil // TODO: parse tint color?

            let screenshotURLs = relativePaths
                .filter({ $0.hasPrefix("Darwin/fastlane/screenshots/en-US/") })
                .map({ rawContentURL.appending(path: $0) })

            let screenshots: AltCatalogAppItem.ScreenshotCollection = .init(["iphone": screenshotURLs.map({ .init($0.absoluteString) })])

            let item = AltCatalogAppItem(name: productName, bundleIdentifier: bundleIdentifier, marketplaceID: marketplaceID, developerName: sourceOptions.developerName, subtitle: subtitle, localizedDescription: localizedDescription, iconURL: iconURL?.absoluteString, tintColor: tintColor, category: category, screenshots: screenshots, versions: [appVersion], appPermissions: appPermissions, patreon: nil)
            return item
        }
    }

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
}

extension NewsItemFormat {
    /// Takes the differences from two catalogs and adds them to the postings with the given formats and limits.
    /// Also sends out updates to various channels, such as Twitter (experimental) and ATOM (planned)
//    public func postUpdates(to catalog: inout AppCatalog, with diffs: [AltCatalogAppItem.Diff], twitterAuth: OAuth1.Info? = nil, newsLimit: Int? = nil, tweetLimit: Int? = nil) async throws -> [Tweeter.PostResponse] {
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
