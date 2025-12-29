// Copyright (c) 2022 - 2026 The App Fair Project <info@appfair.org>
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
import FairCore
import FairExpo
import ArgumentParser
@testable import fairtool

/// Tests different command options for the FairToolCommand.
///
/// These tests perform tool operations in the same process, which is different from the
/// `FairToolTests.swift`, which performs test by invoking the actual tool executable and parsing the output.
final class FairCommandTests: XCTestCase {
    typealias ToolMessage = (kind: MessageKind, items: [Any?])

    private func runToolOutputSingle<C: FairParsableCommand>(_ commands: CommandConfiguration..., cmd: C.Type, args: [String]) async throws -> (output: C.Output, messages: [(MessageKind, [Any?])]) where C.Output : Decodable {
        let result = try await runTool(commands: commands + [cmd.configuration], args: args)
        let output = result.output.joined()
        //dbg("output:", output)
        return (try C.Output(fromJSON: output.utf8Data, dateDecodingStrategy: .iso8601), result.messages)
    }

    /// Invokes the `FairTool` with a command that expects a JSON-serialized output for a `FairParsableCommand`
    /// The command will be invoked and the result will be deserialized into the expected structure.
    private func runToolOutputStream<C: FairStructuredCommand>(_ commands: CommandConfiguration..., cmd: C.Type, args: [String]) async throws -> (output: [C.Output], messages: [(MessageKind, [Any?])]) where C.Output : Decodable {
        let result = try await runTool(commands: commands + [cmd.configuration], args: args)
        let output = result.output.joined()
        //dbg("output:", output)
        return (try [C.Output](fromJSON: output.utf8Data, dateDecodingStrategy: .iso8601), result.messages)
    }

    /// Invokes the `FairTool` in-process using the specified arguments
    private func runTool(_ op: CommandConfiguration..., args: [String] = []) async throws -> (output: [String], messages: [ToolMessage]) {
        try await runTool(commands: op, args: args)
    }

    private func runTool(commands: [CommandConfiguration], args: [String] = []) async throws -> (output: [String], messages: [ToolMessage]) {
        let arguments = commands.compactMap(\.commandName) + args

        let command = try FairToolCommand.parseAsRoot(arguments)
        guard var cmd = command as? FairMsgCommand else {
            struct NoCommandError : Error { }
            throw NoCommandError()
        }

        // capture the output of the tool run
        let buffer = MessageBuffer()
        cmd.msgOptions.messages = buffer
        try await cmd.run()
        return (buffer.output, buffer.messages)
    }

    func extract(kind: MessageKind = .info, _ messages: [ToolMessage]) -> [String] {
        messages
            .filter({ $0.kind == kind })
            .map({
                $0.items.map({ $0.flatMap(String.init(describing:)) ?? "nil" }).joined(separator: " ")
            })
    }

    /// Returns the URL of the app to download with the standard fairground layout.
    /// - Parameters:
    ///   - appName: the name of the app
    ///   - ios: whether this is iOS or macOS
    private static func appDownloadURL(for appName: String, version: String?, platform: AppPlatform) throws -> URL {
        func dlpath() throws -> String {
            switch platform {
            case .iOS: return appName + "-" + "iOS.ipa"
            case .macOS: return appName + "-" + "macOS.zip"
            default: throw AppError("unknown platform: \(platform)")
            }
        }
        if let version = version {
            guard let remoteURL = URL(string: "https://github.com/\(appName)/App/releases/download/\(version)/" + (try dlpath())) else {
                throw AppError("cannot create url")
            }
            return remoteURL
        } else {
            guard let remoteURL = URL(string: "https://github.com/\(appName)/App/releases/latest/download/" + (try dlpath())) else {
                throw AppError("cannot create url")
            }
            return remoteURL
        }
    }

    /// Downloads the most recent version of the given App Fair app.
    /// - Parameters:
    ///   - appName: the name of the app
    ///   - ios: whether this is iOS or macOS
    private static func downloadApp(name appName: String, version: String?, platform: AppPlatform) async throws -> URL {
        let remoteURL = try appDownloadURL(for: appName, version: version, platform: platform)
        let (localURL, response) = try await prf("download: \(remoteURL.absoluteURL)") {
            try await URLSession.shared.downloadFile(for: URLRequest(url: remoteURL, cachePolicy: .returnCacheDataElseLoad))
        }
        try response.validateHTTPCode()
        return localURL
    }

