// Copyright (c) 2022 - 2026 The App Fair Project <info@appfair.org>
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import FairCore
import Yams

/// We use OrderedDictionary by default
public typealias StringMap<T> = OrderedMap<String, T>
//public typealias StringMap<T> = Dictionary<String, T>
//public typealias StringMap<T> = OrderedDictionary<String, T>

/// A catalog that describes an app, including metadata about the application itself,
/// the platforms for which it is available, and the channels through which the app can be acquired.
///
/// Goals:
/// - Create from Fastlane metadata files
/// - Used to generate index pages for apps (e.g., https://appfair.net)
/// - Embeddable within an app itself to provide useful runtime information (support email, app store links, etc.)
/// - Exportable to F-Droid `index-v2.json` and AltStore `altsource.json`
public struct Appcat: Codable, Equatable, Sendable {
    /// A locale key.
    /// App Store locales: https://developer.apple.com/documentation/appstoreconnectapi/managing-metadata-in-your-app-by-using-locale-shortcodes (https://docs.fastlane.tools/actions/deliver/#available-language-codes ):
    /// `ar-SA, ca, cs, da, de-DE, el, en-AU, en-CA, en-GB, en-US, es-ES, es-MX, fi, fr-CA, fr-FR, he, hi, hr, hu, id, it, ja, ko, ms, nl-NL, no, pl, pt-BR, pt-PT, ro, ru, sk, sv, th, tr, uk, vi, zh-Hans, zh-Hant`
    ///
    /// Play Store locales: https://github.com/ashutoshgngwr/validate-fastlane-supply-metadata/blob/c8857fdbbd3e00f9a5cbe8604bcecfa95ce8fef8/play_store_locales.go#L40 :
    /// `af, sq, am, ar, hy-AM, az-AZ, bn-BD, eu-ES, be, bg, my-MM, ca, zh-HK, zh-CN, zh-TW, hr, cs-CZ, da-DK, nl-NL, en-AU, en-CA, en-GB, en-IN, en-SG, en-US, en-ZA, et, fil, fi-FI, fr-CA, fr-FR, gl-ES, ka-GE, de-DE, el-GR, gu, iw-IL, hi-IN, hu-HU, is-IS, id, it-IT, ja-JP, kn-IN, kk, km-KH, ko-KR, ky-KG, lo-LA, lv, lt, mk-MK, ms-MY, ms, ml-IN, mr-IN, mn-MN, ne-NP, no-NO, fa, fa-AE, fa-AF, fa-IR, pl-PL, pt-BR, pt-PT, pa, ro, rm, ru-RU, sr, si-LK, sk, sl, es-419, es-ES, es-US, sw, sv-SE, ta-IN, te-IN, th, tr-TR, uk, ur, vi, zu`
    public typealias LocalizationKey = String
    public typealias LocalizedDictionary<T> = StringMap<T>
    public typealias LocalizedText = LocalizedDictionary<String>
    public typealias LocalizedTextArray = LocalizedDictionary<[String]>
    public typealias LocalizedResource = LocalizedDictionary<ResourceRef>
    public typealias LocalizedImage = LocalizedDictionary<ImageResourceRef>
    public typealias LocalizedImageList = LocalizedDictionary<[ImageResourceRef]>

    /// The version of this catalog.
    ///
    /// Should be 1
    public var appcatVersion: Int
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
        /// The location of this app's root, either absolute or relative to the catalog's base url
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
        /// A home page for the app
        public var homepage: String?
        /// The name of the author of the app
        public var author: String?
        /// A support email for this app
        public var email: String?
        /// An issue tracker web page for this app
        public var issues: String?
        /// A page for helping with translating this app
        public var translation: String?
        /// An SPDX identifier for the app's license
        public var license: String?
        /// The map of platforms supported by this app
        /// E.g., ios, android, macos, windows, linux
        public var platforms: StringMap<Platform>

        /// An individual platform supported by an app, which can contain multiple distribution channels.
        ///
        /// A platform generally conforms to a certain operating system, such as Android, iOS, Linux, macOS, Windows.
        public struct Platform: Codable, Equatable, Sendable, AppMetadata {
            /// The unique identifier for this app in the context of the platform (e.g., the Android appid or Darwin bundle id)
            public var id: String

            // AppMetadata

            /// Optional channel-specific title for the app
            public var title: LocalizedText?
            /// Optional channel-specific  summary description for the app
            public var summary: LocalizedText?
            /// Optional channel-specific full description for the app
            public var description: LocalizedText?
            /// Optional channel-specific localized keyword list
            public var keywords: LocalizedTextArray?

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
            public var channels: StringMap<Channel>

            /// The physical profile of the device that this app is available.
            ///
            /// e.g., Android: phone, sevenInch, tenInch, wear, tv, …
            /// e.g., iOS: iphone, ipad, …
            public var profiles: StringMap<Profile>

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
                public var screenshots: LocalizedImageList
            }

            /// A specific distribution channel for an app platform (e.g., `appstore`, `playstore`, `fdroid`, `direct`, `homebrew`, `winget`)
            public struct Channel: Codable, Equatable, Sendable, AppMetadata {
                /// A semantic version for the latest release
                public var version: String // e.g., 1.1.2
                /// A build number or identifier for this app
                public var build: Int64? // e.g., 987654
                /// An ISO-8601 date when the given version was released
                public var date: Date // e.g., 2026-01-01T12:00:00Z
                /// An optional channel-specific identifier for this artifact, like the iTunes identifier
                public var identifier: String?
                /// The artifact download information
                public var artifact: ResourceRef?
                /// Channel-specific categories (e.g., for the App Store: https://developer.apple.com/app-store/categories/)
                public var categories: [String]?

                // AppMetadata

                /// Optional channel-specific title for the app
                public var title: LocalizedText?
                /// Optional channel-specific  summary description for the app
                public var summary: LocalizedText?
                /// Optional channel-specific full description for the app
                public var description: LocalizedText?
                /// Optional channel-specific localized keyword list
                public var keywords: LocalizedTextArray?

                /// Arbitrary additional metadata
                public var metadata: StringMap<String>?

                /// Optional release notes for this version in this channel
                public var notes: LocalizedText?
            }
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
    func localized<T>(in dict: StringMap<T>?) -> T? {
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
    /// Merges all the localizd dictionaries into a single one, with earlier entries taking precedence over later ones
    func mergeLocalized<T>(_ meta: LocalizedDictionary<T>?...) -> LocalizedDictionary<T>? {
        var dict: LocalizedDictionary<T> = [:]
        for m in meta.reversed().compactMap(\.self) {
            for (key, value) in m {
                dict[key] = value
            }
        }
        return dict.isEmpty ? nil : dict
    }
}

extension Appcat.App {
    public func toYAML() throws -> String {
        let encoder = YAMLEncoder()
        encoder.options.allowUnicode = true
        let yamlOutput = try encoder.encode(self)
        return yamlOutput
    }
}
