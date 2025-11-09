import Swift
import Foundation
#if canImport(FoundationNetworking)
@_exported import FoundationNetworking
#endif

extension Data {
    /// Async variant to loading from a URL using a session like the standard shared session.
    /// - Parameters:
    ///   - url: the URL to load
    ///   - session: the session use for loading, defaulting to the system's shared URLSession
    ///   - syncOptions: if options are specific, the synchonous version of the Data initializer will be used with the specified options.
    internal init(contentsOf url: URL, session: URLSession? = .shared, syncOptions options: Data.ReadingOptions? = nil) async throws {
        // TODO: fails on Linux, and need to investigate any performance benefits on macOS (simple testing shows a slight performance degradation in serial tests)
//        if options == nil, let session = session {
//            self = try await session.fetch(request: URLRequest(url: url)).data
//        } else {
            self = try Data.init(contentsOf: url, options: options ?? [])
//        }
    }
}

public extension URLResponse {
    func validateHTTPCode(inRange: Range<Int> = 200..<300) throws {
        guard let httpResponse = self as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if !inRange.contains(httpResponse.statusCode) {
            let code: URLError.Code? = URLError.Code(rawValue: httpResponse.statusCode) // on linux this is optional
            throw URLError(code ?? .badServerResponse, userInfo: [:])
        }
    }
}

extension URLRequest {
    public typealias ResponseStream = AsyncThrowingStream<URLResponseEvent, Error>
    public typealias AuthenticationChallengeHandler = (URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?)
    public typealias RedirectHandler = (_ response: HTTPURLResponse, _ request: URLRequest) -> URLRequest?

    public enum URLResponseEvent {
        case waitingForConnectivity
        case response(URLResponse)
        case redirect(_ redirectResponse: HTTPURLResponse, _ newRequest: URLRequest, _ redirectRequest: URLRequest?)
        case challenge(URLAuthenticationChallenge)
        case data(Data)
        case metrics(URLSessionTaskMetrics)
    }

//    public func dataStream(configuration config: URLSessionConfiguration = .ephemeral, redirectHandler: @escaping RedirectHandler = { (response, request) in request }, challengeHandler: @escaping AuthenticationChallengeHandler = { _ in (.performDefaultHandling, nil) }) -> ResponseStream {
//    }

    /// Creates an asynchronous stream of response components (headers, data, redirects, etc.) for the given network URL.
    ///
    /// Unlike `URLSession.bytes`, this sequence will return the events for the URL connection, including the stream events.
    ///
    /// Note that this is only supported for network URLs and not `file://`.
    ///
    /// - Parameters:
    ///   - config: the session configuration to use
    ///   - request: the URL request
    ///   - challengeHandler: the callback for when a challenge occurs
    /// - Returns: an AsyncThrowingStream with the events
    public func openStream(configuration config: URLSessionConfiguration = .ephemeral, redirectHandler: @escaping RedirectHandler = { (response, request) in request }, challengeHandler: @escaping AuthenticationChallengeHandler = { _ in (.performDefaultHandling, nil) }) throws -> ResponseStream {
        guard self.url?.isFileURL != true else {
            throw URLError(.badURL) // file URLs do work for this, but only on Darwin but not on Linux
        }

        return AsyncThrowingStream { c in
            let delegate = Delegate(c, redirectHandler: redirectHandler, challengeHandler: challengeHandler)
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: self)

            c.onTermination = { _ in
                task.cancel()
            }

            // task.delegate = delegate // note that this would allow us to re-use an existing URLSession rather than creating one anew just to holde the delegate, but this callback is not yet supported in swift core-foundation for non-Darwin platforms
            task.resume()
        }

        class Delegate : NSObject, URLSessionDataDelegate {
            let continuation: ResponseStream.Continuation
            let challengeHandler: AuthenticationChallengeHandler
            let redirectHandler: RedirectHandler


            init(_ continuation: ResponseStream.Continuation, redirectHandler: @escaping RedirectHandler, challengeHandler: @escaping AuthenticationChallengeHandler) {
                self.continuation = continuation
                self.challengeHandler = challengeHandler
                self.redirectHandler = redirectHandler
            }

            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
                dbg("response:", response)
                continuation.yield(.response(response))
                completionHandler(.allow)
            }

            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
                //dbg("received:", data)
                continuation.yield(.data(data))
            }

            func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
                continuation.yield(.waitingForConnectivity)
            }


            func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
                let redirectRequest = redirectHandler(response, request)
                continuation.yield(.redirect(response, request, redirectRequest))
                completionHandler(redirectRequest)
            }

            func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
                continuation.yield(.metrics(metrics))
            }

            func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                continuation.finish(throwing: error)
            }

            func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
                continuation.yield(.challenge(challenge))
                let (d, c) = self.challengeHandler(challenge)
                completionHandler(d, c)
            }
        }
    }
}

