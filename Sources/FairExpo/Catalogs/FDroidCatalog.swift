// Copyright (c) 2022 - 2026 The App Fair Project <info@appfair.org>
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import FairCore

/// The collection of URLs associated with an F-Droid API endpoint.
public struct FDroidEndpoint {
    /// The default base for the droid catalog API
    public static let defaultEndpoint = URL(string: "https://f-droid.org/repo/index-v2.json")!

    /// The base endpoint for casks
    public let endpoint: URL

    public init(endpoint: URL) {
        self.endpoint = endpoint
    }
}

/// Version 2 of the F-Droid index format, described at https://gitlab.com/fdroid/wiki/-/wikis/Index-V2
///
/// Based on the Kotlin data classes at:
/// [https://gitlab.com/fdroid/fdroidclient/-/tree/master/libs/index/src/commonMain/kotlin/org/fdroid/index/v2]()
///
/// Python generation code at: [https://gitlab.com/fdroid/fdroidserver/-/blob/master/fdroidserver/index.py#L516]()
///
/// Sample catalog at: [https://f-droid.org/repo/index-v2.json](https://f-droid.org/repo/index-v2.json)
public struct FDroidIndex: Codable, Equatable {
    /// Metadata about the repository
    public var repo: Repo

    /// The list of packages (i.e., apps) that make up the catalog
    public var packages: StringMap<Package>?

    /// A map of language code to the translated text. E.g.: `["en-US": "Name", "fr-FR": "Nom"]`
    public typealias LocalizedText = StringMap<String>

    /// A map of language code to the file resource. E.g.: `["en-US": "images/icon/english.svg", "fr-FR": "images/icon/french.svg"]`
    public typealias LocalizedFile = StringMap<File>

    /// A map of language code to a file resource set.
    ///
    /// E.g.:
    ///
    /// ```
    /// "en-US": [
    /// {
    ///   "name": "/app.id/en-US/phoneScreenshots/screen_1.png",
    ///   "sha256": "9bd71cbed1c2224d4d7a27e12f4ff6b5326605c11cc0ca9d2bb887b50949d110",
    ///   "size": 112122
    /// }
    /// ]
    /// ```
    ///
    public typealias LocalizedFileList = StringMap<Array<File>>

    public init(repo: Repo, packages: StringMap<Package>?) {
        self.repo = repo
        self.packages = packages
    }

    /// A reference to a resource path
    public struct File: Codable, Equatable {
        public var name: String
        public var sha256: String?
        public var size: Int64?
        public var ipfsCIDv1: String?

        public init(name: String, sha256: String? = nil, size: Int64? = nil, ipfsCIDv1: String? = nil) {
            self.name = name
            self.sha256 = sha256
            self.size = size
            self.ipfsCIDv1 = ipfsCIDv1
        }
    }

    /// Metadata about the package repository
    public struct Repo: Codable, Equatable {
        public var name: LocalizedText
        public var icon: LocalizedFile
        public var address: String
        public var webBaseUrl: String?
        public var description: LocalizedText?
        public var mirrors: Array<Mirror>?
        public var timestamp: Int64
        public var antiFeatures: StringMap<AntiFeature>?
        /// A mapping of the category name of metadata about the category
        public var categories: StringMap<Category>?
        public var releaseChannels: StringMap<ReleaseChannel>?

        public init(name: LocalizedText, icon: LocalizedFile, address: String, webBaseUrl: String? = nil, description: LocalizedText? = nil, mirrors: Array<Mirror>? = nil, timestamp: Int64, antiFeatures: StringMap<AntiFeature>? = nil, categories: StringMap<Category>? = nil, releaseChannels: StringMap<ReleaseChannel>? = nil) {
            self.name = name
            self.icon = icon
            self.address = address
            self.webBaseUrl = webBaseUrl
            self.description = description
            self.mirrors = mirrors
            self.timestamp = timestamp
            self.antiFeatures = antiFeatures
            self.categories = categories
            self.releaseChannels = releaseChannels
        }
    }

    public struct Mirror: Codable, Equatable {
        public var url: String
        public var countryCode: String?
        public var isPrimary: Bool? // undocumented

