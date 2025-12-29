import Foundation

/// Goals:
/// - Round-trip between: Fastlane metadata files (iOS + Android), F-Droid index-v2.json, altstore.json
public struct Appcat: Codable, Equatable, Sendable {
    /// A locale key.
    /// E.g., https://docs.fastlane.tools/actions/deliver/#available-language-codes : ar-SA, ca, cs, da, de-DE, el, en-AU, en-CA, en-GB, en-US, es-ES, es-MX, fi, fr-CA, fr-FR, he, hi, hr, hu, id, it, ja, ko, ms, nl-NL, no, pl, pt-BR, pt-PT, ro, ru, sk, sv, th, tr, uk, vi, zh-Hans, zh-Hant
    public typealias LocalizationKey = String
    public typealias LocalizedText = Dictionary<LocalizationKey, String>
    public typealias LocalizedTextArray = Dictionary<LocalizationKey, [String]>
    public typealias LocalizedResource = Dictionary<LocalizationKey, ResourceRef>
    public typealias LocalizedImage = Dictionary<LocalizationKey, ImageResourceRef>

    /// The version of this catalog.
    ///
    /// Should be 1.0
    public var appcatVersion: Double
    /// The base URL for this catalog, which will be used as the relative base for child resources
    public var url: String?
    /// The list of default localization keys for this catalog which will be used to resolve text for unknown locales
    public var defaultLocales: [String]?
    /// A title for the catalog
    public var title: LocalizedText
    /// A full description of the catalog
    public var description: LocalizedText
    /// An iconic representation for this catalog
    public var icon: LocalizedImage?
    /// A HEX RGB code for the tint for the display of this app (e.g., `A1C2E3`)
    public var tint: String?
    /// The list of applications
    public var apps: [App]

    public enum CodingKeys: String, CodingKey {
        case appcatVersion = "appcat-version"
        case defaultLocales = "default-locales"
        case title
        case description
        case icon
        case tint
        case url
        case apps
    }

    /// An individual app in a catalog.
    ///
    /// An app consists of high-level metadata (title, summary, description, keywords),
    /// as well as a list of platforms it is available for, each of which can
    /// contain multiple distribution channels and device profiles.
    public struct App: Codable, Equatable, Sendable, AppMetadata {
        /// The unique identifier for this app in the context of the catalog (i.e., not the Android appid or Darwin bundle id)
        public var id: String
        /// The date on which the app was first created
        public var created: Date?
        /// The location of this app's root, either absilute or relative to the catalog's url
        public var location: String?
        /// The top-level title of the app
        public var title: LocalizedText?
        /// A brief summary description of the app
        public var summary: LocalizedText?
        /// A full description of the app
        public var description: LocalizedText?
        /// A localized keyword list
        public var keywords: LocalizedTextArray?
        /// An iconic representation of the app
        public var icon: LocalizedImage
        /// A HEX RGB code for the tint for the display of this app (e.g., `A1C2E3`)
        public var tint: String?
        /// The map of platforms supported by this app
        /// E.g., ios, android, macos, windows, linux
        public var platforms: [String: Platform]

        /// An individual platform supported by an app, which can contain multiple distribution channels.
        ///
        /// A platform generally conforms to a certain operating system, such as Android, iOS, Linux, macOS, Windows.
        public struct Platform: Codable, Equatable, Sendable {
            /// The unique identifier for this app in the context of the platform (e.g., the Android appid or Darwin bundle id)
            public var id: String

            /// The minimum OS version that is needed for this app
            public var minVersion: String?

            /// The maximum OS version that this app can be installed on
            public var maxVersion: String?

            /// The target OS version this app was built for
            public var targetVersion: String?

            /// The channels through which this app is available.
            ///
            /// e.g., Android: direct, fdroid, playstore, samsung
            /// e.g., iOS: direct, altstore, appstore
            public var channels: [String: Channel]

            /// The physical profile of the device that this app is available.
            ///
            /// e.g., Android: phone, sevenInch, tenInch, wear, tv, …
            /// e.g., iOS: iphone, ipad, …
            public var profiles: [String: Profile]

            /// Permissions and entitlements list
            public var permissions: [Permission]?

