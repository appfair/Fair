import Foundation
import FairCore
import FairExpo
import ArgumentParser

public struct FairConfigureOutput : FairCommandOutput, Decodable {
    public var productName: String?
    public var bundleIdentifier: String?
    public var version: SemVer?
    public var buildNumber: Int?
    public var supportedPlatforms: String?
}

extension SemVer.Component : ExpressibleByArgument {
}

extension SemVer : ExpressibleByArgument {
}


public struct AppCommand : AsyncParsableCommand {
    public static let experimental = true
    public static var configuration = CommandConfiguration(commandName: "app",
                                                           abstract: "Commands for creating and validating an App Fair app.",
                                                           shouldDisplay: !experimental, subcommands: Self.subcommands)
#if os(macOS)
    static let subcommands: [ParsableCommand.Type] = [
        InfoCommand.self,
        ConfigureCommand.self,
        RefreshCommand.self,
        LocalizeCommand.self,
    ]
#else
    static let subcommands: [ParsableCommand.Type] = [
        InfoCommand.self,
        ConfigureCommand.self,
    ]
#endif

    public init() {
    }

    public struct ConfigureCommand: FairProjectCommand, FairStructuredCommand {
        public static let experimental = false
        public static var configuration = CommandConfiguration(commandName: "configure", abstract: "Update build appfair.xcconfig settings.", shouldDisplay: !experimental)

        public typealias Output = FairConfigureOutput

        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var projectOptions: ProjectOptions

        @Option(name: [.long], help: ArgumentHelp("Set the app name", valueName: "name"))
        public var name: String?

        @Option(name: [.long], help: ArgumentHelp("Set the bundle identifier"))
        public var id: String?

        @Option(name: [.long], help: ArgumentHelp("Set the supported platforms"))
        public var platforms: String?

        @Option(name: [.long], help: ArgumentHelp("Bump the major/minor/patch version", valueName: "component"))
        public var bump: SemVer.Component?

        @Option(name: [.long], help: ArgumentHelp("Set the build number", valueName: "int"))
        public var buildNumber: Int?

        @Option(name: [.long], help: ArgumentHelp("Set a specific version", valueName: "semver"))
        public var version: SemVer?

        public init() {
        }

        public func executeCommand() -> AsyncThrowingStream<FairConfigureOutput, Error> {
            msg(.debug, "getting info from project:", projectOptions.projectPathFlag)
            warnExperimental(Self.experimental)
            let projects = [URL(fileURLWithPath: projectOptions.projectPathFlag)]
            return executeStream(projects, block: configureCommand)
        }

        public func configureCommand(_ url: URL) throws -> Output {
            let origSettings = try projectOptions.buildSettings()
            var settings = origSettings

            let appVersion = settings.appVersion
            if let bump = self.version ?? self.bump.flatMap({ appVersion?.bumping($0) }) {
                msg(.info, self.version == nil ? "bumping" : "setting", "version from:", appVersion?.versionString, "to:", bump.versionString)
                settings.appVersion = bump
            }

            let productName = settings.productName
            if let name = self.name {
                msg(.info, "setting name from:", productName, "to:", name)
                settings.productName = name.trimmed()
            }

            let buildNumber = settings.buildNumber
            if let build = self.buildNumber {
                msg(.info, "setting build number from:", buildNumber, "to:", build)
                settings.buildNumber = build
            }

            let bundleIdentifier = settings.bundleIdentifier
            if let id = self.id {
                msg(.info, "setting bundle id from:", bundleIdentifier, "to:", id)
                settings.bundleIdentifier = id.trimmed()
            }

            let supportedPlatforms = settings.supportedPlatforms
            if let platforms = self.platforms {
                msg(.info, "setting platforms from:", supportedPlatforms, "to:", platforms)
                settings.supportedPlatforms = platforms.trimmed()
            }

            // when the settings have changed, try to save them
            if settings != origSettings {
                msg(.info, "saving settings to:", projectOptions.settingsPath.path)
                try settings.save(to: projectOptions.settingsPath)
            }

            return FairConfigureOutput(productName: settings.productName ?? productName, bundleIdentifier: settings.bundleIdentifier ?? id, version: settings.appVersion ?? appVersion, buildNumber: settings.buildNumber ?? buildNumber, supportedPlatforms: settings.supportedPlatforms ?? supportedPlatforms)
        }
    }

