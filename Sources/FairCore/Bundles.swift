import Foundation

public extension Bundle {
    /// The URL for the `Fair` module's resource bundle
    static var fairAssetsURL: URL! {
        Bundle.module.url(forResource: "Assets", withExtension: nil)
    }

    /// The "Bundle" path is no longer used (becauses it confuses Xcode). Renamed to "Assets".
    @available(*, deprecated, renamed: "fairAssetsURL")
    static var fairBundleURL: URL! {
        Bundle.module.url(forResource: "Bundle", withExtension: nil)
    }
}

public extension Bundle {
    /// Returns the bundle's `infoDictionary` key value
    subscript<T>(info key: PropertyListKey, localized localized: Bool = false) -> T? {
        (localized ? localizedInfoDictionary?[key.plistKey] : infoDictionary?[key.plistKey]) as? T
    }

    /// The bundle's `CFBundleName`
    var bundleName: String? { self[info: .CFBundleName] }

    /// The localized bundle's `CFBundleName`
    var bundleNameLocalized: String? { self[info: .CFBundleName, localized: true] }

    /// The bundle's `CFBundleDisplayName`
    var bundleDisplayName: String? { self[info: .CFBundleDisplayName] }

    /// The localized bundle's `CFBundleDisplayName`
    var bundleDisplayNameLocalized: String? { self[info: .CFBundleDisplayName, localized: true] }

    /// The bundle's `CFBundleIdentifier`
    var bundleID: String? { self[info: .CFBundleIdentifier] }

    /// The bundle's `CFBundleVersion` incrementing counter number
    var bundleVersionCounter: Int? { self[info: .CFBundleVersion] }

    /// The bundle's `CFBundleShortVersionString` semantic version string
    var bundleVersionString: String? { self[info: .CFBundleShortVersionString] }

    /// The `CFBundleShortVersionString` converted to an AppVersion. Note that these are always considered non-prerelease since the prerelease flag is an ephemeral part of the hub's release, and is not indicated in the app's plist in any way
    var bundleVersion: SemVer? { bundleVersionString.flatMap({ SemVer(string: $0) }) }

    /// The name of the package's app/org, which is the bundle's name with hyphens for spaces
    var appOrgName: String? {
        if let bundleID = bundleID, let lastBundleComponent = bundleID.split(separator: ".").last {
            return lastBundleComponent.rehyphenated()
        } else {
            return bundleName?.rehyphenated()
        }
    }
}


extension Bundle {
    /// Returns the resources bundle for `FairCore`
    public static var fairCore: Bundle { Bundle.module }

    /// Returns the info dictionary for the `FairCore.plist` resource
    public static let fairCoreInfo = Plist(rawValue: Info as NSDictionary) // Info should be generated manually with: plutil -convert swift Info.plist

    /// The version of the FairCore library in use
    public static let fairCoreVersion = fairCoreInfo.CFBundleShortVersionString.flatMap(SemVer.init(string:))

    /// Returns all the URLs in the given asset path of the bundle
    public func assetPaths(in folder: String, includeLinks: Bool, includeFolders: Bool) throws -> [URL] {
        guard let bundleURL = url(forResource: folder, withExtension: nil, subdirectory: "Assets") else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        return try FileManager.default.deepContents(of: bundleURL, includeLinks: includeLinks, includeFolders: includeFolders)
    }

    /// Loads the resource with the given name
    public func loadResource(named name: String, options: Data.ReadingOptions = .mappedIfSafe) throws -> Data {
        guard let url = url(forResource: name, withExtension: nil, subdirectory: nil) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return try Data(contentsOf: url, options: options)
    }

    /// Loads the resource with the given name from the `Assets` resource path, which can be used to store non-flattened resource hierarchies
    public func loadBundleAsset(named name: String, options: Data.ReadingOptions = .mappedIfSafe) throws -> Data {
        guard let url = url(forResource: name, withExtension: nil, subdirectory: "Assets") else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return try Data(contentsOf: url, options: options)
    }
}

extension Bundle {
    /// Returns a result designed to be used in static caches of the packages bundled `Package.resolved` file (which must be copied manually into the bundle's resources)
    public func resolvedPackages() -> Result<ResolvedPackage, Error> {
        Result { try ResolvedPackage(fromJSON: self.loadResource(named: "Package.resolved")) }
    }
}

/// The contents of a `Package.resolved` file, which contains information about the project's dependencies.
public struct ResolvedPackage : RawCodable, Codable {
    public var rawValue: Either<ResolvedPackageV1>.Or<ResolvedPackageV2>

    public var version: Int { rawValue.map(\.version.rawValue, \.version.rawValue).value }

    public init(rawValue: Either<ResolvedPackageV1>.Or<ResolvedPackageV2>) {
        self.rawValue = rawValue
    }

