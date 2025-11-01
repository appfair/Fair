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

    public static var backoffCodes: IndexSet = []

    public init(endpointBase: URL = URL(string: "https://api.appstoreconnect.apple.com/v1/")!, keystoreURL: URL) throws {
        self.endpointBase = endpointBase
        self.keystoreURL = keystoreURL
        self.keystore = try JSONDecoder().decode(FastlaneKeyJSON.self, from: Data(contentsOf: keystoreURL))
        self.privateKey = try keystore.loadPrivateKey(fromBaseURL: keystoreURL)
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

private extension Data {
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}


//// MARK: - Configuration
//let issuerID = "<YOUR_ISSUER_ID>"
//let keyID = "<YOUR_KEY_ID>"
//let privateKeyPath = "apple_key.p8"
//
//// MARK: - JWT Generation
//func loadPrivateKey(from path: String) -> P256.Signing.PrivateKey? {
//    guard let pemString = try? String(contentsOfFile: path),
//          let keyData = extractKeyData(from: pemString) else {
//        print("Failed to load or parse .p8 file")
//        return nil
//    }
//
//    return try? P256.Signing.PrivateKey(rawRepresentation: keyData)
//}
//
//func extractKeyData(from pem: String) -> Data? {
//    let lines = pem.components(separatedBy: .newlines)
//    let base64Key = lines
//        .filter { !$0.contains("BEGIN") && !$0.contains("END") }
//        .joined()
//    return Data(base64Encoded: base64Key)
//}
//
//func generateJWT(using privateKey: P256.Signing.PrivateKey) -> String? {
//    let header = ["alg": "ES256", "kid": keyID]
//    let iat = Int(Date().timeIntervalSince1970)
//    let exp = iat + 1200 // 20 minutes
//    let payload: [String: Any] = ["iss": issuerID, "iat": iat, "exp": exp, "aud": "appstoreconnect-v1"]
//
//    guard let headerData = try? JSONSerialization.data(withJSONObject: header),
//          let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
//        return nil
//    }
//
//    let headerBase64 = headerData.base64URLEncodedString()
//    let payloadBase64 = payloadData.base64URLEncodedString()
//    let signingInput = "\(headerBase64).\(payloadBase64)"
//
//    let signature = try? privateKey.signature(for: Data(signingInput.utf8))
//    let signatureBase64 = signature?.derRepresentation.base64URLEncodedString()
//
//    return [headerBase64, payloadBase64, signatureBase64].compactMap { $0 }.joined(separator: ".")
//}
//
//// MARK: - API Request
//func fetchApps(jwt: String) {
//    let url = URL(string: "https://api.appstoreconnect.apple.com/v1/apps")!
//    var request = URLRequest(url: url)
//    request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
//
//    let task = URLSession.shared.dataTask(with: request) { data, response, error in
//        if let error = error {
//            print("Request error: \(error)")
//            return
//        }
//
//        guard let data = data,
//              let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
//            print("Failed to parse response")
//            return
//        }
//
//        print("Apps response:\n\(json)")
//    }
//
//    task.resume()
//}
//


//
//func xxx() throws {
//    // MARK: - Main
//    if let privateKey = loadPrivateKey(from: privateKeyPath),
//       let jwt = generateJWT(using: privateKey) {
//        fetchApps(jwt: jwt)
//        RunLoop.main.run() // Keep CLI alive for async request
//    } else {
//        print("Failed to generate JWT")
//    }
//}
