// Copyright (c) 2022 - 2026 The App Fair Project <info@appfair.org>
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import FairCore
import FairExpo
import ArgumentParser

public struct SourceCommand : AsyncParsableCommand {
    public static var configuration = CommandConfiguration(
        commandName: "source",
        abstract: "App source catalog management commands",
        subcommands: [
            CreateCommand.self,
            MergeCommand.self,
            //VerifyCommand.self,
            //PostReleaseCommand.self,
        ])

    public init() {
    }

    public struct CreateCommand: AsyncParsableCommand {
        public static var configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Generate a catalog for an app",
            subcommands: [
                CreateAltStoreCatalogCommand.self,
                CreateFDroidCatalogCommand.self,
            ])

        public init() {
        }
    }

    public struct CreateFDroidCatalogCommand: CreateCatalogCommand {
        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var sourceOptions: SourceOptions

        @Flag(inversion: .prefixedNo, help: ArgumentHelp("Upload the app catalog for a single app GitHub release"))
        public var upload: Bool = false

        @Flag(inversion: .prefixedNo, help: ArgumentHelp("Whether to overwrite existing catalog uploads"))
        public var overwrite: Bool = true

        @Argument(help: ArgumentHelp("App token/versions to create the catalog for", valueName: "apps"))
        public var appTokens: [String]

        public static var configuration = CommandConfiguration(
            commandName: "fdroid",
            abstract: "Create an F-Droid catalog source")

        public typealias Output = FDroidIndex

        public init() {
        }

        public func run() async throws {
            let output = try await createCatalog()
            try msgOptions.writeOutput(output)
        }

        public func createCatalog() async throws -> Output {
            var packageList: [(String, FDroidIndex.Package)] = []

            for appToken in appTokens {
                let tokenParts = appToken.split(separator: "/")

                let appName = tokenParts.first?.description ?? appToken
                let appVersion = tokenParts.count > 1 ? tokenParts.dropFirst().first?.description : nil

                msg(.info, "creating app item for: \(appName) version=\(appVersion ?? "")")
                let item = try await createFDroidPackage(token: appName, version: appVersion)
                packageList.append(item)
            }


            var packages: Dictionary<String, FDroidIndex.Package> = [:]
            for (appid, package) in packageList {
                packages[appid] = package
            }

            let repo = FDroidIndex.Repo(name: ["en-US": "name"], icon: ["en-US": .init(name: "images/icon/english.svg")], address: "", timestamp: 0)
            let catalog = FDroidIndex(repo: repo, packages: packages)

            //let json = try outputOptions.writeCatalog(catalog)
            return catalog
        }

        public func createFDroidPackage(token: String, version latestVersion: String?) async throws -> (String, FDroidIndex.Package) {
            msg(.info, "creating f-droid catalog for token: \(token)")

            let version = try await fetchLatestVersion(token: token, unless: latestVersion)
            let dataSource = try await fetchSourceZip(token: token, version: version)
            let pathPrefix = (dataSource.paths.first?.pathName ?? "") + "/" // e.g.: "Tune-Out-1.0.2/"
            let relativePaths = dataSource.paths.map(\.pathName).map({ $0.dropFirst(pathPrefix.count).description })

            let fastlaneMetadataPrefix = "Android/fastlane/metadata/android"
            func loadAndroidFastlaneMetadata(_ path: String, locale: String) throws -> String? {
                String(data: try dataSource.data(atPath: pathPrefix + "\(fastlaneMetadataPrefix)/\(locale)/\(path)"), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // build the list of locales from everything under the Android/fastlane/metadata/android/ path
            let locales = relativePaths
                .filter({ $0.hasPrefix(fastlaneMetadataPrefix + "/") })
                .map({ $0.split(separator: "/") })
                .filter({ $0.count == 5 })
                .compactMap({ $0.last?.description })

            func loadFastlaneMetadata(_ key: String) -> FDroidIndex.LocalizedText? {
                var dict = FDroidIndex.LocalizedText()

                for locale in locales {
                    if let value = try? loadAndroidFastlaneMetadata(key, locale: locale) {
                        dict[locale] = value
                    }
                }

                if !dict.isEmpty {
                    return dict
                } else {
                    return nil
                }
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
            //let productName = try env(key: "PRODUCT_NAME")
            //let marketingVersion = try env(key: "MARKETING_VERSION")
            //let projectVersion = try env(key: "CURRENT_PROJECT_VERSION")
            let appIdentifier = try env(key: "PRODUCT_BUNDLE_IDENTIFIER").replacing("-", with: "_") // FIXME: check manifest for overridden identifier
            //let packageName = try env(key: "ANDROID_PACKAGE_NAME")


            let file = FDroidIndex.File(name: "", sha256: "", size: 0)
            let manifest = FDroidIndex.Package.Manifest(versionName: "", versionCode: 0)
            let packageVersion = FDroidIndex.Package.PackageVersion(added: 0, file: file, manifest: manifest)

            var metadata = FDroidIndex.Package.Metadata(added: 0, lastUpdated: 0)
            metadata.name = loadFastlaneMetadata("title.txt")
            metadata.summary = loadFastlaneMetadata("short_description.txt")
            metadata.description = loadFastlaneMetadata("full_description.txt")
            let package = FDroidIndex.Package(metadata: metadata, versions: [version: packageVersion])

            return (appIdentifier, package)
        }
    }

    /// Creates an AltStore source from one or more source folders or zip URLs.
    ///
    /// Example use: `fairtool source create altstore --adpid 412cd63d-180f-4ee0-a06a-accca8fe349e Skip-Notes/0.8.6`
    public struct CreateAltStoreCatalogCommand: CreateCatalogCommand, AppIndexCommand, HubCommand, ASCCommand {
        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var sourceOptions: SourceOptions
        @OptionGroup public var hubOptions: HubOptions
        @OptionGroup public var ascOptions: ASCOptions
        @OptionGroup public var appIndexOptions: AppIndexOptions

        @Option(help: ArgumentHelp("The Alternative Distribution Package ID for the release", valueName: "id"))
        public var adpid: String?

        @Option(help: ArgumentHelp("The App Store Connect version ID to use for building the package"))
        public var versionid: String?

        @Flag(inversion: .prefixedNo, help: ArgumentHelp("Upload the app catalog for a single app GitHub release"))
        public var upload: Bool = false

        @Option(name: .shortAndLong, help: ArgumentHelp("The base directory for downloading package"))
        public var directory: String?

        @Option(help: ArgumentHelp("The number of times to retry failed requests")) // TODO: not yet implemented
        public var retryCount: Int?

        @Flag(inversion: .prefixedNo, help: ArgumentHelp("Whether to overwrite existing catalog uploads"))
        public var overwrite: Bool = true

        @Flag(inversion: .prefixedNo, help: ArgumentHelp("Whether to generate assetURLs redirects for flattened assets"))
        public var generateAssetURLs: Bool = false // we default this to false in order to allow delivery.appfair.net/.htaccess to handle the recdirects for delta/ and variant/ folders

        @Argument(help: ArgumentHelp("App token/versions for the catalog", valueName: "apps"))
        public var appTokens: [String] = []

        public static var configuration = CommandConfiguration(
            commandName: "altstore",
            abstract: "Create an AltSouce catalog source",
            usage: """
            # create a single entry by uploading an Alternative Distribution Package
            fairtool source create altstore --versionid 211bf27b-ab9f-46eb-b11a-8f3d0adc8ebe
            """)

        public typealias Output = AltCatalog


        public init() {
        }

        public func run() async throws {
            let output = try await createCatalog()
            try msgOptions.writeOutput(output)
        }

        fileprivate func fetchADP(uploadToHub: Bool = true) async throws -> String {
            // when we specified the versionid and no app tokens, then download the version info
            let endpoint = try createASCEndpoint()
            let adpid = try await endpoint.resolveADPID(from: self.adpid, versionID: self.versionid)

            let directory = self.directory ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let (manifest, files) = try await endpoint.downloadADP(adpid: adpid, directory: directory, logger: { msg(.info, $0) })

            let appBundle = manifest.bundleId
            if !appBundle.hasPrefix("org.appfair.app.") {
                throw AppError("Bundle for \(manifest.bundleId) is not in the expected format: org.appfair.app.<bundle-id>")
            }

            // we need to look up the bundleID from the app index
            let appIndex = try await appIndexOptions.fetchAppIndex()
            guard let app = appIndex.apps.first(where: { $0.ios?.bundleId == appBundle }) else {
                throw AppError("Could not locate bundle ID \(manifest.bundleId) is in app index at \(appIndexOptions.appIndex)")
            }

            let appToken = app.token
            let appVersion = manifest.shortVersionString
            
            // now upload files to releases…
            if uploadToHub {
                try await githubReleaseUpload(appToken: appToken, version: appVersion, overwrite: true, paths: Set(files.values))
            }

            // now populate the app name and version from the bundle
            return appToken + "/" + appVersion
        }
        
        public func createCatalog() async throws -> Output {
            msg(.info, "creating altstore catalog")
            var catalog = AltCatalog()
            catalog.name = sourceOptions.catalogName

            var appTokens = appTokens
            if appTokens.isEmpty, (adpid != nil || versionid != nil) {
                // no token specified; try to extract it from the adpid or versionid and transfer the ADP up to the githubReleases
                // look up the bundle ID in the app tokens list
                //let appIndex = try await appIndexOptions.fetchAppIndex()
                appTokens = [try await fetchADP()]
            }

            var apps: [(appToken: String, appItem: AltCatalog.App)] = []
            for appToken in appTokens {
                let tokenParts = appToken.split(separator: "/")

                let appName = tokenParts.first?.description ?? appToken
                let appVersion = tokenParts.count > 1 ? tokenParts.dropFirst().first?.description : nil

                msg(.info, "creating app item for: \(appName) version=\(appVersion ?? "")")
                let item = try await createAltCatalogAppItem(token: appName, version: appVersion)
                apps.append(item)
            }

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

                let json = try catalog.toJSON(outputFormatting: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes], dateEncodingStrategy: .iso8601, dataEncodingStrategy: .base64)

                // upload the generated catalog to the GitHub releases
                try await fm.withTemporaryFile(named: "altstore.json", contents: json) { path in
                    try await githubReleaseUpload(appToken: sourceItem.appToken, version: appVersion, overwrite: overwrite, paths: [path])
                }
            }

            return catalog
        }

        func createAltCatalogAppItem(token appToken: String, version releaseVersion: String?) async throws -> (appToken: String, appItem: AltCatalog.App) {
            let version = try await fetchLatestVersion(token: appToken, unless: releaseVersion)
            let dataSource = try await fetchSourceZip(token: appToken, version: version)
            let pathPrefix = (dataSource.paths.first?.pathName ?? "") + "/" // e.g.: "Tune-Out-1.0.2/"
            let relativePaths = dataSource.paths.map(\.pathName).map({ $0.dropFirst(pathPrefix.count).description })

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

            //msg(.info, "productName: \(productName)")

            let releaseDate = Calendar.current.startOfDay(for: Date()).ISO8601Format() // FIXME: use the date of the release

            func loadDarwinFastlaneMetadata(_ path: String, locale: String = "en-US") throws -> String? {
                String(data: try dataSource.data(atPath: pathPrefix + "Darwin/fastlane/metadata/\(locale)/\(path)"), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let localizedTitle = try loadDarwinFastlaneMetadata("title.txt")
            let localizedDescription = try loadDarwinFastlaneMetadata("description.txt")
            let subtitle = try loadDarwinFastlaneMetadata("subtitle.txt")
            let releaseNotes = try loadDarwinFastlaneMetadata("release_notes.txt")
            let primaryCategory = try? loadDarwinFastlaneMetadata("primary_category.txt")

            let repositoryURL = try self.repositoryBaseURL.appending(component: appToken)
            let releaseBaseURL = repositoryURL.appending(components: "releases", "download", version)
            let rawContentURL = try self.contentURL.appending(components: appToken, "refs", "tags", version)

            let manifestURL = releaseBaseURL.appending(path: "manifest.json")
            let (mdata, mresponse) = try await URLSession.shared.data(for: URLRequest(url: manifestURL))
            try mresponse.validateHTTPCode()
            let manifest: ADPManifest = try JSONDecoder().decode(ADPManifest.self, from: mdata)

            let marketplaceID = manifest.appleItemId

            if manifest.bundleId != bundleIdentifier {
                throw AppError("Bundle identifier mismatch with manifest.json: \(manifest.bundleId) vs. \(bundleIdentifier)")
            }
            if manifest.shortVersionString != marketingVersion {
                throw AppError("Bundle version mismatch with manifest.json: \(manifest.shortVersionString) vs. \(marketingVersion)")
            }

            // build the mapping from delta/variant asset to the flattened form stored at the GitHub release
            var assetURLs: [String: String]? = nil

            if generateAssetURLs {
                assetURLs = [:]
                assetURLs?["manifest"] = manifestURL.absoluteString
                assetURLs?["signature"] = releaseBaseURL.appending(path: "signature").absoluteString
                // all the other assets are either deltas/ or variants/
                for assetPath in manifest.deltas.map(\.assetPath) + manifest.variants.map(\.assetPath) {
                    guard let lastAssetPath = assetPath.split(separator: "/").last else { continue }
                    let lastAssetBase = lastAssetPath.split(separator: ".").dropLast().joined(separator: ".")
                    assetURLs?[lastAssetBase] = releaseBaseURL.appending(path: lastAssetPath).absoluteString
                }
            }

            // the app version seems to require a size, but that doesn't make sense for a PAL catalog with the separate ADP segments; so just take the largest size of all the variants
            let maxAssetSize = manifest.variants.map(\.variantDetails.uncompressedSize).max() ?? 0 // FIXME: should this be compressedSize instead?

            let minOSVersion: String? = nil // TODO: get from Info.plist
            let maxOSVersion: String? = nil // TODO: get from Info.plist

            let appVersion = AltCatalog.App.Version(version: marketingVersion, buildVersion: projectVersion, date: releaseDate, localizedDescription: releaseNotes, downloadURL: manifestURL.absoluteString, size: maxAssetSize, assetURLs: assetURLs, minOSVersion: minOSVersion, maxOSVersion: maxOSVersion)

            var appPermissions = AltCatalog.App.Permission()

            let infoPlist = try Plist(data: dataSource.data(atPath: pathPrefix + "Darwin/Info.plist"))
            var permissions: [AltCatalog.App.Permission.PermissionPrivacy] = []
            for (key, value) in infoPlist.rawValue {
                guard let key = key as? String else { continue }
                guard let value = value as? String else { continue }
                guard key.hasSuffix("UsageDescription") else { continue }
                permissions.append(AltCatalog.App.Permission.PermissionPrivacy(name: key, usageDescription: value))
            }
            if !permissions.isEmpty {
                appPermissions.privacy = .init(permissions.sorting(by: \.name))
            }

            let entitlementsPlist = try Plist(data: dataSource.data(atPath: pathPrefix + "Darwin/Entitlements.plist"))
            var entitlements: [AltCatalog.App.Permission.PermissionEntitlement] = []
            for (key, _) in entitlementsPlist.rawValue {
                if let key = key as? String {
                    entitlements.append(.init(name: key))
                }
            }
            if !entitlements.isEmpty {
                appPermissions.entitlements = entitlements.sorting(by: \.name).map({ .init($0) })
            }

            // TODO: parse category from Info.plist and map it into https://faq.altstore.io/developers/make-a-source#category-string
            // options: developer, entertainment, games, lifestyle, other, photo-video, social, utilities
            // TODO: also parse the .xcconfig for INFOPLIST_KEY_LSApplicationCategoryType like "public.app-category.utilities"
            // TODO: fall back to names in fastlane primaryCategory
            let _ = primaryCategory
            let category = "other"

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

            let screenshots: AltCatalog.App.ScreenshotCollection = .init(["iphone": screenshotURLs.map({ .init($0.absoluteString) })])

            let item = AltCatalog.App(name: localizedTitle ?? productName, bundleIdentifier: bundleIdentifier, marketplaceID: marketplaceID, developerName: sourceOptions.developerName, subtitle: subtitle, localizedDescription: localizedDescription, iconURL: iconURL?.absoluteString, tintColor: tintColor, category: category, screenshots: screenshots, versions: [appVersion], appPermissions: appPermissions, patreon: nil)
            return (appToken, item)
        }
    }

    public struct MergeCommand: AsyncParsableCommand {
        public static var configuration = CommandConfiguration(
            commandName: "merge",
            abstract: "Merge multiple app catalogs into a single source",
            subcommands: [
                MergeAltStoreCatalogCommand.self,
                MergeFDroidCatalogCommand.self,
            ])

        public init() {
        }
    }

    public struct MergeFDroidCatalogCommand: AppIndexCommand {
        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var sourceOptions: SourceOptions
        @OptionGroup public var appIndexOptions: AppIndexOptions

        @Flag(inversion: .prefixedNo, help: ArgumentHelp("Upload the app catalog for a single app GitHub release"))
        public var upload: Bool = false

        @Flag(inversion: .prefixedNo, help: ArgumentHelp("Whether to overwrite existing catalog uploads"))
        public var overwrite: Bool = true

        @Argument(help: ArgumentHelp("App token/versions to merge", valueName: "apps"))
        public var apps: [String]


        public static var configuration = CommandConfiguration(
            commandName: "fdroid",
            abstract: "Merge F-Droid catalogs into a single source")

        public typealias Output = FDroidIndex

        public init() {
        }

        public func run() async throws {
            msg(.info, "merging altstore catalog")
            throw AppError("TODO")

//            let output = try await createCatalog()
//            try msgOptions.writeOutput(output)
        }
    }

    public struct MergeAltStoreCatalogCommand: AppIndexCommand {
        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var sourceOptions: SourceOptions
        @OptionGroup public var appIndexOptions: AppIndexOptions

        @Flag(inversion: .prefixedNo, help: ArgumentHelp("Upload the app catalog for a single app GitHub release"))
        public var upload: Bool = false

        //@Flag(inversion: .prefixedNo, help: ArgumentHelp("Whether to overwrite existing catalog uploads"))
        //public var overwrite: Bool = true

        public static var configuration = CommandConfiguration(
            commandName: "altstore",
            abstract: "Merge AltStore catalogs into a single source")

        public typealias Output = AltCatalog

        public init() {
        }

        public func run() async throws {
            msg(.info, "merging altstore catalog")

            // fetch catalog template and app list from appIndexOptions
            let indexSource: AppCatalogIndex = try await appIndexOptions.fetchAppIndex()
            var altSourceIndex: Output = indexSource.catalogs.altstore ?? AltCatalog()

            // go through each app and fetch the latest releases/altstore.json
            for app in indexSource.apps {
                guard let ios = app.ios else {
                    continue // Android-only app
                }

                msg(.info, "app: \(ios.bundleId)")

                // get the releases feed from the app release
                let releaseTags = try await self.fetchReleaseTags(token: app.token)
                var altstoreData: Data?
                for version in releaseTags {
                    let altstoreURL = try releaseAssetURL(token: app.token, version: version, resource: "altstore.json")
                    do {
                        (altstoreData, _) = try await URLSession.shared.fetch(request: URLRequest(url: altstoreURL))
                        break
                    } catch {
                        // we tolerate missing assets because a release might not yet contain the altstore data due to the ADP not yet being uploaded; try the next release
                        continue
                    }
                }
                if let altstoreData {
                    let altstoreFragment = try JSONDecoder().decode(AltCatalog.self, from: altstoreData)
                    guard let app = altstoreFragment.apps.first else {
                        throw AppError("AltStore catalog did not contain any apps")
                    }

                    // add the app to the catalog
                    altSourceIndex.apps.append(app)
                }
            }

            try msgOptions.writeEncodableOutput(altSourceIndex)
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


protocol CatalogCommand : FairParsableCommand {
    var sourceOptions: SourceOptions { get }
}

protocol CreateCatalogCommand : CatalogCommand {
}

protocol AppIndexCommand : CatalogCommand {
    var appIndexOptions: AppIndexOptions { get }
}

public struct AppIndexOptions: ParsableArguments {
    /// https://appfair.net/appfair-apps.json
    @Option(help: ArgumentHelp("The URL of the catalog index", valueName: "url"))
    public var appIndex: String = "https://appfair.net/appfair-apps.json"

    public init() {
    }
    
    /// Fetches and parsed the app index from the given index parameter
    func fetchAppIndex() async throws -> AppCatalogIndex {
        let url = URL(fileOrScheme: self.appIndex)
        let (data, _) = try await URLSession.shared.fetch(request: URLRequest(url: url))
        let index = try JSONDecoder().decode(AppCatalogIndex.self, from: data)
        return index
    }
}

extension CatalogCommand {
    var repositoryBaseURL: URL {
        get throws {
            guard let repoURL = URL(string: sourceOptions.hubRepository) else {
                throw AppError("Could not create repository URL from: \(sourceOptions.hubRepository)")
            }
            return repoURL
        }
    }

    var contentURL: URL {
        get throws {
            guard let repoURL = URL(string: sourceOptions.hubContent) else {
                throw AppError("Could not create content URL from: \(sourceOptions.hubContent)")
            }
            return repoURL
        }
    }

    /// Get the latest version by parsing the RSS for the hub's releases
    func fetchLatestVersion(token: String, unless existingVersion: String?) async throws -> String {
        if let existingVersion { return existingVersion }

        guard let latestVersion = try await fetchReleaseTags(token: token).first else {
            throw AppError("No releases found in atom feed for \(token)")
        }
        msg(.info, "fetched latest version for \(token): \(latestVersion)")
        return latestVersion
    }

    func fetchReleaseTags(token: String) async throws -> [String] {
        let feedURL = try repositoryBaseURL.appending(path: token).appending(path: "releases.atom")
        let (atomData, _) = try await URLSession.shared.fetch(request: URLRequest(url: feedURL))

        let atom = try AtomFeed(xmlData: atomData)

        return try atom.entries.map { release in
            // the GitHub Atom feed doesn't list the actual tag directly, so we parse it from the link in the entry
            guard let link = release.links?.first(where: { $0.rel == "alternate" })?.href,
                  let linkURL = URL(string: link) else {
                throw AppError("No matching links in latest RSS feed for release")
            }

            // the link will be something like:
            let latestVersion = linkURL.lastPathComponent
            return latestVersion
        }
    }

    func releaseAssetURL(token: String, version: String, resource: String) throws -> URL {
        // e.g.: https://delivery.appfair.net/Tune-Out/releases/download/1.0.8/altstore.json
        try repositoryBaseURL.appending(path: token).appending(components: "releases", "download", version, resource)
    }

    func fetchSourceZip(token: String, version: String) async throws -> ZipArchiveDataWrapper {
        let repositoryURL = try repositoryBaseURL.appending(path: token)

        // e.g.: https://delivery.appfair.net/Tune-Out/archive/refs/tags/1.0.2.zip
        let sourceArchiveURL = repositoryURL.appending(components: "archive", "refs", "tags", version + ".zip")

        //msg(.info, "checking sourceArchiveURL: \(sourceArchiveURL.absoluteString)")
        msg(.info, "downloading sourceArchiveURL: \(sourceArchiveURL.absoluteString)")
        let (localURL, response) = try await prf("download: \(sourceArchiveURL.absoluteURL)") {
            try await URLSession.shared.downloadFile(for: URLRequest(url: sourceArchiveURL, cachePolicy: .returnCacheDataElseLoad))
        }

        try response.validateHTTPCode()
        let dataSource = try ZipArchiveDataWrapper(archive: ZipArchive(url: localURL, accessMode: .read))

        return dataSource
    }
}

extension HubCommand {
    func githubAPIRequest(url: URL, method: String? = nil) throws -> URLRequest {
        guard let token = try self.hubOptions.fairHub().authToken else {
            throw AppError("No GitHub token specified in arguments or GITHUB_TOKEN environment")
        }

        var request = URLRequest(url: url)
        if let method {
            request.httpMethod = method
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Upload the specified file paths to the release for the given appToken and version
    func githubReleaseUpload(appToken: String, version: String, overwrite: Bool, paths: Set<URL>) async throws {
        let orgName = self.hubOptions.organizationName
        guard let releasesEndpoint = URL(string: "https://api.github.com/repos/\(orgName)/\(appToken)/releases") else {
            throw AppError("Could not create base release URL from \(appToken)/\(version)")
        }

        // need to get the releaseID from the version tag
        // https://docs.github.com/rest/releases/releases#get-a-release-by-tag-name
        let releaseInfoURL = releasesEndpoint.appending(components: "tags", version)
        msg(.info, "fetching release ID for: \(orgName)/\(appToken)/\(version) from: \(releaseInfoURL.absoluteString)")
        let (releaseData, releaseResult) = try await URLSession.shared.fetch(request: githubAPIRequest(url: releaseInfoURL, method: "GET"))
        _ = releaseResult
        let releaseInfo = try JSONDecoder().decode(GitHubRepoReleasesResponse.self, from: releaseData)
        let releaseID = releaseInfo.id
        // create a map from name: digest
        let releaseAssets: [String : (assetID: Int64?, digest: String?)] = Dictionary(releaseInfo.assets?.compactMap({ $0.name == nil ? nil : ($0.name!, (assetID: $0.id, digest: $0.digest)) }) ?? [], uniquingKeysWith: { $1 })

        msg(.info, "fetched release ID for: \(orgName)/\(appToken)/\(version): \(releaseID)")
        // we sort the paths so that the manifest.json and signature is uploaded after the hashes, so that a partial upload is not incorrectly seen as being complete and valid
        for path in paths.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let assetName = path.lastPathComponent

            let fileData = try Data(contentsOf: path, options: .mappedIfSafe)
            let fileDigest = "sha256:" + fileData.sha256().hex()

            // check to see if an asset already exists with the given name; if so, and if they checksum matches, skip over it; otherwise delete it so we can re-upload it
            if let assetInfo = releaseAssets[assetName] {
                if assetInfo.digest == fileDigest {
                    msg(.info, "release asset: \(assetName) is already uploaded and digest matches: \(fileDigest)")
                    continue
                }

                if let assetID = assetInfo.assetID {
                    if !overwrite {
                        msg(.info, "release asset: \(assetName) is already uploaded with different digest but overwrite not specified")
                        continue
                    }
                    // release asset already exists with a different checksum; delete it so we can replace it
                    // https://docs.github.com/rest/releases/assets#delete-a-release-asset
                    let deleteAssetURL = releasesEndpoint.appending(components: "assets", "\(assetID)")
                    let deleteRequest = try githubAPIRequest(url: deleteAssetURL, method: "DELETE")
                    msg(.info, "deleting asset: \(deleteRequest)")
                    let (deleteData, deleteResult) = try await URLSession.shared.fetch(request: deleteRequest)
                    _ = deleteResult
                    msg(.debug, "delete asset response: \(String(data: deleteData, encoding: .utf8) ?? "none")")
                }
            }

            guard let uploadURL = URL(string: "https://uploads.github.com/repos/\(orgName)/\(appToken)/releases/\(releaseID)/assets?name=\(assetName)") else {
                throw AppError("Could not create URL for upload from \(appToken)/\(version)")
            }
            msg(.info, "uploading release asset: \(assetName) to \(uploadURL.absoluteString)")

            // https://docs.github.com/rest/releases/assets
            var request = try githubAPIRequest(url: uploadURL, method: "POST")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

            //request.httpBody = fileData
            let (data, result) = try await URLSession.shared.upload(for: request, fromFile: path)
            msg(.info, "result: \(String(data: data, encoding: .utf8) ?? "none")")
            try result.validateHTTPCode()
        }
    }
}

/// Information about a GitHub release, including assets
/// https://docs.github.com/rest/releases/releases#get-a-release-by-tag-name
private struct GitHubRepoReleasesResponse : Decodable {
    let id: Int64
    let url: String
    let assets_url: String
    let node_id: String? // "RE_kwDOPbKbF84PVZY_"
    let tag_name: String? // "1.0.7"
    //let target_commitish: String? // "main"
    let name: String? // "Release 1.0.7"
    //let draft: Bool // false
    //let immutable: Bool // false
    //let prerelease: Bool // false
    //let created_at: Date? // "2025-10-26T00:54:22Z"
    //let updated_at: Date? // "2025-11-06T01:02:37Z"
    //let published_at: Date? // "2025-10-26T01:19:18Z"
    let assets: [Asset]?

    struct Asset : Decodable {
        //let url: String? // "https://api.github.com/repos/appfair/Tune-Out/releases/assets/312666587",
        let id: Int64? // 312666587,
        let node_id: String? // "RA_kwDOPbKbF84Sounb",
        let name: String? // "06ccfb94-d5f3-3593-a57b-9030697f6a6b.ipa",
        //let label: String? // "",
        //let content_type: String? // "application/octet-stream",
        let state: String? // "uploaded",
        let size: Int64? // 968779,
        let digest: String? // "sha256:c909df40ad2a4046b830444006a7d2aee2746fdcaea7fe2d40da12b0f7210f81",
        //let download_count: Int? // 0,
        //let created_at: Date? // "2025-11-05T02:26:36Z",
        //let updated_at: Date? // "2025-11-05T02:26:36Z",
        //let browser_download_url: String? // "https://github.com/appfair/Tune-Out/releases/download/1.0.7/06ccfb94-d5f3-3593-a57b-9030697f6a6b.ipa"
    }
}