    /// A version of the given package, handling both .v1 and .v2 of the packages.
    public var packages: [Package] {
        switch rawValue {
        case .a(let v1):
            return v1.object.pins.map({ Package(identity: nil, location: $0.repositoryURL, state: $0.state) })
        case .b(let v2):
            return v2.pins.map({ Package(identity: $0.identity, location: $0.location, state: $0.state) })
        }
    }

    public struct Package {
        public var identity: String?
        public var location: String
        public var state: PackageState
    }

    /// The contents of a `Package.resolved` version 1 file
    public struct ResolvedPackageV1: Codable, Equatable {
        public enum Version : Int, Codable { case v1 = 1 }
        public var version: Version
        public var object: Pins

        public struct Pins: Codable, Equatable {
            public var pins: [SwiftPackage]
        }

        public struct SwiftPackage: Codable, Equatable {
            public var package: String
            public var repositoryURL: String
            public var state: PackageState
        }
    }

    /// The contents of a `Package.resolved` version 2 file
    public struct ResolvedPackageV2: Codable, Equatable {
        public enum Version : Int, Codable { case v2 = 2 }
        public var version: Version
        public var pins: [SwiftPackage]

        public struct SwiftPackage: Codable, Equatable {
            public var identity: String
            public var kind: String
            public var location: String
            public var state: PackageState

        }
    }

    public struct PackageState: Codable, Equatable {
        public var branch: String?
        public var revision: String
        public var version: String?
    }

}

public extension Plist {
    /// Returns the untypes content of the given plist key
    func plistValue(for key: PropertyListKey) -> Any? {
        rawValue[key.plistKey]
    }

    /// Returns the string contents of the given plist key
    func stringValue(for key: PropertyListKey) -> String? {
        guard let value = plistValue(for: key) as? String else {
            return nil
        }

        if value.isEmpty {
            return nil
        }

        return value

    }

    /// The value of the `CFBundleIdentifier` string
    var CFBundleIdentifier: String? {
        stringValue(for: .CFBundleIdentifier)
    }


    /// The value of the `CFBundleName` string
    var CFBundleName: String? {
        stringValue(for: .CFBundleName)
    }

    /// The value of the `CFBundleDisplayName` string
    var CFBundleDisplayName: String? {
        stringValue(for: .CFBundleDisplayName)
    }


    /// The value of the `CFBundleVersion` string
    var CFBundleVersion: String? {
        stringValue(for: .CFBundleVersion)
    }

    /// The value of the `CFBundleShortVersionString` string
    var CFBundleShortVersionString: String? {
        stringValue(for: .CFBundleShortVersionString)
    }

    /// The value of the `CFBundleExecutable` string
    var CFBundleExecutable: String? {
        stringValue(for: .CFBundleExecutable)
    }

    /// The value of the `DTPlatformName` string
    var DTPlatformName: String? {
        stringValue(for: .DTPlatformName)
    }
}

/// A key in a ``Plist`` holding a standard `Info.plist`.
///
/// Some common properties include:
///
///  - ``CFBundleIdentifier``
///  - ``CFBundleExecutable``
///  - ``CFBundleName``
///  - ``CFBundleDisplayName``
///  - ``CFBundleVersion``
///  - ``CFBundleShortVersionString``
///
/// See:
/// https://developer.apple.com/documentation/bundleresources/information_property_list/bundle_configuration
public struct PropertyListKey : RawCodable {
    public static let CFBundleIdentifier = Self("CFBundleIdentifier") // e.g., "app.My-App"
    public static let CFBundleExecutable = Self("CFBundleExecutable") // e.g., "My App"
    public static let CFBundleName = Self("CFBundleName") // e.g., "My App"
    public static let CFBundleDisplayName = Self("CFBundleDisplayName") // e.g., "My App"
    public static let CFBundleVersion = Self("CFBundleVersion") // e.g., 699162671
    public static let CFBundleShortVersionString = Self("CFBundleShortVersionString")

    public static let CFBundlePackageType = Self("CFBundlePackageType") // e.g., "APPL"
    public static let CFBundleSupportedPlatforms = Self("CFBundleSupportedPlatforms") // e.g., ["iPhoneOS"]
    public static let CFBundleInfoDictionaryVersion = Self("CFBundleInfoDictionaryVersion") // e.g., 6.0

    public static let CFBundleIconName = Self("CFBundleIconName") // e.g., "AppIcon"
    public static let CFBundleIcons = Self("CFBundleIcons")
    public static let CFBundlePrimaryIcon = Self("CFBundlePrimaryIcon")
    public static let CFBundleIconFiles = Self("CFBundleIconFiles")

    public static let NSHumanReadableCopyright = Self("NSHumanReadableCopyright")

