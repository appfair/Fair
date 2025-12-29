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

/// Version 2 of the F-Droid index format.
///
/// Sample catalog at: [https://f-droid.org/repo/index-v2.json](https://f-droid.org/repo/index-v2.json)
///
/// Based on the Kotlin data classes at:
/// [https://gitlab.com/fdroid/fdroidclient/-/tree/master/libs/index/src/commonMain/kotlin/org/fdroid/index/v2]()
///
/// Python generation code at: [https://gitlab.com/fdroid/fdroidserver/-/blob/master/fdroidserver/index.py#L516]()
public struct FDroidIndex: Codable, Equatable {
    /// Metadata about the repository
    public var repo: Repo

    /// The list of packages (i.e., apps) that make up the catalog
    public var packages: Dictionary<String, Package>?

    /// A map of language code to the translated text. E.g.: `["en-US": "Name", "fr-FR": "Nom"]`
    public typealias LocalizedText = Dictionary<String, String>

    /// A map of language code to the file resource. E.g.: `["en-US": "images/icon/english.svg", "fr-FR": "images/icon/french.svg"]`
    public typealias LocalizedFile = Dictionary<String, File>

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
    public typealias LocalizedFileList = Dictionary<String, Array<File>>

    public init(repo: Repo, packages: Dictionary<String, Package>?) {
        self.repo = repo
        self.packages = packages
    }

    /// A reference to a resource path
    public struct File: Codable, Equatable {
        public var name: String
        public var sha256: String?
        public var size: Int64?

        public init(name: String, sha256: String? = nil, size: Int64? = nil) {
            self.name = name
            self.sha256 = sha256
            self.size = size
        }
    }

    public struct Entry: Codable, Equatable {
        public var timestamp: Int64
        public var version: Int64
        public var maxAge: Int?
        public var index: EntryFile
        public var diffs: Dictionary<String, EntryFile>

        public init(timestamp: Int64, version: Int64, maxAge: Int? = nil, index: EntryFile, diffs: Dictionary<String, EntryFile>) {
            self.timestamp = timestamp
            self.version = version
            self.maxAge = maxAge
            self.index = index
            self.diffs = diffs
        }
    }

    public struct EntryFile: Codable, Equatable {
        public var name: String
        public var sha256: String
        public var size: Int64
        public var numPackages: Int

        public init(name: String, sha256: String, size: Int64, numPackages: Int) {
            self.name = name
            self.sha256 = sha256
            self.size = size
            self.numPackages = numPackages
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
        public var antiFeatures: Dictionary<String, AntiFeature>?
        /// A mapping of the category name of metadata about the category
        public var categories: Dictionary<String, Category>?
        public var releaseChannels: Dictionary<String, ReleaseChannel>?

        public init(name: LocalizedText, icon: LocalizedFile, address: String, webBaseUrl: String? = nil, description: LocalizedText? = nil, mirrors: Array<Mirror>? = nil, timestamp: Int64, antiFeatures: Dictionary<String, AntiFeature>? = nil, categories: Dictionary<String, Category>? = nil, releaseChannels: Dictionary<String, ReleaseChannel>? = nil) {
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
        public var versions: Dictionary<String, PackageVersion>

        public init(metadata: Metadata, versions: Dictionary<String, PackageVersion>) {
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

        public typealias Screenshots = [String: LocalizedFileList]

        //public struct Screenshots: Codable, Equatable {
        //    public var phone: LocalizedFileList?
        //    public var sevenInch: LocalizedFileList?
        //    public var tenInch: LocalizedFileList?
        //    public var wear: LocalizedFileList?
        //    public var tv: LocalizedFileList?
        //
        //    public init(phone: LocalizedFileList? = nil, sevenInch: LocalizedFileList? = nil, tenInch: LocalizedFileList? = nil, wear: LocalizedFileList? = nil, tv: LocalizedFileList? = nil) {
        //        self.phone = phone
        //        self.sevenInch = sevenInch
        //        self.tenInch = tenInch
        //        self.wear = wear
        //        self.tv = tv
        //    }
        //}

        // public interface PackageVersion {
        //     public val versionCode: Long
        //     public val signer: Signer?
        //     public val releaseChannels: List<String>?
        //     public val packageManifest: PackageManifest
        //     public val hasKnownVulnerability: Boolean
        // }

        public struct PackageVersion: Codable, Equatable {
            public var added: Int64
            public var file: FileV1
            public var src: File?
            public var manifest: Manifest
            public var releaseChannels: Array<String>?
            public var antiFeatures: Dictionary<String, LocalizedText>?
            public var whatsNew: LocalizedText?

            public init(added: Int64, file: FileV1, src: File? = nil, manifest: Manifest, releaseChannels: Array<String>? = nil, antiFeatures: Dictionary<String, LocalizedText>? = nil, whatsNew: LocalizedText? = nil) {
                self.added = added
                self.file = file
                self.src = src
                self.manifest = manifest
                self.releaseChannels = releaseChannels
                self.antiFeatures = antiFeatures
                self.whatsNew = whatsNew
            }
        }

        public struct FileV1: Codable, Equatable {
            public var name: String
            public var sha256: String
            public var size: Int64?

            public init(name: String, sha256: String, size: Int64? = nil) {
                self.name = name
                self.sha256 = sha256
                self.size = size
            }
        }

        // public interface PackageManifest {
        //     public val minSdkVersion: Int?
        //     public val maxSdkVersion: Int?
        //     public val featureNames: List<String>?
        //     public val nativecode: List<String>?
        // }

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

