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
struct FDroidIndex : Codable, Equatable {
    /// Metadata about the repository
    var repo: Repo

    /// The list of packages (i.e., apps) that make up the catalog
    var packages: Dictionary<String, Package>

    /// A map of language code to the translated text. E.g.: `["en-US": "Name", "fr-FR": "Nom"]`
    typealias LocalizedText = Dictionary<String, String>

    /// A map of language code to the file resource. E.g.: `["en-US": "images/icon/english.svg", "fr-FR": "images/icon/french.svg"]`
    typealias LocalizedFile = Dictionary<String, File>

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
    typealias LocalizedFileList = Dictionary<String, Array<File>>

    /// A reference to a resource path
    struct File : Codable, Equatable {
        var name: String?
        var sha256: String?
        var size: Int64?
    }

    struct Entry : Codable, Equatable {
        var timestamp: Int64
        var version: Int64
        var maxAge: Int?
        var index: EntryFile
        var diffs: Dictionary<String, EntryFile>
    }

    struct EntryFile : Codable, Equatable {
        var name: String
        var sha256: String
        var size: Int64
        var numPackages: Int
    }

    /// Metadata about the package repository
    struct Repo : Codable, Equatable {
        var name: LocalizedText
        var icon: LocalizedFile
        var address: String
        var webBaseUrl: String?
        var description: LocalizedText?
        var mirrors: Array<Mirror>
        var timestamp: Int64
        var antiFeatures: Dictionary<String, AntiFeature>?
        /// A mapping of the category name of metadata about the category
        var categories: Dictionary<String, Category>?
        var releaseChannels: Dictionary<String, ReleaseChannel>?
    }

    struct Mirror : Codable, Equatable {
        var url: String
        var location: String?
        var isPrimary: Bool? // undocumented
    }


    /// Flag for potentially undesirable features (e.g., "Ads", "DisabledAlgorithm", "KnownVuln", "NSFW", "NoSourceSince", "NonFreeAdd", "NonFreeAssets", "NonFreeDep", "NonFreeNet", "Tracking", "UpstreamNonFree")
    struct AntiFeature : Codable, Equatable {
        var icon: LocalizedFile?
        var name: LocalizedText?
        var description: LocalizedText?
    }

    /// A categorization of an app (e.g, "Connectivity", "Development", "Games", "Graphics", "Internet", "Money", "Multimedia", "Navigation", "Phone & SMS", "Reading", "Science & Education", "Security", "Sports & Health", "System", "Theming", "Time", "Writing")
    struct Category : Codable, Equatable {
        var icon: LocalizedFile?
        var name: LocalizedText?
        var description: LocalizedText?
    }

    struct ReleaseChannel : Codable, Equatable {
        var name: LocalizedText
        var description: LocalizedText?
    }

    struct Package : Codable, Equatable {
        var metadata: Metadata
        /// A of versions, keyed by the sha256 of the primary artifact.
        var versions: Dictionary<String, PackageVersion>

        struct Metadata : Codable, Equatable {
            var name: LocalizedText?
            var summary: LocalizedText?
            var description: LocalizedText?
            var added: Int64
            var lastUpdated: Int64
            var webSite: String?
            var changelog: String?
            var license: String?
            var sourceCode: String?
            var issueTracker: String?
            var translation: String?
            var preferredSigner: String?
            var categories: Array<String>?
            var authorName: String?
            var authorEmail: String?
            var authorWebSite: String?
            var authorPhone: String?
            var donate: Array<String>?
            var liberapayID: String?
            var liberapay: String?
            var openCollective: String?
            var bitcoin: String?
            var litecoin: String?
            var flattrID: String?
            var icon: LocalizedFile?
            var featureGraphic: LocalizedFile?
            var promoGraphic: LocalizedFile?
            var tvBanner: LocalizedFile?
            var video: LocalizedText?
            var screenshots: Screenshots?
        }

        struct Screenshots : Codable, Equatable {
            var phone: LocalizedFileList?
            var sevenInch: LocalizedFileList?
            var tenInch: LocalizedFileList?
            var wear: LocalizedFileList?
            var tv: LocalizedFileList?
        }

        // public interface PackageVersion {
        //     public val versionCode: Long
        //     public val signer: Signer?
        //     public val releaseChannels: List<String>?
        //     public val packageManifest: PackageManifest
        //     public val hasKnownVulnerability: Boolean
        // }

        struct PackageVersion : Codable, Equatable {
            var added: Int64
            var file: FileV1
            var src: File?
            var manifest: Manifest
            var releaseChannels: Array<String>?
            var antiFeatures: Dictionary<String, LocalizedText>?
            var whatsNew: LocalizedText?
        }

        struct FileV1 : Codable, Equatable {
            var name: String
            var sha256: String
            var size: Int64?
        }

        // public interface PackageManifest {
        //     public val minSdkVersion: Int?
        //     public val maxSdkVersion: Int?
        //     public val featureNames: List<String>?
        //     public val nativecode: List<String>?
        // }

        struct Manifest : Codable, Equatable {
            var versionName: String
            var versionCode: Int64
            var usesSdk: UsesSdk?
            var maxSdkVersion: Int?
            var signer: Signer?
            var usesPermission: Array<Permission>?
            var usesPermissionSdk23: Array<Permission>?
            var nativecode: Array<String>?
            var features: Array<Feature>?
        }

        struct UsesSdk : Codable, Equatable {
            var minSdkVersion: Int
            var targetSdkVersion: Int
        }

        struct Signer : Codable, Equatable {
            var sha256: Array<String>
            var hasMultipleSigners: Bool?
        }

        struct Permission : Codable, Equatable {
            var name: String
            var maxSdkVersion: Int?
        }

        struct Feature : Codable, Equatable {
            var name: String
        }
    }
}