    public static let DTSDKName = Self("DTSDKName") // e.g., "iphoneos15.0" or "macosx12.0"
    public static let DTSDKBuild = Self("DTSDKBuild") // e.g., 19A5297f

    public static let DTPlatformBuild = Self("DTPlatformBuild") // e.g., 19A5297f
    public static let DTPlatformVersion = Self("DTPlatformVersion") // e.g., 15.0 or 12.0
    public static let DTPlatformName = Self("DTPlatformName") // e.g., "iphoneos" or "macosx"
    public static let DTCompiler = Self("DTCompiler") // e.g., "com.apple.compilers.llvm.clang.1_0"

    public static let DTXcode = Self("DTXcode") // e.g., 1300
    public static let DTXcodeBuild = Self("DTXcodeBuild") // e.g., "13A5192j"

    public static let LSMinimumSystemVersion = Self("LSMinimumSystemVersion")
    public static let LSApplicationCategoryType = Self("LSApplicationCategoryType")
    public static let LSApplicationSecondaryCategoryType = Self("LSApplicationSecondaryCategoryType")
    public static let LSFileQuarantineEnabled = Self("LSFileQuarantineEnabled")
    public static let LSBackgroundOnly = Self("LSBackgroundOnly")
    public static let LSUIElement = Self("LSUIElement")
    public static let LSUIPresentationMode = Self("LSUIPresentationMode")

    public static let MinimumOSVersion = Self("MinimumOSVersion")
    public static let BuildMachineOSBuild = Self("BuildMachineOSBuild") // e.g., 20G71

    public static let UIDeviceFamily = Self("UIDeviceFamily") // e.g., [1,2]
    public static let UIRequiredDeviceCapabilities = Self("UIRequiredDeviceCapabilities")
    public static let UISupportedInterfaceOrientations = Self("UISupportedInterfaceOrientations") // e.g., [UIInterfaceOrientationPortrait, UIInterfaceOrientationPortraitUpsideDown, UIInterfaceOrientationLandscapeLeft, UIInterfaceOrientationLandscapeRight]

    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Returns the key for the plist
    public var plistKey: String {
        rawValue
    }
}

/// A semantic version of an app with a `major`, `minor`, and `patch` component.
///
/// E.g.: `1.0.0-alpha.beta`
public struct SemVer : Sendable, Hashable, Codable, Comparable, RawRepresentable {
    /// The lowest possible version that can exist
    public static let min = SemVer(major: .min, minor: .min, patch: .min, prerelease: nil, build: nil)
    /// The highest possible version that can exist
    public static let max = SemVer(major: .max, minor: .max, patch: .max, prerelease: nil, build: nil)

    public let major, minor, patch: UInt

    public let prerelease: String?
    public let build: String?

    public enum Component : String, Codable { case major, minor, patch }

    public var rawValue: String { versionString }

    public init?(rawValue: String) {
        self.init(string: rawValue)
    }

    public init(major: UInt, minor: UInt, patch: UInt, prerelease: String? = nil, build: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.build = build
    }

    /// Initialize the version by parsing the string
    public init?(string versionString: String) {
        guard let version = Self.parse(string: versionString) else {
            return nil
        }
        self = version
    }

    /// Increments the given component of the semantic version by the given amount.
    /// - Parameter component: the `.major`, `.minor`, or `.patch` component to bump
    /// - Returns: the version after bumping the given component
    public func bumping(_ component: Component) -> SemVer {
        var (major, minor, patch) = (major, minor, patch)
        switch component {
        case .major:
            major += 1
            minor = 0
            patch = 0
        case .minor:
            minor += 1
            patch = 0
        case .patch:
            patch += 1
        }
        return SemVer(major: major, minor: minor, patch: patch)
    }

