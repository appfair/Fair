import Foundation
import FairCore

/// A Fair Ground is a platform for app distribution
public enum FairGround {
    /// A fairground that uses hosted git repository with a REST API,
    /// such as github.com
    case hub(FairHub)

    /// The `FairHub` for repositories that use that model
    public var hub: FairHub? {
        switch self {
        case .hub(let x): return x
        }
    }
}

/// The seal of the given URL, summarizing its cryptographic hash, entitlements,
/// and other build-time information
public struct FairSeal : Codable, JSONSignable {
    // legacy fields that have been removed:
    /// The version of the fairseal JSON
    // public private(set) var fairsealVersion: Version?
    // public enum Version : Int, Codable, CaseIterable { case v1 = 1 }

    /// The version of the fairtool library that initially created this seal
    public internal(set) var generatorVersion: AppVersion?

    /// The AppSource metadata from `App.yml` and `Info.plist`
    public var appSource: AltCatalogItem?
    /// The sealed assets
    public var assets: [Asset]?
    /// The size of the artifact's executable binary
    public var coreSize: Int?
    /// The contents of the `App.yml` metadata
    public var metadata: JSON?
    /// The permission for this app
    public var permissions: [AppPermission]?
    /// The signature for this payload, authenticating the fairseal issuer with HMAC-256
    public var signature: Data?
    /// The tint color as an RGBA hex string
    public var tint: String?

    public struct Asset : Codable {
        /// The asset's URL
        public var url: URL
        /// The asset's size in bytes
        public var size: Int
        /// The validated sha256 checksum for the asset contents
        public var sha256: String

        public init(url: URL, size: Int, sha256: String) {
            self.url = url
            self.size = size
            self.sha256 = sha256
        }
    }

    public var signatureData: Data? {
        get { signature }
        set { signature = newValue }
    }

    public init(metadata: JSON?, assets: [Asset]? = nil, permissions: [AppPermission]? = nil, appSource: AltCatalogItem? = nil, coreSize: Int? = nil, tint: String? = nil) {
        self.metadata = metadata
        self.generatorVersion = Bundle.fairCoreVersion
        //self.fairsealVersion = Version.allCases.last!

        self.assets = assets
        self.permissions = permissions
        self.appSource = appSource
        self.coreSize = coreSize
        self.tint = tint
    }

    /// The app org associated with this seal; this will be the first component of the first URL's path
    public var appOrg: String? {
        assets?.first?.url.path.split(separator: "/").first?.description
    }
}

extension FairSeal {
    /// Tries to parse the "app" property of the metadata as a `AppMetadata`
    func parseAppMetaData() throws -> AppMetadata? {
        guard let app = self.metadata?["app"]?.object else {
            return nil
        }

        return try AppMetadata(json: app.json())
    }
}

extension URL {
    /// Adds a hash with the given string to the end of the URL
    func appendingHash(_ hashString: String?) -> URL {
        guard let hashString = hashString else { return self }
        return URL(string: self.absoluteString + "#" + hashString) ?? self
    }
}
