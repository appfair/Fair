import FairCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Crypto)
import Crypto
#else
import CryptoKit
#endif

/// An interface for accessing App Store Connect.
///
/// See https://developer.apple.com/documentation/appstoreconnectapi
public struct AppStoreConnectEndpoint : EndpointService {
    public var endpointBase: URL
    private var keystoreURL: URL
    private var keystore: FastlaneKeyJSON
    private var privateKey: P256.Signing.PrivateKey
    public var requestRetryCount: Int
    public static var backoffCodes: IndexSet = []

    public init(endpointBase: URL = URL(string: "https://api.appstoreconnect.apple.com/v1/")!, keystoreURL: URL, requestRetryCount: Int) throws {
        self.endpointBase = endpointBase
        self.keystoreURL = keystoreURL
        self.keystore = try JSONDecoder().decode(FastlaneKeyJSON.self, from: Data(contentsOf: keystoreURL))
        self.privateKey = try keystore.loadPrivateKey(fromBaseURL: keystoreURL)
        self.requestRetryCount = requestRetryCount
    }

    // https://docs.fastlane.tools/app-store-connect-api/#using-fastlane-api-key-json-file
    /**
     ```
     {
       "key_id": "D383SF739",
       "issuer_id": "6053b7fe-68a8-4acb-89be-165aa6465141",
       "key": "-----BEGIN PRIVATE KEY-----\nMIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHknlhdlYdLu\n-----END PRIVATE KEY-----",
       "duration": 1200, # optional (maximum 1200)
       "in_house": false # optional but may be required if using match/sigh
     }
     ```
     */
    private struct FastlaneKeyJSON : Decodable {
        let key_id: String
        let issuer_id: String
        let key: String?
        let key_filepath: String?
        let duration: Int?
        let in_house: Bool?

        func loadPrivateKey(fromBaseURL baseURL: URL) throws -> P256.Signing.PrivateKey {
            let key = try self.key ?? self.key_filepath.flatMap({ try Data(contentsOf: URL(fileURLWithPath: $0, relativeTo: baseURL)).utf8String })
            guard let key else {
                throw AppError("Neither key nor key_filepath was specified in keystore")
            }
            let keyMaterialBase64 = key.components(separatedBy: .newlines)
                .filter { !$0.contains("BEGIN") && !$0.contains("END") }
                .joined()

            let keyData = Data(base64Encoded: keyMaterialBase64) ?? Data()
            return try P256.Signing.PrivateKey(derRepresentation: keyData)
        }
    }

    /// Creates a JWT token for signing requests to the ASC API.
    ///
    /// See https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests
    func createJTWBearerToken() throws -> String {
        let header = ["alg": "ES256", "typ": "JWT", "kid": keystore.key_id]
        let iat = Int(Date().timeIntervalSince1970)
        let exp = iat + (keystore.duration ?? 1200) // 20 minute default
        let payload: [String: Any] = ["iss": keystore.issuer_id, "iat": iat, "exp": exp, "aud": "appstoreconnect-v1"]

        let headerData = try JSONSerialization.data(withJSONObject: header, options: .sortedKeys).base64URLEncodedString()
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys).base64URLEncodedString()

        let signingInput = [headerData, payloadData].joined(separator: ".")
        let signature: P256.Signing.ECDSASignature = try privateKey.signature(for: Data(signingInput.utf8))
        let signatureBase64 = signature.rawRepresentation.base64URLEncodedString()