    private static let semverRE = try! NSRegularExpression(pattern: #"^(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)(?:-(?<prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?<buildmetadata>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$"#, options: [])

    /// Parse the semantic version string as per https://semver.org/#is-there-a-suggested-regular-expression-regex-to-check-a-semver-string
    ///
    /// Uses the regular expression modified for Cocoa regex conventions (no P before capture group names):
    ///
    ///  ```
    ///  ^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)(?:-(?P<prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?P<buildmetadata>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$
    ///  ```
    private static func parse(string versionString: String) -> Self? {
        guard let match = semverRE.matches(in: versionString, options: [], range: versionString.span).first else {
            return nil // no matchges
        }

        let majorRange = match.range(withName: "major")
        guard majorRange.location != NSNotFound,
            let major = UInt((versionString as NSString).substring(with: majorRange)) else {
            return nil
        }

        let minorRange = match.range(withName: "minor")
        guard minorRange.location != NSNotFound,
            let minor = UInt((versionString as NSString).substring(with: minorRange)) else {
            return nil
        }

        let patchRange = match.range(withName: "patch")
        guard patchRange.location != NSNotFound,
            let patch = UInt((versionString as NSString).substring(with: patchRange)) else {
            return nil
        }

        let prerelease: String?
        let prereleaseRange = match.range(withName: "prerelease")
        if prereleaseRange.location == NSNotFound {
            prerelease = nil
        } else {
            prerelease = ((versionString as NSString).substring(with: prereleaseRange))
        }

        let buildmetadata: String?
        let buildmetadataRange = match.range(withName: "buildmetadata")
        if buildmetadataRange.location == NSNotFound {
            buildmetadata = nil
        } else {
            buildmetadata = ((versionString as NSString).substring(with: buildmetadataRange))
        }

        //dbg("parsing version:", major, minor, patch)

        return SemVer(major: major, minor: minor, patch: patch, prerelease: prerelease, build: buildmetadata)
    }

    public static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        lhs.major < rhs.major
            || (lhs.major == rhs.major && lhs.minor < rhs.minor)
            || (lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch < rhs.patch)
            || (lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch && suffixLT(lhs.prerelease, rhs.prerelease))
            || (lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch && lhs.prerelease == rhs.prerelease && suffixLT(lhs.build, rhs.build))

    }

    private static func suffixLT(_ s1: String?, _ s2: String?) -> Bool {
        guard let s1 = s1 else {
            return false
        }
        guard let s2 = s2 else {
            return true
        }

        let n1 = UInt(s1)
        let n2 = UInt(s1)

        if let n1 = n1, let n2 = n2, n1 < n2 {
            return false
        }

        if n1 == nil {
            // “Numeric identifiers always have lower precedence than non-numeric identifiers”
            return true
        }

        if n2 == nil {
            // “Numeric identifiers always have lower precedence than non-numeric identifiers”
            return false
        }

        return s1 < s2 // “Identifiers with letters or hyphens are compared lexically in ASCII sort order”
    }

    /// The version string in the form `major`.`minor`.`patch`-`prerelease`+`build`
    public var versionString: String {
        var str = "\(major).\(minor).\(patch)"
        if let prerelease = prerelease {
            str += "-" + prerelease
        }
        if let build = build {
            str += "+" + build
        }
        return str
    }

    public func encode(to encoder: Encoder) throws {
        try versionString.encode(to: encoder)
    }

    public init(from decoder: Decoder) throws {
        let str = try decoder.singleValueContainer().decode(String.self)
        let version = Self.init(string: str)
        guard let version = version else {
            throw Errors.cannotParseVersionString(str)
        }
        self = version
    }

    public enum Errors : Error {
        case cannotParseVersionString(String)
    }
}

extension SemVer {
    /// True when the major and minor versions are the same as the other version
    public func minorCompatible(with version: SemVer) -> Bool {
        compatible(with: version, to: .minor)
    }

    public func compatible(with version: SemVer, to component: Component) -> Bool {
        switch component {
        case .major:
            return self.major == version.major
        case .minor:
            return self.major == version.major && self.minor == version.minor
        case .patch:
            return self.major == version.major && self.minor == version.minor && self.patch == version.patch
        }
    }
}

extension FileManager {
    /// Runs ``FileManager.enumerate`` in an async ``Task``, returning an ``AsyncThrowingStream`` with the elements.
    /// - Parameters:
    ///   - url: The location of the directory for which you want an enumeration. This URL must not be a symbolic link that points to the desired directory. You can use the resolvingSymlinksInPath method to resolve any symlinks in the URL.
    ///   - haltOnError: Whether to stop if any errors are encountered
    ///   - resourceKeys: An array of keys that identify the properties that you want pre-fetched for each item in the enumeration.
    ///   - options: Options for the enumeration.
    /// - Returns: An async stream yielding a `Result<URL, Error>`
    public func enumeratorAsync(at url: URL, haltOnError: Bool = false, includingPropertiesForKeys resourceKeys: [URLResourceKey]? = nil, options: DirectoryEnumerationOptions = []) -> AsyncThrowingStream<Result<URL, Error>, Error> {
        AsyncThrowingStream { c in
            guard let directoryEnumerator = self.enumerator(at: url, includingPropertiesForKeys: resourceKeys, options: options, errorHandler: { url, error in
                c.yield(.failure(error))
                if haltOnError || Task.isCancelled {
                    return false // stop the enumeration
                } else {
                    return true
                }
            }) else {
                c.yield(.failure(CocoaError(.fileReadUnknown)))
                return
            }

            for case let fileURL as URL in directoryEnumerator {
                c.yield(.success(fileURL))
            }
            c.finish()
        }
    }

