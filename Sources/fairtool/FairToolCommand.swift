import Foundation
import FairCore
import FairExpo
import ArgumentParser
#if canImport(CoreFoundation)
import CoreFoundation
#endif

#if canImport(SwiftUI)
import SwiftUI
#endif

public struct FairToolCommand : AsyncParsableCommand {
    public static let experimental = false
    public static var configuration = CommandConfiguration(commandName: "fairtool",
                                                           abstract: "Manage an ecosystem of apps",
                                                           shouldDisplay: !experimental,
                                                           subcommands: [
                                                            AppCommand.self,
                                                            TranslateCommand.self,
                                                            FairCommand.self,
                                                            ArtifactCommand.self,
                                                            BrewCommand.self,
                                                            JSONCommand.self,
                                                            SourceCommand.self,
                                                            VersionCommand.self, // `fairtool version` shows the current version
                                                           ]
    )

    /// This is needed to handle execution of the tool from as a sandboxed command plugin
    @Option(name: [.long], help: ArgumentHelp("List of targets to apply", valueName: "target"))
    public var target: Array<String> = []

    public init() {
    }

    public struct VersionCommand: FairParsableCommand {
        public static let experimental = false
        public typealias Output = Never
        public static var configuration = CommandConfiguration(commandName: "version",
                                                               abstract: "Show the fairtool version",
                                                               shouldDisplay: !experimental)
        @OptionGroup public var msgOptions: MsgOptions

        public init() {
        }

        public mutating func run() async throws {
            warnExperimental(Self.experimental)
            let version = Bundle.fairCoreVersion
            msg(.info, NSLocalizedString("fairtool", bundle: .module, comment: "the name of the fairtool"), version?.versionString)
        }
    }
}


/// A command that contains options for how messages will be conveyed to the user
public protocol FairMsgCommand : AsyncParsableCommand {
    var msgOptions: MsgOptions { get set }
}

extension FairMsgCommand {
    func warnExperimental(_ experimental: Bool) {
        if experimental {
            msg(.warn, "the \(Self.configuration.commandName ?? "") command is experimental and may change in minor releases")
        }
    }
}

/// A specific command that can write messages (to stderr) and JSON encodable tool output (to stdout)
public protocol FairParsableCommand : FairMsgCommand {
    /// The structured output of this tool
    associatedtype Output
}

/// A command that will issue an asynchronous stream of output items
public protocol FairStructuredCommand : FairParsableCommand where Output : FairCommandOutput {
    /// Executes the command and results a streaming result of command responses
    func executeCommand() -> AsyncThrowingStream<Output, Error>

    func writeCommandStart() throws
    func writeCommandEnd() throws
}

public extension FairStructuredCommand {
    func writeCommandStart() { }
    func writeCommandEnd() { }

    func run() async throws {
        try writeCommandStart()
        msgOptions.writeOutputStart()
        var elements = self.executeCommand().makeAsyncIterator()
        if let first = try await elements.next() {
            try msgOptions.writeOutput(first)
            while let element = try await elements.next() {
                msgOptions.writeOutputSeparator()
                try msgOptions.writeOutput(element)
            }
        }
        msgOptions.writeOutputEnd()
        try writeCommandEnd()
    }
}

public final class MessageBuffer {
    /// The list of messages
    public var messages: [MessagePayload] = []

    /// The output that is written
    public var output: [String] = []

    public init() {
    }
}

// Buffer contents are not really decodable, but the protocol is requires for `ParsableCommand` conformance
extension MessageBuffer : Decodable {
    public convenience init(from decoder: Decoder) throws {
        self.init()
    }
}

/// A command that requires the presence of a project
protocol FairProjectCommand : FairMsgCommand {
    var projectOptions: ProjectOptions { get }
}

public struct FairProjectInfo : FairCommandOutput, Decodable {
    public var name: String
    public var url: URL
}

protocol FairAppCommand : FairProjectCommand {
    var targets: [String] { get }
    var language: [String] { get }
}

extension FairAppCommand {

