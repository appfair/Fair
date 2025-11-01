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
            let response = try await createEndpoint().request(AppStoreConnectEndpoint.RawRequest(path: path))
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
            let response = try await createEndpoint().request(AppStoreConnectEndpoint.ListAppsRequest())
            try msgOptions.writeOutput(response)
        }
    }

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
            abstract: "Download the Alternative Distribution Package")

        public typealias Output = AppStoreConnectEndpoint.AlternativeDistributionPackage.Response

        public init() {
        }

        public func validate() throws {
            if adpid == nil && versionid == nil {
                throw ValidationError("Either --appid or --versionid must be specified")
            }
        }

        public func run() async throws {
            let endpoint = try createEndpoint()

            var adpid = self.adpid

            if let versionid {
                // version id was specified; fetch the version endpoint and get the adpid from it
                let versions = try await endpoint.request(AppStoreConnectEndpoint.AlternativeDistributionPackage(id: versionid))

                if msgOptions.verbose {
                    try msgOptions.writeOutput(versions)
                }

                guard let versionsData = versions.data else {
                    throw AppError("Response did not contain any data payload")
                }

                if versionsData.type != "alternativeDistributionPackages" {
                    throw AppError("Response did not contain an alternative distribution package")
                }

                adpid = versionsData.id
            }

            guard let adpid else {
                throw ValidationError("Either --appid or --versionid must be specified")
            }

            let adpVersions = try await endpoint.request(AppStoreConnectEndpoint.AlternativeDistributionVersions(adpID: adpid))
            if msgOptions.verbose {
                try msgOptions.writeOutput(adpVersions)
            }

            // TODO: wait for completed?
            guard let adpVersionsData = adpVersions.data else {
                throw AppError("No data in response")
            }

            guard let completedADPVersion = adpVersionsData.first(where: { $0.attributes.state == "COMPLETED" }) else {
                throw AppError("No completed version found for this ADP: \(adpVersionsData.map(\.attributes.state).joined(separator: ", "))")
            }

            guard let manifestSignatureZipURL = completedADPVersion.attributes.url else {
                throw AppError("No download URL found for ADP")
            }

            // download the URL and unzip manifest.json and signature to the directory
            let (downloadFile, response) = try await URLSession.shared.downloadFile(for: URLRequest(url: manifestSignatureZipURL, cachePolicy: .returnCacheDataElseLoad))
            try response.validateHTTPCode()
            defer { try? FileManager.default.removeItem(at: downloadFile) }

            //let adpReleaseID = completedADPVersion.id
            let expandPath = URL(fileURLWithPath: self.directory ?? FileManager.default.currentDirectoryPath).appendingPathComponent(adpid, isDirectory: true)

            if expandPath.pathIsDirectory {
                try FileManager.default.trash(url: expandPath)
            }
            try FileManager.default.unzipItem(at: downloadFile, to: expandPath)

            let signaturePath = expandPath.appendingPathComponent("signature", isDirectory: false)
            if !signaturePath.pathIsRegularFile {
                throw ValidationError("signature file not found in ADP package at \(expandPath.path)")
            }
            let manifestPath = expandPath.appendingPathComponent("manifest.json", isDirectory: false)
            if !manifestPath.pathIsRegularFile {
                throw ValidationError("manifest.json file not found in ADP package at \(expandPath.path)")
            }

            let manifest = try JSONDecoder().decode(ADPManifest.self, from: Data(contentsOf: manifestPath))
            if msgOptions.verbose {
                try msgOptions.writeOutput(manifest)
            }

            func downloadAsset(from sourceURL: URL, to destinationPath: String, checksum: String?) async throws {
                // TODO: retry options
                let (downloadDeltaFile, response) = try await URLSession.shared.downloadFile(for: URLRequest(url: sourceURL, cachePolicy: .returnCacheDataElseLoad))
                try response.validateHTTPCode()
                let destination = expandPath.appending(path: destinationPath)
                try FileManager.default.moveItem(at: downloadDeltaFile, to: destination)
                if let checksum {
                    // validate the checksum if it is specified
                    let fileChecksum = try Data(contentsOf: destination).sha256().hex()
                    if checksum.lowercased() != fileChecksum.lowercased() {
                        throw AppError("Checksum of downloaded file \(fileChecksum) does not match expected value \(checksum) at: \(destination.path)")
                    }
                }
            }

            /// A response for either the variants or deltas
            struct DownloadResponse : Codable {
                let data: DownloadData?

                struct DownloadData : Codable {
                    let type: String // "alternativeDistributionPackageVariants" or "alternativeDistributionPackageDeltas"
                    let id: UUID // "219750db-80c2-4c75-aecc-fa67835f384d"
                    let attributes: Attributes
                    struct Attributes : Codable {
                        let url: URL // "<Apple_CDN_base_URL>/mzpse.7668245576990498917.ipa?accessKey=<access_key>"
                        let urlExpirationDate: Date
                        let alternativeDistributionKeyBlob: String // "<key_blob_base64_encoded_string>"
                    }
                }
            }

            // Store the app data at an expected path
            // https://developer.apple.com/documentation/marketplacekit/ingesting-an-alternative-distribution-package#Store-the-app-data-at-an-expected-path

            // download each of the variants
            // https://developer.apple.com/documentation/marketplacekit/ingesting-an-alternative-distribution-package#Download-app-variants
            // GET https://api.appstoreconnect.apple.com/alternativeDistributionPackageVariants/219750db-80c2-4c75-aecc-fa67835f384d

            guard let variantsRelationship = completedADPVersion.relationships["variants"] else {
                throw ValidationError("No variants found for ADP")
            }
            _ = variantsRelationship // TODO: cross-reference variants result with manifest variants to validate
            let variantsFolder = expandPath.appendingPathComponent("variant", isDirectory: true)
            try FileManager.default.createDirectory(at: variantsFolder, withIntermediateDirectories: false)
            for variantInfo in manifest.variants {
                let variantPath = variantInfo.assetPath
                let variantID = variantInfo.publicId
                let variantChecksums = variantInfo.variantDetails.hashes.first(where: { $0.algorithm == "sha256" })?.encryptedChunkDigests

                struct ADPVariantRequest : APIRequest {
                    typealias Response = DownloadResponse
                    let variantID: UUID
                    func queryURL(for service: AppStoreConnectEndpoint) -> URL {
                        service.endpointBase.appending(components: "alternativeDistributionPackageVariants", variantID.uuidString.lowercased())
                    }
                }

                let variantResponse = try await endpoint.request(ADPVariantRequest(variantID: variantID))
                if msgOptions.verbose {
                    try msgOptions.writeOutput(variantResponse)
                }

                guard let variantResponseData = variantResponse.data else {
                    throw AppError("No data returned from API")
                }

                try await downloadAsset(from: variantResponseData.attributes.url, to: variantPath, checksum: variantChecksums?.count == 1 ? variantChecksums?.first : nil)
            }


            // download each of the deltas (optional; might not be included in the initial reported version)
            // “When App Store Connect sends a new app version notification, it sends an app distribution package that includes the variants first, followed by another for deltas, if any are available for the app. Deltas arrive an unspecified amount of time after the app’s variants. You don’t need to wait for deltas to arrive before serving the new app to devices. Rather, App Store Connect sends variants first to expedite the app’s availability for customers.”
            // https://developer.apple.com/documentation/marketplacekit/ingesting-an-alternative-distribution-package#Download-app-deltas
            guard let deltasRelationship = completedADPVersion.relationships["deltas"] else {
                throw ValidationError("No deltas found for ADP")
            }
            _ = deltasRelationship // TODO: cross-reference deltas result with manifest deltas to validate
            let deltasFolder = expandPath.appendingPathComponent("delta", isDirectory: true)
            try FileManager.default.createDirectory(at: deltasFolder, withIntermediateDirectories: false)
            for deltaInfo in manifest.deltas {
                let deltaPath = deltaInfo.assetPath
                let deltaID = deltaInfo.publicId
                let deltaChecksums = deltaInfo.deltaDetails.hashes.first(where: { $0.algorithm == "sha256" })?.encryptedChunkDigests

                // now query the deltas endpoint to get the download URL
                struct ADPDeltaRequest : APIRequest {
                    typealias Response = DownloadResponse
                    let deltaID: UUID
                    func queryURL(for service: AppStoreConnectEndpoint) -> URL {
                        service.endpointBase.appending(components: "alternativeDistributionPackageDeltas", deltaID.uuidString.lowercased())
                    }
                }

                let deltaResponse = try await endpoint.request(ADPDeltaRequest(deltaID: deltaID))
                if msgOptions.verbose {
                    try msgOptions.writeOutput(deltaResponse)
                }

                guard let deltaResponseData = deltaResponse.data else {
                    throw AppError("No data in response")
                }
                try await downloadAsset(from: deltaResponseData.attributes.url, to: deltaPath, checksum: deltaChecksums?.count == 1 ? deltaChecksums?.first : nil)
            }
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
            let response = try await createEndpoint().request(AppStoreConnectEndpoint.AlternativeDistributionPackage(id: versionID))
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
            let response = try await createEndpoint().request(AppStoreConnectEndpoint.AlternativeDistributionVersions(adpID: adpID))
            try msgOptions.writeOutput(response)
        }
    }
}

protocol ASCCommand : FairParsableCommand {
    var ascOptions: ASCOptions { get }
}

extension ASCCommand {
    func createEndpoint() throws -> AppStoreConnectEndpoint {
        let keystorePath = ascOptions.keystore ?? fairtoolDefaultKeystorePath
        if !FileManager.default.isReadableFile(atPath: keystorePath) {
            throw AppError("Could not read the fastlane API Key JSON file at location specified by --keystore argument or 'FAIRTOOL_ASC_API_KEY_FILE' environment or default location: \(keystorePath)")
        }
        let keystoreURL = URL(filePath: keystorePath)
        let endpoint = try AppStoreConnectEndpoint(keystoreURL: keystoreURL)
        return endpoint
    }
}

public struct ASCOptions: ParsableArguments {
    @Option(help: ArgumentHelp("The path to the fastlane API Key JSON file", valueName: "keystore"))
    public var keystore: String?

    public init() {
    }
}