    /// Returns the deep contents of the given file URL, with an option to preserve relative paths in the URLs.
    public func deepContents(of parentFolder: URL, includeLinks: Bool, includeFolders: Bool, relativePath: Bool = false) throws -> [URL] {
        // note that we would like the relativePath option to use
        // FileManager.DirectoryEnumerationOptions.producesRelativePathURLs
        // but it is not available on Linux, so we need to synthesize the relative URLs ourselves
        guard let walker = self.enumerator(at: parentFolder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey], options: []) else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        var paths: [URL] = []
        for case let url as URL in walker {
            let isLink = try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink
            if includeLinks == false && isLink == true {
                continue
            }

            let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory

            if includeFolders || isDirectory != true {
                if !relativePath {
                    // we don't need to synthesize relative URLs
                    paths.append(url)
                } else {
                    let resolvedParent = try findCommonRelative(from: url, parent: parentFolder) ?? parentFolder
                    //dbg("parentFolder:", parentFolder, "resolvedParent:", resolvedParent)
                    let relativePath = url.pathComponents.suffix(from: resolvedParent.pathComponents.count).joined(separator: "/")
                    // note that the relative URL will be relative to the specified parent folder, rather than to the path that it resolves to
                    let relativeURL = URL(fileURLWithPath: relativePath, isDirectory: isDirectory == true, relativeTo: parentFolder)
                    //dbg("adding:", relativeURL.path, "dir?", isDirectory)
                    // relativeURL.setResourceValues([.isDirectoryKey: isDir, .fileSizeKey: key]) // TODO: transfer size?
                    paths.append(relativeURL)
                }
            }
        }

        return paths
    }

    /// Finds a common root from the given url to the specified parent.
    /// Handles the case where the parent may be a link to elsewhere, and the check urls are in the destination of that link
    private func findCommonRelative(from url: URL, parent: URL) throws -> URL? {
        // the common case where the child URL just includes the path of the parent
        if url.path.hasPrefix(parent.path) {
            return parent
        }

        var checkURL = url
        var rel: URLRelationship = .contains
        while rel == .contains {
            try getRelationship(&rel, ofDirectoryAt: parent, toItemAt: checkURL)
            if rel == .same {
                return checkURL
            }
            checkURL = checkURL.deletingLastPathComponent()
        }
        return nil
    }

    /// Attempts to place the item at the given URL in the Trash on platforms that support it.
    /// An error will be thrown if the operation fails, and on platforms that support Trash, the return value will be the URL of the trashed item.
    @discardableResult public func trash(url: URL) throws -> URL? {
        #if canImport(AppKit)
        var trashResult: NSURL? = nil
        try trashItem(at: url, resultingItemURL: &trashResult)
        return trashResult as URL?
        #else
        try removeItem(at: url)
        return nil
        #endif
    }

    /// Returns true if the folder is a directory, false if it is a file,
    /// and nil if it doesn't exist
    public func isDirectory(url: URL) -> Bool? {
        var isDir: ObjCBool = false
        if !fileExists(atPath: url.path, isDirectory: &isDir) {
            return nil
        }
        return isDir.boolValue
    }

    /// Returns true if the path at the given url has the `URLResourceKey.quarantinePropertiesKey` bit set.
    public func isQuarantined(at url: URL) throws -> Bool {
        #if os(macOS)
        try (url as NSURL).resourceValues(forKeys: [URLResourceKey.quarantinePropertiesKey]).isEmpty == false
        #else
        false
        #endif
    }

    /// Removes any quarantine properties from the given URL
    public func clearQuarantine(at url: URL) throws {
        #if os(macOS)
        // try to clear the quarantine flag
        do {
//            let quarantineProperties: [String: Any] = [
//                kLSQuarantineAgentNameKey as String: "App Fair",
//                kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload,
//                kLSQuarantineDataURLKey as String: dataURL,
//                kLSQuarantineOriginURLKey as String: originURL
//            ]

            try (url as NSURL).setResourceValue(nil, forKey: .quarantinePropertiesKey)
        } catch {
            dbg("unable to clear quarantine flag for:", url.path, error)
        }

        // check to ensure we have cleared the props
        if try isQuarantined(at: url) == true {
            dbg("found quarantine xattr for:", url.path)
            throw CocoaError(.executableNotLoadable)
        }
        #endif
    }

    /// Updates the contents of the project resource at the given relative path.
    ///
    /// - Parameters:
    ///   - url: the url to write to
    ///   - contents: the contents to write; `nil` deletes the file
    /// - Returns: the previous data if it was changed or removed, or nil if no write operation was performed
    @discardableResult public func update(url: URL, with contents: Data?) throws -> Data? {
        // we simply ignore read errors and treat them as if the file does not exist
        let existing = try? Data(contentsOf: url)
        if let contents = contents {
            if contents != existing {
                try contents.write(to: url)
                return existing
            } else {
                return nil // no changes
            }
        } else {
            if existing != nil {
                try removeItem(at: url)
                return existing
            } else {
                return nil
            }
        }
    }
}