    public struct InfoCommand: FairProjectCommand, FairStructuredCommand {
        public static let experimental = false
        public static var configuration = CommandConfiguration(commandName: "info", abstract: "Output information about the specified app(s).", shouldDisplay: !experimental)

        public typealias Output = FairProjectInfo

        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var projectOptions: ProjectOptions

        public init() {
        }

        public func executeCommand() -> AsyncThrowingStream<FairProjectInfo, Error> {
            msg(.debug, "getting info from project:", projectOptions.projectPathFlag)
            warnExperimental(Self.experimental)
            let projects = [URL(fileURLWithPath: projectOptions.projectPathFlag)]
            return executeStream(projects) {
                try parseGitConfig(from: $0)
            }
        }
    }

#if os(macOS)

    /// An aggregate command that performs the following tasks:
    ///
    ///  - create or update the docs/CNAME file
    ///  - create and update the localized strings file
    public struct RefreshCommand: FairAppCommand {
        public static let experimental = false
        public static var configuration = CommandConfiguration(commandName: "refresh", abstract: "Update project resources and configuration.", shouldDisplay: !experimental)

        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var projectOptions: ProjectOptions

        @Option(name: [.long], help: ArgumentHelp("The app target."))
        public var targets: [String] = ["App"]

        @Option(name: [.long], help: ArgumentHelp("The language to generate."))
        public var language: [String] = []

        public init() {
        }

        public func run() async throws {
            let info = try parseGitConfig(from: URL(fileURLWithPath: projectOptions.projectPathFlag))
            msg(.info, "refreshing project:", info.url)

            let fm = FileManager.default
            let host = info.url.deletingLastPathComponent().lastPathComponent.lowercased() + ".appfair.net"
            if try fm.update(url: projectOptions.projectPathURL(path: "docs/CNAME"), with: host.utf8Data) != nil {
                msg(.info, "set landing page:", host)
            }

            try await generateLocalizedStrings()
        }
    }

    public struct LocalizeCommand: FairAppCommand {
        public static let experimental = false
        public static var configuration = CommandConfiguration(commandName: "localize", abstract: "Generate Localized.strings files from source code.", shouldDisplay: !experimental)

        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var projectOptions: ProjectOptions

        @Option(name: [.long], help: ArgumentHelp("The package localization target."))
        public var targets: [String] = ["App"]

        @Option(name: [.long], help: ArgumentHelp("The locale to generate."))
        public var language: [String] = []

        public init() {
        }

        public func run() async throws {
            try await generateLocalizedStrings()
        }
    }

#endif
}

fileprivate extension FairProjectCommand {
    /// Get the git information from the given repository.
    func parseGitConfig(from url: URL, configPath: String = ".git/config") throws -> FairProjectInfo {
        msg(.info, "extracting info: \(url.path)")
        let gitConfigPath = projectOptions.projectPathURL(path: configPath)
        if !FileManager.default.isReadableFile(atPath: gitConfigPath.path) {
            throw AppError(String(format: NSLocalizedString("Project folder expected to be a git repository, but it does not contain a .git/FETCH_HEAD file", bundle: .module, comment: "error message")))
        }

        let config = try GitConfig(url: gitConfigPath)

        guard let origin = config["url", section: #"remote "origin""#],
              let originURL = URL(string: origin) else {
            throw AppError(String(format: NSLocalizedString("Missing remote origin url in .git/config file", bundle: .module, comment: "error message")))
        }


        let repoName = originURL.lastPathComponent
        let orgName = originURL.deletingLastPathComponent().lastPathComponent
        let baseURL = originURL.deletingLastPathComponent().deletingLastPathComponent()

        if baseURL.absoluteString != "https://github.com/" {
            throw AppError(String(format: NSLocalizedString("Unsupported repository host: %@", bundle: .module, comment: "error message"), arguments: [baseURL.absoluteString]))
        }

        if repoName != "App.git" && repoName != "App" {
            throw AppError(String(format: NSLocalizedString("Repository must be named “App”, but found “%@”", bundle: .module, comment: "error message"), arguments: [repoName]))

        }

        let org = orgName.dehyphenated()
        return FairProjectInfo(name: org, url: originURL)
    }
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