    #if os(macOS)
    /// Run `genstrings` on the source files in the project.
    func generateLocalizedStrings(locstr: String = "Localizable.strings") async throws {
        //msg(.info, "Scanning strings for localization")

        for target in targets {
            let resourcesFolder = projectOptions.projectPathURL(path: "Sources")
                .appendingPathComponent(target)
                .appendingPathComponent("Resources")

            let tmp = projectOptions.projectPathURL(path: ".fairtool").appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer {
                // clean up temporary localization file
                try? FileManager.default.removeItem(at: tmp)
            }

            let sourceFiles = try projectOptions.projectPathURL(path: "Sources").fileChildren(deep: true).filter { url in
                url.pathExtension == "swift"
            }

            // rather than forking genstrings, some simple regular expressions for
            // NSLocalizedString(…) might suffice.
            // SwiftUI.Text(…) interpolation might make it a bit tricker, since inline
            // parameter values would need to be handled (which would involve parsing a subset
            // of the Swift language).
            let args = ["genstrings", "-SwiftUI", "-o", tmp.path] + sourceFiles.map(\.path)
            msg(.debug, "running command:", args)
            let cmd = try await Process.exec(cmd: "/usr/bin/xcrun", args: args)
            msg(.debug, "process exited with:", cmd.terminationStatus)

            let outputFile = tmp.appendingPathComponent(locstr)

            var generatedEncoding: String.Encoding = .utf16 // genstrings outputs UTF-16
            let generatedStrings = try String(contentsOf: outputFile, usedEncoding: &generatedEncoding)
            // the generated locale file
            let generatedLocaleFile = try LocalizedStringsFile(fileContents: generatedStrings)

            msg(.debug, "created strings file", outputFile.path, "encoding:", generatedEncoding)

            for (lang, matches) in try loadLocalizations(resourcesFolder: resourcesFolder) {
                for (url, plist) in matches {
                    _ = plist
                    if !language.isEmpty && !language.contains(lang) {
                        msg(.info, "skipping excluded language code:", lang, url.absoluteString)
                        continue
                    }

                    let localizedStringsPath = resourcesFolder
                        .appendingPathComponent(lang)
                        .appendingPathExtension("lproj")
                        .appendingPathComponent(locstr)

                    msg(.info, "Scanning strings in \(target) for localization to:", localizedStringsPath.path)

                    var existingEncoding: String.Encoding = .utf8

                    // load the initial strings to check for changes
                    let existingStrings = try String(contentsOf: localizedStringsPath, usedEncoding: &existingEncoding)
                    let existingLocaleFile = try LocalizedStringsFile(fileContents: existingStrings)

                    var updatedLocale = generatedLocaleFile
                    try updatedLocale.update(strings: existingLocaleFile.plist)
                    var localizedStrings = updatedLocale.fileContents
                    //generatedLocaleFile

                    let locale = Locale(identifier: lang)
                    let languageNameCurrent = Locale.current.localizedString(forLanguageCode: lang) ?? ""
                    let languageName = locale.localizedString(forLanguageCode: lang) ?? ""

                    let comments = [
                        "Localized \(languageNameCurrent) (\(languageName)) strings for this App Fair App.",
                        "Translators: edit this file to fork the repository and contribute your translated strings.",
                        "Visit https://appfair.net/#translation for more details.",
                    ]

                    // create a comment header for the file
                    localizedStrings = comments.map({ "// " + $0 }).joined(separator: "\n") + "\n\n" + localizedStrings

                    if localizedStrings == existingStrings {
                        msg(.info, "Localizations unchanged:", localizedStringsPath.path)
                    } else {
                        try localizedStrings.write(to: localizedStringsPath, atomically: true, encoding: .utf8)
                        msg(.info, "wrote updated strings file to:", localizedStringsPath.path)
                    }
                }
            }
        }
    }
    #endif
}

extension FairMsgCommand {
    func loadLocalizations(resourcesFolder: URL, localeFileName: String = "Localizable.strings") throws -> [String: [(URL, Plist)]] {
        let fm = FileManager.default
        var localizations: [String: [(URL, Plist)]] = [:]
        for childURL in try fm.contentsOfDirectory(at: resourcesFolder, includingPropertiesForKeys: [.isDirectoryKey]) {
            if childURL.pathIsDirectory && childURL.pathExtension == "lproj" {
                let languageCode = childURL.deletingPathExtension().lastPathComponent

                for localeChildURL in try fm.contentsOfDirectory(at: childURL, includingPropertiesForKeys: [.isDirectoryKey]) {

                    if try localeChildURL.lastPathComponent.matches(regex: localeFileName) == false {
                        continue
                    }

                    let resource = try PropertyListSerialization.propertyList(from: Data(contentsOf: localeChildURL), format: nil)
                    if let resource = resource as? NSDictionary {
                        //msg(.debug, "loaded resource for", resource)
                        localizations[languageCode, default: []].append((localeChildURL, Plist(rawValue: resource)))
                    }
                }
            }
        }

        return localizations
    }

}

public struct ProjectOptions: ParsableArguments {
    @Option(name: [.long, .customShort("m")], help: ArgumentHelp("The project metadata to use", valueName: "file"))
    public var metadata: String?

    @Option(name: [.long, .customShort("p")], help: ArgumentHelp("The project to use", valueName: "path"))
    public var project: String?

    @Option(name: [.long], help: ArgumentHelp("The path to the xcconfig containing metadata", valueName: "xc"))
    public var fairProperties: String = "appfair.xcconfig"

    /// The path to the settings file
    public var settingsPath: URL {
        projectPathURL(path: fairProperties)
    }

    public init() { }

    /// The flag for the project folder
    public var projectPathFlag: String {
        self.project ?? FileManager.default.currentDirectoryPath
    }

    /// Loads the data for the project file at the given relative path
    func projectPathURL(path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: false, relativeTo: URL(fileURLWithPath: projectPathFlag, isDirectory: true))
    }

    /// If the `--fair-properties` flag was specified, tries to parse the build settings
    func buildSettings() throws -> EnvFile {
        try EnvFile(url: settingsPath)
    }
}