public extension URLRequest {
    /// Downloads the URL and verifies the HTTP success code and, optionally, the validity of the
    /// SHA-256 hash included as the URL's fragment.
    ///
    /// - Parameters:
    ///   - session: the URLSession to use, defaulting to `URLSession.shared`
    ///   - validateFragmentHash: if `true`, validate that the contents of the data match a SHA256 hash in the URL
    /// - Returns: the `Data` if it downloaded and validated
    func fetch(session: URLSession = .shared, validateFragmentHash: Bool = false) async throws -> Data {
        let (data, response) = try await session.fetch(request: self)
        try response.validateHTTPCode() // ensure the code in within the expected range

        if validateFragmentHash == true,
            let fragmentHash = self.url?.fragment {
            let dataHash = data.sha256().hex()
            if dataHash != fragmentHash {
                //throw AppError(String(format: NSLocalizedString("Hash mismatch for %@: %@ vs. %@", bundle: .module, comment: "error message"), self.url?.absoluteString ?? "", fragmentHash, dataHash))
                throw URLError(.downloadDecodingFailedToComplete)
            }
        }

        return data
    }
}

extension URLResponse {
    public struct InvalidHTTPCode : Error, LocalizedError {
        public let code: Int
        public let url: URL?
        //public let response: HTTPURLResponse

        public var errorDescription: String? {
            //NSLocalizedString("Invalud Cide", bundle: .module, comment: "invalid code error")
            "Invalid HTTP Response: \(code) for URL: \(url?.absoluteString ?? "none")"
        }
    }

    /// Attempts to validate the status code in the given range and throws an error if they fail.
    func validating(codes: IndexSet?) throws -> Self {
        guard let codes = codes else {
            return self // no validation
        }

        guard let httpResponse = self as? HTTPURLResponse else {
            // loading from the file system doesn't expose codes
            return self // throw URLError(.badServerResponse)
        }

        if !codes.contains(httpResponse.statusCode) {
            throw InvalidHTTPCode(code: httpResponse.statusCode, url: self.url)
        }

        return self // the response is valid
    }
}

extension URLSession {
    /// Fetches the given request asynchronously, optionally validating that the response code is within the given range of HTTP codes.
    public func fetch(request: URLRequest, validate codes: IndexSet? = IndexSet(200..<300)) async throws -> (data: Data, response: URLResponse) {
        // on Darwin platforms, URLSession.shared.data works with file URLs, but fails on Linux, so manually check whether it is a file URL and load it from disk
        if let url = request.url, url.isFileURL {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let response = URLResponse(url: url, mimeType: nil, expectedContentLength: data.count, textEncodingName: nil)
            return (data, response)
        }

        return try await fetchTask(request: request, validate: codes)
    }

    /// A shim for async URL download for back-ported async/await without corresponding URLSession API support
    private func fetchTask(request: URLRequest, validate codes: IndexSet?) async throws -> (data: Data, response: URLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        let validResponse = try response.validating(codes: codes)
        return (data, validResponse)
    }
}

//extension URLSession {
//    /// Asynchronously generate a SHA-256 for the contents of this URL (experimental and slow).
//    @available(*, deprecated, message: "42x slower than Data(contentsOfURL:).sha256()")
//    func sha256(for url: URL, hashBufferSize: Int = 1024 * 1024) async throws -> Data {
//        let (asyncBytes, _) = try await self.bytes(for: URLRequest(url: url))
//
//        var bytes = Data()
//        bytes.reserveCapacity(hashBufferSize)
//
//        let hasher = SHA256Hasher()
//
//        func flushBuffer(_ bytesCount: Int64) async throws {
//            try Task.checkCancellation()
//            await hasher.update(data: bytes) // update the running hash
//            bytes.removeAll(keepingCapacity: true) // clear the buffer
//        }
//
//        var bytesCount: Int64 = 0
//        for try await byte in asyncBytes {
//            bytesCount += 1
//            bytes.append(byte)
//            if bytes.count == hashBufferSize {
//                try await flushBuffer(bytesCount)
//            }
//        }
//        if !bytes.isEmpty {
//            try await flushBuffer(bytesCount)
//        }
//
//        let sha256 = await hasher.final()
//        return sha256
//    }
//}