        return [signingInput, signatureBase64].joined(separator: ".")
    }

    /// The HTTP headers that should be attached to all API requests
    public var requestHeaders: [String: String] {
        get throws {
            var headers: [String: String] = [:]
            let jwt = try createJTWBearerToken()
            headers["Authorization"] = "Bearer \(jwt)"
            headers["Accept"] = "application/json"
            headers["User-Agent"] = "fairtool/\(Bundle.fairCoreVersion?.versionString ?? "development")"
            return headers
        }
    }

    /// A freeform raw request that returns a raw `JSON` blob
    public struct RawRequest : APIRequest {
        public typealias Response = JSON

        let path: String

        public init(path: String) {
            self.path = path
        }

        public func queryURL(for service: AppStoreConnectEndpoint) -> URL {
            URL(string: path, relativeTo: service.endpointBase) ?? service.endpointBase.appending(path: path)
        }
    }

    /// https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps
    public struct ListAppsRequest : APIRequest {
        let limit: Int?

        public init(limit: Int? = nil) {
            self.limit = limit
        }

        public func queryURL(for service: AppStoreConnectEndpoint) -> URL {
            var url = service.endpointBase.appending(components: "apps")
            if let limit {
                url.append(queryItems: [URLQueryItem(name: "limit", value: "\(limit)")])
            }
            return url
        }

        /**
        ```
         {
           "data": [
             {
               "type": "apps",
               "id": "10746822401",
               "attributes": {
                 "name": "Your Next Cortado",
                 "bundleId": "com.bdt.ync",
                 "sku": "YNC",
                 "primaryLocale": "en-US",
                 "isOrEverWasMadeForKids": false,
                 "subscriptionStatusUrl": null,
                 "subscriptionStatusUrlVersion": null,
                 "subscriptionStatusUrlForSandbox": null,
                 "subscriptionStatusUrlVersionForSandbox": null,
                 "contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT",
                 "streamlinedBuyEnabled": false
               },
               "relationships": {
                 "appEncryptionDeclarations": {
                   "links": {
                     "self": "https://api.appstoreconnect.apple.com/v1/apps/10746822401/relationships/appEncryptionDeclarations",
                     "related": "https://api.appstoreconnect.apple.com/v1/apps/10746822401/appEncryptionDeclarations"
                   }
                 }
                ```
         */
        public struct Response : Codable {
            public var data: [AppInfo]?
            public var links: Links
            public var meta: Meta

            public struct AppInfo : Codable {
                public var type: String // "apps"
                public var id: String // "10746822401"
                public var attributes: Attributes
                public var links: Links

                public struct Attributes : Codable {
                    public var name: String? // "Your Next Cortado",
                    public var bundleId: String? // "com.bdt.ync",
                    public var sku: String? // "YNC",
                    public var primaryLocale: String? // "en-US",
                    public var isOrEverWasMadeForKids: Bool? // false,
                    public var subscriptionStatusUrl: String? // null,
                    public var subscriptionStatusUrlVersion: String? // null,
                    public var subscriptionStatusUrlForSandbox: String? // null,
                    public var subscriptionStatusUrlVersionForSandbox: String? // null,
                    public var contentRightsDeclaration: String? // "DOES_NOT_USE_THIRD_PARTY_CONTENT",
                    public var streamlinedBuyEnabled: Bool? // false
                }

                public var relationships: [String: Relationship]
            }
        }
    }

    public struct AlternativeDistributionVersions : APIRequest {
        let adpID: String

        public init(adpID: String) {
            self.adpID = adpID
        }

        public func queryURL(for service: AppStoreConnectEndpoint) -> URL {
            // GET https://api.appstoreconnect.apple.com/v1/alternativeDistributionPackages/d1663e24-4360-4f7f-a661-8e616e3b3c3b/versions

            let url = service.endpointBase.appending(components: "alternativeDistributionPackages", adpID, "versions")
            return url
        }

        public struct Response : Codable {
            public var data: [AlternativeDistributionInfo.Response.AlternativeDistributionPackageInfo]?
            public var links: Links
            public var meta: Meta
        }
    }

    /// https://developer.apple.com/documentation/appstoreconnectapi/get-v1-alternativedistributionpackageversions-_id_
    public struct AlternativeDistributionInfo : APIRequest {
        let adpID: String

        public init(adpID: String) {
            self.adpID = adpID
        }

        public func queryURL(for service: AppStoreConnectEndpoint) -> URL {
            // GET https://api.appstoreconnect.apple.com/v1/alternativeDistributionPackageVersions/d1663e24-4360-4f7f-a661-8e616e3b3c3b

            let url = service.endpointBase.appending(components: "alternativeDistributionPackageVersions", adpID)
            return url
        }

        public struct Response : Codable {
            public var data: AlternativeDistributionPackageInfo?
            public var links: Links

            public struct AlternativeDistributionPackageInfo : Codable {
                public var type: String // "alternativeDistributionPackages"
                public var id: String // "e651dbc7-a7a7-4e84-a1ae-2afcd92ec6cb"
                public var attributes: Attributes
                public var relationships: [String: Relationship] // e.g., "versions"

                public struct Attributes : Codable {
                    public var url: URL?
                    public var urlExpirationDate: Date? // "2024-03-29T21:22:19-07:00"
                    public var version: String? // "1"
                    public var state: String // "completed"
                }
            }
        }
    }

    /// https://developer.apple.com/documentation/appstoreconnectapi/get-v1-appstoreversions-_id_-alternativedistributionpackage
    public struct AlternativeDistributionPackage : APIRequest {
        let id: String

        public init(id: String) {
            self.id = id
        }

        public func queryURL(for service: AppStoreConnectEndpoint) -> URL {
            /// GET https://api.appstoreconnect.apple.com/v1/appStoreVersions/{id}/alternativeDistributionPackage
            let url = service.endpointBase.appending(components: "appStoreVersions", id, "alternativeDistributionPackage")
            return url
        }

        public struct Response : Codable {
            public var data: AlternativeDistributionPackageInfo?
            public var links: Links

            public struct AlternativeDistributionPackageInfo : Codable {
                public var type: String // "alternativeDistributionPackages"
                public var id: String // "e651dbc7-a7a7-4e84-a1ae-2afcd92ec6cb"
                public var relationships: [String: Relationship] // e.g., "versions"
            }
        }
    }

    public struct ADPVariantRequest : APIRequest {
        public typealias Response = DownloadResponse
        let variantID: UUID

        public init(variantID: UUID) {
            self.variantID = variantID
        }

        public func queryURL(for service: AppStoreConnectEndpoint) -> URL {
            service.endpointBase.appending(components: "alternativeDistributionPackageVariants", variantID.uuidString.lowercased())
        }
    }

    public struct ADPDeltaRequest : APIRequest {
        public typealias Response = DownloadResponse
        let deltaID: UUID

        public init(deltaID: UUID) {
            self.deltaID = deltaID
        }
        
        public func queryURL(for service: AppStoreConnectEndpoint) -> URL {
            service.endpointBase.appending(components: "alternativeDistributionPackageDeltas", deltaID.uuidString.lowercased())
        }
    }

    /// A response for either the variants or deltas
    public struct DownloadResponse : Codable {
        public let data: DownloadData?

        public struct DownloadData : Codable {
            public let type: String // "alternativeDistributionPackageVariants" or "alternativeDistributionPackageDeltas"
            public let id: UUID // "219750db-80c2-4c75-aecc-fa67835f384d"
            public let attributes: Attributes
            public struct Attributes : Codable {
                public let url: URL // "<Apple_CDN_base_URL>/mzpse.7668245576990498917.ipa?accessKey=<access_key>"
                public let urlExpirationDate: Date
                public let alternativeDistributionKeyBlob: String // "<key_blob_base64_encoded_string>"
            }
        }
    }

    public struct Relationship : Codable {
        public var links: Links
    }

    public struct Links : Codable {
        public var `self`: String? // "https://api.appstoreconnect.apple.com/v1/apps?limit=2"
        public var related: String? // "https://api.appstoreconnect.apple.com/v1/apps/10746821976/marketplaceSearchDetail"
        public var next: String? // "https://api.appstoreconnect.apple.com/v1/apps?cursor=AoJ4g7mg6o4DKzEwNzQ2ODIxOTc2.ANrJC88&limit=2"
    }

    public struct Meta : Codable {
        public var paging: Paging

        public struct Paging : Codable {
            public var total: Int
            public var limit: Int
        }
    }
}