extension JSON : SigningContainer {
}


public typealias FairCommandOutput = Encodable // & Decodable


public struct OutputOptions: ParsableArguments {
    @Option(name: [.long, .customShort("o")], help: ArgumentHelp("The output path"))
    public var output: String = "-"

    public init() { }

    /// The flag for the output folder or the current director
    var outputDirectoryFlag: String {
        self.output
    }

    func write(_ data: Data) throws {
        if output == "-" {
            print(data.utf8String ?? "")
        } else {
            try data.write(to: URL(fileURLWithPath: output))
        }
    }
}

extension OutputOptions {
    func writeCatalog(_ catalog: AltCatalog) throws -> Data {
        let json = try catalog.toJSON(outputFormatting: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes], dateEncodingStrategy: .iso8601, dataEncodingStrategy: .base64)
        try self.write(json)
        return json
    }
}

public struct SourceOptions: ParsableArguments {
    @Option(help: ArgumentHelp("The name of the fairground", valueName: "name"))
    public var fairgroundName: String = "appfair"

    @Option(help: ArgumentHelp("The name of the developer of the catalog", valueName: "name"))
    public var developerName: String = "The App Fair Project"

    @Option(help: ArgumentHelp("The name of the catalog", valueName: "name"))
    public var catalogName: String = "The App Fair Project"

    @Option(help: ArgumentHelp("The base URL of the hub repository", valueName: "url"))
    public var hubRepository: String = "https://delivery.appfair.net" // "https://github.com/appfair"

    @Option(help: ArgumentHelp("The base URL of the hub raw content", valueName: "url"))
    public var hubContent: String = "https://assets.appfair.net" // "https://raw.githubusercontent.com/appfair"

    @Option(help: ArgumentHelp("The subtitle of the catalog", valueName: "name"))
    public var catalogSubtitle: String = "The free and open-source app catalog"

    @Option(help: ArgumentHelp("The description for this catalog", valueName: "desc"))
    public var catalogDescription: String = "This catalog contains free and open-source apps distributed through the App Fair Project."

    @Option(help: ArgumentHelp("The icon URL of the catalog", valueName: "url"))
    public var catalogIconURL: String = "https://appfair.org/appfair-icon.png"

    @Option(help: ArgumentHelp("The web site of the catalog", valueName: "url"))
    public var catalogWebsite: String = "https://appfair.org"

    @Option(help: ArgumentHelp("The tint color for this catalog", valueName: "rgbhex"))
    public var catalogTintColor: String?

    // Per-app arguments

//    @Option(help: ArgumentHelp("The default description(s) for the app(s)", valueName: "desc"))
//    public var appLocalizedDescription: [String] = []
//
//    @Option(help: ArgumentHelp("The default versionDescription for the app(s)", valueName: "desc"))
//    public var appVersionDescription: [String] = []
//
//    @Option(help: ArgumentHelp("The default subtitle(s) for the app(s)", valueName: "title"))
//    public var appSubtitle: [String] = []
//
//    @Option(help: ArgumentHelp("The default developer name(s) for the app(s)", valueName: "email"))
//    public var appDeveloperName: [String] = []
//
//    @Option(help: ArgumentHelp("The download URLfor the app(s)", valueName: "URL"))
//    public var appDownloadURL: [String] = []

    public init() {
    }

}

public struct MsgOptions: ParsableArguments {
    @Flag(name: [.long, .customShort("v")], help: ArgumentHelp("Whether to display verbose messages"))
    public var verbose: Bool = false

    @Flag(name: [.long, .customShort("q")], help: ArgumentHelp("Quiet mode: suppress output"))
    public var quiet: Bool = false

    @Flag(name: [.long, .customShort("J")], help: ArgumentHelp("Exclude root JSON array from output"))
    public var promoteJSON: Bool = false

    public var messages: MessageBuffer? = nil

    public init() {
    }

    /// Write the given message to standard out, unless the output buffer is set, in which case output is sent to the buffer
    public func write(_ value: String) {
        if let messages = messages {
            messages.output.append(value)
        } else {
            print(value)
        }
    }

    /// The output that comes at the beginning of a sequence of elements; an opening bracket, for JSON arrays
    public func writeOutputStart() {
        if !promoteJSON { write("[") }
    }

    /// The output that comes at the end of a sequence of elements; a closing bracket, for JSON arrays
    public func writeOutputEnd() {
        if !promoteJSON { write("]") }
    }

    /// The output that separates elements; a comma, for JSON arrays
    public func writeOutputSeparator() {
        if !promoteJSON { write(",") }
    }