        public init(url: String, countryCode: String? = nil, isPrimary: Bool? = nil) {
            self.url = url
            self.countryCode = countryCode
            self.isPrimary = isPrimary
        }
    }


    /// Flag for potentially undesirable features (e.g., "Ads", "DisabledAlgorithm", "KnownVuln", "NSFW", "NoSourceSince", "NonFreeAdd", "NonFreeAssets", "NonFreeDep", "NonFreeNet", "Tracking", "UpstreamNonFree")
    public struct AntiFeature: Codable, Equatable {
        public var icon: LocalizedFile?
        public var name: LocalizedText?
        public var description: LocalizedText?

        public init(icon: LocalizedFile? = nil, name: LocalizedText? = nil, description: LocalizedText? = nil) {
            self.icon = icon
            self.name = name
            self.description = description
        }
    }

    /// A categorization of an app (e.g, "Connectivity", "Development", "Games", "Graphics", "Internet", "Money", "Multimedia", "Navigation", "Phone & SMS", "Reading", "Science & Education", "Security", "Sports & Health", "System", "Theming", "Time", "Writing")
    ///
    /// e.g., see the list at https://gitlab.com/fdroid/fdroiddata/-/blob/master/config/categories.yml
    public struct Category: Codable, Equatable {
        public var icon: LocalizedFile?
        public var name: LocalizedText?
        public var description: LocalizedText?

        public init(icon: LocalizedFile? = nil, name: LocalizedText? = nil, description: LocalizedText? = nil) {
            self.icon = icon
            self.name = name
            self.description = description
        }
    }

    public struct ReleaseChannel: Codable, Equatable {
        public var name: LocalizedText
        public var description: LocalizedText?

        public init(name: LocalizedText, description: LocalizedText? = nil) {
            self.name = name
            self.description = description
        }
    }

    public struct Package: Codable, Equatable {
        public var metadata: Metadata
        /// A of versions, keyed by the sha256 of the primary artifact.
        public var versions: StringMap<PackageVersion>

        public init(metadata: Metadata, versions: StringMap<PackageVersion>) {
            self.metadata = metadata
            self.versions = versions
        }

        public struct Metadata: Codable, Equatable {
            public var name: LocalizedText?
            public var summary: LocalizedText?
            public var description: LocalizedText?
            public var categories: Array<String>?

            public var added: Int64
            public var lastUpdated: Int64
            public var changelog: String?

            public var license: String?
            public var sourceCode: String?
            public var preferredSigner: String?

            public var webSite: String?
            public var issueTracker: String?
            public var translation: String?

            // MARK: Author
            public var authorName: String?
            public var authorEmail: String?
            public var authorWebSite: String?
            public var authorPhone: String?

            // MARK: Funding
            public var donate: Array<String>?
            public var liberapayID: String?
            public var liberapay: String?
            public var openCollective: String?
            public var bitcoin: String?
            public var litecoin: String?
            public var flattrID: String?

            // MARK: Graphics
            public var icon: LocalizedFile?
            public var featureGraphic: LocalizedFile?
            public var promoGraphic: LocalizedFile?
            public var tvBanner: LocalizedFile?
            public var video: LocalizedText?
            public var screenshots: Screenshots?

            public init(name: LocalizedText? = nil, summary: LocalizedText? = nil, description: LocalizedText? = nil, added: Int64, lastUpdated: Int64, webSite: String? = nil, changelog: String? = nil, license: String? = nil, sourceCode: String? = nil, issueTracker: String? = nil, translation: String? = nil, preferredSigner: String? = nil, categories: Array<String>? = nil, authorName: String? = nil, authorEmail: String? = nil, authorWebSite: String? = nil, authorPhone: String? = nil, donate: Array<String>? = nil, liberapayID: String? = nil, liberapay: String? = nil, openCollective: String? = nil, bitcoin: String? = nil, litecoin: String? = nil, flattrID: String? = nil, icon: LocalizedFile? = nil, featureGraphic: LocalizedFile? = nil, promoGraphic: LocalizedFile? = nil, tvBanner: LocalizedFile? = nil, video: LocalizedText? = nil, screenshots: Screenshots? = nil) {
                self.name = name
                self.summary = summary
                self.description = description
                self.added = added
                self.lastUpdated = lastUpdated
                self.webSite = webSite
                self.changelog = changelog
                self.license = license
                self.sourceCode = sourceCode
                self.issueTracker = issueTracker
                self.translation = translation
                self.preferredSigner = preferredSigner
                self.categories = categories
                self.authorName = authorName
                self.authorEmail = authorEmail
                self.authorWebSite = authorWebSite
                self.authorPhone = authorPhone
                self.donate = donate
                self.liberapayID = liberapayID
                self.liberapay = liberapay
                self.openCollective = openCollective
                self.bitcoin = bitcoin
                self.litecoin = litecoin
                self.flattrID = flattrID
                self.icon = icon
                self.featureGraphic = featureGraphic
                self.promoGraphic = promoGraphic
                self.tvBanner = tvBanner
                self.video = video
                self.screenshots = screenshots
            }
        }