    func testVersionCommand() async throws {
        let result = try await runTool(FairToolCommand.VersionCommand.configuration)
        let output = extract(result.messages).first
        XCTAssertTrue(output?.hasPrefix("fairtool") == true, output ?? "")
    }

    func testSourceCreateAPI() async throws {
        let url = try Self.appDownloadURL(for: "Cloud-Cuckoo", version: nil, platform: .iOS)
        let _ = url
//        let catalog = try await AltCatalogAPI.shared.catalogApp(url: url)
//        XCTAssertEqual("Cloud Cuckoo", catalog.name)
//        XCTAssertEqual("A whimsical game of excitement and delight", catalog.subtitle)
        //XCTAssertEqual(nil, catalog.fundingLinks?.first?.platform) // no longer present in AppSource
    }

    func fetchApp(named name: String, unzip: Bool = true) async throws -> URL {
        let localURL = try await Self.downloadApp(name: name, version: nil, platform: .iOS)
        if !unzip {
            return localURL
        }

        let downloadName = localURL.deletingPathExtension().lastPathComponent

        let targetFolder = URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: .tmpdir)
        try FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true)

        let downloadAppURL = URL(fileURLWithPath: downloadName, isDirectory: true, relativeTo: targetFolder)
        if FileManager.default.fileExists(atPath: downloadAppURL.path) == true {
            try FileManager.default.removeItem(at: downloadAppURL)
        }

        try FileManager.default.unzipItem(at: localURL, to: downloadAppURL, skipCRC32: true)
        dbg("unzipped to:", downloadAppURL.path)

        return downloadAppURL
    }

    #if os(macOS)