    func writeOutput<T: FairCommandOutput>(_ item: T) throws {
        try write(item.toJSON(outputFormatting: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes], dateEncodingStrategy: .iso8601).utf8String ?? "")
    }

    /// Iterates over each of the given arguments and executes the block against the arg, outputting the result as it goes.
    func executeStreamJoined<T, U: FairCommandOutput>(_ arguments: [T], block: @escaping (T) async throws -> AsyncThrowingStream<U, Error>) -> AsyncThrowingStream<U, Error> {
        return AsyncThrowingStream<U, Error>(U.self) { c in
            Task {
                do {
                    for arg in arguments {
                        for try await item in try await block(arg) {
                            c.yield(item)
                        }
                    }
                    c.finish()
                } catch {
                    c.finish(throwing: error)
                }
            }
        }
    }
}

public struct RegOptions: ParsableArguments {
    @Option(name: [.long], help: ArgumentHelp("Allow patterns for integrate PR names", valueName: "pattern"))
    public var allowName: [String] = []

    @Option(name: [.long], help: ArgumentHelp("Disallow patterns for integrate PR names", valueName: "pattern"))
    public var denyName: [String] = []

    @Option(name: [.long], help: ArgumentHelp("Allow patterns for integrate PR users", valueName: "pattern"))
    public var allowFrom: [String] = []

    @Option(name: [.long], help: ArgumentHelp("Disallow patterns for integrate PR users", valueName: "pattern"))
    public var denyFrom: [String] = []

    @Option(name: [.long], help: ArgumentHelp("Permitted license IDs", valueName: "id"))
    public var allowLicense: [String] = []

    @Option(name: [.long], help: ArgumentHelp("Permitted license titles"))
    public var license: [String] = []

    public init() {

    }

    func createProjectConfiguration() throws -> FairHub.ProjectConfiguration {
        try FairHub.ProjectConfiguration(allowName: joinWhitespaceSeparated(self.allowName), denyName: joinWhitespaceSeparated(self.denyFrom), allowFrom: joinWhitespaceSeparated(self.allowFrom), denyFrom: joinWhitespaceSeparated(self.denyFrom), allowLicense: joinWhitespaceSeparated(self.allowLicense))
    }
}

/// A Hub is represented by a string "`service.host`/`organization`".
///
/// E.g., "github.com/appfair"
public struct HubOptions: ParsableArguments {
    @Option(name: [.long, .customShort("h")], help: ArgumentHelp("The name of the hub to use (e.g., gitub.com/appfair)", valueName: "host/org"))
    public var hub: String

    @Option(name: [.long, .customShort("B")], help: ArgumentHelp("The name of the hub's base repository", valueName: "repo"))
    public var baseRepo: String = baseFairgroundRepoName

    @Option(name: [.long, .customShort("k")], help: ArgumentHelp("The token used for the hub's authentication"))
    public var token: String?

    @Option(name: [.long], help: ArgumentHelp("Name of the login that issues the fairseal", valueName: "usr"))
    public var fairsealIssuer: String?

    @Option(name: [.long], help: ArgumentHelp("The base64-encoded signing key for the fairseal issuer", valueName: "key"))
    public var fairsealKey: String?

    public init() { }

    /// The hub service we should use for this tool
    public func fairHub() throws -> FairHub {
        try FairHub(hostOrg: self.hub, authToken: self.token ?? ProcessInfo.processInfo.environment["GITHUB_TOKEN"], fairsealIssuer: self.fairsealIssuer, fairsealKey: self.fairsealKey.flatMap({ Data(base64Encoded: $0) }))
    }

    /// The host service address. E.g., the "github.com" part of "github.com/appfair"
    public var serviceHost: String {
        hub.split(separator: "/").first?.description ?? hub
    }

    /// The name of the organization for this hub.  E.g., the "appfair" part of "github.com/appfair"
    public var organizationName: String {
        hub.split(separator: "/").last?.description ?? hub
    }
}

extension FairMsgCommand {

    /// Output the given message to standard error
    func msg(_ kind: MessageKind = .info, _ message: Any?...) {
        if msgOptions.quiet == true {
            return
        }

        let msg = message.compactMap({ $0.flatMap(String.init(describing:)) }).joined(separator: " ")

        if kind == .debug && msgOptions.verbose != true {
            return // skip debug output unless we are running verbose
        }


        if msgOptions.messages != nil {
            msgOptions.messages!.messages.append((kind, message))
        } else {

            // let (checkMark, failMark) = ("✓", "X")
            if kind == .info {
                // info just gets printed directly
                print(msg, to: &StandardErrorOutputStream.shared)
            } else {
                print(kind.name, msg, to: &StandardErrorOutputStream.shared)
            }
        }
    }
}

private struct StandardErrorOutputStream: TextOutputStream {
    static var shared = StandardErrorOutputStream()
    let stderr = FileHandle.standardError

    func write(_ string: String) {
        stderr.write(string.utf8Data)
    }
}