extension AppStoreConnectEndpoint {
    public struct ADPDownloadError : LocalizedError {
        public var errorDescription: String?
    }

    /// Look up the ADP ID for the given app version ID
    public func fetchADPId(forVersionID versionID: String) async throws -> String {
        // version id was specified; fetch the version endpoint and get the adpid from it
        let versions = try await self.request(AlternativeDistributionPackage(id: versionID))

        guard let versionsData = versions.data else {
            throw ADPDownloadError(errorDescription: "Response did not contain any data payload")
        }

        if versionsData.type != "alternativeDistributionPackages" {
            throw ADPDownloadError(errorDescription: "Response did not contain an alternative distribution package")
        }

        return versionsData.id
    }

    /// Given either an ADP ID or a version ID, return either the ADP ID itself or else resolve the version ID's ADP ID and return that
    public func resolveADPID(from adpID: String?, versionID: String?) async throws -> String {
        if let adpID {
            // we specified the ADP ID directly, so just use that
            return adpID
        }
        guard let versionID else {
            throw ADPDownloadError(errorDescription: "Either --appid or --versionid must be specified")
        }

        let adpID = try await self.fetchADPId(forVersionID: versionID)
        return adpID
    }

    func download(url: URL, successRange: Range<Int> = 200..<300) async throws -> (URL, URLResponse) {
        // TODO: implement retryCount to handle various errors by re-trying after a delay, like is done with EndpointSerice.fetchWithRetry
        var retries = max(1, self.requestRetryCount)
        while retries > 0 {
            retries -= 1
            do {
                let (downloadFile, response) = try await URLSession.shared.downloadFile(for: URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad))
                try response.validateHTTPCode(inRange: successRange)
                return (downloadFile, response)
            } catch {
                if retries == 0 {
                    throw error
                }
                // e.g., retryCount = 5, reties = 3, backoff for 3 seconds
                let backoff = min(1.0, (TimeInterval((self.requestRetryCount - retries)) * 5.0) + 1.0)
                dbg("download error backoff=\(backoff): \(error)")
                try await Task.sleep(interval: backoff)
            }
        }
        throw ADPDownloadError(errorDescription: "did not try to download url: \(url)")
    }

    /// Downloads all the assets from an Alternative Distribution Package to the speficied directory
    /// - Parameters:
    ///   - adpid: either the ADP ID or the version ID must be specified
    ///   - versionid: either the ADP ID or the version ID must be specified
    ///   - directory: the base directory to download the package
    ///   - logger: an optional logger for an Encodable
    /// - Returns: a map from relative file paths to absolute locations
    public func downloadADP(adpid: String, directory: String?, logger: ((String?) -> ())?) async throws -> (ADPManifest, [String: URL]) {

        var downloaded: [String: URL] = [:]

        let adpVersions = try await self.request(AlternativeDistributionVersions(adpID: adpid))

        // TODO: wait for completed?
        guard let adpVersionsData = adpVersions.data else {
            throw ADPDownloadError(errorDescription: "No data in response")
        }

        guard let completedADPVersion = adpVersionsData.first(where: { $0.attributes.state == "COMPLETED" }) else {
            throw ADPDownloadError(errorDescription: "No completed version found for this ADP: \(adpVersionsData.map(\.attributes.state).joined(separator: ", "))")
        }

        guard let manifestSignatureZipURL = completedADPVersion.attributes.url else {
            throw ADPDownloadError(errorDescription: "No download URL found for ADP")
        }

        // download the URL and unzip manifest.json and signature to the directory
        let (downloadFile, response) = try await download(url: manifestSignatureZipURL)
        try response.validateHTTPCode()
        defer { try? FileManager.default.removeItem(at: downloadFile) }

        //let adpReleaseID = completedADPVersion.id
        let expandPath = URL(fileURLWithPath: directory ?? FileManager.default.currentDirectoryPath).appendingPathComponent(adpid, isDirectory: true)

        if expandPath.pathIsDirectory {
            // note that we do *not* trash the directory because we want to save previously-cached files in order to handle resuming interrupted transfers
            //try FileManager.default.trash(url: expandPath)
        }
        try FileManager.default.unzipItem(at: downloadFile, to: expandPath, overwrite: true)

        let signaturePath = expandPath.appendingPathComponent("signature", isDirectory: false)
        if !signaturePath.pathIsRegularFile {
            throw ADPDownloadError(errorDescription: "signature file not found in ADP package at \(expandPath.path)")
        }
        downloaded[signaturePath.lastPathComponent] = signaturePath

        let manifestPath = expandPath.appendingPathComponent("manifest.json", isDirectory: false)
        if !manifestPath.pathIsRegularFile {
            throw ADPDownloadError(errorDescription: "manifest.json file not found in ADP package at \(expandPath.path)")
        }
        downloaded[manifestPath.lastPathComponent] = manifestPath

        let manifest = try JSONDecoder().decode(ADPManifest.self, from: Data(contentsOf: manifestPath))
        //try logger?(manifest)

        func downloadAsset(from sourceURLClosure: @autoclosure () async throws -> URL?, to destinationPath: String, checksum: String?) async throws -> URL {
            let destination = expandPath.appending(path: destinationPath)

            logger?("checking checksum at \(destination.path) against \(checksum ?? "none")")
            // first check to see if the file already exists, and if it matches the checksum, we don't need to download it again
            if let checksum, FileManager.default.isReadableFile(atPath: destination.path) {
                let fileChecksum = try Data(contentsOf: destination, options: .mappedIfSafe).sha256().hex()
                if checksum.lowercased() == fileChecksum.lowercased() {
                    logger?("file at destination \(destination.path) already matches expected checksum, skipping download")
                    return destination
                }
            }

            guard let sourceURL = try await sourceURLClosure() else {
                throw ADPDownloadError(errorDescription: "No data returned from API to get asset info")
            }

            let (downloadDeltaFile, response) = try await download(url: sourceURL)
            try response.validateHTTPCode()
            try? FileManager.default.removeItem(at: destination) // remove it if it happens to already exist
            try FileManager.default.moveItem(at: downloadDeltaFile, to: destination)
            if let checksum {
                // validate the checksum if it is specified
                let fileChecksum = try Data(contentsOf: destination, options: .mappedIfSafe).sha256().hex()
                if checksum.lowercased() != fileChecksum.lowercased() {
                    throw ADPDownloadError(errorDescription: "Checksum of downloaded file \(fileChecksum) does not match expected value \(checksum) at: \(destination.path)")
                }
            }
            return destination
        }

        // Store the app data at an expected path
        // https://developer.apple.com/documentation/marketplacekit/ingesting-an-alternative-distribution-package#Store-the-app-data-at-an-expected-path

        // download each of the variants
        // https://developer.apple.com/documentation/marketplacekit/ingesting-an-alternative-distribution-package#Download-app-variants
        // GET https://api.appstoreconnect.apple.com/alternativeDistributionPackageVariants/219750db-80c2-4c75-aecc-fa67835f384d

        let variantsFolder = expandPath.appendingPathComponent("variant", isDirectory: true)
        try FileManager.default.createDirectory(at: variantsFolder, withIntermediateDirectories: true)
        guard let variantsRelationship = completedADPVersion.relationships["variants"] else {
            throw ADPDownloadError(errorDescription: "No variants found for ADP")
        }
        _ = variantsRelationship // TODO: cross-reference variants result with manifest variants to validate
        for variantInfo in manifest.variants {
            let variantChecksum = variantInfo.variantDetails.sha256Hash
            logger?("downloading variant: \(variantInfo.assetPath)")
            downloaded[variantInfo.assetPath] = try await downloadAsset(from: try await self.request(ADPVariantRequest(variantID: variantInfo.publicId)).data?.attributes.url, to: variantInfo.assetPath, checksum: variantChecksum)
        }


        // download each of the deltas (optional; might not be included in the initial reported version)
        // “When App Store Connect sends a new app version notification, it sends an app distribution package that includes the variants first, followed by another for deltas, if any are available for the app. Deltas arrive an unspecified amount of time after the app’s variants. You don’t need to wait for deltas to arrive before serving the new app to devices. Rather, App Store Connect sends variants first to expedite the app’s availability for customers.”
        // https://developer.apple.com/documentation/marketplacekit/ingesting-an-alternative-distribution-package#Download-app-deltas

        let deltasFolder = expandPath.appendingPathComponent("delta", isDirectory: true)
        try FileManager.default.createDirectory(at: deltasFolder, withIntermediateDirectories: true)
        guard let deltasRelationship = completedADPVersion.relationships["deltas"] else {
            throw ADPDownloadError(errorDescription: "No deltas found for ADP")
        }
        _ = deltasRelationship // TODO: cross-reference deltas result with manifest deltas to validate
        for deltaInfo in manifest.deltas {
            let deltaChecksum = deltaInfo.deltaDetails.sha256Hash
            logger?("downloading delta: \(deltaInfo.assetPath)")
            downloaded[deltaInfo.assetPath] = try await downloadAsset(from: try await self.request(ADPDeltaRequest(deltaID: deltaInfo.publicId)).data?.attributes.url, to: deltaInfo.assetPath, checksum: deltaChecksum)
        }

        return (manifest, downloaded)
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension ADPManifest.AssetDetails {
    /// Returns the sha256 hash iff there is exactly a single one in the hashes list.
    var sha256Hash: String? {
        hashes.filter({ $0.algorithm == "sha256" }).onlyElement?.encryptedChunkDigests.onlyElement
    }
}
private extension Collection {
    /// Returns the first element iff the collection consists of a single element
    var onlyElement: Element? {
        return count == 1 ? first : nil
    }
}
