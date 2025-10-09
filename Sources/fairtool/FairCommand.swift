import Foundation
import FairCore
import FairExpo
import ArgumentParser

public struct FairCommand : AsyncParsableCommand {
    public static let experimental = false
    public static var configuration = CommandConfiguration(commandName: "fair",
                                                           abstract: "Fairground app utility commands.",
                                                           shouldDisplay: !experimental,
                                                           subcommands: [
                                                            ValidateCommand.self,
                                                            CatalogCommand.self,
                                                            MergeCommand.self,
                                                            MetadataCommand.self,
                                                           ])

    public init() {
    }
}

extension FairCommand {
    public struct OrgOptions: ParsableArguments {
        @Option(name: [.long, .customShort("g")], help: ArgumentHelp("The repository to use."))
        public var org: String

        public init() { }

//        var isCatalogApp: Bool {
//            self.org == Bundle.catalogBrowserAppOrg
//        }

        /// Returns `App Name`
        func appNameSpace() throws -> String {
            self.org.dehyphenated()
        }

        /// Loads all the entitlements and matches them to corresponding UsageDescription entires in the app's Info.plist file.
        @discardableResult
        func checkEntitlements(entitlementsURL: URL, infoProperties: Plist, needsSandbox: Bool) throws -> Array<AppEntitlementPermission> {
            let entitlements_dict = try Plist(url: entitlementsURL)

            if needsSandbox == true && entitlements_dict.rawValue[AppEntitlement.app_sandbox.entitlementKey] as? NSNumber != true {
                // despite having LSFileQuarantineEnabled=false and `com.apple.security.files.user-selected.executable`, apps that the catalog browser app writes cannot be launched; the only solution seems to be to disable sandboxing, which is a pity…
//                if !self.isCatalogApp {
//                    throw FairToolCommand.Errors.sandboxRequired
//                }
            }

            var permissions: [AppEntitlementPermission] = []

            // Check that the given entitlement is permitted, and that entitlements that require a usage description are specified in the app's Info.plist `FairUsage` dictionary
            func check(_ entitlement: AppEntitlement) throws -> (usage: String, value: Any)? {
                guard let entitlementValue = entitlements_dict.rawValue[entitlement.entitlementKey] else {
                    return nil // no entitlement set
                }

                if (entitlementValue as? NSNumber) == false {
                    return nil // false entitlements are treated as unset
                }

                // a nil usage description means the property is explicitely forbidden (e.g., "files-all")
                guard let props = entitlement.usageDescriptionProperties else {
                    throw FairToolCommand.Errors.forbiddenEntitlement(entitlement.entitlementKey)
                }

                // on the other hand, an empty array means we don't require any explanation for the entitlemnent's usage (e.g., enabling JIT)
                if props.isEmpty {
                    return nil
                }

                guard let usageDescription = props.compactMap({
                    // the usage is contained in the `FairUsage` dictionary of the Info.plist; the key is simply the entitlement name
                    infoProperties.FairUsage?[$0] as? String

                    // TODO: perhaps also permit the sub-set of top-level usage description properties like "NSDesktopFolderUsageDescription", "NSDocumentsFolderUsageDescription", and "NSLocalNetworkUsageDescription"
                    // ?? infoProperties[$0] as? String
                }).first else {
                    throw FairToolCommand.Errors.missingUsageDescription(entitlement)
                }

                if usageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw FairToolCommand.Errors.missingUsageDescription(entitlement)
                }

                return (usageDescription, entitlementValue)
            }

            for entitlement in AppEntitlement.allCases {
                if let (usage, _) = try check(entitlement) {
                    permissions.append(AppEntitlementPermission(entitlement: entitlement, usageDescription: usage))
                }
            }

            return permissions
        }
    }
}

extension FairCommand {
    public struct MergeCommand: FairParsableCommand {
        public static let experimental = false
        public typealias Output = Never
        public static var configuration = CommandConfiguration(commandName: "merge",
                                                               abstract: "Merge base fair-ground updates into the project.",
                                                               shouldDisplay: !experimental)
        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var outputOptions: OutputOptions
        @OptionGroup public var projectOptions: ProjectOptions
        @OptionGroup public var regOptions: RegOptions
        @OptionGroup public var validateOptions: ValidateOptions
        @OptionGroup public var orgOptions: OrgOptions
        @OptionGroup public var hubOptions: HubOptions

        public init() { }

        public mutating func run() async throws {
            warnExperimental(Self.experimental)
            msg(.info, "merge")

            if outputOptions.outputDirectoryFlag == projectOptions.projectPathFlag {
                throw FairToolCommand.Errors.sameOutputAndProjectPath(outputOptions.outputDirectoryFlag, projectOptions.projectPathFlag)
            }

            let outputURL = URL(fileURLWithPath: outputOptions.outputDirectoryFlag)
            let projectURL = URL(fileURLWithPath: projectOptions.projectPathFlag)
            if outputURL.absoluteString == projectURL.absoluteString {
                throw FairToolCommand.Errors.sameOutputAndProjectPath(outputOptions.outputDirectoryFlag, projectOptions.projectPathFlag)
            }

            // try await validate() // always validate first

            var vc = ValidateCommand()
            vc.msgOptions = self.msgOptions
            vc.hubOptions = self.hubOptions
            vc.validateOptions = self.validateOptions
            vc.orgOptions = self.orgOptions
            vc.projectOptions = self.projectOptions
            vc.regOptions = self.regOptions
            try await vc.run()

            /// Attempt to copy the path from the projectPath to the outputPath,
            /// thereby selectively merging parts of the PR with a customizable transform
            @discardableResult func pull(_ path: String, transform: ((Data) throws -> Data)? = nil) throws -> URL {
                msg(.info, "copying", path, "from", projectURL.path, "to", outputURL.path)
                let outputSrc = outputURL.appendingPathComponent(path)
                msg(.debug, "outputSrc", outputSrc)
                if fm.isDirectory(url: outputSrc) != nil {
                    try fm.trash(url: outputSrc) // clobber the existing path if it exists
                }

                let projectSrc = projectURL.appendingPathComponent(path)
                if let transform = transform { // only peform the transform if the closure is specified…
                    let sourceData = try Data(contentsOf: projectSrc)
                    try transform(sourceData).write(to: outputSrc) // transform the data and write it back out
                } else { // …otherwise simply copy the resource
                    try fm.copyItem(at: projectSrc, to: outputSrc)
                }

                return outputSrc
            }

            // if validation passes, we can copy up the output sources
            try pull("sandbox-macos.entitlements")
            try pull("sandbox-ios.entitlements")

            // copy up the assets, sources, and other metadata
            try pull("appfair.xcconfig")
            try pull("project.xcodeproj")
            try pull("App.yml")
            try pull("Info.plist")
            try pull("Assets.xcassets")
            try pull("README.md")
            try pull("Sources")
            try pull("Tests")

            try pull("Package.swift") { data in
                // We manually copy over the package validations so that we do not require that the user always keep the validations current

                // try compareContents(of: "Package.swift", partial: true, warn: true, guardLine: Self.packageValidationLine)

                //            guard let packageURL = self.basePathURL(path: "Package.swift") else {
                //                throw CocoaError(.fileReadNoSuchFile)
                //            }
                //
                //            let packageTemplate = try String(contentsOf: packageURL, encoding: .utf8).components(separatedBy: Self.packageValidationLine)
                //            if packageTemplate.count != 2 {
                //                throw CocoaError(.fileReadNoSuchFile)
                //            }
                //
                //            let str1 = String(data: data, encoding: .utf8) ?? ""
                //            let str2 = packageTemplate[1]
                //            return (str1 + str2).utf8Data

                return data
            }
        }
    }
}

