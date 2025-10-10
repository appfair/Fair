#if DEBUG // need @testable
import Swift
import XCTest
import FairCore
@testable import FairExpo

#if !os(Windows) // Windows doesn't yet seem to support async tests: invalid conversion from 'async' function of type '() async throws -> ()' to synchronous function type '() throws -> Void'
final class FairHubTests: XCTestCase {

    override class func setUp() {
//        if authToken == nil {
//            XCTFail("Missing GITHUB_TOKEN and GH_TOKEN in environment")
//        }
    }

    /// True if we are running from GitHub CI (in which case we skip some tests to reduce load)
    var runningFromCI: Bool {
        ProcessInfo.processInfo.environment["FAIRHUB_API_SKIP"] == "true"
    }

    /// The hub that we use for testing, the so-called "git"-hub.
    static func hub(skipNoAuth: Bool = false) throws -> FairHub {
        if skipNoAuth == true && Self.authToken == nil {
            throw XCTSkip("cannot run API tests without a token")
        }
        return try FairHub(hostOrg: "github.com/" + appfairName, authToken: authToken, fairsealIssuer: "appfairbot", fairsealKey: nil)
    }

    /// if the environment uses the "GH_TOKEN" or "GITHUB_TOKEN" (e.g., in an Action), then pass it along to the API requests
    static let authToken: String? = ProcessInfo.processInfo.environment["GH_TOKEN"] ?? ProcessInfo.processInfo.environment["GITHUB_TOKEN"]

    /// Issue a request against the hub for the given request type
    func request<A: APIRequest>(_ request: A) async throws -> A.Response? where A.Service == FairHub {
        try await Self.hub().request(request)
    }

