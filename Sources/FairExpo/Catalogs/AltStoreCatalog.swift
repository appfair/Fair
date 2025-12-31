// Copyright (c) 2022 - 2026 The App Fair Project <info@appfair.org>
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-or-later
import Swift
import FairCore
import Foundation

/// A catalog of apps, consisting of a ``name``, ``identifier``,
/// individual ``AltCatalog.App`` instances for each app indexed by this catalog,
/// as well as optional ``AltCatalog.NewsItem`` items.
///
/// https://faq.altstore.io/developers/make-a-source
///
/// See: https://github.com/altstoreio/AltStore/blob/HEAD/AltStoreCore/Model/Source.swift
public struct AltCatalog: Codable, Equatable {
    /// The name of your source as it will appear in AltStore.
    public var name: String?
    /// A short, one-sentence description of your source. This will appear underneath the source's name on its About page.
    public var subtitle: String?
    /// A full-length description of your source. This can include any information you believe is relevant for your source, such as information about your apps or additional links.
    public var description: String?
    /// A link to an image that will be used to visually identify your source. It will appear as a circle.
    public var iconURL: String?
    /// A link to an image that will be displayed as the header of your source's About page. The image will be blurred by default, but can be viewed by swiping the source's info banner.
    public var headerURL: String?
    /// A link to the primary website for your source. It will be displayed underneath your source's name on its About page.
    public var website: String?
    /// Your preferred username for your source's account on explore.alt.store (e.g. "utm" will become @utm@alt.store). This cannot be changed later.
    public var fediUsername: String?
    /// A link to your Patreon campaign.  This will enable you to distribute Patreon-only apps through your Source.
    public var patreonURL: String?
    /// A color that will be used to theme your source's About page. We recommend using a color that works well with your source's icon for consistent theming, but you are free to choose any color you want. Black and white tint colors will be automatically adjusted for legibility.
    public var tintColor: String?
    /// An ordered list of app bundleIdentifier's you want featured on your source's About page. Currently, only the first five will be displayed.
    public var featuredApps: [String]?
    /// The apps that are currently available
    public var apps: [App]
    /// Any news items for the catalog
    public var news: [NewsItem]?

    public init(name: String? = nil, subtitle: String? = nil, description: String? = nil, iconURL: String? = nil, headerURL: String? = nil, website: String? = nil, fediUsername: String? = nil, patreonURL: String? = nil, tintColor: String? = nil, featuredApps: [String]? = nil, apps: [App] = [], news: [NewsItem]? = nil) {
        self.name = name
        self.subtitle = subtitle
        self.description = description
        self.iconURL = iconURL
        self.headerURL = headerURL
        self.website = website
        self.fediUsername = fediUsername
        self.patreonURL = patreonURL
        self.tintColor = tintColor
        self.featuredApps = featuredApps
        self.apps = apps
        self.news = news
    }

    /// An individual App Source Catalog item, defining the name, identifier, and downloadURL of an application archive.
    ///
    /// https://faq.altstore.io/developers/make-a-source#apps
    ///
    /// See: https://github.com/altstoreio/AltStore/blob/HEAD/AltStoreCore/Model/StoreApp.swift
    public struct App: Codable, Equatable {
        /// The name of your app as it will appear on its store page.
        public var name: String
        /// Your app's bundle identifier (CFBundleIdentifier). It is case sensitive and should match exactly what is in your Info.plist.
        public var bundleIdentifier: String?
        /// The "Apple ID" of your notarized app. You can find this on your app's App Store Connect page under "App Information."
        public var marketplaceID: String?
        /// The name of the developer or developers as it will appear on the store page.
        public var developerName: String?
        /// A short, one-sentence description of your app that will appear in the Browse tab of AltStore.
        public var subtitle: String?
        /// Undocumented, e.g.: `{ "en": "English subtitle", "fr": "Subtitle en français" }`
        public var localizedSubtitles: StringMap<String>?
        /// A full-length description of your app. This can include any information you believe is relevant for your app, such as feature descriptions or additional links.
        public var localizedDescription: String?
        /// Undocumented, e.g.: `{ "en": "English description", "fr": "Description en français" }`
        public var localizedDescriptions: StringMap<String>?
        /// A link to you app's icon image. It will automatically be masked to an app icon shape.
        public var iconURL: String?
        /// The color used to theme your app's store page. We recommend using your app's existing tint color (if it has one), but you are free to choose any color you want.
        public var tintColor: String?
        /// The store category best representing your app.
        ///
        /// One of: `developer`, `entertainment`, `games`, `lifestyle`, `other`, `photo-video`, `social`, `utilities`
        ///
        /// https://faq.altstore.io/developers/make-a-source#category-string
        public var category: String?
        /// Screenshots of your app. We recommend showcasing your app's main features.
        public var screenshots: ScreenshotCollection?
        /// Undocumented
        public var beta: Bool?
        /// A list of all the published versions of your app.
        public var versions: [Version]?
        /// An object listing all entitlements and privacy permissions information used by the app.
        public var appPermissions: AltCatalog.App.Permission?
        /// An object specifying the required pledge/tiers to download the app.
        public var patreon: PatreonInfo?

