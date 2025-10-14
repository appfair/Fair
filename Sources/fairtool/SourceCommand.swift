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

    /// Creates an AltStore source from one or more source folders or zip URLs.
    ///
    /// Example use: `fairtool source create https://github.com/appfair/Skip-Notes/archive/refs/tags/0.8.6.zip --adpid 412cd63d-180f-4ee0-a06a-accca8fe349e --upload-app-catalog`
    public struct CreateCommand: FairParsableCommand {
        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var outputOptions: OutputOptions
        @OptionGroup public var sourceOptions: SourceOptions

        @Option(help: ArgumentHelp("The Alternative Distribution Package ID for the release", valueName: "id"))
        public var adpid: String?

        @Flag(inversion: .prefixedNo, help: ArgumentHelp("Upload the app catalog for a single app GitHub release"))
        public var upload: Bool = true

        @Flag(inversion: .prefixedNo, help: ArgumentHelp("Whether to overwrite existing catalog uploads"))
        public var overwrite: Bool = true

        @Option(help: ArgumentHelp("The app token to catalog", valueName: "token"))
        public var token: String

        @Option(help: ArgumentHelp("The app version to catalog", valueName: "version"))
        public var version: String

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

            // old-style way
//            var apps: [(appToken: String, appItem: AltCatalogAppItem)] = []
//            for source in sources {
//                msg(.info, "analyzing source: \(source)")
//                let item = try await createAppItem(path: source)
//                apps.append(item)
//            }
            let item = try await createAppItem(token: token, version: version)
            let apps = [item]
            catalog.apps = apps.map(\.appItem)

            if upload {
                guard let sourceItem = apps.first, apps.count == 1 else {
                    throw AppError("Cannot specify --upload-app-catalog with anything but a single app")
                }

                guard let appVersion = sourceItem.appItem.versions?.first?.version, sourceItem.appItem.versions?.count == 1 else {
                    throw AppError("Cannot specify --upload-app-catalog with anything but a single app version for \(sourceItem.appToken)")
                }

                // when there is a single app and we are generating the catalog for just one, change the catalog name and description to just be that of the app itself
                catalog.name = sourceItem.appItem.name
                catalog.subtitle = sourceItem.appItem.subtitle
                catalog.iconURL = sourceItem.appItem.iconURL
                //catalog.description = sourceItem.appItem.localizedDescription
                catalog.tintColor = sourceItem.appItem.tintColor

                let json = try outputOptions.writeCatalog(catalog)

                // upload the generated catalog to the GitHub releases
                _ = try await FileManager.default.withTemporaryFile(named: "altstore.json", contents: json) { path in
                    try await githubReleaseUpload(appToken: sourceItem.appToken, version: appVersion, paths: [path])
                }
            } else {
                let json = try outputOptions.writeCatalog(catalog)
                _ = json
            }
        }

        func createAppItem(token appToken: String, version: String) async throws -> (appToken: String, appItem: AltCatalogAppItem) {
            guard let repoURL = URL(string: "\(sourceOptions.hubRepository)/\(appToken)") else {
                throw AppError("Could not create repo URL from: \(appToken)")
            }

            // e.g.: https://delivert.appfair.net/Tune-Out/archive/refs/tags/1.0.2.zip
            let sourceArchiveURL = repoURL.appending(path: "archive/refs/tags/\(version).zip")

            msg(.info, "checking sourceArchiveURL: \(sourceArchiveURL.absoluteString)")
            let dataSource: any DataWrapper
            let pathPrefix: String
            let relativePaths: [String] // the paths that will be relative to the pathPrefix

            msg(.info, "downloading sourceArchiveURL: \(sourceArchiveURL.absoluteString)")
            let (localURL, response) = try await prf("download: \(sourceArchiveURL.absoluteURL)") {
                try await URLSession.shared.downloadFile(for: URLRequest(url: sourceArchiveURL, cachePolicy: .returnCacheDataElseLoad))
            }

            try response.validateHTTPCode()
            dataSource = try ZipArchiveDataWrapper(archive: ZipArchive(url: localURL, accessMode: .read))
            pathPrefix = (dataSource.paths.first?.pathName ?? "") + "/" // e.g.: "Tune-Out-1.0.2/"
            relativePaths = dataSource.paths.map(\.pathName).map({ $0.dropFirst(pathPrefix.count).description })

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

            guard let rawContentURL = URL(string: "\(sourceOptions.hubContent)/\(appToken)/refs/tags/\(marketingVersion)") else {
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
            let releaseNotes = try loadFastlaneMetadata("release_notes.txt")

            let manifestURL = releaseBaseURL.appending(path: "manifest.json")
            let manifest: ADPManifest
            let (mdata, mresponse) = try await URLSession.shared.data(for: URLRequest(url: manifestURL))
            if (mresponse as? HTTPURLResponse)?.statusCode == 404 {
                // the manifest.json does not yet exist; if we have specifid the ADPID, download it from the AltStore API, extract it, and upload it to the GitHub release
                guard let adpid = self.adpid else {
                    throw AppError("ADP manifest.json was not found in releases, and could not be automatically fetched due to lack of adpid argument")
                }

                msg(.info, "downloading ADP for id \(adpid)")
                guard let marketplaceEndpoint = URL(string: sourceOptions.marketplaceService) else {
                    throw AppError("AltStoreEndpoing was invalid: \(sourceOptions.marketplaceService)")
                }
                let downloadFile = try await MarketplaceEndpoint(endpointBase: marketplaceEndpoint).download(adpid: adpid, logger: { msg(.info, $0) })
                defer { try? FileManager.default.removeItem(at: downloadFile) }

                let tmpFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

                try FileManager.default.unzipItem(at: downloadFile, to: tmpFolder)
                defer { try? FileManager.default.removeItem(at: tmpFolder) }

                // ensure that the manifest data exists in the folder
                let manifestData = try Data(contentsOf: tmpFolder.appendingPathComponent("manifest.json"))
                manifest = try JSONDecoder().decode(ADPManifest.self, from: manifestData)

                let adpExtractedPaths = try FileManager.default.enumeratedURLs(of: tmpFolder)

                // now upload the contents of the zip to the GitHub repository
                let ghOut = try await githubReleaseUpload(appToken: appToken, version: marketingVersion, paths: adpExtractedPaths.filter(\.pathIsRegularFile))

                msg(.info, "gh upload command: \(String(data: ghOut.stdout, encoding: .utf8) ?? "")")
            } else {
                try mresponse.validateHTTPCode() // make sure it wasn't some other error
                manifest = try JSONDecoder().decode(ADPManifest.self, from: mdata)
            }

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

            // the app version seems to require a size, but that doesn't make sense for a PAL catalog with the separate ADP segments; so just take the largest size of all the variants
            let maxAssetSize = manifest.variants.map(\.variantDetails.uncompressedSize).max() ?? 0 // FIXME: should this be compressedSize instead?

            let minOSVersion: String? = nil // TODO: get from Info.plist
            let maxOSVersion: String? = nil // TODO: get from Info.plist

            let appVersion = AltCatalogAppItemVersion(version: marketingVersion, buildVersion: projectVersion, date: releaseDate, localizedDescription: releaseNotes, downloadURL: manifestURL.absoluteString, size: maxAssetSize, assetURLs: assetURLs, minOSVersion: minOSVersion, maxOSVersion: maxOSVersion)

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
            for (key, _) in entitlementsPlist.rawValue {
                if let key = key as? String {
                    entitlements.append(.init(name: key))
                }
            }
            if !entitlements.isEmpty {
                appPermissions.entitlements = entitlements.map({ .init($0) })
            }

            // TODO: parse category from Info.plist and map it into https://faq.altstore.io/developers/make-a-source#category-string
            // options: developer, entertainment, games, lifestyle, other, photo-video, social, utilities
            // TODO: also parse the .xcconfig for INFOPLIST_KEY_LSApplicationCategoryType
            let category: String = "other"

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
            return (appToken, item)
        }

        /// Upload the specified file paths to the release for the given appToken and version
        func githubReleaseUpload(appToken: String, version: String, paths: [URL]) async throws -> CommandResult {
            // we fork the `gh release upload -R appfair/Tune-Out 1.0.2 files…` for this
            let githubRepo = sourceOptions.fairgroundName + "/" + appToken
            var args = ["release", "upload"]
            if overwrite {
                args += ["--clobber"]
            }
            args += ["-R", githubRepo]
            args += [version]

            args += paths.map(\.path)

            msg(.info, "uploading to GitHub release for \(appToken)/\(version): \(args)")

            let ghOut = try await Process.exec(cmd: "gh", args: args).expect()
            return ghOut
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