public extension URLSession {
    #if os(Linux) || os(Android) || os(Windows)
    /// Stub for missing async data support on Linux & Windows
    func data(for request: URLRequest, delegate: Void?) async throws -> (data: Data, response: URLResponse) {
        let (data, response) = try await fetch(request: request)
        return (data, response ?? URLResponse(url: request.url ?? URL(string: "about:blank")!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
    }
    #endif

    /// Downloads the given URL request in the current session
    func downloadSync(_ request: URLRequest, timeout: DispatchTime = .distantFuture) throws -> (url: URL, response: URLResponse) {
        try sync(request: request, timeout: timeout) { request, handler in
            downloadTaskCopy(with: request, completionHandler: handler)
        }
    }

    /// Initiates the given task (either `dataTask` or `downloadTask`) and waits for completion.
    /// Swift 5.5 applications should avoid using this in favor of the async/await versions of the API.
    private func sync<T>(request: URLRequest, timeout: DispatchTime, createTask: (_ with: URLRequest, _ completionHandler: @escaping (T?, URLResponse?, Error?) -> ()) -> URLSessionTask) throws -> (T, response: URLResponse) {

        let done = DispatchSemaphore(value: 0)
        var data: T?
        var response: URLResponse?
        var error: Error?
        createTask(request) {
            (data, response, error) = ($0, $1, $2)
            done.signal()
        }.resume()
        switch done.wait(timeout: timeout) {
        case .success:
            if let error = error {
                throw error
            } else if let response = response, let data = data {
                return (data, response)
            } else {
                throw URLError(.unknown)
            }
        case .timedOut:
            throw URLError(.timedOut)
        }
    }
}

extension URLResponse {
    private static let gmtDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, dd LLL yyyy HH:mm:ss zzz"
        return fmt
    }()

    /// Returns the last modified date for this response
    public var lastModifiedDate: Date? {
        guard let headers = (self as? HTTPURLResponse)?.allHeaderFields else {
            return nil
        }
        guard let modDate = headers["Last-Modified"] as? String else {
            return nil
        }
        return Self.gmtDateFormatter.date(from: modDate)
    }
}

extension URLRequest {

    /// Downloads the given request to a cached file location.
    ///
    /// - Parameters:
    ///   - request: the request containing the URL to download
    ///   - memoryBufferSize: the buffer size
    ///   - consumer: a consumer for the data, such as  to update a hashing function
    ///   - parentProgress: the progress to attach to
    ///
    /// - Returns: the downloaded file URL along with the request's response
    public func download(config: URLSessionConfiguration = .ephemeral, consumer: DataConsumer? = nil, parentProgress: Progress? = nil, responseVerifier: (URLResponse) throws -> Bool = { (200..<300).contains(($0 as? HTTPURLResponse)?.statusCode ?? 200) }) async throws -> (URL, URLResponse?) {
        var urlResponse: URLResponse?
        var progress: Progress?

        // create a temporary file in the caches directory from which we will extract the data
        let downloadedArtifact = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(self.url?.lastPathComponent ?? "download")

        dbg("downloading to temporary path:", downloadedArtifact.path)

        // ensure parent path exists
        try FileManager.default.createDirectory(at: downloadedArtifact.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

        // the file must exist before we can open the file handle
        FileManager.default.createFile(atPath: downloadedArtifact.path, contents: nil, attributes: nil)

        var bytesCount: Int64 = 0
        var fh: FileHandle? = nil
        defer { try? fh?.close() }

    out:
        for try await event in try openStream(configuration: config) {
            switch event {
            case .waitingForConnectivity:
                break
            case .response(let response):
                if try responseVerifier(response) == false {
                    break out
                }
                let length = response.expectedContentLength
                let progress1 = Progress(totalUnitCount: length)
                parentProgress?.addChild(progress1, withPendingUnitCount: 3)
                progress = progress1
                urlResponse = response
                break
            case .redirect(_, _, _):
                break
            case .challenge(_):
                break // TODO: permit challenge response
            case .data(let d):
                // if we receive data before we receive the response, throw an error
                if urlResponse == nil || progress?.isCancelled == true {
                    dbg("cancelled")
                    //try Task.checkCancellation()
                    throw URLError(.cancelled)
                }
                if fh == nil {
                    // wait to open the file until we have validated the response
                    fh = try FileHandle(forWritingTo: downloadedArtifact)
                }

                try fh!.write(contentsOf: d)
                bytesCount += Int64(d.count)

                let total = Double(progress?.totalUnitCount ?? 0)
                let _ = total
                //let percentComplete = total == 0.0 ? 0.0 : Double(progress?.completedUnitCount ?? 0) / total
                dbg(progress?.completedUnitCount.localizedByteCount(), progress?.totalUnitCount.localizedByteCount())
                progress?.completedUnitCount = bytesCount

                await consumer?.update(data: d)
                break
            case .metrics(_):
                break
            }
        }

        return (downloadedArtifact, urlResponse)
    }
}

extension URLSession {
    /// Issues a `HEAD` request for the given URL and returns the response
    public func fetchHEAD(url: URL, cachePolicy: URLRequest.CachePolicy) async throws -> URLResponse? {
        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        request.httpMethod = "HEAD"
        let (_, response) = try await fetch(request: request)
        return response
    }