        public typealias Screenshots = StringMap<LocalizedFileList>

        public struct PackageVersion: Codable, Equatable {
            public var added: Int64
            public var file: File
            public var src: File?
            public var manifest: Manifest
            public var releaseChannels: Array<String>?
            public var antiFeatures: StringMap<LocalizedText>?
            public var whatsNew: LocalizedText?

            public init(added: Int64, file: File, src: File? = nil, manifest: Manifest, releaseChannels: Array<String>? = nil, antiFeatures: StringMap<LocalizedText>? = nil, whatsNew: LocalizedText? = nil) {
                self.added = added
                self.file = file
                self.src = src
                self.manifest = manifest
                self.releaseChannels = releaseChannels
                self.antiFeatures = antiFeatures
                self.whatsNew = whatsNew
            }
        }

        public struct Manifest: Codable, Equatable {
            public var versionName: String
            public var versionCode: Int64
            public var usesSdk: UsesSdk?
            public var maxSdkVersion: Int?
            public var signer: Signer?
            public var usesPermission: Array<Permission>?
            public var usesPermissionSdk23: Array<Permission>?
            public var nativecode: Array<String>?
            public var features: Array<Feature>?

            public init(versionName: String, versionCode: Int64, usesSdk: UsesSdk? = nil, maxSdkVersion: Int? = nil, signer: Signer? = nil, usesPermission: Array<Permission>? = nil, usesPermissionSdk23: Array<Permission>? = nil, nativecode: Array<String>? = nil, features: Array<Feature>? = nil) {
                self.versionName = versionName
                self.versionCode = versionCode
                self.usesSdk = usesSdk
                self.maxSdkVersion = maxSdkVersion
                self.signer = signer
                self.usesPermission = usesPermission
                self.usesPermissionSdk23 = usesPermissionSdk23
                self.nativecode = nativecode
                self.features = features
            }
        }

        public struct UsesSdk: Codable, Equatable {
            public var minSdkVersion: Int
            public var targetSdkVersion: Int

            public init(minSdkVersion: Int, targetSdkVersion: Int) {
                self.minSdkVersion = minSdkVersion
                self.targetSdkVersion = targetSdkVersion
            }
        }

        public struct Signer: Codable, Equatable {
            public var sha256: Array<String>
            public var hasMultipleSigners: Bool?

            public init(sha256: Array<String>, hasMultipleSigners: Bool? = nil) {
                self.sha256 = sha256
                self.hasMultipleSigners = hasMultipleSigners
            }
        }

        public struct Permission: Codable, Equatable {
            public var name: String
            public var maxSdkVersion: Int?

            public init(name: String, maxSdkVersion: Int? = nil) {
                self.name = name
                self.maxSdkVersion = maxSdkVersion
            }
        }

        public struct Feature: Codable, Equatable {
            public var name: String

            public init(name: String) {
                self.name = name
            }
        }
    }
}