extension FairCommand {
    public struct ValidateOptions: ParsableArguments {
        @Option(name: [.long], help: ArgumentHelp("The IR title"))
        public var integrationTitle: String?

        @Option(name: [.long, .customShort("b")], help: ArgumentHelp("The base path."))
        public var base: String?

        @Option(name: [.long], help: ArgumentHelp("Commit ref to validate."))
        public var ref: String?

        public init() { }
    }

    public struct ValidateCommand: FairParsableCommand {
        public static let experimental = false
        public typealias Output = Never
        public static var configuration = CommandConfiguration(commandName: "validate",
                                                               abstract: "Validate the project.",
                                                               shouldDisplay: !experimental)
        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var hubOptions: HubOptions
        @OptionGroup public var regOptions: RegOptions
        @OptionGroup public var validateOptions: ValidateOptions
        @OptionGroup public var orgOptions: OrgOptions
        @OptionGroup public var projectOptions: ProjectOptions


        public init() { }

        public mutating func run() async throws {
            warnExperimental(Self.experimental)
            msg(.info, "Validating project:", projectOptions.projectPathURL(path: "").path)
            //msg(.debug, "flags:", flags)

            let orgName = orgOptions.org

            // check whether we are validating as the upstream origin or
            let isFork = try orgName != hubOptions.fairHub().org
            //dbg("isFork", isFork, "hubFlag", hubFlag, "orgName", orgName, "fairHub().org", try! fairHub().org)

            /// Verifies that the given plist contains the specified value
            func check(_ plist: Plist, key: String, in expected: [String], empty: Bool = false, url: URL) throws {
                if plist.rawValue[key] == nil && empty == true {
                    return // permit empty values
                }

                guard let actual = plist.rawValue[key] as? NSObject else {
                    throw FairToolCommand.Errors.invalidPlistValue(key, expected, nil, url)
                }

                if !expected.isEmpty && !expected.map({ $0 as NSObject }).contains(actual) {
                    throw FairToolCommand.Errors.invalidPlistValue(key, expected, actual, url)
                }
            }

            /// Checks that the contents at the given path match the
            /// contents of the local resources at the same path
            /// - Parameters:
            ///   - path: the relative path of the resource
            ///   - partial: whether to validate partially based on the guard line
            ///   - warn: whether to warn rather than raise an error
            ///   - guardLine: the string to use to split the valiation string into prefix/suffix parts
            /// - Throws: a validation error
            @discardableResult func compareContents(of path: String, partial: Bool, warn: Bool = false, guardLine: String? = nil) throws -> Bool {
                msg(.debug, "  comparing \(partial ? "partial" : "exact") match:", path)
                let projectURL = projectOptions.projectPathURL(path: path)
                let projectSource = try String(contentsOf: projectURL, encoding: .utf8)

                // when this is not a fork (i.e., it is the root fairground), we always validate
                do {
                    try compareScaffold(project: projectSource, path: path, afterLine: !isFork ? nil : partial ? guardLine : nil)
                } catch {
                    if warn {
                        msg(.warn, "  failed \(partial ? "partial" : "exact") match:", path)
                        return false // we failed validation
                    } else {
                        throw error
                    }
                }
                return true
            }

            /// Loads the data for the project file at the given relative path
            func basePathURL(path: String) -> URL? {
                guard let basePathFlag = validateOptions.base else { return nil }
                return URL(fileURLWithPath: path, isDirectory: false, relativeTo: URL(fileURLWithPath: basePathFlag, isDirectory: true))
            }

            /// Validates that the given project source matches the given scaffold source
            func compareScaffold(project projectSource: String, path: String, afterLine guardLine: String? = nil) throws {
                msg(.debug, "checking:", path, "against base path:", validateOptions.base)
                guard let scaffoldURL = basePathURL(path: path) else {
                    throw CocoaError(.fileReadNoSuchFile)
                }

                let scaffoldSource = try String(contentsOf: scaffoldURL, encoding: .utf8)

                if scaffoldSource != projectSource {
                    // check for partial matches, which means that we only compare the header parts of the files
                    if let guardLine = guardLine {
                        let scaffoldParts = scaffoldSource.components(separatedBy: guardLine)
                        let projectParts = projectSource.components(separatedBy: guardLine)
                        if scaffoldParts.count < 2
                            || projectParts.count < 2
                            || scaffoldParts.last != projectParts.last {
                            throw FairToolCommand.Errors.invalidContents(scaffoldParts.last, projectParts.last, path, Self.firstDifferentLine(scaffoldParts.last ?? "", projectParts.last ?? ""))
                        }
                    } else {
                        throw FairToolCommand.Errors.invalidContents(scaffoldSource, projectSource, path, Self.firstDifferentLine(scaffoldSource, projectSource))
                    }
                }
            }

            // the generic term for the base folder is "App-Name"
            let appOrgName = !isFork ? "App-Name" : orgName

            // 1. Check Info.plist
            let infoProperties: Plist
            do {
                let path = "Info.plist"
                msg(.debug, "comparing metadata:", path)
                let infoPlistURL = projectOptions.projectPathURL(path: path)
                let plist_dict = try Plist(url: infoPlistURL)

                infoProperties = plist_dict

                func checkStr(key: PropertyListKey, in strings: [String]) throws {
                    try check(plist_dict, key: key.plistKey, in: strings, url: infoPlistURL)
                }

                // check that the Info.plist contains the correct values for certain keys

                // ensure the Info.plist uses the correct constants
                try checkStr(key: .CFBundleName, in: ["$(PRODUCT_NAME)"])
                try checkStr(key: .CFBundleIdentifier, in: ["$(PRODUCT_BUNDLE_IDENTIFIER)"])
                try checkStr(key: .CFBundleExecutable, in: ["$(EXECUTABLE_NAME)"])
                try checkStr(key: .CFBundlePackageType, in: ["$(PRODUCT_BUNDLE_PACKAGE_TYPE)"])
                try checkStr(key: .CFBundleVersion, in: ["$(CURRENT_PROJECT_VERSION)"])
                try checkStr(key: .CFBundleShortVersionString, in: ["$(MARKETING_VERSION)"])
                try checkStr(key: .LSApplicationCategoryType, in: ["$(APP_CATEGORY)"])

                let licenseFlag = self.regOptions.license
                if !licenseFlag.isEmpty {
                    try checkStr(key: .NSHumanReadableCopyright, in: licenseFlag)
                }
            }

            // 2. Check appfair.xcconfig
            do {
                let appOrgNameSpace = appOrgName.dehyphenated()
                //let appID = "app." + appOrgName

                let settings = try projectOptions.buildSettings()

                guard let appName = settings["PRODUCT_NAME"] else {
                    throw AppError(NSLocalizedString("Missing PRODUCT_NAME in appfair.xcconfig", bundle: .module, comment: "error message"))
                }

                if appName != appOrgNameSpace {
                    throw AppError(String(format: NSLocalizedString("Expected PRODUCT_NAME in appfair.xcconfig (“%@”) to match the organization name (“%@”)", bundle: .module, comment: "error message"), arguments: [appName, appOrgNameSpace]))
                }

                guard let appVersion = settings.appVersion else {
                    throw AppError(NSLocalizedString("Missing MARKETING_VERSION in appfair.xcconfig", bundle: .module, comment: "error message"))
                }

                let expectedIntegrationTitle = appName + " " + appVersion.versionString

                if let integrationTitle = self.validateOptions.integrationTitle,
                   integrationTitle != expectedIntegrationTitle {
                    throw FairToolCommand.Errors.invalidIntegrationTitle(integrationTitle, expectedIntegrationTitle)
                }

                //let buildVersion = try FairHub.AppBuildVersion(plistURL: infoPlistURL)
                //msg(.info, "Version", buildVersion.version.versionDescription, "(\(buildVersion.build))")
            }

            // 3. Check sandbox-*.entitlements
            for path in ["sandbox-macos.entitlements", "sandbox-ios.entitlements"] {
                msg(.debug, "comparing entitlements:", path)
                let entitlementsURL = projectOptions.projectPathURL(path: path)
                try orgOptions.checkEntitlements(entitlementsURL: entitlementsURL, infoProperties: infoProperties, needsSandbox: entitlementsURL.lastPathComponent == "sandbox-macos.entitlements")
            }

            // 4. Check LICENSE.txt, etc.
            try compareContents(of: "LICENSE.AGPL", partial: false)
            try compareContents(of: "LICENSE_EXCEPTION.FAIR", partial: false)
            try compareContents(of: "CONTRIBUTION.txt", partial: false)

            // 5. Check Package.swift; we only warn, because the `merge` process will append the authoratative checks to the Package.swift file
            try compareContents(of: "Package.swift", partial: true, warn: true, guardLine: Self.packageValidationLine)
            try compareContents(of: "xcode.swift", partial: false)

            // 6. Check Sources/
            try compareContents(of: "Sources/App/AppMain.swift", partial: false)

            // 7. Check Package.resolved if it exists and we've specified the hub to validate
            if let packageResolvedData = try? load(url: projectOptions.projectPathURL(path: "Package.resolved")) {
                msg(.debug, "validating Package.resolved")
                let packageResolved = try ResolvedPackage.ResolvedPackageV2(fromJSON: packageResolvedData)
                if let httpHost = URL(string: "https://\(hubOptions.hub)")?.host, let hubURL = URL(string: "https://\(httpHost)") {
                    // all dependencies must reside at the same fairground
                    // TODO: add include-hub/exclude-hub flags to permit cross-fairground dependency networks
                    // e.g., permit GitLab apps depending on projects in GitHub repos
                    let host = hubURL.deletingLastPathComponent().deletingLastPathComponent()
                    //dbg("verifying hub host:", host)
                    for pin in packageResolved.pins {
                        if pin.location.hasPrefix(host.absoluteString) == false
                            && pin.location.hasPrefix("https://fair-ground.org/") == false {
                            throw FairToolCommand.Errors.badRepository(host.absoluteString, pin.location)
                        }
                    }
                }
            }

            // also verify the hub if we have specified it in the arguments
            if hubOptions.hub != "" {
                try await verify(org: orgName, repo: appName, hub: hubOptions.fairHub())
            }

            msg(.info, "Successfully validated project:", projectOptions.projectPathURL(path: "").path)


            // validate the reference
            if let refFlag = validateOptions.ref {
                try await validateCommit(ref: refFlag, hub: hubOptions.fairHub())
            }
        }