    /// the number of progress segments for the download part; the remainder will be the zip decompression
    public static let progressUnitCount: Int64 = 4

    #if !os(Linux) && !os(Android) && !os(Windows) // bytes not available: https://github.com/apple/swift-corelibs-foundation/issues/3205
    /// Downloads the given request to a cached file location.
    ///
    /// - Parameters:
    ///   - request: the request containing the URL to download
    ///   - memoryBufferSize: the buffer size
    ///   - consumer: a consumer for the data, such as  to update a hashing function
    ///   - parentProgress: the progress to attach to
    ///
    /// - Returns: the downloaded file URL along with the request's response
    ///
    /// Note: this operation downloads directly into memory instead of the potentially-more-efficient download task.
    /// We would like to use a download task to save directly to a file and have progress callbacks go through DownloadDelegate, but it is not working with async/await (see https://stackoverflow.com/questions/68276940/how-to-get-the-download-progress-with-the-new-try-await-urlsession-shared-downlo)
    /// However, an advantage of using streaming bytes is that we can maintain a running sha256 hash for the download without have to load the whole data chunk into memory after the download has completed
    private func downloadOLD(request: URLRequest, memoryBufferSize: Int = 1024 * 64, consumer: DataConsumer? = nil, parentProgress: Progress? = nil, responseVerifier: (URLResponse) throws -> Bool = { (200..<300).contains(($0 as? HTTPURLResponse)?.statusCode ?? 200) }) async throws -> (URL, URLResponse) {
        let downloadedArtifact: URL
        let (asyncBytes, response) = try await self.bytes(for: request)
        if try responseVerifier(response) == false {
            throw CocoaError(.fileNoSuchFile)
        }
        let length = response.expectedContentLength
        let progress1 = Progress(totalUnitCount: length)
        parentProgress?.addChild(progress1, withPendingUnitCount: Self.progressUnitCount - 1)

        try Task.checkCancellation()

        // create a temporary zip file in the caches directory from which we will extract the data
        downloadedArtifact = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(request.url?.lastPathComponent ?? "download")

        dbg("downloading to temporary path:", downloadedArtifact.path)

        // ensure parent path exists
        try FileManager.default.createDirectory(at: downloadedArtifact.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

        try Task.checkCancellation()

        // the file must exist before we can open the file handle
        FileManager.default.createFile(atPath: downloadedArtifact.path, contents: nil, attributes: nil)

        let fh = try FileHandle(forWritingTo: downloadedArtifact)

        var success = false

        defer {
            // if any errors occur, close the delete the temporary artifact;
            // this is expected to fail unless we have successfully moved the file
            if success == false {
                do {
                    try fh.close()
                    try FileManager.default.removeItem(at: downloadedArtifact)
                } catch {
                    dbg("error when cleaning up failed download:", error)
                }
            }
        }

        var bytes = Data()
        bytes.reserveCapacity(memoryBufferSize)

        func flushBuffer(_ bytesCount: Int64) async throws {
            try Task.checkCancellation()

            try fh.write(contentsOf: bytes) // write out the buffer
            await consumer?.update(data: bytes) // update the running hash
            bytes.removeAll(keepingCapacity: true) // clear the buffer

            if let parentProgress = parentProgress {
                if parentProgress.isCancelled == true {
                    throw CocoaError(.userCancelled)
                }
                progress1.completedUnitCount = bytesCount
            }
        }

        var bytesCount: Int64 = 0
        for try await byte in asyncBytes {
            bytesCount += 1
            bytes.append(byte)
            if bytes.count == memoryBufferSize {
                try await flushBuffer(bytesCount)
            }
        }
        if !bytes.isEmpty {
            try await flushBuffer(bytesCount)
        }

        success = true // prevent the cleanup
        try fh.close()
        return (downloadedArtifact, response)
    }
    #endif // !os(Linux) && !os(Android) && !os(Windows)

    /// Downloads the given file. It should behave the same as the async URLSession.download function (which is missing from linux).
    public func downloadFile(for request: URLRequest, useContentDispositionFileName: Bool = true, useLastModifiedDate: Bool = true) async throws -> (localURL: URL, response: URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            downloadTaskCopy(with: request, useContentDispositionFileName: useContentDispositionFileName, useLastModifiedDate: useLastModifiedDate) { url, response, error in
                if let url = url, let response = response, error == nil {
                    continuation.resume(returning: (url, response))
                } else {
                    continuation.resume(throwing: error ?? URLError(.badServerResponse))
                }
            }
            .resume()
        }
    }