        /// Screenshots are complicated: they can be either an array of strings, an array of screenshot objects, or a dictionary of strings to an array of screenshot objects
        /// https://faq.altstore.io/developers/make-a-source#universal-apps
        public typealias ScreenshotCollection = Either<[ScreenshotChoice]>.Or<StringMap<[ScreenshotChoice]>>
        public typealias ScreenshotChoice = Either<String>.Or<Screenshot>

        public init(name: String, bundleIdentifier: String? = nil, marketplaceID: String? = nil, developerName: String? = nil, subtitle: String? = nil, localizedSubtitles: StringMap<String>? = nil, localizedDescription: String? = nil, localizedDescriptions: StringMap<String>? = nil, iconURL: String? = nil, tintColor: String? = nil, category: String? = nil, screenshots: ScreenshotCollection? = nil, versions: [Version]? = nil, appPermissions: AltCatalog.App.Permission? = nil, patreon: PatreonInfo? = nil) {
            self.name = name
            self.bundleIdentifier = bundleIdentifier
            self.marketplaceID = marketplaceID
            self.developerName = developerName
            self.subtitle = subtitle
            self.localizedSubtitles = localizedSubtitles
            self.localizedDescription = localizedDescription
            self.localizedDescriptions = localizedDescriptions
            self.iconURL = iconURL
            self.tintColor = tintColor
            self.category = category
            self.screenshots = screenshots
            self.versions = versions
            self.appPermissions = appPermissions
            self.patreon = patreon
        }

        /// https://faq.altstore.io/developers/make-a-source#app-versions
        ///
        /// See: https://github.com/altstoreio/AltStore/blob/HEAD/AltStoreCore/Model/AppVersion.swift
        public struct Version: Codable, Equatable {
            /// Your app's version number (CFBundleShortVersionString). It is case sensitive and should match exactly what is in your Info.plist.
            public var version: String
            /// Your app's build number (CFBundleVersion). It is case sensitive and should match exactly what is in your Info.plist.
            public var buildVersion: String?
            /// The full version displayed to users on your app's store page and throughout the UI. This can be anything you want and does not need to match version or buildVersion.
            /// If not provided, this will default to combining version and buildVersion,e.g. 1.3 (4)
            public var marketingVersion: String?
            /// The release date for this version.
            /// This should be in ISO 8601 format (e.g. 2023-2-17 or 2023-02-17T12:00:00-06:00)
            public var date: String
            /// A description of what's new in this version. You can use this to tell users about new features, bug fixes, etc.
            public var localizedDescription: String?
            /// A description of what's new in this version. You can use this to tell users about new features, bug fixes, etc.
            public var localizedDescriptions: StringMap<String>?
            /// AltStore Classic: The URL of the uploaded .ipa file.
            /// AltStore PAL: The URL of the manifest.json in your uploaded ADP, or the root directory of the ADP itself.
            public var downloadURL: String
            /// Undocumented, but seems to be required
            public var size: Int64
            public var sha256: String?
            /// If you are unable to preserve an ADP's directory structure as-is, this allows you to manually specify the download URL for individual files in an ADP.  The keys are the names of the files you want to override (minus file extensions) and the values are the URLs where they are hosted.
            public var assetURLs: StringMap<String>?
            /// The minimum iOS version supported by this release. AltStore will hide any updates that are not supported by the user's device.
            public var minOSVersion: String?
            /// The maximum iOS version supported by this release (inclusive). AltStore will hide any updates that are not supported by the user's device.
            public var maxOSVersion: String?

            public init(version: String, buildVersion: String? = nil, marketingVersion: String? = nil, date: String, localizedDescription: String? = nil, localizedDescriptions: StringMap<String>? = nil, downloadURL: String, size: Int64, sha256: String? = nil, assetURLs: StringMap<String>? = nil, minOSVersion: String? = nil, maxOSVersion: String? = nil) {
                self.version = version
                self.buildVersion = buildVersion
                self.marketingVersion = marketingVersion
                self.date = date
                self.localizedDescription = localizedDescription
                self.localizedDescriptions = localizedDescriptions
                self.downloadURL = downloadURL
                self.size = size
                self.sha256 = sha256
                self.assetURLs = assetURLs
                self.minOSVersion = minOSVersion
                self.maxOSVersion = maxOSVersion
            }
        }

        /// https://faq.altstore.io/developers/make-a-source#app-permissions
        public struct Permission: Codable, Equatable {
            /// A list of all entitlements used by the app and its app extensions.
            public var entitlements: [PermissionEntitlementElement]?
            public typealias PermissionEntitlementElement = Either<PermissionEntitlement>.Or<String>

            /// A dictionary with all the "UsageDescription" keys in your app's Info.plist along with their descriptions. We recommend using the same descriptions already in your Info.plist.
            public var privacy: PermissionPrivacyOption?
            public typealias PermissionPrivacyOption = Either<[PermissionPrivacy]>.Or<StringMap<String>>

            public init(entitlements: [PermissionEntitlementElement]? = nil, privacy: PermissionPrivacyOption? = nil) {
                self.entitlements = entitlements
                self.privacy = privacy
            }