        func verify(org: String, repo repoName: String, hub: FairHub) async throws {
            // when the app we are validating is the actual hub's root organization, use special validation rules (such as not requiring issues)
            msg(.info, "Validating App-Name:", org)

            let response = try await hub.request(FairHub.RepositoryQuery(owner: org, name: repoName)).get().data
            let organization = response.organization
            let repo = organization.repository

            msg(.debug, "  name:", organization.name)
            msg(.debug, "  isInOrganization:", repo.isInOrganization)
            msg(.debug, "  has_issues:", repo.hasIssuesEnabled)
            msg(.debug, "  discussion categories:", repo.discussionCategories.totalCount)

            let configuration = try self.regOptions.createProjectConfiguration()
//            let invalid = hub.validate(org: organization, configuration: configuration)
//            if !invalid.isEmpty {
//                throw FairHub.Errors.repoInvalid(invalid, org, repoName)
//            }
        }
    }
}

extension FairCommand {
//    public struct FairsealCommand: FairParsableCommand {
//
//        public struct SealOptions: ParsableArguments {
//            @Option(name: [.long], help: ArgumentHelp("URL for the artifact that will be generated."))
//            public var artifactURL: String?
//
//            @Option(name: [.long], help: ArgumentHelp("The artifact created in a trusted environment."))
//            public var trustedArtifact: String?
//
//            @Option(name: [.long], help: ArgumentHelp("The artifact created in an untrusted environment."))
//            public var untrustedArtifact: String?
//
//            @Option(name: [.long], help: ArgumentHelp("The artifact staging folder."))
//            public var artifactStaging: [String] = []
//
//            @Option(name: [.long], help: ArgumentHelp("The number of diffs for a build to be reproducible.", valueName: "count"))
//            public var permittedDiffs: Int?
//
//            @Option(name: [.long], help: ArgumentHelp("The disassembler to use for comparing binaries.", valueName: "cmd"))
//            public var disassembler: String?
//
//            @Option(name: [.long], help: ArgumentHelp("The issue number for posting the fairseal."))
//            public var postIssue: Int?
//
//            public init() { }
//        }
//
//
//        public static let experimental = false
//        public typealias Output = Never
//        public static var configuration = CommandConfiguration(commandName: "fairseal",
//                                                               abstract: "Generates fairseal from trusted artifact.",
//                                                               shouldDisplay: !experimental)
//        @OptionGroup public var msgOptions: MsgOptions
//        @OptionGroup public var hubOptions: HubOptions
//        @OptionGroup public var sealOptions: SealOptions
//        @OptionGroup public var retryOptions: RetryOptions
//        @OptionGroup public var iconOptions: IconOptions
//        @OptionGroup public var orgOptions: OrgOptions
//        @OptionGroup public var projectOptions: ProjectOptions
//
//        public init() { }
//
//        public mutating func run() async throws {
//            warnExperimental(Self.experimental)
//            msg(.info, "Fairseal")
//
//            guard let trustedArtifactFlag = sealOptions.trustedArtifact else {
//                throw FairToolCommand.Errors.missingFlag("-trusted-artifact")
//            }
//
//            let trustedArtifactURL = URL(fileURLWithPath: trustedArtifactFlag)
//            guard let trustedArchive = try? ZipArchive(url: trustedArtifactURL, accessMode: .read, preferredEncoding: .utf8) else {
//                throw AppError(String(format: NSLocalizedString("Error opening trusted archive: %@", bundle: .module, comment: "error message"), arguments: [trustedArtifactURL.absoluteString]))
//            }
//
//            let untrustedArtifactLocalURL = try await fetchUntrustedArtifact()
//
//            guard let untrustedArchive = try? ZipArchive(url: untrustedArtifactLocalURL, accessMode: .read, preferredEncoding: .utf8) else {
//                throw AppError(String(format: NSLocalizedString("Error opening untrusted archive: %@", bundle: .module, comment: "error message"), arguments: [untrustedArtifactLocalURL.absoluteString]))
//            }
//
//            if untrustedArtifactLocalURL == trustedArtifactURL {
//                throw AppError(NSLocalizedString("Trusted and untrusted artifacts may not be the same", bundle: .module, comment: "error message"))
//            }
//
//            // Load the zip entries, skipping over signature entries we are exlcuding from the comparison
//            func readEntries(_ archive: ZipArchive) -> [ZipArchive.Entry] {
//                Array(archive.makeIterator())
//                    .filter { entry in
//                        // these can be in either _CodeSignature or Contents
//                        !entry.path.hasSuffix("/CodeSignature")
//                        && !entry.path.hasSuffix("/CodeResources")
//                        && !entry.path.hasSuffix("/CodeDirectory")
//                        && !entry.path.hasSuffix("/CodeRequirements-1")
//                    }
//            }
//
//            let trustedEntries = readEntries(trustedArchive)
//            let untrustedEntries = readEntries(untrustedArchive)
//
//            if trustedEntries.count != untrustedEntries.count {
//                throw AppError(String(format: NSLocalizedString("Trusted and untrusted artifact content counts do not match (%lu vs. %lu)", bundle: .module, comment: "error message"), arguments: [trustedEntries.count, untrustedEntries.count]))
//            }
//
//            let rootPaths = Set(trustedEntries.compactMap({
//                $0.path.split(separator: "/")
//                    .drop(while: { $0 == "Payload" }) // .ipa archives store Payload/App Name.app/Info.plist
//                    .first
//            }))
//
//            guard rootPaths.count == 1, let rootPath = rootPaths.first, rootPath.hasSuffix(Self.appSuffix) else {
//                throw AppError(String(format: NSLocalizedString("Invalid root path in archive: %@", bundle: .module, comment: "error message"), arguments: [rootPaths.first?.description ?? ""]))
//            }
//
//            let appName = rootPath.dropLast(Self.appSuffix.count)
//
//            // TODO: we should instead check the `CFBundleExecutable` key for the executable name
//
//            let macOSExecutable = "\(appName).app/Contents/MacOS/\(appName)" // macOS: e.g., Photo Box.app/Contents/MacOS/Photo Box
//            let macOSInfo = "\(appName).app/Contents/Info.plist" // macOS: e.g., Photo Box.app/Contents/MacOS/Photo Box
//
//            let iOSExecutable = "Payload/\(appName).app/\(appName)" // iOS: e.g., Photo Box.app/Photo Box
//            let iOSInfo = "Payload/\(appName).app/Info.plist"
//
//            let executablePaths = [
//                macOSExecutable,
//                iOSExecutable,
//            ]
//
//            var infoPlist: Plist? = nil
//
//            var coreSize: UInt64 = 0 // the size of the executable itself
//
//            for (trustedEntry, untrustedEntry) in zip(trustedEntries, untrustedEntries) {
//                if trustedEntry.path != untrustedEntry.path {
//                    throw AppError(String(format: NSLocalizedString("Trusted and untrusted artifact content paths do not match: %@ vs. %@", bundle: .module, comment: "error message"), arguments: [trustedEntry.path, untrustedEntry.path]))
//                }
//
//                let entryIsMainBinary = executablePaths.contains(trustedEntry.path)
//                let entryIsInfo = trustedEntry.path == macOSInfo || trustedEntry.path == iOSInfo
//
//                if entryIsMainBinary {
//                    coreSize = trustedEntry.uncompressedSize // the "core" size is just the size of the main binary itself
//                }
//
//                if entryIsInfo {
//                    // parse the compiled Info.plist for processing
//                    infoPlist = try withErrorContext("parsing plist entry: \(trustedEntry.path)") {
//                        try Plist(data: trustedArchive.extractData(from: trustedEntry))
//                    }
//                }
//
//                if trustedEntry.checksum == untrustedEntry.checksum {
//                    continue
//                }
//
//                // checksum mismatch: check the actual binary contents so we can summarize the differences
//                msg(.info, "checking mismached entry: \(trustedEntry.path)")
//
//                let pathParts = trustedEntry.path.split(separator: "/")
//
//                if pathParts.last == "Assets.car" {
//                    // assets are not deterministically compiled; we let these pass
//                    continue
//                }
//
//                if trustedEntry.path.hasSuffix(".nib") {
//                    // nibs sometimes get compiled differently as well
//                    continue
//                }
//
//                if pathParts.dropLast().last?.hasSuffix(".storyboardc") == true {
//                    // Storyboard files sometimes get compiled differently (e.g., differences in the date in Info.plist)
//                    continue
//                }
//
//
//                //msg(.debug, "checking", trustedEntry.path)
//
//                var trustedPayload = try trustedArchive.extractData(from: trustedEntry)
//                var untrustedPayload = try untrustedArchive.extractData(from: untrustedEntry)
//
//                // handles the dynamic library at: Payload/App Name.app/Frameworks/App.framework/App
//                let isExecutable = trustedPayload.starts(with: [0xfe, 0xed, 0xfa, 0xce]) // 32-bit magic
//                || trustedPayload.starts(with: [0xfe, 0xed, 0xfa, 0xcf]) // 64-bit magic
//                || trustedPayload.starts(with: [0xca, 0xfe, 0xba, 0xbe]) // universal magic
//                || trustedPayload.starts(with: [0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0x00, 0x00, 0x01]) // dylib
//
//                let isAppBinary = entryIsMainBinary || isExecutable
//
//                // the code signature is embedded in executables, but since since the trusted and un-trusted versions can be signed with different certificates (ad-hoc or otherwise), the code signature section in the compiled binary will be different; ideally we would figure out how to strip the signature from the data block itself, but for now just save to a temporary location, strip the signature using `codesign --remove-signature`, and then check the binaries again
//
//                // TODO: open as MachOBinary and compare individual segments
//
//
//#if os(macOS) // we can only launch `codesign` on macOS
//                // TODO: handle plug-ins like: Lottie Motion.app/Contents/PlugIns/Lottie Motion Quicklook.appex/Contents/MacOS/Lottie Motion Quicklook
//                if isAppBinary && trustedPayload != untrustedPayload {
//                    // save the given data to a temporary file
//                    func savetmp(_ data: Data, uuid: UUID = UUID()) throws -> URL {
//                        let tmpFile = URL.tmpdir.appendingPathComponent("fairbinary-" + uuid.uuidString)
//                        try data.write(to: tmpFile)
//                        return tmpFile
//                    }
//
//                    func stripSignature(from url: URL) async throws -> Data {
//                        try await Process.codesignStrip(url: url).expect()
//                        return try Data(contentsOf: url)
//                    }
//
//                    func disassemble(_ tool: String, from url: URL) async throws -> Data {
//                        try await Process.otool(tool: tool, url: url, params: ["-tVX"]).expect().stdout
//                    }
//
//                    if let otool = sealOptions.disassembler {
//                        msg(.info, "disassembling binary with \(otool) \(trustedEntry.path) \(trustedPayload.count) vs. \(untrustedPayload.count)")
//                        let uuid = UUID() // otool includes the path of the binary file in the output, so we need to use the same path for both files, since we'll be diffing the output
//                        trustedPayload = try await disassemble(otool, from: savetmp(trustedPayload, uuid: uuid))
//                        untrustedPayload = try await disassemble(otool, from: savetmp(untrustedPayload, uuid: uuid))
//                    } else {
//                        msg(.info, "stripping code signatures: \(trustedEntry.path)")
//                        trustedPayload = try await stripSignature(from: savetmp(trustedPayload))
//                        untrustedPayload = try await stripSignature(from: savetmp(untrustedPayload))
//                    }
//                }
//#endif
//
//                // the signature can change the binary size
//                //            if trustedEntry.uncompressedSize != untrustedEntry.uncompressedSize {
//                //                throw AppError("Trusted and untrusted artifact content size mismatch at \(trustedEntry.path): \(trustedEntry.uncompressedSize) vs. \(untrustedEntry.uncompressedSize)")
//                //            }
//
//                msg(.info, "comparing payloads \(trustedEntry.path) (\(trustedPayload.count)) vs. \(untrustedEntry.path) (\(untrustedPayload.count))")
//
//                if trustedPayload != untrustedPayload {
//                    //                    // if we don't permit any differences at all, then just throw an error
//                    //                    guard let permittedDiffs = sealOptions.permittedDiffs, permittedDiffs > 0 else {
//                    //                        throw AppError("Trusted and untrusted artifact mismatch at \(trustedEntry.path)")
//                    //                    }
//
//                    // otherwise calculate the total differences
//                    msg(.info, " scanning payload differences")
//                    let diff: CollectionDifference<UInt8> = trustedPayload.difference(from: untrustedPayload) // .inferringMoves()
//
//                    msg(.info, " checking mismached differences: \(diff.count)")
//
//                    msg(.info, " checking mismached entry: \(trustedEntry.path) SHA256 trusted: \(trustedPayload.sha256().hex()) untrusted: \(untrustedPayload.sha256().hex())")
//                    func offsets<T>(in changeSet: [CollectionDifference<T>.Change]) -> IndexSet {
//                        IndexSet(changeSet.map({
//                            switch $0 {
//                            case .insert(let offset, _, _): return offset
//                            case .remove(let offset, _, _): return offset
//                            }
//                        }))
//                    }
//
//                    //                    let insertionRanges = offsets(in: diff.insertions)
//                    //                    let insertionRangeDesc = insertionRanges
//                    //                        .rangeView
//                    //                        .prefix(10)
//                    //                        .map({ $0.description })
//                    //
//                    //                    let removalRanges = offsets(in: diff.removals)
//                    //                    let removalRangeDesc = removalRanges
//                    //                        .rangeView
//                    //                        .prefix(10)
//                    //                        .map({ $0.description })
//
//                    let totalChanges = diff.insertions.count + diff.removals.count
//                    if totalChanges > 0 {
//                        let permittedDiffs = sealOptions.permittedDiffs ?? 0
//
//                        let error = AppError("Trusted and untrusted artifact content mismatch at \(trustedEntry.path): \(diff.insertions.count) insertions and \(diff.removals.count) removals and totalChanges \(totalChanges) beyond permitted threshold: \(permittedDiffs)")
//
//
//                        if isAppBinary {
//                            if totalChanges < permittedDiffs {
//                                // when we are analyzing the app binary itself we need to tolerate some minor differences that seem to result from non-reproducible builds
//                                // TODO: instead of comparing the bytes of the binary, we should instead use MachOBinary to compare the content of the code pages, which would eliminate the need to strip the signatures
//                                msg(.info, "tolerating \(totalChanges) differences for: \(error)")
//                            } else {
//                                //for d in diff { }
//                                throw error
//                            }
//                        } else {
//                            throw error
//                        }
//                    }
//                }
//            }
//
//            var assets: [FairSeal.Asset] = []
//
//            // publish the hash for the artifact binary URL
//            if let artifactURLFlag = self.sealOptions.artifactURL, let artifactURL = URL(string: artifactURLFlag) {
//
//                // the staging folder contains raw assets (e.g., screenshots and README.md) that are included in a release
//                for stagingFolder in sealOptions.artifactStaging {
//                    let artifactAssets = try FileManager.default.contentsOfDirectory(at: projectOptions.projectPathURL(path: stagingFolder), includingPropertiesForKeys: [.fileSizeKey], options: [.skipsPackageDescendants])
//                        .sorting(by: \.lastPathComponent)
//                    msg(.info, "scanning assets:", artifactAssets.map(\.relativePath))
//
//                    for localURL in artifactAssets {
//                        guard let assetSize = localURL.fileSize() else {
//                            continue
//                        }
//
//                        // the published asset URL is the name of the local path relative to the download URL for the artifact
//                        let assetURL = artifactURL.deletingLastPathComponent().appendingPathComponent(localURL.lastPathComponent, isDirectory: false)
//                        if assetURL.lastPathComponent == artifactURL.lastPathComponent {
//                            let assetHash = try Data(contentsOf: untrustedArtifactLocalURL, options: .mappedIfSafe).sha256().hex()
//                            // the primary asset uses the special hash handling
//                            msg(.info, "hash for artifact:", assetURL.lastPathComponent, assetHash)
//                            assets.append(FairSeal.Asset(url: assetURL, size: assetSize, sha256: assetHash))
//                        } else {
//                            let assetHash = try Data(contentsOf: localURL, options: .mappedIfSafe).sha256().hex()
//                            // all other artifacts are hashed directly from their local counterparts
//                            assets.append(FairSeal.Asset(url: assetURL, size: assetSize, sha256: assetHash))
//                        }
//                    }
//                }
//            }
//
//            guard let plist = infoPlist else {
//                throw AppError(NSLocalizedString("Missing property list", bundle: .module, comment: "error message"))
//            }
//
//            var permissions: [AppEntitlementPermission] = []
//
//            for entitlementsURL in [
//                projectOptions.projectPathURL(path: "sandbox-macos.entitlements"),
//                projectOptions.projectPathURL(path: "sandbox-ios.entitlements"),
//            ] {
//                let perms = try orgOptions.checkEntitlements(entitlementsURL: entitlementsURL, infoProperties: plist, needsSandbox: entitlementsURL.lastPathComponent == "sandbox-macos.entitlements")
//                for permission in perms {
//                    msg(.info, "entitlement:", permission.type.rawValue, "usage:", permission.usageDescription)
//                }
//                permissions += perms
//            }
//
//            let tint = try? parseTintColor()
//
//            // extract the AppSource metadata for the item
//            let sourceInfo: AltCatalogItem? = {
//                guard let artifactURL = self.sealOptions.artifactURL,
//                      let url = URL(string: artifactURL) else {
//                    return nil
//                }
//                do {
//                    return try infoPlist?.appCatalogInfo(downloadURL: url)
//                } catch {
//                    msg(.warn, "error extracting AppSource from Info.plist")
//                    return nil
//                }
//            }()
//
//            // locate the metadata and parse the
//            let metadata = try projectOptions.metadata.flatMap { metadataPath in
//                try YAML.parse(Data(contentsOf: projectOptions.projectPathURL(path: metadataPath))).json()
//            }
//
//            let fairseal = FairSeal(metadata: metadata, assets: assets, permissions: permissions.map(AppPermission.init), appSource: sourceInfo, coreSize: Int(coreSize), tint: tint)
//
//            msg(.info, "generated fairseal:", try fairseal.debugJSON.count)
//
//            // if we specify a hub, then attempt to post the fairseal to the first open PR for that project
//            msg(.info, "posting fairseal for artifact:", assets.first?.url.absoluteString, "JSON:", try fairseal.debugJSON)
//            let postURL = try await hubOptions.fairHub().postFairseal(fairseal, owner: hubOptions.organizationName, baseRepository: hubOptions.baseRepo, issueNumber: sealOptions.postIssue)
//            msg(.info, "posted fairseal to:", postURL.absoluteString)
//        }
//
//        func parseTintColor() throws -> String? {
//            // first check the `appfair.xcconfig` file for customization
//            let settings = try projectOptions.buildSettings()
//
////            if let tint = settings["ICON_TINT"] {
////                if let hexColor = HexColor(hexString: tint) {
////                    return hexColor.colorString(hashPrefix: false)
////                }
////            }
//
//            // fall back to the asset catalog, if any
//            if let accentColorFlag = iconOptions.accentColor {
//                let accentColorPath = projectOptions.projectPathURL(path: accentColorFlag)
//                if let rgba = try parseColorContents(url: accentColorPath) {
//                    let tintColor = String(format:"%02X%02X%02X", Int(rgba.r * 255), Int(rgba.g * 255), Int(rgba.b * 255))
//                    dbg("parsed tint color: \(rgba): \(tintColor)")
//                    return tintColor
//                }
//            }
//
//            return nil
//        }
//
//        private func fetchUntrustedArtifact() async throws -> URL {
//            // if we specified the artifact as a local file, just use it directly
//            if let untrustedArtifactFlag = sealOptions.untrustedArtifact {
//                if FileManager.default.fileExists(atPath: untrustedArtifactFlag) {
//                    return URL(fileURLWithPath: untrustedArtifactFlag)
//                }
//            }
//
//            guard let artifactURLFlag = self.sealOptions.artifactURL,
//                  let artifactURL = URL(string: artifactURLFlag) else {
//                throw FairToolCommand.Errors.missingFlag("-artifact-url")
//            }
//
//            let fetchedURL = try await fetchArtifact(url: artifactURL)
//
//            // if we have specified a target flag for the artifact, copy it over first
//            if let untrustedArtifactFlag = sealOptions.untrustedArtifact {
//                let targetURL = URL(fileURLWithPath: untrustedArtifactFlag)
//                try FileManager.default.moveItem(at: fetchedURL, to: targetURL)
//                return targetURL
//            } else {
//                return fetchedURL
//            }
//        }
//
//        private func fetchArtifact(url artifactURL: URL) async throws -> URL {
//            try await retryOptions.retrying() {
//                var request = URLRequest(url: artifactURL)
//                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
//                let (downloadedURL, response) = try URLSession.shared.downloadSync(request)
//                if let response = response as? HTTPURLResponse,
//                   (200..<300).contains(response.statusCode) { // e.g., 404
//                    msg(.info, "downloaded:", artifactURL.absoluteString, "to:", downloadedURL, "response:", response)
//                    return downloadedURL
//                } else {
//                    msg(.info, "failed to download:", artifactURL.absoluteString, "code:", (response as? HTTPURLResponse)?.statusCode)
//                    throw AppError(String(format: NSLocalizedString("Unable to download: %@ code: %lu", bundle: .module, comment: "error message"), arguments: [artifactURL.absoluteString, ((response as? HTTPURLResponse)?.statusCode ?? 0)]))
//                }
//            }
//        }
//
//    }
}