//    func testConvertIPA() async throws {
//        let downloadAppURL = try await fetchApp(named: "Cloud-Cuckoo", unzip: true)
//        let bundle = try await AppBundle(folderAt: downloadAppURL)
//
//        try bundle.validatePaths()
//
//        let convertedURL = try await bundle.setCatalystPlatform(resign: "-")
//        dbg("converted platform at:", convertedURL.path)
//
//        //try await Process.exec(cmd: "/usr/bin/open", convertedURL.path).expect()
//        //try await Process.spctlAssess(appURL: convertedURL).expect()
//        try await Process.codesignVerify(appURL: convertedURL).expect()
//    }
//
//    func testDisassembly() async throws {
//        let downloadAppURL = try await fetchApp(named: "Cloud-Cuckoo", unzip: true)
//        let lib = URL(fileURLWithPath: "Payload/Cloud Cuckoo.app/Frameworks/App.framework/App", isDirectory: false, relativeTo: downloadAppURL)
//        let assembly = try await Process.otool(url: lib, params: ["-tVX"]).expect().stdout
//        XCTAssertNotEqual(0, assembly.count)
//    }
    #endif

    /// Runs "fairtool app info <url>" on a remote .ipa file, which it will download and analyze.
    func testArtifactInfoCommandiOS() async throws {
        let (result, _) = try await runToolOutputStream(ArtifactCommand.configuration, cmd: ArtifactCommand.InfoCommand.self, args: [Self.appDownloadURL(for: "Cloud-Cuckoo", version: nil, platform: .iOS).absoluteString])

        XCTAssertEqual("app.Cloud-Cuckoo", result.first?.info.object?["CFBundleIdentifier"]?.string)
        XCTAssertEqual(0, result.first?.entitlements?.count, "no entitlements expected in this ios app")
    }

    /// Runs "fairtool app info <url>" on a remote .app .zip file, which it will download and analyze.
    func testArtifactInfoCommandMacOS() async throws {
        let (result, _) = try await runToolOutputStream(ArtifactCommand.configuration, cmd: ArtifactCommand.InfoCommand.self, args: [Self.appDownloadURL(for: "Cloud-Cuckoo", version: nil, platform: .macOS).absoluteString])

        XCTAssertEqual("app.Cloud-Cuckoo", result.first?.info.object?["CFBundleIdentifier"]?.string)
        XCTAssertEqual(2, result.first?.entitlements?.count, "expected two entitlements in a fat binary")
        XCTAssertEqual(true, result.first?.entitlements?.first?.object?["com.apple.security.app-sandbox"])
        XCTAssertEqual(false, result.first?.entitlements?.first?.object?["com.apple.security.network.client"])
    }

    func testArtifactInfoCommandMacOSStream() async throws {
        var cmd = try ArtifactCommand.InfoCommand.parseAsRoot(["info"]) as! ArtifactCommand.InfoCommand

        cmd.apps = []
        cmd.apps += [try Self.appDownloadURL(for: "Cloud-Cuckoo", version: nil, platform: .iOS).absoluteString]
        cmd.apps += [try Self.appDownloadURL(for: "Cloud-Cuckoo", version: nil, platform: .macOS).absoluteString]

        var count = 0

        for try await result in cmd.executeCommand() {
            //XCTAssertEqual("app.Cloud-Cuckoo", result.info.obj?["CFBundleIdentifier"]?.str)
            XCTAssertNotNil(result.info.object?["CFBundleIdentifier"]?.string)

            if cmd.apps.first?.hasSuffix("macOS.zip") == true {
                XCTAssertEqual(2, result.entitlements?.count, "expected two entitlements in a fat binary")
                XCTAssertEqual(true, result.entitlements?.first?.object?["com.apple.security.app-sandbox"])
                XCTAssertEqual(false, result.entitlements?.first?.object?["com.apple.security.network.client"])
            }
            //return

            count += 1
        }

        XCTAssertGreaterThan(count, 0, "expected at least one result")
    }

    func testSourceMergeAltStoreCommand() async throws {
        let args: [String] = ["--app-index", "https://appfair.net/appfair-apps.json"]

        let (mergedCatalog, messages) = try await runToolOutputSingle(SourceCommand.configuration, SourceCommand.MergeCommand.configuration, cmd: SourceCommand.MergeAltStoreCatalogCommand.self, args: Array(args))

        _ = messages

        XCTAssertEqual("The App Fair Project", mergedCatalog.name)
    }

    func testAppStoreConnectListAppsCommand() async throws {
        if !FileManager.default.isReadableFile(atPath: fairtoolDefaultKeystorePath) {
            throw XCTSkip("Skipping test due to missing keystore")
        }
        let args: [String] = [] // ["--keystore", keystore]
        let (output, messages) = try await runToolOutputSingle(AppStoreConnectCommand.configuration, AppStoreConnectCommand.AppCommand.configuration, cmd: AppStoreConnectCommand.ListAppsCommand.self, args: Array(args))
        _ = messages

        let tuneOut = try XCTUnwrap(output.data?.first(where: { $0.attributes.name == "Tune-Out" }))
        XCTAssertEqual("Tune-Out", tuneOut.attributes.name)
        XCTAssertEqual("org.appfair.app.Tune-Out", tuneOut.attributes.bundleId)
        XCTAssertEqual("3432232323", tuneOut.attributes.sku)
    }

    func testSourceCreateAltStoreCommand() async throws {
        let tuneOutVersion = "1.0.7"
        let netSkipVersion = "1.4.5"
        let skipNotesVersion = "0.8.7"

        let args = ["Tune-Out/\(tuneOutVersion)", "Net-Skip/\(netSkipVersion)", "Skip-Notes/\(skipNotesVersion)"]

        let (output, messages) = try await runToolOutputSingle(SourceCommand.configuration, SourceCommand.CreateCommand.configuration, cmd: SourceCommand.CreateAltStoreCatalogCommand.self, args: Array(args))

        _ = messages
        //dbg("output:", output)

        XCTAssertEqual(3, output.apps.count)

        let tuneOut = try XCTUnwrap(output.apps.dropFirst(0).first, "catalog should have contained at least one app")
        XCTAssertEqual("Tune-Out", tuneOut.name)
        XCTAssertEqual("org.appfair.app.Tune-Out", tuneOut.bundleIdentifier)
        XCTAssertEqual("other", tuneOut.category) // FIXME
        XCTAssertEqual("1639901758", tuneOut.marketplaceID)
        XCTAssertEqual("Stream internet radio", tuneOut.subtitle)
        XCTAssertEqual(1, tuneOut.versions?.count)
        XCTAssertEqual(tuneOutVersion, tuneOut.versions?.first?.version)

        let netSkip = try XCTUnwrap(output.apps.dropFirst(1).first, "catalog should have contained a second app")
        XCTAssertEqual("Net Skip", netSkip.name)
        XCTAssertEqual("org.appfair.app.Net-Skip", netSkip.bundleIdentifier)
        XCTAssertEqual("other", netSkip.category) // FIXME
        XCTAssertEqual("1640618584", netSkip.marketplaceID)
        XCTAssertEqual("A humane web browser", netSkip.subtitle)
        XCTAssertEqual(1, netSkip.versions?.count)
        XCTAssertEqual(netSkipVersion, netSkip.versions?.first?.version)

        let skipNotes = try XCTUnwrap(output.apps.dropFirst(2).first, "catalog should have contained a third app")
        XCTAssertEqual("Skip Notes", skipNotes.name)
        XCTAssertEqual("org.appfair.app.SkipNotes", skipNotes.bundleIdentifier)
        XCTAssertEqual("other", skipNotes.category) // FIXME
        XCTAssertEqual("6740916318", skipNotes.marketplaceID)
        XCTAssertEqual("Simple and secure notes", skipNotes.subtitle)
        XCTAssertEqual(1, skipNotes.versions?.count)
        XCTAssertEqual(skipNotesVersion, skipNotes.versions?.first?.version)
    }

    func testSourceCreateFDroidCommand() async throws {
        let netSkipVersion = "1.4.5"
        let args = ["Tune-Out", "Net-Skip/\(netSkipVersion)", "Skip-Notes"]

        let (output, messages) = try await runToolOutputSingle(SourceCommand.configuration, SourceCommand.CreateCommand.configuration, cmd: SourceCommand.CreateFDroidCatalogCommand.self, args: Array(args))

        _ = messages

        XCTAssertEqual(3, output.packages?.count)

        let tuneOut = try XCTUnwrap(output.packages?["org.appfair.app.Tune_Out"], "missing app")
        XCTAssertEqual("TuneOut", tuneOut.metadata.name?["en-US"])

        let netSkip = try XCTUnwrap(output.packages?["org.appfair.app.Net_Skip"], "missing app")
        let _ = netSkip
        //XCTAssertEqual("Skip Showcase", netSkip.metadata.name?["en-US"]) // oops

        let skipNotes = try XCTUnwrap(output.packages?["org.appfair.app.SkipNotes"], "missing app")
        XCTAssertEqual("Skip Notes", skipNotes.metadata.name?["en-US"])

        //let catalog: AltCatalog = try SourceCommand.CreateCommand.Output(fromJSON: output.utf8Data, dateDecodingStrategy: .iso8601)
        //dbg("catalog:", try? catalog.toJSON(outputFormatting: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes], dateEncodingStrategy: .iso8601).utf8String)

        // TODO: validate against fdroidserver's `fdroid update` output for the app:
        let expected = try JSONDecoder().decode(FDroidIndex.self, from: """
        {
          "repo": {
            "name": {
              "en-US": "The App Fair Project"
            },
            "description": {
              "en-US": "This is a repository of apps to be used with F-Droid. Applications in this repository are either official binaries built by the original application developers, or are binaries built from source by the admin of f-droid.org using the tools on https://gitlab.com/fdroid."
            },
            "icon": {
              "en-US": {
                "name": "/icons/icon.png",
                "sha256": "7b42abdb1ec052f24f6957b73789355bdf5d1ba9d9c432d636a515838aa16989",
                "size": 681
              }
            },
            "address": "https://api.appfair.net/fdroid/repo",
            "timestamp": 1760571293000,
            "categories": {
              "server": {
                "name": {
                  "en-US": "server"
                }
              }
            }
          },
          "packages": {
            "org.appfair.app.Tune_Out": {
              "metadata": {
                "added": 1760571293000,
                "categories": [
                  "server"
                ],
                "lastUpdated": 1760571293000,
                "name": {
                  "en-US": "TuneOut"
                },
                "preferredSigner": "082e7b25ea1120bfb1b5e72a15dd359a5300b7b7d44297271ee0c870285bff38"
              },
              "versions": {
                "dcf83b18561745baecb8013f542d883dab7d1d1b3cf391173603add9c78df809": {
                  "added": 1760571293000,
                  "file": {
                    "name": "https://github.com/appfair/Tune-Out/releases/download/1.0.5/TuneOut-release.apk",
                    "sha256": "dcf83b18561745baecb8013f542d883dab7d1d1b3cf391173603add9c78df809",
                    "size": 22206307
                  },
                  "manifest": {
                    "nativecode": [
                      "arm64-v8a",
                      "armeabi",
                      "armeabi-v7a",
                      "mips",
                      "mips64",
                      "x86",
                      "x86_64"
                    ],
                    "versionName": "1.0.5",
                    "versionCode": 17,
                    "usesSdk": {
                      "minSdkVersion": 28,
                      "targetSdkVersion": 36
                    },
                    "signer": {
                      "sha256": [
                        "082e7b25ea1120bfb1b5e72a15dd359a5300b7b7d44297271ee0c870285bff38"
                      ]
                    },
                    "usesPermission": [
                      {
                        "name": "android.permission.INTERNET"
                      },
                      {
                        "name": "android.permission.FOREGROUND_SERVICE"
                      },
                      {
                        "name": "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"
                      },
                      {
                        "name": "android.permission.POST_NOTIFICATIONS"
                      },
                      {
                        "name": "android.permission.WAKE_LOCK"
                      },
                      {
                        "name": "android.permission.ACCESS_NETWORK_STATE"
                      },
                      {
                        "name": "org.appfair.app.Tune_Out.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"
                      }
                    ]
                  }
                }
              }
            }
          }
        }
        """.data(using: .utf8)!)

        XCTAssertEqual(1, expected.packages?.count)
    }

    func testValidateCommand() async throws {
        do {
            let result = try await runTool(FairCommand.configuration, FairCommand.ValidateCommand.configuration)
            // TODO:
            // let result = try await runToolOutputStream(FairCommand.self, cmd: FairCommand.ValidateCommand.self, "--hub", "appfair/App")
            XCTAssertFalse(result.messages.isEmpty)
        } catch { // let error as CommandError {
            // the hub key is required
            // XCTAssertEqual("\(error.parserError)", #"noValue(forKey: FairCore.InputKey(rawValue: "hub"))"#)
            // XCTAssertEqual(error.localizedDescription, #"Bad argument: "org""#)
        }
    }

    #if os(macOS)