public extension URL {
    /// The directory for temporary files
    static var tmpdir: URL { URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true) }
}

extension URL {
    /// Attempts to create a cached file based on the contents of the given URL's folder ending with ".parts".
    /// This folder is expected to contain individual files which, when concatinated in alphabetical order, will re-create the specified file
    ///
    /// This allows large files to be split into individual parts to work around [SPM's lack of git LFS support](https://forums.swift.org/t/swiftpm-with-git-lfs/42396/6).
    public func assemblePartsCache(overwrite: Bool = false) throws -> URL {
        let fm = FileManager.default

        if fm.isDirectory(url: self) != true {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let cacheBase = self.deletingPathExtension().lastPathComponent
        let cacheFile = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: self, create: true).appendingPathComponent(cacheBase)

        let parts = try self.fileChildren(deep: false, keys: [.fileSizeKey, .contentModificationDateKey])
            .filter { fm.isDirectory(url: $0) == false }
            .filter { $0.lastPathComponent.hasPrefix(".") == false }
            .sorting(by: \.lastPathComponent)

        let totalSize = parts.compactMap({ $0.fileSize() }).reduce(0, +)
        let lastModified = parts.compactMap(\.modificationDate).sorted().last

        if fm.isReadableFile(atPath: cacheFile.path) && overwrite == false {
            // ensure that the file size is equal to the sum of the individual path components
            // note that we skip any checksum validation here, so we expect the resource to be trusted (which it will be if it is included in a signed app bundle)
            let cacheNewerThanParts = (cacheFile.modificationDate ?? Date()) > (lastModified ?? Date())
            if cacheFile.fileSize() == totalSize && cacheNewerThanParts == true {
                return cacheFile
            } else {
                if !cacheNewerThanParts {
                    dbg("rebuilding cache file:", cacheFile.path, "modified:", cacheFile.modificationDate, "latest part:", lastModified)
                }
            }
        }

        dbg("assembling parts in", self.path, "into:", cacheFile.path, "size:", totalSize.localizedByteCount(), "from:", parts.map(\.lastPathComponent))

        // clear any existing cache file that we aren't using (e.g., due to bad size)
        try? FileManager.default.removeItem(at: cacheFile)

        // file must exist before writing
        FileManager.default.createFile(atPath: cacheFile.path, contents: nil, attributes: nil)
        let fh = try FileHandle(forWritingTo: cacheFile)
        defer { try? fh.close() }

        for part in parts {
            try fh.write(contentsOf: Data(contentsOf: part))
        }

        return cacheFile
    }

    /// Returns the contents of the given file URL's folder.
    /// - Parameter deep: whether to retrieve the deep or shallow contents
    /// - Parameter skipHidden: whether to skip hidden files
    /// - Parameter keys: resource keys to pre-cache, such as `[.fileSizeKey]`
    /// - Returns: the list of URL children relative to the current URL's folder
    public func fileChildren(deep: Bool, skipHidden: Bool = false, keys: [URLResourceKey]? = nil) throws -> [URL] {
        let fm = FileManager.default

        if fm.isDirectory(url: self) != true {
            throw CocoaError(.fileReadUnknown)
        }

        var mask: FileManager.DirectoryEnumerationOptions = skipHidden ? [.skipsHiddenFiles] : []

        if deep == false {
            // we could alternatively use `enumerator` with the `FileManager.DirectoryEnumerationOptions.skipsSubdirectoryDescendants` mask
            return try fm.contentsOfDirectory(at: self, includingPropertiesForKeys: keys, options: mask) // “the only supported option is skipsHiddenFiles”
        } else {
            #if !os(Linux) && !os(Android) && !os(Windows)
            mask.insert(.producesRelativePathURLs) // unavailable on windows
            #endif

            guard let walker = fm.enumerator(at: self, includingPropertiesForKeys: keys, options: mask) else {
                throw CocoaError(.fileReadNoSuchFile)
            }

            var paths: [URL] = []
            for path in walker {
                if let url = path as? URL {
                    paths.append(url)
                } else if let path = path as? String {
                    paths.append(URL(fileURLWithPath: path, relativeTo: self))
                }
            }

            return paths
        }
    }
}

