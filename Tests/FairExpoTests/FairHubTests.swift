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
        return try FairHub(hostOrg: "github.com/" + appfairName, authToken: authToken, fairsealIssuer: "appfairbot", fairsealKey: nil, requestRetryCount: 5)
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
        let response = try await hub.request(FairHub.GetCommitQuery(owner: "appfair", name: "Fair", ref: "93d86ba5884772c8ef189bead1ca131bb11b90f2")).get().data

        guard let sig = response.repository.object.signature else {
            return XCTFail("no signature in response")
        }

        XCTAssertNotNil(response.repository.object.author?.name)
        XCTAssertNotNil(sig.signer.email)
        XCTAssertEqual(.VALID, sig.state)
        XCTAssertEqual(true, sig.isValid)
        XCTAssertEqual(false, sig.wasSignedByGitHub)
    }

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

    func testParseDroidCatalog() async throws {
        // let catalogData = try Data(contentsOf: URL(fileURLWithPath: "f-droid-index-v2.json", relativeTo: baseDir))
        let catalogData = try await URLSession.shared.fetch(request: URLRequest(url: FDroidEndpoint.defaultEndpoint)).data
        let catalog = try FDroidIndex(fromJSON: catalogData)
        XCTAssertLessThan(3_900, catalog.packages?.count ?? -1, "F-Droid catalog should have contained packages")

        let complete = try FDroidIndex.codableComplete(data: catalogData)
        //XCTAssertTrue(complete.difference == nil, "catalog serialized differently")
        let _ = complete // FIXME: catalog fidelity
    }

    func testParseDroidCatalogs() async throws {
        /// Parses the FDroidIndex at the given test resource path, ensuring that it is codable complete
        func parseResource(_ name: String, roundtrip: Bool) throws -> FDroidIndex {
            let data = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil)))
            let decoder = JSONDecoder()

            // bug in round-trip codableComplete checking where large numbers are serialized differently depending whether they are an Int or Double
            // "size":9223372036854775807
            // "size":9.223372036854776e+18
            /*
            let (index, diff) = try FDroidIndex.codableComplete(data: data)
            if roundtrip {
                //let json = decoder.decode(JSON.self, from: data)
                //print("raw JSON: \(try json.prettyJSON)")
                //print("cat JSON: \(try index.prettyJSON)")
                XCTAssertNil(diff, "index at \(name) has serialization differences")
            }
             */

            let index = try decoder.decode(FDroidIndex.self, from: data)
            if roundtrip {
                var rawJSON = try decoder.decode(JSON.self, from: data)
                rawJSON["unknownKey"] = nil // trick with fdroid-index-max-v2.json ("should get ignored")
                let rawPretty = try rawJSON.prettyJSON

                let rtJSON = try decoder.decode(JSON.self, from: try JSONEncoder().encode(index))
                let rtPretty = try rtJSON.prettyJSON
                XCTAssertTrue(rawJSON == rtJSON, "mismatch between raw parse: \(rawPretty) and round-tripped: \(rtPretty)")
            }

            return index
        }

        let empty = try parseResource("fdroid-index-empty-v2.json", roundtrip: true)
        XCTAssertEqual(nil, empty.packages?.count)

        let min = try parseResource("fdroid-index-min-v2.json", roundtrip: true)
        XCTAssertEqual(1, min.packages?.count)

        let mid = try parseResource("fdroid-index-mid-v2.json", roundtrip: true)
        XCTAssertEqual(2, mid.packages?.count)

        let max = try parseResource("fdroid-index-max-v2.json", roundtrip: true)
        XCTAssertEqual(3, max.packages?.count)
    }

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

//        seal.appSource = AltCatalogAppItem(name: "App Name", bundleIdentifier: "app.appName", downloadURL: URL(string: "about:blank")!)
//        XCTAssertEqual("+arE45SfHJamOXtDvrT3lwB4tcSOogebqbJl2X0/d6Y=", try sig(), "seal with catalog information should be consistent")

    }

}
#endif // os(Windows)
#endif // DEBUG for @testable