extension Appcat {
    /// Generates an F-Droid Index from this Appcat.
    public func toFDroidIndex(repoURL: String) -> FDroidIndex {
        var packages = StringMap<FDroidIndex.Package>()
        for app in self.apps {
            guard let platform = app.platforms["android"] else { continue }
            guard let channel = platform.channels["fdroid"] else { continue }
            guard let artifact = channel.artifact else { continue }
            let meta = channel.metadata ?? [:]

            var usesSdk: FDroidIndex.Package.UsesSdk? = nil
            if let minSdk = platform.minVersion.flatMap({ Int($0) }),
               let targetSdk = platform.targetVersion.flatMap({ Int($0) }){
                usesSdk = FDroidIndex.Package.UsesSdk(minSdkVersion: minSdk, targetSdkVersion: targetSdk)
            }

            let versionManifest = FDroidIndex.Package.Manifest(
                versionName: channel.version,
                versionCode: channel.build ?? 0,
                usesSdk: usesSdk,
                maxSdkVersion: platform.maxVersion.flatMap({ Int($0) }),
                signer: nil,
                usesPermission: platform.permissions?.map({ FDroidIndex.Package.Permission(name: $0.key) }),
                usesPermissionSdk23: nil,
                nativecode: nil,
                features: nil)

            var versions: StringMap<FDroidIndex.Package.PackageVersion> = [:]
            // TODO: resolve location against specified f-droid `repoURL`
            let file = FDroidIndex.File(name: artifact.location, sha256: artifact.hash, size: artifact.size)

            // The convention is to index versions by the artifact's hash, but is that the best way for these catalogs?
            //let versionID = app.id
            let versionID = artifact.hash
            versions[versionID] = FDroidIndex.Package.PackageVersion(
                added: Int64(channel.date.timeIntervalSince1970 * 1_000),
                file: file,
                src: nil,
                manifest: versionManifest,
                releaseChannels: nil,
                antiFeatures: nil,
                whatsNew: channel.notes)

            let screenshots: FDroidIndex.Package.Screenshots = platform.profiles.mapValues({ profile in
                let files: FDroidIndex.LocalizedFileList = profile.screenshots.mapValues({ $0.map({ $0.toFDroidFile() }) })
                return files
            })

            let metadata = FDroidIndex.Package.Metadata(
                name: mergeLocalized(channel.title, platform.title, app.title),
                summary: mergeLocalized(channel.summary, platform.summary, app.summary),
                description: mergeLocalized(channel.description, platform.description, app.description),
                added: .init((app.created?.timeIntervalSince1970 ?? 0) * 1_000), // seconds to milliseconds
                lastUpdated: 0,
                webSite: meta["webSite"] ?? app.homepage,
                changelog: meta["changelog"],
                license: meta["license"] ?? app.license,
                sourceCode: meta["sourceCode"],
                issueTracker: meta["issueTracker"] ?? app.issues,
                translation: meta["translation"] ?? app.translation,
                preferredSigner: meta["preferredSigner"],
                categories: channel.categories,
                authorName: meta["authorName"] ?? app.author,
                authorEmail: meta["authorEmail"] ?? app.email,
                authorWebSite: meta["authorWebSite"],
                authorPhone: meta["authorPhone"],
                donate: meta["donate"].flatMap({ [$0] }),
                liberapayID: meta["liberapayID"],
                liberapay: meta["liberapay"],
                openCollective: meta["openCollective"],
                bitcoin: meta["bitcoin"],
                litecoin: meta["litecoin"],
                flattrID: meta["flattrID"],
                icon: app.icon.toFDroidLocalizedFile(),
                featureGraphic: nil,
                promoGraphic: nil,
                tvBanner: nil,
                video: nil,
                screenshots: screenshots.isEmpty ? nil : screenshots)

            let fdroidApp = FDroidIndex.Package(metadata: metadata, versions: versions)
            packages[channel.identifier ?? platform.id] = fdroidApp
        }
        let repo = FDroidIndex.Repo(
            name: self.title,
            icon: icon?.toFDroidLocalizedFile() ?? [:],
            address: repoURL,
            timestamp: 0)
        return FDroidIndex(repo: repo, packages: packages)
    }
}

extension Appcat.LocalizedImage {
    func toFDroidLocalizedFile() -> FDroidIndex.LocalizedFile {
        self.mapValues({ $0.toFDroidFile() })
    }
}

extension Appcat.ImageResourceRef {
    func toFDroidFile() -> FDroidIndex.File {
        FDroidIndex.File(name: self.location, sha256: self.hash, size: self.size)
    }
}
