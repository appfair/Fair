import Swift
import FairCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An interface for Alternative App Distribution marketplace web services, which provide web APIs for
/// processing and downloading ADP binaries.
///
/// e.g., https://faq.altstore.io/developers/rest-api
public struct MarketplaceEndpoint : EndpointService {
    /// E.g., https://api.altstore.io
    public var endpointBase: URL

    public static var backoffCodes: IndexSet = []

    public init(endpointBase: URL) {
        self.endpointBase = endpointBase
    }

    /// The HTTP headers that should be attached to all API requests
    public var requestHeaders: [String: String] {
        var headers: [String: String] = [:]
        headers["Content-Type"] = "application/json"
        //if let authToken = authToken {
        //    headers["Authorization"] = "token " + authToken
        //}
        return headers
    }

    /// https://faq.altstore.io/developers/rest-api#download-adp
    public struct ADPDownloadRequest : APIRequest {
        public typealias Response = ADPProcessResponse

        public let adpID: String

        public init(adpID: String) {
            self.adpID = adpID
        }

        public func queryURL(for service: MarketplaceEndpoint) -> URL {
            service.endpointBase.appending(components: "adps", adpID) // GET
        }
        
        public func postData() throws -> Data? {
            nil
        }
    }

    /// https://faq.altstore.io/developers/rest-api#process-adp
    public struct ADPProcessRequest : APIRequest {
        public typealias Response = ADPProcessResponse

        public let adpID: String

        public init(adpID: String) {
            self.adpID = adpID
        }

        public func queryURL(for service: MarketplaceEndpoint) -> URL {
            service.endpointBase.appending(components: "adps") // POST
        }

        public func postData() throws -> Data? {
            struct Request : Encodable {
                let adpID: String
            }
            return try JSONEncoder().encode(Request(adpID: adpID))
        }
    }
    
    /// Downloads the specified ADPID, optionally requesting that it be processed (in the event of unprocessed or expired downloads) and waiting for the processing for the given amount of time.
    /// - Parameter adpid: the Altenative Distribution Identifier
    public func download(adpid: String, requestProcessingTimeout: TimeInterval? = 60 * 60 * 10, logger: (String) -> ()) async throws -> URL {
        var dateNow = Date.now
        let expiration = dateNow.addingTimeInterval(requestProcessingTimeout ?? 0)
        while dateNow <= expiration {
            defer { dateNow = Date.now }
            do {
                let downloadResponse = try await request(MarketplaceEndpoint.ADPDownloadRequest(adpID: adpid))

                // 404 will be raised if it has never seen an ADP ID

                if downloadResponse.status == "inProgress" {
                    logger("processing for adpid=\(adpid) inProgress, waiting…")
                    try await Task.sleep(interval: 10)
                    continue
                } else if downloadResponse.downloadExpired == true {
                    // request processing, then continue to wait…
                    logger("download expired for adpid=\(adpid), requesting re-download…")
                    let processing = try await request(MarketplaceEndpoint.ADPProcessRequest(adpID: adpid))
                    logger("request processing for adpid=\(adpid) with status \(processing.status ?? "unknown")")
                    try await Task.sleep(interval: 10)
                    continue
                }

                guard let downloadURL = downloadResponse.downloadURL else {
                    throw AppError("ADP manifest.json was not found in releases and could not download for id \(adpid) with response: \(downloadResponse)")
                }

                // download the ADP zip
                let (downloadFile, response) = try await URLSession.shared.downloadFile(for: URLRequest(url: downloadURL, cachePolicy: .returnCacheDataElseLoad))
                try response.validateHTTPCode()

                return downloadFile
            } catch let error as URLResponse.InvalidHTTPCode {
                if error.code == 404 {
                    // 404 error means that the ADPID hasn't been seen, or has been forgotten
                    // try requesting the download
                    logger("download unknown for adpid=\(adpid), requesting processing…")
                    // TODO: these seem to trigger a 202 with no data when processing is initiated
                    _ = try await requestOptional(MarketplaceEndpoint.ADPProcessRequest(adpID: adpid))
                    try await Task.sleep(interval: 10)
                    continue
                } else {
                    // all other errors bubble up
                    throw error
                }
            }
        }

        throw AppError("Could not obtain a download URL for ADP id \(adpid)")
    }

    /// Examples:
    /// `{"updated":"2025-09-30T22:09:15Z","status":"success","downloadExpired":true,"id":"51a5bdf8-e0a8-4cda-8fa5-00c8a68a4bf3","operationID":"18144721590","created":"2025-09-30T22:06:18Z","downloadExpiration":"2025-10-05T22:09:02Z"}`
    ///`{"operationID":"18351111388","updated":"2025-10-08T16:15:14Z","created":"2025-10-08T16:15:11Z","status":"inProgress","id":"25612dfb-12ce-41d5-819c-354de71c23f8"}`
    /// `{"downloadExpired":false,"downloadExpiration":"2025-10-13T16:18:03Z","id":"25612dfb-12ce-41d5-819c-354de71c23f8","operationID":"18351111388","updated":"2025-10-08T16:18:13Z","status":"success","downloadURL":"https://productionresultssa5.blob.core.windows.net/actions-results/a764e296-d4de-4ecb-bd04-791a873c4dcc/…","created":"2025-10-08T16:15:11Z"}`
    public struct ADPProcessResponse : Codable {
        public let id: String
        public let status: String? // e.g., "inProgress" or "success"
        public let downloadExpiration: Date?
        public let downloadExpired: Bool?
        public let operationID: String?
        public let created: Date?
        public let updated: Date?
        public let downloadURL: URL?
    }
}