#if !os(Linux) && !os(Android) && !os(Windows)
/// A watcher for changes to a folder
public actor FileSystemObserver {
    private let fileDescriptor: CInt
    private let source: DispatchSourceProtocol

    public init(URL: URL, queue: DispatchQueue = .global(), block: @escaping () -> Void) {
        self.fileDescriptor = open(URL.path, O_EVTONLY)
        self.source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: self.fileDescriptor, eventMask: .all, queue: queue)
        self.source.setEventHandler {
            block()
        }
        self.source.resume()
    }

    deinit {
        self.source.cancel()
        close(fileDescriptor)
    }
}
#endif

public struct DynamicBundleError : LocalizedError {
    public var errorDescription: String?
}

extension Bundle {
    /// Searches for the native library with the given name and invokes `registerLibrary()`.
    ///
    /// A dynamic library whose native functionality can be loaded at runtime.
    ///
    /// - Parameters:
    ///   - name: the name of the extensions library
    ///   - registerPrefix: the prefix for the registration function to invoke.
    ///   - frameworksFolder: the folder in which to search for frameworks
    /// - Returns: the return value for the `registerPrefix``extensionName` C function invocation, which must be `@convention(c) () -> Bool` (a no-argument function that reutrns a Bool)
    public func registerDynamic(name extensionName: String, registerPrefix: String = "register", in frameworksFolder: String? = "PackageFrameworks") throws -> Bool {
        let bundle = self

        func findPluginPath(for name: String) throws -> URL {
            guard let frameworksFolder = frameworksFolder else {
                guard let exeURL = bundle.executableURL else {
                    throw DynamicBundleError(errorDescription: "Missing executable URL for bundle: \(bundle)")
                }
                return exeURL
            }

            let baseURL = URL(fileURLWithPath: frameworksFolder, isDirectory: true, relativeTo: bundle.bundleURL.appendingPathComponent(".."))

            guard let frameworkBundle = Bundle(url: URL(fileURLWithPath: name + ".framework", isDirectory: true, relativeTo: baseURL)) else {
                throw DynamicBundleError(errorDescription: "missing \(name).framework folder in \(baseURL.path)")
            }

            let bundleExecutable = URL(fileURLWithPath: name, isDirectory: false, relativeTo: frameworkBundle.bundleURL)
            dbg("checking bundleExecutable:", bundleExecutable.path)
            guard FileManager.default.isExecutableFile(atPath: bundleExecutable.path) else {
                throw DynamicBundleError(errorDescription: "module is not executable at: \(bundleExecutable.path)")
            }
            return bundleExecutable
        }

        typealias RegisterPluginFunction = @convention(c) () -> Bool

        let bundlePath = try findPluginPath(for: extensionName)
        let registerFunctionName = registerPrefix + extensionName // the name of the C function to call to register

        guard let pluginHandle = dlopen(bundlePath.path, RTLD_NOW) else {
            if let error = dlerror() {
                throw DynamicBundleError(errorDescription: "dlopen error: \(String(cString: error))")
            } else {
                throw DynamicBundleError(errorDescription: "Unknown dlopen error")
            }
        }

        guard let registerPlugin = dlsym(pluginHandle, registerFunctionName).map({ unsafeBitCast($0, to: (RegisterPluginFunction).self) }) else {
            throw DynamicBundleError(errorDescription: "Plugin doesn't contain the expected symbol")
        }

        let result = registerPlugin()
        return result
    }

}


/// A collection of data resources, such as a file system hierarchy or a zip archive of files.
public protocol DataWrapper : AnyObject {
    associatedtype Path : DataWrapperPath
    /// The root URL of this data wrapper
    var containerURL: URL { get }
    /// Child nodes of the given parent.
    func nodes(at path: Path?) throws -> [Path]
    /// A pointer to the data at the given path; this could be either an in-memory structure (in the case if zip archives) or a wrapper around a FilePointer (in the case of a file system hierarchy)
    func seekableData(at path: Path) throws -> SeekableData

    /// All the paths contained in this wrapper
    var paths: [Path] { get }

    func find(pathsMatching: NSRegularExpression) -> [Path]
}

public protocol DataWrapperPath {
    /// The name of this path relative to the root of the file system
    var pathName: String { get }
    /// The size of the element represented by this path
    var pathSize: UInt64? { get throws }
    /// True if the path is a directory
    var pathIsDirectory: Bool { get throws }
    /// True if the path is a symbolic link
    var pathIsLink: Bool { get throws }
}

extension DataWrapperPath {
    /// The individual components of this path.
    ///
    /// - TODO: on Windows do we need to use backslash?
    public var pathComponents: [String] {
        get {
            // (pathName as NSString).pathComponents // not correct: will return "/" elements when they are at the beginning or else
            pathName
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(\.description)
        }
    }
}

// MARK: FileSystemDataWrapper

public class FileSystemDataWrapper : DataWrapper {
    public typealias Path = URL
    let root: Path
    let fm: FileManager
    public let paths: [URL]

