import Swift
import XCTest
import FairCore
import FairExpo

public class FairExpoTests : XCTestCase {

    func testAppCatalogIndex() async throws {
        /// https://appfair.net/appfair-apps.json
        let (data, _) = try await URLSession.shared.fetch(request: URLRequest(url: AppCatalogIndex.appfairCatalogURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData))
        let index = try JSONDecoder().decode(AppCatalogIndex.self, from: data)
        XCTAssertGreaterThan(index.apps.count, 0)

        XCTAssertEqual("The App Fair Project", index.catalogs.fdroid?.name["en-US"])
        XCTAssertEqual("The App Fair Project", index.catalogs.altstore?.name)

        XCTAssertEqual("https://api.appfair.net/fdroid/repo/", index.catalogs.fdroid?.address)
        XCTAssertEqual("https://appfair.org", index.catalogs.altstore?.website)

        XCTAssertEqual("/icons/appfair-icon.png", index.catalogs.fdroid?.icon["en-US"]?.name)
        XCTAssertEqual("https://appfair.net/appfair-icon.png", index.catalogs.altstore?.iconURL)
    }

    func testParseCatalogs() throws {
        // list obtained from https://cdn.altstore.io/file/altstore/altstore/marketplace-sources.json
        let dir = ProcessInfo.processInfo.environment["FAIR_EXPO_TESTS_MARKETPLACE_SOURCES_DIR"] ?? "/opt/src/github/altstore/sources/marketplace-sources"

        if !FileManager.default.fileExists(atPath: dir) {
            throw XCTSkip("No local marketplace .json files for testing")
        }

        let allFiles = try FileManager.default.enumeratedURLs(of: URL(fileURLWithPath: dir))

        let paths = allFiles
            .filter({ $0.pathExtension == "json" })
            .filter({ $0.lastPathComponent != "marketplace-sources.json" }) // the marketplace index

        if paths.isEmpty {
            throw XCTSkip("No local marketplace .json files for testing")
        }

        for path in paths {
            print("parsing source at path: \(path.path)")
            do {
                let catalog = try AltCatalog(fromJSON: Data(contentsOf: path))
                print("successfully parsed: \(path.path): \(catalog.name ?? "Unnamed") with \(catalog.apps.count) apps")
            } catch {
                XCTFail("error parsing \(path.path): \(error)")
            }
        }
    }

    func testEnvFile() throws {
        do {
            let env = try EnvFile(data: """
            """.utf8Data)
            XCTAssertEqual(nil, env["x"])
        }

        do {
            let env = try EnvFile(data: """
            x = y
            """.utf8Data)
            XCTAssertEqual("y", env["x"])
        }

        do {
            var env = try EnvFile(data: """
            // comment
            ABC = 123
            """.utf8Data)
            XCTAssertEqual("123", env["ABC"])
            XCTAssertEqual("""
            // comment
            ABC = 123
            """, env.contents)

            env["ABC"] = "qrs"
            XCTAssertEqual("""
            // comment
            ABC = qrs
            """, env.contents)

            env["ABCD"] = "XYZ"
            XCTAssertEqual("""
            // comment
            ABC = qrs
            ABCD = XYZ
            """, env.contents)

            env["ABC"] = nil
            XCTAssertEqual("""
            // comment
            ABCD = XYZ
            """, env.contents)

            env["ABCD"] = nil
            XCTAssertEqual("""
            // comment
            """, env.contents)
        }
    }

}