extension FairCommand {
    public struct CaskOptions: ParsableArguments {
        @Option(name: [.long], help: ArgumentHelp("The output folder for the app casks.", valueName: "dir"))
        public var caskFolder: String?

        @Option(name: [.long], help: ArgumentHelp("The artifact extensions."))
        public var artifactExtension: [String] = []

        @Option(name: [.long], help: ArgumentHelp("Maximum number of Hub API requests per session."))
        public var requestLimit: Int?

        public init() { }
    }


    public struct CatalogCommand: FairParsableCommand {
        public static let experimental = false
        public typealias Output = Never
        public static var configuration = CommandConfiguration(commandName: "catalog",
                                                               abstract: "Build the app catalog.",
                                                               shouldDisplay: !experimental)
        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var hubOptions: HubOptions
        @OptionGroup public var regOptions: RegOptions
        @OptionGroup public var caskOptions: CaskOptions
        @OptionGroup public var sourceOptions: SourceOptions
        @OptionGroup public var retryOptions: RetryOptions
        @OptionGroup public var outputOptions: OutputOptions

        @Flag(name: [.long], help: ArgumentHelp("Whether the include funding source info.", valueName: "funding"))
        public var fundingSources: Bool = false

        public init() { }

        public mutating func run() async throws {
            warnExperimental(Self.experimental)
            try await self.catalog()
        }

