import Foundation
import FairCore
import FairExpo
import ArgumentParser

public struct AppStoreConnectCommand : AsyncParsableCommand {
    public static var configuration = CommandConfiguration(
        commandName: "asc",
        abstract: "App Store Connect commands",
        subcommands: [
            RequestCommand.self,
            ADPCommand.self,
            AppCommand.self,
        ])

    public init() {
    }

    public struct RequestCommand: ASCCommand {
        public static var configuration = CommandConfiguration(
            commandName: "request",
            abstract: "Make raw request to arbitrary endpoint"
            )

        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var outputOptions: OutputOptions
        @OptionGroup public var ascOptions: ASCOptions

        @Argument(help: "The full or partial URL to the ADP endpoint")
        public var path: String

        public typealias Output = AppStoreConnectEndpoint.RawRequest.Response // JSON

        public init() {
        }

        public func run() async throws {
            let response = try await createASCEndpoint().request(AppStoreConnectEndpoint.RawRequest(path: path))
            try msgOptions.writeOutput(response)
        }
    }

    public struct AppCommand: AsyncParsableCommand {
        public static var configuration = CommandConfiguration(
            commandName: "app",
            abstract: "app query and manipulation commands",
            subcommands: [
                ListAppsCommand.self,
            ])

        public init() {
        }
    }

    public struct ADPCommand: AsyncParsableCommand {
        public static var configuration = CommandConfiguration(
            commandName: "adp",
            abstract: "alternative distribution package commands",
            subcommands: [
                GetADPVersionCommand.self,
                GetADPInfoCommand.self,
                DownloadADPCommand.self,
            ])

        public init() {
        }
    }

    public struct ListAppsCommand: ASCCommand {
        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var outputOptions: OutputOptions
        @OptionGroup public var ascOptions: ASCOptions

        public static var configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List apps available")

        public typealias Output = AppStoreConnectEndpoint.ListAppsRequest.Response

        public init() {
        }

        public func run() async throws {
            let response = try await createASCEndpoint().request(AppStoreConnectEndpoint.ListAppsRequest())
            try msgOptions.writeOutput(response)
        }
    }

    /// e.g.: `fairtool asc adp download -v --versionid 73d0251f-1f4e-4499-850f-53dcb1885b33`
    public struct DownloadADPCommand: ASCCommand {
        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var outputOptions: OutputOptions
        @OptionGroup public var ascOptions: ASCOptions

        @Option(name: .shortAndLong, help: ArgumentHelp("The base directory for downloading package"))
        public var directory: String?

        @Option(help: ArgumentHelp("The identifier for the Alternative Distribution Package"))
        public var adpid: String?

        @Option(help: ArgumentHelp("The version ID of the release for the Alternative Distribution Package"))
        public var versionid: String?

//        @Option(help: ArgumentHelp("The name of the app for the Alternative Distribution Package"))
//        public var appname: String?

        public static var configuration = CommandConfiguration(
            commandName: "download",
            abstract: "Download the Alternative Distribution Package",
            usage: """
            """)

        public typealias Output = AppStoreConnectEndpoint.AlternativeDistributionPackage.Response

        public init() {
        }

        public func validate() throws {
            if adpid == nil && versionid == nil {
                throw ValidationError("Either --appid or --versionid must be specified")
            }
        }

        public func run() async throws {
            let endpoint = try createASCEndpoint()
            let adpid = try await endpoint.resolveADPID(from: self.adpid, versionID: self.versionid)
            let (manifest, files) = try await endpoint.downloadADP(adpid: adpid, directory: directory, logger: { msg(.info, $0) })
            let (_, _) = (manifest, files)
        }
    }

    public struct GetADPVersionCommand: ASCCommand {
        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var outputOptions: OutputOptions
        @OptionGroup public var ascOptions: ASCOptions

        @Argument(help: "The version ID for the ADP")
        public var versionID: String

        public static var configuration = CommandConfiguration(
            commandName: "adpversion",
            abstract: "Get ADP version for a release")

        public typealias Output = AppStoreConnectEndpoint.AlternativeDistributionPackage.Response

        public init() {
        }

        public func run() async throws {
            let response = try await createASCEndpoint().request(AppStoreConnectEndpoint.AlternativeDistributionPackage(id: versionID))
            try msgOptions.writeOutput(response)
        }
    }

    public struct GetADPInfoCommand: ASCCommand {
        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var outputOptions: OutputOptions
        @OptionGroup public var ascOptions: ASCOptions

        @Argument(help: "The version ID for the ADP")
        public var adpID: String

        public static var configuration = CommandConfiguration(
            commandName: "adpinfo",
            abstract: "Get ADP info for a release")

        public typealias Output = AppStoreConnectEndpoint.AlternativeDistributionInfo.Response

        public init() {
        }

        public func run() async throws {
            let response = try await createASCEndpoint().request(AppStoreConnectEndpoint.AlternativeDistributionVersions(adpID: adpID))
            try msgOptions.writeOutput(response)
        }
    }
}

protocol ASCCommand : FairParsableCommand {
    var ascOptions: ASCOptions { get }
}

extension ASCCommand {
    func createASCEndpoint() throws -> AppStoreConnectEndpoint {
        let keystorePath = ascOptions.keystore ?? fairtoolDefaultKeystorePath
        if !FileManager.default.isReadableFile(atPath: keystorePath) {
            throw AppError("Could not read the fastlane API Key JSON file at location specified by --keystore argument or 'FAIRTOOL_ASC_API_KEY_FILE' environment or default location: \(keystorePath)")
        }
        let keystoreURL = URL(filePath: keystorePath)
        let endpoint = try AppStoreConnectEndpoint(keystoreURL: keystoreURL, requestRetryCount: ascOptions.ascRequestRetryCount)
        return endpoint
    }

}

public struct ASCOptions: ParsableArguments {
    @Option(help: ArgumentHelp("The path to the fastlane API Key JSON file", valueName: "keystore"))
    public var keystore: String?

    @Option(help: ArgumentHelp("The number of times to retry failed requests", valueName: "retries"))
    public var ascRequestRetryCount: Int = 5

    public init() {
    }
}