//    func testIconCommand() async throws {
//        do {
//            let result = try await runTool(type: FairCommand.configuration.commandName, op: FairCommand.IconCommand.configuration)
//            XCTAssertFalse(result.messages.isEmpty)
//        } catch {
//            XCTAssertEqual("\(error)", #"CommandError(commandStack: [fairtool.FairToolCommand, fairtool.FairCommand, fairtool.FairCommand.IconCommand], parserError: ArgumentParser.ParserError.noValue(forKey: orgOptions.org))"#)
//        }
//    }

    /// Runs "fairtool app info <url>" on a homebrew cask .app .zip file
    func testArtifactInfoCommandStocks() async throws {
        let stocksPath = "/System/Applications/Stocks.app"
//        if !FileManager.default.itemExists(at: URL(fileURLWithPath: stocksPath)) {
//            throw XCTSkip("no stocks app") // e.g., Linux
//        }
        let (result, _) = try await runToolOutputStream(ArtifactCommand.configuration, cmd: ArtifactCommand.InfoCommand.self, args: [stocksPath])

        XCTAssertEqual("com.apple.stocks", result.first?.info.object?["CFBundleIdentifier"]?.string)
        XCTAssertEqual(2, result.first?.entitlements?.count, "expected two entitlements in a fat binary")
        XCTAssertEqual(true, result.first?.entitlements?.first?.object?["com.apple.security.app-sandbox"])
        XCTAssertEqual(true, result.first?.entitlements?.first?.object?["com.apple.security.network.client"])
    }

    #endif

    func testMergeCommand() async throws {
        do {
            let result = try await runTool(FairCommand.configuration, FairCommand.MergeCommand.configuration, args: ["--verbose", "--hub", "github.com/appfair", "--org", "Cloud-Cuckoo", "--token", "XXX", "--base", "XXX", "--project", "XXX", "--fair-properties", "Info.plist"])
            XCTAssertFalse(result.messages.isEmpty)
        } catch {
            //XCTAssertEqual("\(error)", #"CommandError(commandStack: [FairExpo.FairToolCommand, FairExpo.FairCommand, FairExpo.FairCommand.MergeCommand], parserError: FairCore.ParserError.noValue(forKey: FairCore.InputKey(rawValue: "org")))"#)
            XCTAssertTrue("\(error)".contains("file"), "unexpected error: \(error)")
        }
    }

    func testCatalogCommand() async throws {
        do {
            let result = try await runTool(FairCommand.configuration, FairCommand.CatalogCommand.configuration)
            XCTAssertFalse(result.messages.isEmpty)
        } catch {
            XCTAssertEqual("\(error)", #"CommandError(commandStack: [fairtool.FairToolCommand, fairtool.FairCommand, fairtool.FairCommand.CatalogCommand], parserError: ArgumentParser.ParserError.noValue(forKey: hubOptions.hub))"#)
        }
    }

    func testAppcasksCommand() async throws {
        do {
            let result = try await runTool(BrewCommand.configuration, BrewCommand.AppCasksCommand.configuration)
            XCTAssertFalse(result.messages.isEmpty)
        } catch {
            XCTAssertEqual("\(error)", #"CommandError(commandStack: [fairtool.FairToolCommand, fairtool.BrewCommand, fairtool.BrewCommand.AppCasksCommand], parserError: ArgumentParser.ParserError.noValue(forKey: hubOptions.hub))"#)
        }
    }

    func testFetchCaskInfo() async throws {
        let (casks, _) = try await HomebrewAPI(caskAPIEndpoint: HomebrewAPI.defaultEndpoint).fetchCasks()
        XCTAssertGreaterThan(casks.count, 4_000, "too few casks") // 4_021 at last count
    }

    func testFetchCaskStats() async throws {
        let stats = try await HomebrewAPI(caskAPIEndpoint: HomebrewAPI.defaultEndpoint).fetchAppStats()
        XCTAssertGreaterThan(stats.total_count, 1000, "too few casks") // 13936 at last count
    }

    /// Ensures that the catalog verifies against various public sources
    func testExternalCatalogVerification() async throws {
        /// downloads the catalog at the given URL and ensures that it parses correctly
        let fetch = { url in try AltCatalog.parse(jsonData: await URLSession.shared.fetch(request: URLRequest(url: URL(string: dump(url, name: "downloading catalog from: \(url)"))!)).data) }

        do {
            let cat = try await fetch("https://apps.altstore.io")
            XCTAssertNotEqual(0, cat.apps.count)
        }

        do {
            let cat = try await fetch("https://alt.getutm.app")
            XCTAssertNotEqual(0, cat.apps.count)
        }

        do {
            let cat = try await fetch("https://flyinghead.github.io/flycast-builds/altstore.json")
            XCTAssertNotEqual(0, cat.apps.count)
        }

        do {
            let cat = try await fetch("https://altstore.oatmealdome.me/")
            XCTAssertNotEqual(0, cat.apps.count)
        }
    }

    func testSignableJSON() throws {
        let key = "another test key"

        struct Demo : Encodable {
            let name: String
            let date: Date
        }

        let instance = Demo(name: "Abc", date: Date(timeIntervalSinceReferenceDate: 4321))

        struct SignableJSON<T: Encodable> : SigningContainer {
            let rawValue: T

            init(_ rawValue: T) {
                self.rawValue = rawValue
            }

            func encode(to encoder: Encoder) throws {
                try rawValue.encode(to: encoder)
            }
        }

        let signable = SignableJSON(instance)
        let sig = try signable.sign(key: key.utf8Data)
        XCTAssertEqual("lahFynjU/GPoeQA2xwqeiNE3i3nLVVvSvNhY0C0Ok1Q=", sig.base64EncodedString())

        do {
            // re-create the SignableJSON as a top-level type;
            // the signatures should match
            struct DemoSignable : Encodable, JSONSignable {
                let name: String
                let date: Date
                var signatureData: Data?
            }

            // fTr5rZNutkg8fmpQx0nWwiuA0UczFb3yfRxpducDw3Y=
            let instance2 = DemoSignable(name: instance.name, date: instance.date)
            let sig2 = try instance2.sign(key: key.utf8Data)
            XCTAssertEqual(sig.base64EncodedString(), sig2.base64EncodedString())
        }

    }

    func testLocalizableStrings() throws {
        do {
            let strings = """
            "A" = "B";
            """
            let file = try LocalizedStringsFile(fileContents: strings)
            XCTAssertEqual(["A"], file.keys)
        }

        do {
            let strings = """
            // comment 1
            "A" = "B";
            /* comment 2 */
            "C" = "D";
            """
            var file = try LocalizedStringsFile(fileContents: strings)
            XCTAssertEqual(["A", "C"], file.keys)
            try file.update(strings: .init(rawValue: ["A": "X"]))
            XCTAssertEqual(["A"], file.keys)

            XCTAssertEqual(file.fileContents, """
            // comment 1
            "A" = "X";
            /* comment 2 */
            "C" = "D";
            """)
        }
    }

    func testFairMetadataCommand() async throws {

        @discardableResult func check(_ yaml: String, customize: (inout FairCommand.MetadataCommand) -> () = { _ in }) async throws -> (folder: URL, metadata: [FastlaneAppStoreMetadata]) {
            let folder = URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: URL.tmpdir)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let metadata = URL(fileURLWithPath: "metadata.yml", isDirectory: false, relativeTo: folder)

            try yaml.write(to: metadata, atomically: true, encoding: .utf8)

            var cmd = try FairCommand.MetadataCommand.parseAsRoot(["metadata"]) as! FairCommand.MetadataCommand

            // cmd.valueOverride = ["key=value"]
            cmd.yaml = [metadata.absoluteString]
            cmd.export = folder.path // export to the same folder as the metadata source

            customize(&cmd)

            var results: [FastlaneAppStoreMetadata] = []
            for try await result in cmd.executeCommand() {
                results.append(result)
            }
            XCTAssertGreaterThan(results.count, 0, "expected at least one result")
            return (folder, results)
        }

        func load(from folder: URL, path: String) throws -> String {
            try String(contentsOf: URL(fileURLWithPath: path, relativeTo: folder))
        }

        do {
            let result = try await check("app:\n  name: 'Some App'\n  subtitle: '123456789012345678901234567890'")
            XCTAssertEqual("Some App", result.metadata.first?.name)
            XCTAssertEqual("123456789012345678901234567890", result.metadata.first?.subtitle)
            XCTAssertEqual("Some App", try load(from: result.folder, path: "default/name.txt"))
            XCTAssertEqual("123456789012345678901234567890", try load(from: result.folder, path: "default/subtitle.txt"))
        }


        // test localized prefix/override
        do {
            let result = try await check("""
            app:
              name: 'Some App'
              subtitle: '123456789012345678901234567890'
              localizations:
               fr-FR:
                 name: 'Le App'
               de-DE:
                 subtitle: 'Ein App Awesome!'
               en-GB:
                 description: 'A super good app that does anything you want.'
               xxx: # note: we currently tolerate unrecognized locales; should we fail?
                 name: 'XXX'
            """) { cmd in
                cmd.valueAppend = ["fr-FR/name=!!!"]
                cmd.valueDefault = ["de-DE/description=GERMAN DESCRIPTION"]
                cmd.valueOverride = ["en-GB/subtitle=A jolly good app"]
            }

            XCTAssertEqual("Some App", result.metadata.first?.name)
            XCTAssertEqual("123456789012345678901234567890", result.metadata.first?.subtitle)

            XCTAssertEqual("Some App", try load(from: result.folder, path: "default/name.txt"))
            XCTAssertEqual("123456789012345678901234567890", try load(from: result.folder, path: "default/subtitle.txt"))

            XCTAssertEqual("Le App!!!", try load(from: result.folder, path: "fr-FR/name.txt"))

            XCTAssertEqual("Ein App Awesome!", try load(from: result.folder, path: "de-DE/subtitle.txt"))
            XCTAssertEqual("GERMAN DESCRIPTION", try load(from: result.folder, path: "de-DE/description.txt"))

            XCTAssertEqual("A jolly good app", try load(from: result.folder, path: "en-GB/subtitle.txt"))
            XCTAssertEqual("A super good app that does anything you want.", try load(from: result.folder, path: "en-GB/description.txt"))

            // unrecognized locale; maybe we should fail?
            XCTAssertEqual("XXX", try load(from: result.folder, path: "xxx/name.txt"))
        }

        do {
            try await check("app:\n  subtitle: '1234567890123456789012345678901'") { cmd in
            }
            XCTFail("expected error from value over max length")
        } catch {
            // expected
        }

        do {
            try await check("""
            xapp:
                name: "parse_error"
            """) { cmd in

            }
            XCTFail("expected error from metadata parsing")
        } catch {
            // expected
        }
    }

    func testAppConfigureCommand() async throws {
        let projectFolder = URL(fileURLWithPath: #function, isDirectory: true, relativeTo: .tmpdir)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true, attributes: nil)
        let xcconfig = projectFolder.appendingPathComponent("appfair.xcconfig", isDirectory: false)

        try """
        // This is the name of the app
        PRODUCT_NAME = Some App

        // This is the semantic version for the app
        MARKETING_VERSION = 1.2.3

        // This is the build number of the app
        CURRENT_PROJECT_VERSION = 987
        """.write(to: xcconfig, atomically: true, encoding: .utf8)

        func checkProject(_ args: String...) async throws -> FairConfigureOutput {
            let results = try await runToolOutputStream(AppCommand.configuration, cmd: AppCommand.ConfigureCommand.self, args: ["--project", projectFolder.path] + args)
            return try XCTUnwrap(results.output.first)
        }

        do {
            let output = try await checkProject()
            XCTAssertEqual("Some App", output.productName)
            XCTAssertEqual("1.2.3", output.version?.versionString)
            XCTAssertEqual(987, output.buildNumber)
        }

        do {
            let output = try await checkProject("--bump", "patch")
            XCTAssertEqual("1.2.4", output.version?.versionString)
        }

        do {
            let output = try await checkProject("--bump", "minor")
            XCTAssertEqual("1.3.0", output.version?.versionString)
        }

        do {
            let output = try await checkProject("--bump", "major")
            XCTAssertEqual("2.0.0", output.version?.versionString)
        }

        do {
            let output = try await checkProject("--version", "1.1.1")
            XCTAssertEqual("1.1.1", output.version?.versionString)
        }

        do {
            let output = try await checkProject("--name", "Another App")
            XCTAssertEqual("Another App", output.productName)
        }

        do {
            let output = try await checkProject("--build-number", "989")
            XCTAssertEqual(989, output.buildNumber)
        }

        do {
            let output = try await checkProject("--id", "app.Another-App")
            XCTAssertEqual("app.Another-App", output.bundleIdentifier)
        }

        do {
            let output = try await checkProject("--platforms", "macosx iphoneos iphonesimulator")
            XCTAssertEqual("macosx iphoneos iphonesimulator", output.supportedPlatforms)
        }

        XCTAssertEqual("""
        // This is the name of the app
        PRODUCT_NAME = Another App

        // This is the semantic version for the app
        MARKETING_VERSION = 1.1.1

        // This is the build number of the app
        CURRENT_PROJECT_VERSION = 989
        PRODUCT_BUNDLE_IDENTIFIER = app.Another-App
        SUPPORTED_PLATFORMS = macosx iphoneos iphonesimulator
        """, try String(contentsOf: xcconfig, encoding: .utf8), "comments should be preserved when updating env")
    }
}

public struct PackageManifest : Hashable, Decodable {
    public var name: String
    //public var toolsVersion: String // can be string or dict
    public var products: [Product]
    public var dependencies: [Dependency]
    //public var targets: [Either<Target>.Or<String>]
    public var platforms: [SupportedPlatform]
    public var cModuleName: String?
    public var cLanguageStandard: String?
    public var cxxLanguageStandard: String?

    public struct Target: Hashable, Decodable {
        public enum TargetType: String, Hashable, Decodable {
            case regular
            case test
            case system
        }

        public var `type`: TargetType
        public var name: String
        public var path: String?
        public var excludedPaths: [String]?
        //public var dependencies: [String]? // dict
        //public var resources: [String]? // dict
        public var settings: [String]?
        public var cModuleName: String?
        // public var providers: [] // apt, brew, etc.
    }


    public struct Product : Hashable, Decodable {
        //public var `type`: ProductType // can be string or dict
        public var name: String
        public var targets: [String]

        public enum ProductType: String, Hashable, Decodable, CaseIterable {
            case library
            case executable
        }
    }

    public struct Dependency : Hashable, Decodable {
        public var name: String?
        public var url: String
        //public var requirement: Requirement // revision/range/branch/exact
    }

    public struct SupportedPlatform : Hashable, Decodable {
        var platformName: String
        var version: String
    }
}
