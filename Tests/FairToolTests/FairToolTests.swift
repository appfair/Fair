import XCTest
import Foundation
import FairCore
import FairExpo
import fairtool

final class FairToolTests: XCTestCase {
    #if os(macOS)
    func testToolVersion() async throws {
        let result = try await invokeTool(["version"])
        XCTAssertEqual(result.stderr.utf8String, "fairtool \(Bundle.fairCoreVersion?.versionString ?? "")\n")
    }

    /// Verifies that the "fairtool app info" command will output valid JSON that correctly identifies the app.
    func testToolAppInfo() async throws {
        let infoJSON = try await invokeTool(["artifact", "info", "/System/Applications/TextEdit.app"]).stdout
        let json = try [ArtifactCommand.InfoCommand.Output](fromJSON: infoJSON)
        XCTAssertEqual("com.apple.TextEdit", json.first?.info.object?["CFBundleIdentifier"]?.string)
    }

    @discardableResult func invokeTool(toolPath: String = "fairtool", _ args: [String], expectSuccess: Int32? = 0) async throws -> CommandResult {
        try await Process.exec(cmd: buildOutputFolder().appendingPathComponent(toolPath).path, args: args).expect(exitCode: expectSuccess)
    }
    #endif

    /// Returns the path to the built products directory.
    func buildOutputFolder() -> URL {
        #if os(macOS) // check for Xcode test bundles
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        #endif

        // on linux, this should be the folder above the tool
        return Bundle.main.bundleURL
    }
}