    public init(root: Path, fileManager: FileManager = .default) throws {
        self.root = root
        self.fm = fileManager
        self.paths = try fileManager.deepContents(of: root, includeLinks: true, includeFolders: true, relativePath: true)
    }

    public var containerURL: URL {
        root
    }

    public func parent(of path: Path) throws -> Path? {
        path.deletingLastPathComponent()
    }

    /// FileManager nodes
    public func nodes(at path: Path?) throws -> [Path] {
        #if os(Linux) || os(Android) || os(Windows)
        try fm.contentsOfDirectory(at: path ?? root, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: []) // .producesRelativePathURLs unavailable
        #else
        try fm.contentsOfDirectory(at: path ?? root, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.producesRelativePathURLs])
        #endif
    }

    public func seekableData(at path: Path) throws -> SeekableData {
        // try URLSession.shared.fetch(request: URLRequest(url: path)).data
        // SeekableDataHandle(try Data(contentsOf: path), bigEndian: bigEndian)
        if fm.isReadableFile(atPath: path.path) == false {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return try SeekableFileHandle(FileHandle(forReadingFrom: path))
    }

    public func find(pathsMatching expression: NSRegularExpression) -> [Path] {
        paths.filter { path in
            expression.firstMatch(in: path.relativePath, range: path.relativePath.span) != nil
        }
    }
}


extension FileSystemDataWrapper.Path : DataWrapperPath {
    public var pathName: String {
        self.relativePath
    }

    public var pathSize: UInt64? {
        (try? self.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap({ .init($0) })
    }

    public var pathIsDirectory: Bool {
        (try? self.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    public var pathIsLink: Bool {
        (try? self.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
    }
}

// MARK: ZipArchiveDataWrapper

public class ZipArchiveDataWrapper : DataWrapper {
    public typealias Path = ZipArchivePath
    let archive: ZipArchive
    public let paths: [ZipArchivePath]

    public struct ZipArchivePath : DataWrapperPath {
        let path: String
        public let pathIsDirectory: Bool
        public let entry: ZipArchive.Entry?

        public var pathName: String {
            self.path
        }

        public var pathSize: UInt64? {
            entry?.uncompressedSize
        }


        // this is a property to enable synthesis
        //public var pathIsDirectory: Bool {
        //    entry?.type == .directory
        //}

        public var pathIsLink: Bool {
            entry?.type == .symlink
        }
    }

    public init(archive: ZipArchive) {
        self.archive = archive

        var paths = archive.map { entry in
            ZipArchivePath(path: entry.path.deletingTrailingSlash, pathIsDirectory: entry.type == .directory, entry: entry)
        }

        // find all the paths that do not have a directory entry and synthesize a folder for it, since zip file are not guaranteed to have a proper directory entry for each file entry
        var allPaths = paths.map(\.path).set()
        let parentPaths = allPaths.map(\.deletingLastPathComponent).set()
        for parentPath in parentPaths.sorted() {
            var path = parentPath
            while !path.isEmpty {
                //dbg(path)
                if allPaths.insert(path).inserted == true {
                    // synthesize a directory entry
                    // dbg("synthesizing parent directory:", parentPath)
                    paths.append(ZipArchivePath(path: path.deletingTrailingSlash, pathIsDirectory: true, entry: nil))
                }
                let subPath = path.deletingLastPathComponent
                if path == subPath { break }
                path = subPath
            }
        }
        self.paths = paths
    }

    public var containerURL: URL {
        archive.url
    }

    public func parent(of path: Path) throws -> Path? {
        paths.first(where: { p in
            path.path.deletingLastPathComponent == p.path
        })
    }

    /// ZipArchive nodes
    public func nodes(at path: Path?) throws -> [Path] {
        if let parentPath = path {
            // brute-force scan all the entries; this should be made into a tree
            return paths.filter({ p in
                p.path.deletingLastPathComponent == parentPath.path
            })
        } else {
            let rootEntries = paths.filter({ p in
                p.pathComponents.count == 1 // all top-level entries
            })

            //dbg("root entries:", rootEntries.map(\.path))
            return rootEntries
        }
    }

    public func seekableData(at path: Path) throws -> SeekableData {
        guard let entry = path.entry else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return SeekableDataHandle(try archive.extractData(from: entry))
    }

    public func find(pathsMatching expression: NSRegularExpression) -> [Path] {
        paths.filter { path in
            expression.firstMatch(in: path.path, range: path.path.span) != nil
        }
    }
}

private extension String {
    var deletingTrailingSlash: String {
        var str = self
        while str.last == "/" {
            str = String(str.dropLast())
        }
        return str
    }

    var deletingLastPathComponent: String {
        (self as NSString).deletingLastPathComponent
    }

    var lastPathComponent: String {
        (self as NSString).lastPathComponent
    }
}