extension FairToolCommand {
    enum Errors : LocalizedError {
        case missingCommand
        case unknownCommand(_ cmd: String)
        case badArgument(_ arg: String)
        case badOperation(_ op: String?)
        case missingSDK
        case dumpPackageError
        case invalidAppSourceHeader(_ url: URL)
        case cannotInitNonEmptyFolder(_ url: URL)
        case sameOutputAndProjectPath(_ output: String, _ project: String)
        case cannotOverwriteAlteredFile(_ url: URL)
        case invalidData(_ url: URL)
        case invalidPlistValue(_ key: String, _ expected: [String], _ actual: NSObject?, _ url: URL)
        case invalidContents(_ scaffoldSource: String?, _ projectSource: String?, _ path: String, _ line: Int)
        case invalidHub(_ host: String?)
        case badRepository(_ expectedHost: String, _ repository: String?)
        case missingArguments
        case downloadMissing(_ url: URL)
        case missingAppPath
        case badApplicationsPath(_ url: URL)
        case installAppMissing(_ appName: String, _ url: URL)
        case installedAppExists(_ appURL: URL)
        case processCommandUnavailable(_ command: String)
        case matchFailed(_ arg: String)
        case noBundleID(_ url: URL)
        case mismatchedBundleID(_ url: URL, _ sourceID: String, _ destID: String)
        case sandboxRequired
        case forbiddenEntitlement(_ entitlement: String)
        case missingUsageDescription(_ entitlement: AppEntitlement)
        case missingFlag(_ flag: String)
        case invalidIntegrationTitle(_ integrationName: String, _ expectedName: String)

        public var errorDescription: String? {
            switch self {
            case .missingCommand: return "Missing command"
            case .unknownCommand(let cmd): return "Unknown command \"\(cmd)\""
            case .badArgument(let arg): return "Bad argument: \"\(arg)\""
            case .badOperation(let op): return "Bad operation: \"\(op ?? "none")\"."
            case .missingSDK: return "Missing SDK"
            case .dumpPackageError: return "Error reading Package.swift"
            case .invalidAppSourceHeader(let url): return "Invalid modification of source header at \(url.lastPathComponent)."
            case .cannotInitNonEmptyFolder(let url): return "Folder is not empty: \(url.path)."
            case .sameOutputAndProjectPath(let output, let project): return "The output path specified by -o (\(output)) may not be the same as the project path specified by -p (\(project))."
            case .cannotOverwriteAlteredFile(let url): return "Cannot overwrite path \(url.relativePath) with changed contents."
            case .invalidData(let url): return "The data at \(url.path) is invalid."
            case .invalidPlistValue(let key, let expected, let actual, let url): return "The key \"\(key)\" at \(url.path) is invalid: expected one of \"\(expected)\" but found \"\(actual ?? ("nil" as NSString))\"."
            case .invalidContents(_, _, let path, let line): return "The contents at \"\(path)\" does not match the contents of the original source starting at line \(line + 1)."
            case .invalidHub(let host): return "The hub (\"\(host ?? "null")\") specified by the -h/--hub flag is invalid"
            case .badRepository(let expectedHost, let repository): return "The pinned repository \"\(repository ?? "")\" does not match the hub (\"\(expectedHost)\") specified by the -h/--hub flag"
            case .missingArguments: return "The operation requires at least one argument"
            case .downloadMissing(let url): return "The download file could not be found: \(url.path)"
            case .missingAppPath: return "The applications install path (-a/--appPath) is required"
            case .badApplicationsPath(let url): return "The applications install path (-a/--appPath) did not exist and could not be created: \(url.path)"
            case .installAppMissing(let appName, let url): return "The install archive was missing a root \"\(appName)\" at: \(url.path)"
            case .installedAppExists(let appURL): return "Cannot install over existing app without update: \(appURL.path)"
            case .processCommandUnavailable(let command): return "Platform does not support Process and therefore cannot run: \(command)"
            case .matchFailed(let arg): return "Found no match for: \"\(arg)\""
            case .noBundleID(let url): return "No bundle ID found for app: \"\(url.path)\""
            case .mismatchedBundleID(let url, let sourceID, let destID): return "Update cannot change bundle ID from \"\(sourceID)\" to \"\(destID)\" in app: \(url.path)"
            case .sandboxRequired: return "The sandbox-macos.entitlements must activate sandboxing with the \"com.apple.security.app-sandbox\" property"
            case .forbiddenEntitlement(let entitlement): return "The entitlement \"\(entitlement)\" is not permitted."
            case .missingUsageDescription(let entitlement): return "The entitlement \"\(entitlement.entitlementKey)\" requires a corresponding usage description property in the Info.plist FairUsage dictionary"
            case .missingFlag(let flag): return "The operation requires the -\(flag) flag"
            case .invalidIntegrationTitle(let title, let expectedName): return "The title of the integration pull request \"\(title)\" must match the product name and version in the appfair.xcconfig file (expected: \"\(expectedName)\")"
            }
        }
    }
}

/// Options for how downloading remote files should work.
public struct DownloadOptions: ParsableArguments {
    @Option(name: [.long], help: ArgumentHelp("Location of folder for downloaded artifacts", valueName: "dir"))
    public var cacheFolder: String?

    public init() { }

    /// Downloads a remote URL, or else returns the fule URL unadorned
    func acquire(path: String, onDownload: (URL) -> (URL) = { $0 }) async throws -> (from: URL, local: URL) {
        if let url = URL(string: path), ["http", "https"].contains(url.scheme) {
            let url = onDownload(url)
            return (url, try await self.download(url: url))
        } else {
            return (URL(fileURLWithPath: path), URL(fileURLWithPath: path))
        }
    }