            /// TODO: what other permission information do we need?
            public struct Permission: Codable, Equatable, Sendable {
                public var key: String
                public var reason: LocalizedText?
            }

            /// A device profile, such as `phone` and `tablet`
            public struct Profile: Codable, Equatable, Sendable {
                /// The screenshots associate which this profile
                public var screenshots: [LocalizedImage]
            }
        }

        /// A specific distribution channel for an app (e.g., `appstore`, `playstore`, `fdroid`, `direct`, `homebrew`, `winget`)
        public struct Channel: Codable, Equatable, Sendable, AppMetadata {
            /// A semantic version for the latest release
            public var version: String // e.g., 1.1.2
            /// A build number or identifier for this app
            public var build: Int? // e.g., 987654
            /// An ISO-8601 date when the given version was released
            public var date: Date // e.g., 2026-01-01T12:00:00Z
            /// An optional channel-specific idenfier for this artifact, like the iTunes identifier
            public var identifier: String?
            /// The artifact download information
            public var artifact: ResourceRef?
            /// Channel-specific categories (e.g., for the App Store: https://developer.apple.com/app-store/categories/)
            public var categories: [String]?

            /// Optional channel-specific title for the app
            public var title: LocalizedText?
            /// Optional channel-specific  summary description for the app
            public var summary: LocalizedText?
            /// Optional channel-specific full description for the app
            public var description: LocalizedText?
            /// Optional channel-specific localized keyword list
            public var keywords: LocalizedTextArray?

            /// Optional release notes for this version in this channel
            public var notes: LocalizedText?
        }
    }

    public struct ResourceRef: Codable, Equatable, Sendable, ResourceLocation {
        public var mimeType: String?
        public var location: String
        public var size: Int64
        public var hash: String
    }

    public struct ImageResourceRef: Codable, Equatable, Sendable, ResourceLocation {
        public var mimeType: String?
        public var location: String
        public var size: Int64
        public var hash: String
        public var width: Int
        public var height: Int
        public var caption: String?
    }
}

public protocol ResourceLocation {
    /// An optional MIME type for the resource
    var mimeType: String? { get }
    /// The path to the resource, either a full URL or a relative path to the parent's base URL
    var location: String { get }
    /// The size of the resource, in bytes
    var size: Int64 { get }
    /// A SHA-256 hash of the contents of the resource
    var hash: String { get }
}

public protocol AppMetadata {
    /// The top-level title of the app
    var title: Appcat.LocalizedText? { get }
    /// A brief description of the app
    var summary: Appcat.LocalizedText? { get }
    /// A full description of the app
    var description: Appcat.LocalizedText? { get }
    /// A list of keywords for the app
    var keywords: Appcat.LocalizedTextArray? { get }
}

extension Appcat {
    /// Returns the first element of the localized map based on the preferred defaultLocales
    func localized<T>(in dict: [String: T]?) -> T? {
        ((self.defaultLocales ?? []) + ["en-US"]).compactMap {
            dict?[$0]
        }.first
        ?? dict?.sorted(by: { $0.key < $1.key }).first?.value // fall back to any element in the dictionary (sorted for stability)
    }

    /// Returns a full URL relative to the given relative path
    func location(relativeTo: String?) -> String? {
        if let relativeTo, let baseURLString = self.url, let baseURL = URL(string: baseURLString) {
            return URL(string: relativeTo, relativeTo: baseURL)?.absoluteString ?? relativeTo
        } else {
            return relativeTo // no base URL, so just return the fragment
        }
    }
}

extension Appcat {