    func testQueryError() async throws {
        let hub = try Self.hub(skipNoAuth: true)
        do {
            do {
                let response = try await hub.request(FairHub.LookupPRNumberQuery(owner: "xxx", name: "xxx", prid: -1))

                XCTAssertNil(response.result.successValue, "request should not have succeeded")
                if response.result.failureValue?.isRateLimitError != true {
                    let reason = response.result.failureValue?.firstFailureReason
                    XCTAssertEqual("Could not resolve to a Repository with the name 'xxx/xxx'.", reason)
                }
            } catch let error as URLResponse.InvalidHTTPCode {
                // if it fails, it is probably a rate-limiting error
                XCTAssertEqual(403, error.code, "unexpected error code")
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        do {
            let response = try await hub.request(FairHub.LookupPRNumberQuery(owner: "", name: "", prid: 1))
            XCTAssertNil(response.result.successValue, "request should not have succeeded")
            if response.result.failureValue?.isRateLimitError != true {
                let reason = response.result.failureValue?.firstFailureReason
                XCTAssertEqual("Could not resolve to a Repository with the name '/'.", reason)
            }
        }
    }

    func testFetchRepositoryQuery() async throws {
        let hub = try Self.hub(skipNoAuth: true)
        let response = try await hub.request(FairHub.RepositoryQuery(owner: appfairName, name: baseFairgroundRepoName))
        do {
            let content = try response.get().data
            let org = content.organization
            let repo = org.repository

            XCTAssertEqual("appfair@appfair.org", org.email)
            XCTAssertEqual(appfairName, org.login)

            XCTAssertEqual(0, repo.discussionCategories.totalCount)
            XCTAssertEqual(false, repo.hasIssuesEnabled)
            XCTAssertEqual(false, repo.isFork)
            XCTAssertEqual(false, repo.isEmpty)
            XCTAssertEqual(false, repo.isLocked)
            XCTAssertEqual(false, repo.isMirror)
            XCTAssertEqual(false, repo.isPrivate)
            XCTAssertEqual(false, repo.isArchived)
            XCTAssertEqual(false, repo.isDisabled)
        } catch {
            if response.result.failureValue?.isRateLimitError == true {
                throw XCTSkip("Skipping due to rate limit error")
            } else {
                throw error
            }
        }
    }

    func testCurrentViewerLoginQuery() async throws {
        let hub = try Self.hub(skipNoAuth: true)
        let response = try await hub.request(FairHub.CurrentViewerLoginQuery()).get()
        let login = response.data.viewer.login

        if runningFromCI {
            XCTAssertEqual("github-actions[bot]", login)
        } else {
            XCTAssertEqual("appfairbot", login)
        }
    }

    func testFindPullRequestsQuery() async throws {
        let hub = try Self.hub(skipNoAuth: true)
        do {
            let response = try await hub.request(FairHub.FindPullRequests(owner: appfairName, name: baseFairgroundRepoName, state: .CLOSED, count: 99))
            let content = try response.get().data
            let pr = try XCTUnwrap(content.repository.pullRequests.nodes.first, "no PRs found")
            XCTAssertNotEqual(nil, pr.headRefName, "head ref should have been a branch")
        } catch {
            XCTFail("Error: \(error)")
            throw error
        }
    }

    func testLookupPRNumberQuery() async throws {
        let hub = try Self.hub(skipNoAuth: true)
        let response = try await hub.request(FairHub.LookupPRNumberQuery(owner: appfairName, name: baseFairgroundRepoName, prid: 1)).get().data

        XCTAssertEqual(1, response.repository.pullRequest.number)
        XCTAssertEqual("PR_kwDOGHtQpc4sSrBQ", response.repository.pullRequest.id.rawValue)
    }

    func testFetchCommitQuery() async throws {
        let hub = try Self.hub(skipNoAuth: true)
        let response = try await hub.request(FairHub.GetCommitQuery(owner: "fair-ground", name: "Fair", ref: "93d86ba5884772c8ef189bead1ca131bb11b90f2")).get().data

        guard let sig = response.repository.object.signature else {
            return XCTFail("no signature in response")
        }

        XCTAssertNotNil(response.repository.object.author?.name)
        XCTAssertNotNil(sig.signer.email)
        XCTAssertEqual(.VALID, sig.state)
        XCTAssertEqual(true, sig.isValid)
        XCTAssertEqual(false, sig.wasSignedByGitHub)
    }

//    func testFetchSponsorshipListings() async throws {
//        if runningFromCI || true { // not permitted with default action token: GraphQLError(message: "Resource not accessible by integration", type: Optional("FORBIDDEN"), path: Optional(["repository", "owner", "sponsorsListing"])
//            throw XCTSkip("disabled to reduce API load")
//        }
//
//        let hub = try Self.hub(skipNoAuth: true)
//
//        do {
//            let fundingSources = try await Self.hub(skipNoAuth: true).buildFundingSources(owner: appfairName, baseRepository: baseFairgroundRepoName)
//            let response = try await hub.request(FairHub.GetSponsorsQuery(owner: appfairName, name: baseFairgroundRepoName)).get().data
//            XCTAssertLessThan(20, response.repository.forks.totalCount ?? 0)
//
//            XCTAssertEqual("The App Fair!", response.repository.owner.name)
//
//
//            do {
//                let goal = try XCTUnwrap(fundingSources.first?.goals.first, "missing goal")
//                XCTAssertEqual("TOTAL_SPONSORS_COUNT", goal.kind)
//                XCTAssertEqual("100 sponsors", goal.title)
//                XCTAssertEqual(100, goal.targetValue)
//                //XCTAssertEqual(0, goal.percentComplete)
//                //XCTAssertEqual("Attaining our sponsorship goal will enable us to set out a firm roadmap for version 1.0 of the project, as well as break ground on implementing support for additional platforms and integrations.", goal.description)
//            }
//        } catch {
//            //print("error: \(error)")
//            XCTFail("error: \(error)")
//        }
//    }

    func testCatalogQuery() async throws {
        if runningFromCI {
            throw XCTSkip("disabled to reduce API load")
        }

        let hub = try Self.hub(skipNoAuth: true)

        // tests that paginated queries work and return consistent results
        // Note that this can fail when a catalog update occurs during the sequence of runs
        // e.g.: testCatalogQuery(): failed: caught error: "The operation couldn’t be completed. Something went wrong while executing your query. This may be the result of a timeout, or it could be a GitHub bug. Please include `EBCB:1386:4A828EB:9901AA6:638F6055` when reporting this issue."
        var resultResults: [[FairHub.BaseFork]] = []
        let results = hub.requestBatchedStream(FairHub.CatalogForksQuery(owner: appfairName, name: baseFairgroundRepoName, count: Int.random(in: 8...18)))
        for try await result in results {
            let forks = try result.get().data.repository.forks.nodes
            resultResults.append(forks)
        }

        XCTAssertEqual(resultResults[0].count, resultResults[1].count)
        XCTAssertEqual(resultResults[0].count, resultResults[2].count)
    }

    func testSemanticForkIndex() async throws {
        if runningFromCI {
            throw XCTSkip("disabled to reduce API load")
        }

        let hub = try Self.hub(skipNoAuth: true)
        for try await batch in hub.requestBatchedStream(FairHub.SemanticForksQuery(owner: "appfair", name: "App")) {
            let repo = try batch.get().data.repository
            XCTAssertEqual("appfair/App", repo.nameWithOwner)
            XCTAssertLessThan(20, repo.forks.totalCount ?? 0)
            let forks = repo.forks.nodes
            dbg("fetched forks:", forks.count, forks.map(\.nameWithOwner))
        }
    }

    /// Debugging slow connections to GH API
//    func XXXtestGHAPISpeed() async throws {
//        let token = wip("XXX")
//        var req = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
//        req.addValue("token \(token)", forHTTPHeaderField: "Authorization")
//        req.addValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
//        req.httpMethod = "POST"
//        req.httpBody = #"{"query":"query { viewer { login } }"}  "#.data(using: .utf8)
//
//        // dbg("requesting:", req.cURL(pretty: false))
//        let t1 = DispatchTime.now().uptimeNanoseconds
//        var response: URLResponse?
//        let data = try NSURLConnection.sendSynchronousRequest(req, returning: &response)
//        //let (data, response) = try await URLSession.shared.data(for: req)
//        let t2 = DispatchTime.now().uptimeNanoseconds
//        print("response in:", Double(t2 - t1) / 1_000_000_000, data.count, response)
//    }

//    func testIngestCatalogData() throws {
//        var app = AltCatalogItem(name: "X", bundleIdentifier: "X", downloadURL: URL(string: "about:blank")!)
//        XCTAssertTrue(try app.ingest(json: #"```{ "localizedDescription": "XYZ" }```"#))
//        XCTAssertEqual("XYZ", app.localizedDescription)
//        XCTAssertTrue(try app.ingest(json: #"```json { "localizedDescription": "ABC" }```"#))
//        XCTAssertEqual("ABC", app.localizedDescription)
//        XCTAssertTrue(try app.ingest(json: #"```{ "localizedDescription": "XYZ", "tintColor": "AABBCC" }```"#))
//        XCTAssertEqual("AABBCC", app.tintColor)
//    }
//
//    func testBuildAppCasks() async throws {
//        if runningFromCI {
//            // this quickly exhausts the API limit for the default actions token
//            throw XCTSkip("disabled to reduce API load")
//        }
//
//        let _ = try Self.hub(skipNoAuth: true) // just to throw a skipwhen there is no token
//
//        let api = HomebrewAPI(caskAPIEndpoint: HomebrewAPI.defaultEndpoint)
//        let maxApps: Int? = 123 // wip(3808) // 123 // _000_000
//        let catalog = try await Self.hub(skipNoAuth: true).buildAppCasks(owner: appfairName, catalogName: "Catalog", catalogIdentifier: "net.catalog.id", baseRepository: "appcasks", topicName: "appfair-cask", starrerName: "appfairbot", maxApps: maxApps, mergeCasksURL: api.caskList, caskStatsURL: api.caskStats30, boostFactor: 1000, caskQueryCount: 10, releaseQueryCount: 10, assetQueryCount: 10)
//        let names = Set(catalog.apps.map({ $0.name })) // + " " + ($0.version ?? "") }))
//        let ids = Set(catalog.apps.map({ $0.bundleIdentifier }))
//        dbg("catalog", names.sorted())
//
//        XCTAssertEqual(ids.count, catalog.apps.count, "expected to have unique identifiers")
//
//        if let maxApps = maxApps {
//            XCTAssertEqual(ids.count, maxApps)
//            XCTAssertEqual(catalog.apps.count, maxApps)
//        }
//
////        XCTAssertTrue(names.contains("CotEditor"))
////        XCTAssertTrue(ids.contains("coteditor"))
//
//        XCTAssertGreaterThanOrEqual(names.count, 1)
//
//        //dbg(catalog.prettyJSON)
//        dbg("created app casks catalog count:", ids.count, "size:", try? catalog.prettyJSON.count.localizedByteCount())
//    }
//
//    @discardableResult private func checkApp(_ id: String, catalog: AppCatalog, fundingPlatform: AppFundingPlatform? = nil) -> AltCatalogItem? {
//        guard let app = catalog.apps.first(where: { $0.bundleIdentifier == id }) else {
//            XCTFail("no app \(id) found in app list: \(catalog.apps.map(\.bundleIdentifier))")
//            return nil
//        }
//
//        XCTAssertNotNil(app.subtitle, "missing subtitle in app: \(app.bundleIdentifier ?? "")")
//        XCTAssertNotNil(app.version, "missing version in app: \(app.bundleIdentifier ?? "")")
//        XCTAssertNotNil(app.versionDate, "missing versionDate in app: \(app.bundleIdentifier ?? "")")
//        XCTAssertNotNil(app.sha256, "missing sha256 in app: \(app.bundleIdentifier ?? "")")
//        XCTAssertNotNil(app.stats?.downloadCount, "missing downloadCount in app: \(app.bundleIdentifier ?? "")")
//
//        if let fundingPlatform = fundingPlatform {
//            if let link = app.fundingLinks?.first {
//                XCTAssertEqual(fundingPlatform, link.platform, "unexpected funding platform")
//            } else {
//                //XCTAssertNotNil(app.fundingLinks)
//                //XCTFail("no funding links")
//            }
//        }
//
//        return app
//    }
//
//    func testBuildMacOSCatalog() async throws {
//        if runningFromCI {
//            throw XCTSkip("disabled to reduce API load")
//        }
//
//        let target = ArtifactTarget(artifactType: "macOS.zip", devices: ["mac"])
//        let configuration = try FairHub.ProjectConfiguration()
//        let catalog = try await Self.hub(skipNoAuth: true).buildAppCatalog(title: "The App Fair macOS Catalog", identifier: "net.appfair.catalog", owner: appfairName, baseRepository: baseFairgroundRepoName, fairsealCheck: true, artifactTarget: target, configuration: configuration, requestLimit: nil)
//        let names = Set(catalog.apps.map({ $0.name })) // + " " + ($0.version ?? "") }))
//        dbg("catalog", names.sorted())
//        //dbg("### catalog", wip(catalog.prettyJSON))
//
//        XCTAssertFalse(names.contains(baseFairgroundRepoName))
//        XCTAssertEqual("net.appfair.catalog", catalog.identifier)
//
//        checkApp("app.App-Fair", catalog: catalog)
//        checkApp("app.Cloud-Cuckoo", catalog: catalog, fundingPlatform: .GITHUB)
//        checkApp("app.Tune-Out", catalog: catalog, fundingPlatform: .GITHUB)
//
//        dbg("created macOS catalog count:", names.count, "size:", try? catalog.prettyJSON.count.localizedByteCount())
//    }
//
//    func testBuildIOSAppSourceCatalog() async throws {
//        if runningFromCI {
//            throw XCTSkip("disabled to reduce API load")
//        }
//
//        let target = ArtifactTarget(artifactType: "iOS.ipa", devices: ["iphone", "ipad"])
//        let configuration = try FairHub.ProjectConfiguration()
//        let catalog = try await Self.hub(skipNoAuth: true).buildAppCatalog(title: "The App Fair iOS Catalog", identifier: "net.appfair.catalog", owner: appfairName, baseRepository: baseFairgroundRepoName, fairsealCheck: true, artifactTarget: target, configuration: configuration, requestLimit: nil)
//        let names = Set(catalog.apps.map({ $0.name })) // + " " + ($0.version ?? "") }))
//        dbg("catalog", names.sorted())
//
//        XCTAssertFalse(names.contains(baseFairgroundRepoName))
//        XCTAssertEqual("net.appfair.catalog", catalog.identifier)
//
//        checkApp("app.Cloud-Cuckoo", catalog: catalog, fundingPlatform: .GITHUB)
//        checkApp("app.Tune-Out", catalog: catalog, fundingPlatform: .GITHUB)
//
//        dbg("created iOS catalog count:", names.count, "size:", try? catalog.prettyJSON.count.localizedByteCount())
//        try print(catalog.prettyJSON)
//    }
//
    func testParseDroidCatalog() async throws {
        // let catalogData = try Data(contentsOf: URL(fileURLWithPath: "f-droid-index-v2.json", relativeTo: baseDir))
        let catalogData = try await URLSession.shared.fetch(request: URLRequest(url: FDroidEndpoint.defaultEndpoint)).data
        let catalog = try FDroidIndex(fromJSON: catalogData)
        XCTAssertLessThan(3_900, catalog.packages.count, "F-Droid catalog should have contained packages")

        let complete = try FDroidIndex.codableComplete(data: catalogData)
        //XCTAssertTrue(complete.difference == nil, "catalog serialized differently")
        let _ = complete // FIXME: catalog fidelity
    }

//    func testFetchCatalog() async throws {
//        let url = appfairCatalogURLMacOS
//
//        let (data, response) = try await URLSession.shared.fetch(request: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10.0))
//        XCTAssertEqual(200, (response as? HTTPURLResponse)?.statusCode)
//
//        let catalog = try AppCatalog.parse(jsonData: data)
//        XCTAssertEqual("Fair Apps", catalog.name)
//        dbg("loaded catalog apps:", catalog.apps.count)
//    }

//    func testFairHubAllowDenyPatterns() throws {
//        func check(success successEmail: String? = nil, failure failureEmail: String? = nil, verification reason: String = "valid", allow: [String] = [], deny: [String] = []) throws {
//            var hub = try Self.hub()
//            hub.allowFrom = allow
//            hub.denyFrom = deny
//
//            let mkcommit = { (email: String) in
//                FairHub.CommitInfo(sha: "", node_id: "", url: nil, html_url: nil, comments_url: nil, commit: FairHub.CommitInfo.Commit(author: FairHub.User(name: "Some Name", email: email, date: nil), committer: FairHub.User(name: "Some Name", email: email, date: nil), message: "message", url: .tmpdir, comment_count: nil, verification: FairHub.CommitInfo.Verification(verified: true, reason: reason, signature: "", payload: "")))
//            }
//
//            if let successEmail = successEmail {
//                XCTAssertNoThrow(try hub.authorize(commit: mkcommit(successEmail)))
//            }
//
//            if let failureEmail = failureEmail {
//                XCTAssertThrowsError(try hub.authorize(commit: mkcommit(failureEmail)))
//            }
//        }
//
//        try check(success: "abc@QiZ.edu", allow: [".*@QIZ.EDU"])
//        try check(failure: "abc@AQiZ.edu", allow: [".*@QIZ.EDU"])
//
//        try check(success: "abc@qiz.edu", allow: [".*@QIZ.EDU", ".*@ZIQ.EDU"])
//        try check(success: "abc@ziq.edu", allow: [".*@QIZ.EDU", ".*@ZIQ.EDU"])
//        try check(failure: "abc@ziz.edu", allow: [".*@QIZ.EDU", ".*@ZIQ.EDU"])
//        try check(failure: "abc@qiq.edu", allow: [".*@QIZ.EDU", ".*@ZIQ.EDU"])
//
//        try check(failure: "abc@badbadbad.edu", deny: [".*@badbadbad.edu"])
//        try check(failure: "abc@badbadbad.edu", allow: ["abc@badbadbad.edu"], deny: [".*@badbadbad.edu"]) // deny trumps allow
//        try check(success: "abc@badbad.edu", deny: [".*@badbadbad.edu"])
//
//    }


    /// Verifies the default name validation strategy
    func testNameValidation() throws {
        let validate = { try AppNameValidation.standard.validate(name: $0) }

        XCTAssertNoThrow(try validate("Fair-App"))
        XCTAssertNoThrow(try validate("Awesome-Town"))
        XCTAssertNoThrow(try validate("Fair-App"))
        XCTAssertNoThrow(try validate("Fair-Awesome"))

        XCTAssertNoThrow(try validate("ABCDEFGHIJKL-LKJIHGFEDCBA"))

        XCTAssertThrowsError(try validate("ABCDEFGHIJKLM-LKJIHGFEDCBA"), "word too long")
        XCTAssertThrowsError(try validate("ABCDEFGHIJKL-MLKJIHGFEDCBA"), "word too long")

        XCTAssertNoThrow(try validate("One"), "fewer than two words should be allowed")
        XCTAssertNoThrow(try validate("One-Two-Three"), "more than two words should be allowed")
        XCTAssertNoThrow(try validate("App-App"), "duplicate words should be allowed")

        XCTAssertThrowsError(try validate("Fair App"), "spaces are not allowed")
        XCTAssertThrowsError(try validate("Awesome Town"), "spaces are not allowed")
        XCTAssertThrowsError(try validate("Fair App"), "spaces are not allowed")
        XCTAssertThrowsError(try validate("Fair Awesome"), "spaces are not allowed")

        XCTAssertThrowsError(try validate("Fair-App2"), "digits in names should be not allowed")
        XCTAssertThrowsError(try validate("Fair-1App"), "digits in names should be not allowed")
        XCTAssertThrowsError(try validate("Lucky-App4U"), "digits in names should be not allowed")
    }


    func testFairSealSigning() throws {
        let key = "OTFBRTExNEUtQzIxNi00MzQ0LTkyMjktNjM5QTI1QjZGNkRF" // echo -n "91AE114E-C216-4344-9229-639A25B6F6DE" | base64
        XCTAssertEqual("91AE114E-C216-4344-9229-639A25B6F6DE", Data(base64Encoded: key)?.utf8String)

        var seal = FairSeal(metadata: nil)
        let sig = { try seal.sign(key: XCTUnwrap(Data(base64Encoded: key))).base64EncodedString() }

        seal.generatorVersion = nil // clear the genrator version which is set on init
        XCTAssertEqual("{}", try seal.debugJSON)

        XCTAssertEqual("OW2qU590oQOhzk9wUdRSt+BaSIBiQkY+6C8dxdv3t5Q=", try sig(), "signature of empty JSON should be consistent")

        seal.permissions = []
        XCTAssertEqual("bJwxJc1P3ebSID2jztUZ/6BKnmrl6eE4uU8wGbsS5dw=", try sig(), "signature on empty array should differ from null")

//        seal.appSource = AltCatalogItem(name: "App Name", bundleIdentifier: "app.appName", downloadURL: URL(string: "about:blank")!)
//        XCTAssertEqual("+arE45SfHJamOXtDvrT3lwB4tcSOogebqbJl2X0/d6Y=", try sig(), "seal with catalog information should be consistent")

    }

}
#endif // os(Windows)
#endif // DEBUG for @testable