    func download(url: URL) async throws -> URL {
        let (downloadedURL, response) = try await URLSession.shared.downloadFile(for: URLRequest(url: url))
        guard let status = (response as? HTTPURLResponse)?.statusCode,
              (200..<300).contains(status) else {
            throw URLError(.badServerResponse)
        }
        if let cacheFolder = cacheFolder.flatMap(URL.init(fileURLWithPath:)),
           FileManager.default.isDirectory(url: cacheFolder) == true {
            let cacheName = url.cachePathName // the full URL download
            let localURL = URL(fileURLWithPath: cacheName, relativeTo: cacheFolder)
            let _ = try? FileManager.default.trash(url: localURL) // in case it exists
            try FileManager.default.moveItem(at: downloadedURL, to: localURL)
            return localURL
        }
        return downloadedURL
    }
}

public struct DelayOptions: ParsableArguments {
    @Option(name: [.long], help: ArgumentHelp("Amount of time to wait between operations", valueName: "secs"))
    public var delay: TimeInterval?

    @Option(name: [.long], help: ArgumentHelp("Min amount of time to wait between operations", valueName: "secs"))
    public var delayMin: TimeInterval?

    @Option(name: [.long], help: ArgumentHelp("Max amount of time to wait between operations", valueName: "secs"))
    public var delayMax: TimeInterval?

    public init() { }

    /// Delays this task, first invoking the block with the time interval that will be delayed
    func sleepTask(_ block: ((TimeInterval) throws -> ())? = nil) async throws {
        if let delay = delay {
            try block?(delay)
            try await Task.sleep(interval: delay)
        } else if let delayMin = delayMin, let delayMax = delayMax, delayMax > delayMin {
            let delay = TimeInterval.random(in: delayMin...delayMax)
            try block?(delay)
            try await Task.sleep(interval: delay)
        }
    }
}

public struct RetryOptions: ParsableArguments {
    @Option(name: [.long], help: ArgumentHelp("Amount of time to continue re-trying downloading a resource", valueName: "secs"))
    public var retryDuration: TimeInterval?

    @Option(name: [.long], help: ArgumentHelp("Backoff time for waiting to retry", valueName: "secs"))
    public var retryWait: TimeInterval = 30

    public init() { }

    /// Retries the given operation until the `retry-duration` flag as been exceeded
    public func retrying<T>(operation: () async throws -> T) async throws -> T {
        let timeoutDate = Date().addingTimeInterval(self.retryDuration ?? 0)
        while true {
            do {
                return try await operation()
            } catch {
                // TODO: schedule on a queue rather than blocking on Thread.sleep
                if try backoff(timeoutDate, error: error) == false {
                    throw error
                }
            }
        }

        /// Backs off until the given timeout date
        @discardableResult func backoff(_ timeoutDate: Date, error: Error?) throws -> Bool {
            // we we are timed out, or if we don't want to retry, then simply re-download
            if (self.retryDuration ?? 0) <= 0 || self.retryWait <= 0 || Date() >= timeoutDate {
                return false
            } else {
                //msg(.info, "retrying operation in \(self.retryWait) seconds from \(Date()) due to error:", error)
                Thread.sleep(forTimeInterval: self.retryWait)
                return true
            }
        }
    }

}


extension FairParsableCommand {
    var fm: FileManager { .default }

    static var appSuffix: String { ".app" }

    /// The name of the App & the repository; defaults to "App"
    var appName: String { baseFairgroundRepoName }

    var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// Fail the command and exit the tool
    func fail<E: Error>(_ error: E) -> E {
        return error
    }