    /// If the download from `downloadTask` is successful, the completion handler receives a URL indicating the location of the downloaded file on the local filesystem. This storage is temporary. To preserve the file, this will move it from the temporary location before returning from the completion handler.
    /// In practice, macOS seems to be inconsistent in when it ever cleans up these files, so a failure here will manifest itself in occasional missing files.
    /// This is needed for running an async operation that will still have access to the resulting file.
    /// - Parameters:
    ///   - request: the request for the download
    ///   - useContentDispositionFileName: whether to attempt to rename the file based on the file name specified in the `Content-Disposition` header, if present.
    ///   - useLastModifiedDate: whether to transfer the server's reported "Last-Modified" header to set the creation time of the file.
    ///   - completionHandler: the handler to invoke when the download is complete
    /// - Returns: the task that was initiated
    func downloadTaskCopy(with request: URLRequest, useContentDispositionFileName: Bool = true, useLastModifiedDate: Bool = true, completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        self.downloadTask(with: request) { url, response, error in
            /// Files are generally placed somewhere like: file:///var/folders/24/8k48jl6d249_n_qfxwsl6xvm0000gn/T/CFNetworkDownload_q0k6gM.tmp
            do {
                /// We'll copy it to a temporary replacement directory with the base name matching the URL's name
                if let temporaryLocalURL = url,
                   temporaryLocalURL.isFileURL {
                    var pathName = temporaryLocalURL.lastPathComponent

                    if useContentDispositionFileName == true,
                       let disposition = (response as? HTTPURLResponse)?.allHeaderFields["Content-Disposition"] as? String,
                       disposition.hasPrefix("attachment; filename="),
                       let contentDispositionFileName = disposition.components(separatedBy: "filename=").last,
                       contentDispositionFileName.unicodeScalars.filter(CharacterSet.urlPathAllowed.inverted.contains).isEmpty,
                       contentDispositionFileName.contains("/") == false {
                        pathName = contentDispositionFileName
                    }

                   let tempDir = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: temporaryLocalURL, create: true)
                    let destinationURL = tempDir.appendingPathComponent(pathName)
                    try FileManager.default.moveItem(at: temporaryLocalURL, to: destinationURL)

                    if useLastModifiedDate == true, let lastModifiedDate = response?.lastModifiedDate {
                        // preserve Last-Modified by transferring the date to the item
                        try? FileManager.default.setAttributes([.creationDate : lastModifiedDate, .modificationDate : lastModifiedDate], ofItemAtPath: destinationURL.path)
                    }

                    dbg("replace download file for:", response?.url, "local:", temporaryLocalURL.path, "moved:", destinationURL.path, (try? destinationURL.self.resourceValues(forKeys: [.fileSizeKey]).fileSize)?.localizedByteCount())
                    return completionHandler(destinationURL, response, error)
                }
            } catch {
                dbg("ignoring file move error and falling back to un-copied file:", error)
            }

            // fall-back to the completion handler
            return completionHandler(url, response, error)
        }
    }
}