            /// Note that this differs from the docs, which state that the permissions should just be an array of strings
            public struct PermissionEntitlement: Codable, Equatable {
                public var name: String

                public init(name: String) {
                    self.name = name
                }
            }

            /// Note that this differs from the docs, which state that the permissions should just be a String:String dictionary
            public struct PermissionPrivacy: Codable, Equatable {
                public var name: String
                public var usageDescription: String

                public init(name: String, usageDescription: String) {
                    self.name = name
                    self.usageDescription = usageDescription
                }
            }
        }
    }

    /// https://faq.altstore.io/developers/make-a-source#screenshots
    public struct Screenshot: Codable, Equatable {
        public var imageURL: String
        public var width: Int?
        public var height: Int?

        public init(imageURL: String, width: Int? = nil, height: Int? = nil) {
            self.imageURL = imageURL
            self.width = width
            self.height = height
        }
    }

    /// https://faq.altstore.io/developers/make-a-source#patreon
    public struct PatreonInfo: Codable, Equatable {
        /// The minimum pledge amount required for download. This can be used to limit downloads to higher tiers.
        public var pledge: Double
        /// The ISO currency code of your campaign's currency.
        public var currency: String?
        /// The identifier of a campaign benefit. You can add benefits to any of your Patreon campaign tiers, then specify it using this key to allow anyone with that benefit to download your app.
        public var benefit: String?
        /// A list of tier identifiers designating which tiers are required to download. A user must be a member of one of these tiers to download your app.
        public var tiers: [String]?

        public init(pledge: Double, currency: String? = nil, benefit: String? = nil, tiers: [String]? = nil) {
            self.pledge = pledge
            self.currency = currency
            self.benefit = benefit
            self.tiers = tiers
        }
    }

    /// An individual item of news, consiting of a unique identifier, a date, title, caption, and optional additional properties.
    ///
    /// https://faq.altstore.io/developers/make-a-source#news-items
    public struct NewsItem: Codable, Equatable {
        /// The title of your News item.
        public var title: String
        /// A unique value to distinguish this News item from others in your source.
        public var identifier: String
        /// A short, one-sentence description of your News item.
        public var caption: String
        /// The publishing date for this News item.
        public var date: String // can be either "2022-05-05" or "2020-04-10T13:30:00-07:00"
        /// The background color for your News item.
        public var tintColor: String?
        /// A link to the image you want featured with your News item.
        public var imageURL: String?
        /// When true, AltStore will send a push notification about this News item when it next checks for updates in the background.
        public var notify: Bool?
        /// A link that AltStore should open when the News item is tapped. Links will be opened in an in-app web browser.
        public var url: String?
        /// The bundle identifier of an associated app. This will make the app's info banner appear below the News item, which will open the app's Store page when tapped.
        public var appID: String?

        public init(title: String, identifier: String, caption: String, date: String, tintColor: String? = nil, imageURL: String? = nil, notify: Bool? = nil, url: String? = nil, appID: String? = nil) {
            self.title = title
            self.identifier = identifier
            self.caption = caption
            self.date = date
            self.tintColor = tintColor
            self.imageURL = imageURL
            self.notify = notify
            self.url = url
            self.appID = appID
        }
    }
}

let iso8601DateParser: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    return formatter
}()

/// A lenient ISO-8601 parser that will accept dates both in full datetime mode as well as date-only (e.g., "1999-12-31")
private func decodeISO8601Date(_ decoder: Decoder) throws -> Date {
    let container = try decoder.singleValueContainer()
    let dateString = try container.decode(String.self)

    if let date = iso8601DateParser.date(from: dateString) {
        return date
    }

    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
}

public extension AltCatalog {
    /// Parses the `AppCatalog` with the expected parameters (i.e., date encoding as lenient iso8601).
    static func parse(jsonData: Data) throws -> Self {
        try AltCatalog(fromJSON: jsonData, dateDecodingStrategy: .custom(decodeISO8601Date))
    }
}

extension Appcat {
    /// Generates an AltCatalog from this Appcat.
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

            var screenshots: StringMap<[AltCatalog.App.ScreenshotChoice]> = [:]
            for (profileName, profile) in platform.profiles {

                let shots: [AltCatalog.Screenshot] = (self.localized(in: profile.screenshots) ?? []).map { shot in
                    AltCatalog.Screenshot(imageURL: appLocation(relativeTo: shot.location) ?? shot.location, width: shot.width, height: shot.height)
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
                name: self.localized(in: mergeLocalized(channel.title, platform.title, app.title)) ?? "",
                bundleIdentifier: platform.id,
                marketplaceID: channel.identifier,
                developerName: app.author,
                subtitle: self.localized(in: mergeLocalized(channel.summary, platform.summary, app.summary)),
                localizedSubtitles: mergeLocalized(channel.summary, platform.summary, app.summary),
                localizedDescription: self.localized(in: mergeLocalized(channel.description, platform.description, app.description)),
                localizedDescriptions: mergeLocalized(channel.description, platform.description, app.description),
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
}