    func load(url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func validateCommit(ref: String, hub: FairHub) async throws {
        msg(.info, "Validating commit ref:", ref)
        let response = try await hub.request(FairHub.GetCommitQuery(owner: hub.org, name: appName, ref: ref)).get().data
        let author: Void = try hub.authorize(commit: response)
        let _ = author
        //msg(.info, "Validated commit author:", author)
    }

    /// Perform update checks before copying the app into the destination
    private func validateUpdate(from sourceApp: URL, to destApp: URL) throws {
        let sourceInfo = try Plist(url: sourceApp.appendingPathComponent("Contents/Info.plist"))
        let destInfo = try Plist(url: destApp.appendingPathComponent("Contents/Info.plist"))

        guard let sourceBundleID = sourceInfo.CFBundleIdentifier else {
            throw FairToolCommand.Errors.noBundleID(sourceApp)
        }

        guard let destBundleID = destInfo.CFBundleIdentifier else {
            throw FairToolCommand.Errors.noBundleID(destApp)
        }

        if sourceBundleID != destBundleID {
            throw FairToolCommand.Errors.mismatchedBundleID(destApp, sourceBundleID, destBundleID)
        }
    }

    /// Parses the `AccentColor.colorset/Contents.json` file and returns the first color item
//    func parseColorContents(url: URL) throws -> (r: Double, g: Double, b: Double, a: Double)? {
//        try AccentColorList(fromJSON: Data(contentsOf: url)).firstRGBAColor
//    }

//    @discardableResult func saveCask(_ app: AltCatalogAppItem, to caskFolderFlag: String, prereleaseSuffix: String?) throws -> Bool {
//        let appNameSpace = app.name
//        let appNameHyphen = app.name.rehyphenated()
//
//        guard let version = app.version else {
//            msg(.info, "no version for app: \(appNameHyphen)")
//            return false
//        }
//
//        guard let sha256 = app.sha256 else {
//            msg(.info, "no hash for app: \(appNameHyphen)")
//            return false
//        }
//
//        let fairground = Bundle.catalogBrowserAppOrg // e.g., App-Fair
//
//        let isCatalogAppCask = appNameHyphen == fairground
//
//        var caskName = appNameHyphen.lowercased()
//
//        if app.beta == true {
//            guard let prereleaseSuffix = prereleaseSuffix else {
//                return false // we've speficied not to generate casks for pre-releases
//            }
//            caskName = caskName + prereleaseSuffix
//        }
//
//        let caskPath = caskName + ".rb"
//
//        // apps other than "Catalog Name.app" are installed att "/Applications/Catalog Name/App Name.app"
//        let installPrefix = isCatalogAppCask ? "" : (fairground.dehyphenated() + "/")
//
//        // depending on the fair-ground's catalog app becomes difficult when the catalog app updates itself; homebrew won't overwrite the self-updated app even with the force flag, which means that a user may need to manually delete and re-install the app;
//        // let fairgroundCask = fairground.lowercased() // e.g., app-fair
//        let dependency = "" // isCatalogAppCask ? "" : "depends_on cask: \"\(fairgroundCask)\""
//
//        let appDesc = (app.subtitle ?? appNameSpace).replacingOccurrences(of: "\"", with: "'")
//        guard var downloadURL = app.downloadURL?.absoluteString else {
//            dbg("missing downloadURL")
//            return false
//        }
//
//        // all apps other than the catalog browser are
//        let appStanza = "app \"\(appNameSpace).app\", target: \"\(installPrefix)\(appNameSpace).app\""
//
//        // this helper stanza will make an executable symlink from the app binary to the cask name
//        // it will allow the running of "Super App.app" CLI with /usr/local/bin/super-app
//        let appHelper = /* !isCatalogAppCask ? "" : */ "binary \"#{appdir}/\(installPrefix)\(appNameSpace).app/Contents/MacOS/\(appNameSpace)\", target: \"\(caskName)\""
//
//        // change the hardcoded version string to a "#{version}" token, which minimizes the number of source changes when the app is upgraded
//        downloadURL = downloadURL.replacingOccurrences(of: "/\(version)/", with: "/#{version}/")
//
//        let repobase = "github.com/\(appNameHyphen)/"
//
//        let caskSpec = """
//cask "\(caskName)" do
//  version "\(version)"
//  sha256 "\(sha256)"
//
//  url "\(downloadURL)",
//      verified: "\(repobase)"
//  name "\(appNameSpace)"
//  desc "\(appDesc)"
//  homepage "https://\(repobase)App/"
//
//  depends_on macos: ">= :monterey"
//  \(dependency)
//
//  \(appStanza)
//  \(appHelper)
//
//  postflight do
//    system "xattr", "-r", "-d", "com.apple.quarantine", "#{appdir}/\(installPrefix)\(app.name).app"
//  end
//
//  zap trash: [
//    \(app.installationDataLocations.map({ $0.enquote(with: #"""#) }).joined(separator: ",\n    "))
//  ]
//end
//"""
//
//        let caskFile = URL(fileURLWithPath: caskFolderFlag).appendingPathComponent(caskPath)
//        try caskSpec.write(to: caskFile, atomically: false, encoding: .utf8)
//        return true
//    }

    static var packageValidationLine: String { "// MARK: fair-ground package validation" }

    /// Splits the two strings by newlines and returns the first non-matching line
    static func firstDifferentLine(_ source1: String, _ source2: String) -> Int {
        func split(_ source: String) -> [Substring] {
            source.split(separator: "\n", omittingEmptySubsequences: false)
        }
        let s1 = split(source1)
        let s2 = split(source2)
        for (index, (l1, l2)) in zip(s1 + s1, s2 + s2).enumerated() {
            if l1 != l2 { return index }
        }
        return -1
    }
}

/// A Git config file.
public struct GitConfig : RawRepresentable, Hashable {
    public var rawValue: [String?: [String: String]]

    public init(rawValue: [String?: [String: String]] = [:]) {
        self.rawValue = rawValue
    }

    public init(data: Data) throws {
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.coderInvalidValue)
        }

        var currentSection: String? = nil