        func catalog() async throws {
            msg(.info, "Catalog")
            try await retryOptions.retrying() {
                try await createCatalog()
            }
        }

        private func createCatalog() async throws {
            msg(.debug, "creating catalog")
//            let hub = try hubOptions.fairHub()
//
//            // whether to enforce a fairseal check before the app will be listed in the catalog
//            let fairsealCheck = true // options.fairseal.contains("skip") != true
//
//            let artifactTarget: ArtifactTarget?
//            switch caskOptions.artifactExtension.first ?? "zip" {
//            case "ipa":
//                artifactTarget = ArtifactTarget(artifactType: "ipa", devices: ["iphone", "ipad"])
//            case "zip":
//                artifactTarget = ArtifactTarget(artifactType: "zip", devices: ["mac"])
//            default:
//                artifactTarget = nil
//            }
//
//            let configuration = try regOptions.createProjectConfiguration()
//
//            let sourceURL = sourceOptions.catalogSourceURL.flatMap(URL.init(string:))
//
//            // build the catalog filtering on specific artifact extensions
//            var catalog = try await hub.buildAppCatalog(title: sourceOptions.catalogName ?? "App Source", identifier: sourceOptions.catalogIdentifier ?? "identifier", owner: hubOptions.organizationName, sourceURL: sourceURL, baseRepository: hubOptions.baseRepo, fairsealCheck: fairsealCheck, artifactTarget: artifactTarget, configuration: configuration, requestLimit: self.caskOptions.requestLimit)
//            if fundingSources {
//                catalog.fundingSources = try await hub.buildFundingSources(owner: hubOptions.organizationName, baseRepository: hubOptions.baseRepo)
//            }
//
//            msg(.debug, "releases:", catalog.apps.count) // , "valid:", catalog.count)
//            for apprel in catalog.apps {
//                msg(.debug, "  app:", apprel.name) // , "valid:", validate(apprel: apprel))
//            }
//
//            let json = try catalog.toJSON(outputFormatting: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes], dateEncodingStrategy: .iso8601, dataEncodingStrategy: .base64)
//            try outputOptions.write(json)
//            msg(.info, "Wrote catalog size:", json.count)
//
//            if let caskFolderFlag = caskOptions.caskFolder {
//                msg(.info, "Writing casks to: \(caskFolderFlag)")
//                for app in catalog.apps {
//                    try saveCask(app, to: caskFolderFlag, prereleaseSuffix: "-prerelease")
//                }
//            }
        }
    }

}