    public func toAltstoreSource(channelName: String = "altstore") -> AltCatalog {
        var apps: [AltCatalog.App] = []
        for app in self.apps {
            guard let platform = app.platforms["ios"] else { continue }
            guard let channel = platform.channels[channelName] else { continue }
            guard let artifact = channel.artifact else { continue }

            let appURL = self.location(relativeTo: app.location)

            /// Returns a full URL relative to the given relative path
            func appLocation(relativeTo: String?) -> String? {
                if let relativeTo, let baseURLString = appURL, let baseURL = URL(string: baseURLString) {
                    return URL(string: relativeTo, relativeTo: baseURL)?.absoluteString ?? relativeTo
                } else {
                    return relativeTo // no base URL, so just return the fragment
                }
            }

            var entitlements: [AltCatalog.App.Permission.PermissionEntitlement] = []
            var privacy: [AltCatalog.App.Permission.PermissionPrivacy] = []

            // .init(AltCatalog.App.Permission.PermissionEntitlement(name: "com.apple.developer.networking.background-task.fetch"))
            // AltCatalog.App.Permission.PermissionPrivacy(name: "Bluetooth", usageDescription: "")
            for permission in platform.permissions ?? [] {
                if permission.key.contains(".") { // e.g., com.apple.developer.networking.background-task.fetch
                    entitlements.append(.init(name: permission.key))
                } else {
                    privacy.append(.init(name: permission.key, usageDescription: self.localized(in: permission.reason) ?? ""))
                }
            }

            let permissions: AltCatalog.App.Permission? = entitlements.isEmpty && privacy.isEmpty ? nil : AltCatalog.App.Permission(entitlements: entitlements.map({ .init($0) }), privacy: .init(privacy))

            var screenshots: [String: [AltCatalog.App.ScreenshotChoice]] = [:]
            for (profileName, profile) in platform.profiles {
                let shots: [AltCatalog.Screenshot] = profile.screenshots.compactMap { screenshot in
                    guard let shot = self.localized(in: screenshot) else { return nil }
                    return AltCatalog.Screenshot(imageURL: appLocation(relativeTo: shot.location) ?? shot.location, width: shot.width, height: shot.height)
                }

                if !shots.isEmpty {
                    screenshots[profileName] = shots.map({ .init($0) })
                }
            }

            // we assume the category matches one of the AltStore hardwired categories
            let category = channel.categories?.first ?? "other"

            let altVersion = AltCatalog.App.Version(
                version: channel.version,
                buildVersion: channel.build?.description,
                marketingVersion: nil,
                date: channel.date.ISO8601Format(),
                localizedDescription: self.localized(in: channel.notes),
                localizedDescriptions: channel.notes,
                downloadURL: appLocation(relativeTo: artifact.location) ?? artifact.location,
                size: artifact.size,
                assetURLs: nil,
                minOSVersion: platform.minVersion,
                maxOSVersion: platform.maxVersion)

            let altApp = AltCatalog.App(
                name: self.localized(in: channel.title ?? app.title) ?? "",
                bundleIdentifier: platform.id,
                marketplaceID: channel.identifier,
                developerName: nil,
                subtitle: self.localized(in: channel.summary ?? app.summary),
                localizedSubtitles: channel.summary ?? app.summary,
                localizedDescription: self.localized(in: channel.description ?? app.description),
                localizedDescriptions: channel.description ?? app.description,
                iconURL: appLocation(relativeTo: self.localized(in: app.icon)?.location),
                tintColor: app.tint,
                category: category,
                screenshots: screenshots.isEmpty ? nil : .init(screenshots),
                versions: [altVersion],
                appPermissions: permissions,
                patreon: nil)

            apps.append(altApp)
        }

        return AltCatalog(name: self.localized(in: self.title), subtitle: nil, description: self.localized(in: self.description), iconURL: self.location(relativeTo: self.localized(in: self.icon)?.location), headerURL: nil, website: nil, fediUsername: nil, patreonURL: nil, tintColor: self.tint, featuredApps: nil, apps: apps, news: nil)
    }

//    func toFDroidIndex(repoURL: String) -> FDroidIndex {
//        var repo = FDroidIndex.Repo(name: <#T##FDroidIndex.LocalizedText#>, icon: <#T##FDroidIndex.LocalizedFile#>, address: repoURL, timestamp: <#T##Int64#>)
//        var packages = Dictionary<String, FDroidIndex.Package>()
//        for app in self.apps {
//            var fdroidApp = FDroidIndex.Package(metadata: <#T##FDroidIndex.Package.Metadata#>, versions: <#T##Dictionary<String, FDroidIndex.Package.PackageVersion>#>)
//            packages[app.id] = fdroidApp
//        }
//        return FDroidIndex(repo: repo, packages: packages)
//    }
}