        self.rawValue = [:]
        for (index, line) in string.split(separator: "\n").enumerated() {
            let nocomment = (line.components(separatedBy: "// ").first ?? .init(line)).trimmed()
            if nocomment.isEmpty { continue } // blank & comment-only lines are permitted

            let parts = nocomment.components(separatedBy: " = ")
            if parts.count != 2 {
                // handle sectioned out properties, such as .git/config
                if let section = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                   section.first == "[",
                   section.last == "]" {
                    currentSection = section.dropFirst().dropLast().description
                    continue
                } else {
                    throw AppError(String(format: NSLocalizedString("Error parsing line %lu: key value pairs must be separated by ' = '", bundle: .module, comment: "error message"), arguments: [index]))
                }
            }
            guard let key = parts.first?.trimmed(), !key.isEmpty else {
                throw AppError(String(format: NSLocalizedString("Error parsing line %lu: no key", bundle: .module, comment: "error message"), arguments: [index]))
            }
            guard let value = parts.last?.trimmed(), !key.isEmpty else {
                throw AppError(String(format: NSLocalizedString("Error parsing line %lu: no value", bundle: .module, comment: "error message"), arguments: [index]))
            }

            self.rawValue[currentSection, default: [:]][key] = value
        }
    }

    public init(url: URL) throws {
        // do {
        let data = try Data(contentsOf: url)
        try self.init(data: data)
        // } catch {
        // throw error.withInfo(for: NSLocalizedFailureReasonErrorKey, "Error loading from: \(url.absoluteString)")
        // }
    }

    public subscript(path: String, section section: String? = nil) -> String? {
        rawValue[section]?[path]
    }
}

extension EnvFile {
    /// The `PRODUCT_NAME` parsed as a `String`
    public var productName: String? {
        get { self["PRODUCT_NAME"] }
        set { self["PRODUCT_NAME"] = newValue }
    }

    /// The `PRODUCT_BUNDLE_IDENTIFIER` parsed as a `String`
    public var bundleIdentifier: String? {
        get { self["PRODUCT_BUNDLE_IDENTIFIER"] }
        set { self["PRODUCT_BUNDLE_IDENTIFIER"] = newValue }
    }

    /// The `CURRENT_PROJECT_VERSION` parsed as an `Int`
    public var buildNumber: Int? {
        get { self["CURRENT_PROJECT_VERSION"].flatMap({ Int($0) }) }
        set { self["CURRENT_PROJECT_VERSION"] = newValue?.description }
    }

    /// The `MARKETING_VERSION` parsed as an ``Semver``
    public var appVersion: SemVer? {
        get { self["MARKETING_VERSION"].flatMap({ SemVer(string: $0) }) }
        set { self["MARKETING_VERSION"] = newValue?.versionString }
    }

    /// The `SUPPORTED_PLATFORMS` parsed as a `String`
    public var supportedPlatforms: String? {
        get { self["SUPPORTED_PLATFORMS"] }
        set { self["SUPPORTED_PLATFORMS"] = newValue }
    }
}

/// Allow multiple newline separated elements for a single value, which
/// permits us to pass multiple e-mail addresses in a single
/// `--allow-from` or `--deny-from` setting.
private func joinWhitespaceSeparated(_ addresses: [String]) -> [String] {
    addresses
        .flatMap { $0.components(separatedBy: .whitespacesAndNewlines) }
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}


extension AsyncParsableCommand {
    /// Iterates over each of the given arguments and executes the block against the arg, outputting the JSON result as it goes.
    func executeStream<T, U: FairCommandOutput>(_ arguments: [T], block: @escaping (T) async throws -> U) -> AsyncThrowingStream<U, Error> {
        arguments.asyncMap(block)
    }

    /// Iterates over each of the given arguments and executes the block against the arg, outputting the JSON result as it goes.
    func executeSeries<T, U: FairCommandOutput>(_ arguments: [T], initialValue: U?, block: @escaping (T, U?) async throws -> U) -> AsyncThrowingStream<U, Error> {
        arguments.asyncReduce(initialResult: initialValue, block)
    }
}


/// Shim to work around crash with accessing ``Bundle.module`` from a command-line tool.
///
/// Ideally, we could enable this only when compiling into a single tool
internal func NSLocalizedString(_ key: String, tableName: String? = nil, bundle: @autoclosure () -> Bundle, value: String = "", comment: String) -> String {

    if moduleBundle == nil {
        // No bundle was found, so we are missing our localized resources.
        // Simple
        return key
    }

    // Runtime crash: FairExpo/resource_bundle_accessor.swift:11: Fatal error: could not load resource bundle: from /usr/local/bin/Fair_FairExpo.bundle or /private/tmp/fairtool-20220720-3195-1rk1z7r/.build/x86_64-apple-macosx/release/Fair_FairExpo.bundle

    return Foundation.NSLocalizedString(key, tableName: tableName, bundle: bundle(), value: value, comment: comment)
}
/// #endif

/// The same logic as the generated `resource_bundle_accessor.swift`,
/// so we can check it without crashing with a `fataError`.
private let moduleBundle = Bundle(url: Bundle.main.bundleURL.appendingPathComponent("Fair_FairExpo.bundle"))