extension FairCommand {
    public struct IconOptions: ParsableArguments {
        @Option(name: [.long], help: ArgumentHelp("Path to appiconset/Contents.json."))
        public var appIcon: String?

        @Option(name: [.long], help: ArgumentHelp("Path or symbol name to place in the icon.", valueName: "symbol"))
        public var iconSymbol: [String] = []

        @Option(name: [.long], help: ArgumentHelp("The accent color file.", valueName: "color"))
        public var accentColor: String?

        public init() { }
    }

#if canImport(SwiftUI)

//    public struct IconCommand: FairParsableCommand {
//        public static let experimental = false
//        public typealias Output = Never
//        public static var configuration = CommandConfiguration(commandName: "icon",
//                                                               abstract: "Create an icon for the given project.",
//                                                               shouldDisplay: !experimental)
//        @OptionGroup public var iconOptions: IconOptions
//        @OptionGroup public var msgOptions: MsgOptions
//        @OptionGroup public var orgOptions: OrgOptions
//        @OptionGroup public var projectOptions: ProjectOptions
//
//        public init() { }
//
//        public mutating func run() async throws {
//            warnExperimental(Self.experimental)
//            try await runOnMain()
//        }
//
//        @MainActor mutating func runOnMain() async throws {
//            msg(.info, "icon")
//
//            assert(Thread.isMainThread, "SwiftUI can only be used from main thread")
//
//            guard let appIconPath = iconOptions.appIcon else {
//                throw FairToolCommand.Errors.missingFlag("-app-icon")
//            }
//
//            let appIconURL = projectOptions.projectPathURL(path: appIconPath)
//
//            // load the specified `Assets.xcassets/AppIcon.appiconset/Contents.json` and fill in any of the essential missing icons
//            let iconSet = try AppIconSet(fromJSON: Data(contentsOf: appIconURL))
//
//            let appName = try orgOptions.appNameSpace()
//            let iconColor = try parseTintIconColor()
//
//            var symbolNames = iconOptions.iconSymbol
//            let settings = try projectOptions.buildSettings()
//            if let symbolName = settings["ICON_SYMBOL"] {
//                symbolNames.append(symbolName)
//            }
//
//            // the minimal required icons for macOS + iOS
//            let icons = [
//                iconSet.images(idiom: "mac", scale: "2x", size: "16x16"),
//                iconSet.images(idiom: "mac", scale: "2x", size: "128x128"),
//                iconSet.images(idiom: "mac", scale: "2x", size: "256x256"),
//                iconSet.images(idiom: "mac", scale: "2x", size: "512x512"),
//                iconSet.images(idiom: "iphone", scale: "2x", size: "60x60"),
//                iconSet.images(idiom: "iphone", scale: "3x", size: "60x60"),
//                iconSet.images(idiom: "ipad", scale: "1x", size: "76x76"),
//                iconSet.images(idiom: "ipad", scale: "2x", size: "76x76"),
//                iconSet.images(idiom: "ipad", scale: "2x", size: "83.5x83.5"),
//                iconSet.images(idiom: "ios-marketing", scale: "1x", size: "1024x1024"),
//            ].joined()
//
//            var appIconSet = iconSet
//
//            for imageSet in icons {
//                let iconView = FairIconView(appName, subtitle: nil, paths: symbolNames, iconColor: iconColor, cornerRadiusFactor: imageSet.idiom == "ios-marketing" ? 0.0 : nil) // App Store icon must not have any transparency
//
//                if imageSet.filename != nil {
//                    continue // skip any elements that have a file path specified already
//                }
//
//                // an un-specified filename will be filled in with the default app icon
//
//                let iconFile = URL(fileURLWithPath: "appicon-" + imageSet.standardPath + ".png", relativeTo: appIconURL)
//
//                let assetName = try AssetName(string: iconFile.lastPathComponent)
//
//                let size = max(assetName.width, assetName.height)
//                var scale = Double(assetName.scale ?? 1)
//#if os(macOS)
//                if let screen = NSScreen.main, screen.backingScaleFactor > 0.0 {
//                    // there should be a better way to do this, but rendering a view seems to use the main screens scale, which on the build host seems to be 1.0 and on a macBook is 2.0; we need to alter the scale in order to generate the correctly-sized images on each host
//                    scale /= screen.backingScaleFactor
//                }
//#endif
//
//                let span = CGFloat(size) * CGFloat(scale) // default content scale
//                let bounds = CGRect(origin: CGPoint(x: -span/2, y: -span/2), size: CGSize(width: CGFloat(span), height: CGFloat(span)))
//                let iconInset = imageSet.idiom?.hasPrefix("mac") == true ? 0.10 : 0.00 // mac icons are inset by 10%
//
//                guard let pngData = iconView.padding(span * iconInset).png(bounds: bounds), pngData.count > 1024 else {
//                    throw AppError(NSLocalizedString("Unable to generate PNG data", bundle: .module, comment: "error message"))
//                }
//                try pngData.write(to: iconFile)
//                msg(.info, "output icon to: \(iconFile.path)")
//
//                appIconSet.images = appIconSet.images.map { image in
//                    var img = image
//                    if img.idiom == imageSet.idiom
//                        && img.size == imageSet.size
//                        && img.scale == imageSet.scale
//                        && img.role == imageSet.role
//                        && img.subtype == imageSet.subtype
//                        && img.filename == nil {
//                        img.filename = iconFile.lastPathComponent // update the image to have the given file name
//                    }
//                    return img
//                }
//            }
//
//            if appIconSet != iconSet {
//                // when we have changed the icon set from the origional, save it back to the asset catalog
//                msg(.info, "saving changed assets to: \(appIconURL.path)")
//                try appIconSet.toJSON(outputFormatting: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]).write(to: appIconURL)
//            }
//        }
//
//        func parseTintIconColor() throws -> Color? {
//            let settings = try projectOptions.buildSettings()
//
//            if let tint = settings["ICON_TINT"] {
//                if let hexColor = HexColor(hexString: tint) {
//                    return hexColor.sRGBColor()
//                }
//            }
//
//            // fall back to the asset catalog, if specified
//            if let accentColorFlag = iconOptions.accentColor {
//                let accentColorPath = projectOptions.projectPathURL(path: accentColorFlag)
//                if let rgba = try parseColorContents(url: accentColorPath) {
//                    return Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
//                }
//            }
//
//            return nil
//        }
//
//    }
#endif
}

