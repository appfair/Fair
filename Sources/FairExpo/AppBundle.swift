import Foundation
import FairCore
#if canImport(CoreFoundation)
import CoreFoundation
#endif

// MARK: AppBundle

/// A structure that contains an app, whether as an expanded folder or a zip archive.
public class AppBundle<Source: DataWrapper> {
    public let source: Source
    public let infoDictionary: Plist
    let infoParentNode: Source.Path?
    let infoNode: Source.Path

    /// Cache of entitlements once loaded
    private var _entitlements: [AppEntitlements]??

    public func entitlements() throws -> [AppEntitlements]? {
        if let entitlements = _entitlements {
            return entitlements
        }
        let ent = try self.loadEntitlements()
        self._entitlements = .some(ent)
        return ent
    }

    public func isSandboxed() throws -> Bool? {
        try entitlement(for: .app_sandbox)
    }

    public func appGroups() throws -> [String]? {
        try entitlement(for: .application_groups)
    }

    public init(source: Source) throws {
        self.source = source
        guard let (info, parent, node) = try Self.readInfo(source: source) else {
            throw AppBundleErrors.missingInfo
        }
        self.infoDictionary = info
        self.infoParentNode = parent
        self.infoNode = node

        #if DEBUG
        try validatePaths()
        #endif
    }

    public func entitlement<T>(for key: AppEntitlement) throws -> T? {
        try self.entitlements()?.compactMap({ $0.value(forKey: key) as? T }).first
    }
}

public extension FileManager {
    /// Resolves any symbolic links for the given file URL and returns a URL to the ulimate destination.
    func resolvingSymbolicLink(_ fileURL: URL, maxLinks: Int = 10) -> URL {
        if !fileURL.isFileURL {
            return fileURL
        }

        var linkCount = maxLinks
        var url = fileURL
        while let newPath = try? self.destinationOfSymbolicLink(atPath: url.path), newPath != url.path {
            linkCount -= 1
            if linkCount <= 0 {
                break // should this throw an exception?
            } else {
                url = URL(fileURLWithPath: newPath, relativeTo: url)
            }
        }

        if fileURL.path == url.path {
            return fileURL
        } else {
            var isDir: ObjCBool = false
            let exists = self.fileExists(atPath: url.path, isDirectory: &isDir)
            if !exists {
                return fileURL
            } else {
                return url
            }
        }
    }
}

public enum AppBundleLoader {
    /// Loads the entitlements from an app bundle (either a ipa zip or an expanded binary package).
    /// Multiple entitlements will be returned when an executable is a fat binary, although they are likely to all be equal.
    public static func loadInfo(fromAppBundle url: URL) throws -> (info: Plist, entitlements: [AppEntitlements]?) {
        if FileManager.default.isDirectory(url: FileManager.default.resolvingSymbolicLink(url)) == true {
            return try AppBundle(folderAt: url).loadInfo()
        } else {
            return try AppBundle(zipArchiveAt: url).loadInfo()
        }
    }
}

/// An alias for `Semver`
public typealias AppVersion = SemVer

extension AppBundle {
    func loadInfo() throws -> (info: Plist, entitlements: [AppEntitlements]?) {
        return try (infoDictionary, entitlements())
    }

    public func validatePaths() throws {
        for path in self.source.paths {
            if try path.pathIsLink {
                //dbg("skipping path link:", path)
            } else if try path.pathIsDirectory {
                //dbg("skipping path directory:", path)
            } else {
                //dbg("trying to read path:", path, "size:", path.pathSize, "dir:", path.pathIsDirectory)
                let _ = try self.source.seekableData(at: path)
            }
        }
    }
}

public enum AppBundleErrors : Error, LocalizedError {
    /// The Info.plist is missing from the archive
    case missingInfo

    public var failureReason: String? {
        switch self {
        case .missingInfo: return "Missing Info.plist in application bundle"
        }
    }
}

extension AppBundle {

    public var appType: AppType {
        self.infoDictionary.DTPlatformName == "iphoneos" ? .ios : .macos // not necessarily reliable
    }

    public enum AppType {
        /// A macOS .app folder containing the app
        case macos
        /// An iOS .ipa file, which is a zip containing an .app folder
        case ios
    }

    private func loadEntitlements() throws -> [AppEntitlements]? {
        guard let executable = try self.loadExecutableData() else {
            return nil
        }
        return try MachOBinary(binary: executable).readEntitlements()
    }

    public func loadExecutableData() throws -> SeekableData? {
        guard let executableName = infoDictionary.CFBundleExecutable else {
            return nil
        }

        // check first for macOS convention executable "AppName.app/Contents/MacOS/CFBundleExecutable"
        let folder = try self.source.nodes(at: infoParentNode).first(where: { try $0.pathIsDirectory && $0.pathName.lastPathComponent == "MacOS" }) ?? infoParentNode

        guard let execNode = try self.source.nodes(at: folder).first(where: { $0.pathName.lastPathComponent == executableName }) else {
            return nil
        }

        return try self.source.seekableData(at: execNode)
    }

    private static func readInfo(source: Source) throws -> (Plist, parent: Source.Path?, node: Source.Path)? {
        // dbg("reading info node from:", fs.containerURL.path)
        let rootNodes = try source.nodes(at: nil)
        //dbg("rootNodes:", rootNodes.map(\.pathName))

        func loadInfoPlist(from node: Source.Path) throws -> (Plist, parent: Source.Path, node: Source.Path)? {
            //dbg("attempting to load Info.plist from:", node.pathName)
            let contents = try source.nodes(at: node)
            guard let infoNode = contents.first(where: { $0.pathComponents.last == "Info.plist" }) else {
                // dbg("missing Info.plist node from:", contents.map(\.pathName))
                return nil
            }
            //dbg("found Info.plist node:", infoNode.pathName) // , "from:", contents.map(\.pathName))
            return try (loadPlist(from: infoNode), parent: node, node: infoNode)
        }

        func loadPlist(from infoNode: Source.Path) throws -> Plist {
            return try Plist(data: source.seekableData(at: infoNode).readData(ofLength: nil))
        }

        func rootFolders(named names: Set<String>) throws -> [Source.Path] {
            try rootNodes.filter({
                try $0.pathIsDirectory && names.contains($0.pathName.lastPathComponent)
            })
        }

        if let contentsNode = try rootFolders(named: ["Contents"]).first {
            // dbg("contentsNode", contentsNode)
            // check the "Contents/Info.plist" convention (macOS)
            return try loadInfoPlist(from: contentsNode)
        } else if let infoNode = rootNodes.first(where: { $0.pathName == "Info.plist"}) {
            return try (loadPlist(from: infoNode), parent: nil, node: infoNode)
        } else {
            for payloadNode in try rootFolders(named: ["Payload", "Wrapper"]) {
                // dbg("payloadNode", payloadNode)
                // check the "Payload/App Name.app/Info.plist" convention
                let payloadContents = try source.nodes(at: payloadNode)
                guard let appNode = try payloadContents.first(where: {
                    try $0.pathIsDirectory && $0.pathName.hasSuffix(".app")
                }) else {
                    continue
                }

                return try loadInfoPlist(from: appNode)
            }
        }

        // finally, check for root-level .app files; this handles both the case where a macOS app is distributed in a .zip, as well as .ipa files that are missing a root "Payload/" folder
        for appNode in try rootNodes.filter({
            try $0.pathIsDirectory && $0.pathName.hasSuffix(".app")
        }) {
            // check the "App Name.app/Info.plist" convention
            let appContents = try source.nodes(at: appNode)

            let contentPaths = appContents.map({ $0.pathName })
            dbg("appNode:", (appNode.pathName), "appContents:", contentPaths)

            if let contentsNode = try appContents.first(where: {
                try $0.pathIsDirectory && $0.pathName.lastPathComponent == "Contents"
            }) {
                // dbg("contentsNode", contentsNode)
                // check the "AppName.app/Contents/Info.plist" convention (macOS)
                return try loadInfoPlist(from: contentsNode)
            }

            // fall back to "AppName.app/Info.plist" convention (iOS)
            return try loadInfoPlist(from: appNode)
        }

        dbg("returning nil")
        return nil
    }
}

extension AppBundle {
    /// The path to the `Info.plist` in this bundle
//    public var infoPlistPath: Source.Path? {
//        source.paths.first(where: { $0.pathName == "Info.plist" || $0.pathName == "Contents/Info.plist" })
//    }
}

extension AppBundle where Source.Path == URL {
    /// Returns a tuple of the paths to the ".app" file and the associated "Info.plist"
    public func appInfoURLs(plistName: String = "Info.plist") throws -> (app: Source.Path, info: Source.Path) {
        let rootNodes = try self.source.nodes(at: nil)

        if let containerFolder = rootNodes.first(where: { ["Payload", "Wrapper"].contains($0.pathName) }) {
            // .ipa file: Payload/AppName.app/Info.plist
            if let appFolder = try self.source.nodes(at: containerFolder).first(where: { $0.pathName.hasSuffix(".app") }) {
                if let infoPlist = try self.source.nodes(at: appFolder).first(where: { $0.pathComponents.last == plistName }) {
                    return (appFolder, infoPlist)
                }
            }
        } else if let appFolder = rootNodes.first(where: { $0.pathName.hasSuffix(".app") }) {
            if let contentsFolder = try self.source.nodes(at: appFolder).first(where: { ["Contents"].contains($0.pathName) }) {
                // .app file: AppName.app/Contents/Info.plist
                if let infoPlist = try self.source.nodes(at: contentsFolder).first(where: { $0.pathComponents.last == plistName }) {
                    return (appFolder, infoPlist) // in this case, the app folder is the root itself
                }
            }
        }

        throw CocoaError(.fileNoSuchFile)
    }

    #if os(macOS)
    /// Changes the given platform of this app bundle.
    /// - Parameters:
    ///   - resign: the signature to re-sign with
    ///   - params: the parameters set in the version
    /// - Returns: the URL of the changed app (which will be changed in-place)
    public func setPlatformVersion(resign: String?, params: [String]) async throws -> URL {
        let (appURL, infoURL) = try self.appInfoURLs()

        dbg("setting platform for:", appURL.path, "info:", infoURL.path)

        do {
            // not necessary for fair apps, but other apps need it
            //let _ = try await Process.exec(cmd: "/usr/bin/plutil", args: ["-replace", "MinimumOSVersion", "-string", "11"] + params + [infoURL.path]).expect()
        }

        let machOFiles = try self.machOBinaries()
        dbg("mach-o files:", machOFiles)

        for machOFile in machOFiles {
            dbg("setting version in mach-o:", machOFile.path)

            try await Process.setBuildVersion(url: machOFile, params: params).expect()
            if let identity = resign {
                try await Process.codesign(url: machOFile, identity: identity, deep: false, preserveMetadata: "entitlements").expect()
            }
        }

        if let identity = resign {
            try await Process.codesign(url: appURL, identity: identity, deep: true, preserveMetadata: "entitlements").expect()
        }

        return appURL
    }

    /// Sets the bundle platform to be `"maccatalyst"`.
    /// - Parameters:
    ///   - resign: the signature to resign with
    ///   - platformName: the name of the platform
    ///   - min: the minimum platform version
    ///   - max: the maximum platform version
    /// - Returns: the URL of the converted (in-place) application URL
    public func setCatalystPlatform(resign: String? = "-", name platformName: String = "maccatalyst", min: String = "11.0", max: String = "14.0") async throws -> URL {
        try await setPlatformVersion(resign: resign, params: [platformName, min, max])

    }
    #endif
}


extension AppBundle where Source == FileSystemDataWrapper {
    /// Create an `AppBundle` backed by a `FileSystemDataWrapper` with the given root folder file URL.
    public convenience init(folderAt url: URL) throws {
//        if url.pathIsDirectory != true {
//            throw AppError(String(format: NSLocalizedString("Path was not a directory: %@", bundle: .module, comment: "error message"), url.path))
//        }
        try self.init(source: FileSystemDataWrapper(root: url))
    }
}


extension AppBundle where Source == ZipArchiveDataWrapper {
    /// Create an `AppBundle` backed by a `ZipArchiveDataWrapper` with the given zip file URL.
    public convenience init(zipArchiveAt url: URL) throws {
        try self.init(source: ZipArchiveDataWrapper(archive: ZipArchive(url: url, accessMode: .read)))
    }
}

extension AppBundle where Source.Path == URL {
    /// Returns `true` if the data at the specified path has the Mach-O magic header.
    public func maybeMachO(at path: Source.Path) throws -> Bool {
        // this will throw
        //dbg("checking path:", path.path)
        let data = try source.seekableData(at: path)
        //dbg("checked path data:", data, path.path)
        // but this will swallow exceptions, since MachOBinary is assuming sufficient header size
        return (try? MachOBinary(binary: data).getBinaryType(fromSliceStartingAt: 0)) != nil
    }

    /// Returns the list of paths that are probably (based on magic header) Mach-O binaries,
    /// either executable or dynamic libraries.
    /// - Parameter sizeThreshold: the initial size to filter
    /// - Returns: a sequence of the Mach-O binaries within the resource.
    public func machOBinaries(sizeThreshold: UInt64 = 1024) throws -> [URL] {
        try source.paths
                .filter({ !$0.pathIsDirectory })
                .filter { fileURL in
                    //dbg("filtering:", fileURL.pathName, "dir:", fileURL.pathIsDirectory, "size:", fileURL.pathSize, "macho", try? self.maybeMachO(at: fileURL))
                    (fileURL.pathIsDirectory == false) && (fileURL.pathSize ?? 0 > sizeThreshold)
                }
                .filter({
                    try self.maybeMachO(at: $0) == true
                })
    }
}


// MARK: Internal Mach-O structures

// TODO: Re-implement as read/write to support code signing
// https://github.com/indygreg/PyOxidizer/blob/main/apple-codesign/src/macho.rs#L36

public class MachOBinary {
    enum Error: Swift.Error {
        case binaryOpeningError
        case unknownBinaryFormat
        case codeSignatureCommandMissing
        case signatureReadingError
        case badMagicInSignature
        case unsupportedFatBinary

        var localizedDescription: String {
            switch self {
            case .binaryOpeningError:
                return "Error while opening application binary for reading"
            case .unknownBinaryFormat:
                return "The binary format is not supported"
            case .codeSignatureCommandMissing:
                return "Unable to find code signature load command"
            case .signatureReadingError:
                return "Signature reading error occurred"
            case .unsupportedFatBinary:
                return "Fat application binaries are unsupported"
            case .badMagicInSignature:
                return "The code page magic was incorrect"
            }
        }
    }

    fileprivate enum BinaryType {
        struct HeaderData {
            let headerSize: Int
            let commandCount: Int
        }
        case singleArch(headerInfo: HeaderData)
        case fat(header: MachOFatHeader)
    }

    private let binary: SeekableData

    public init(binary: SeekableData) throws {
        self.binary = binary.reversedEndian()
    }

    fileprivate func getBinaryType(fromSliceStartingAt offset: SeekableData.Offset) throws -> BinaryType? {
        try binary.seek(to: offset)
        let header: MachOHeader = try binary.readBinary()
        let commandCount = Int(header.ncmds)
        switch header.magic {
        case MachOMagic.MH_MAGIC:
            let data = BinaryType.HeaderData(headerSize: MemoryLayout<MachOHeader>.size, commandCount: commandCount)
            return .singleArch(headerInfo: data)
        case MachOMagic.MH_MAGIC_64:
            let data = BinaryType.HeaderData(headerSize: MemoryLayout<MachOHeader64>.size, commandCount: commandCount)
            return .singleArch(headerInfo: data)
//        case MachOMagic.FAT_MAGIC: // doesn't work
//            try binary.seek(to: offset)
//            let data: MachOFatHeader = try binary.readBinary()
//            return .fat(header: data)
//        default:
//            return nil
        default:
            try binary.seek(to: offset)
            let fatHeader: MachOFatHeader = try binary.readBinary()
            return CFSwapInt32(fatHeader.magic) == MachOMagic.FAT_MAGIC ? .fat(header: fatHeader) : nil
        }
    }

    public func readEntitlements(fromSliceStartingAt offset: SeekableData.Offset = 0) throws -> [AppEntitlements] {
        switch try getBinaryType(fromSliceStartingAt: offset) {
        case .singleArch(let headerInfo):
            let headerSize = headerInfo.headerSize
            let commandCount = headerInfo.commandCount
            //dbg("singleArch:", "offset:", offset, "headerSize:", headerSize, "commandCount:", commandCount)
            return try readEntitlementsFromBinarySlice(startingAt: offset + .init(headerSize), cmdCount: commandCount)
        case .fat(header: let header):
            return try readEntitlementsFromFatBinary(header)
        case .none:
            throw Error.unknownBinaryFormat
        }
    }

    private func readEntitlementsFromBinarySlice(startingAt offset: SeekableData.Offset, cmdCount: Int) throws -> [AppEntitlements] {
        try binary.seek(to: offset)
        var entitlements: [AppEntitlements] = []
        for _ in 0..<cmdCount {
            //dbg("checking for entitlements in offset:", offset, "index:", index, "count:", cmdCount)
            let command: LoadCommand = try binary.readBinary()
            if command.cmd == MachOMagic.LC_CODE_SIGNATURE {
                let signatureOffset: UInt32 = try binary.readUInt32()
                //dbg("checking for sig in signatureOffset:", signatureOffset, "offset:", offset, "index:", index, "count:", cmdCount)
                if let ent = try readEntitlementsFromSignature(startingAt: signatureOffset) {
                    entitlements.append(ent)
                }
            }
            try binary.seek(to: binary.offset() + .init(command.cmdsize - UInt32(MemoryLayout<LoadCommand>.size)))
        }

        return entitlements
    }

    private func readEntitlementsFromFatBinary(_ header: MachOFatHeader) throws -> [AppEntitlements] {
        let archCount = CFSwapInt32(header.nfat_arch)
        //dbg("readEntitlementsFromFatBinary:", header, "archCount:", archCount)

        if archCount <= 0 {
            throw Error.unsupportedFatBinary
        }

//        let arches: [FatArch] = try (0..<archCount).map { _ in
//            try binary.readBinary()
//        }
        var arches: [FatArch] = []
        for _ in 0..<archCount {
            arches.append(try binary.readBinary())
        }

        var entitlementList: [AppEntitlements] = []

        for arch in arches {
            let offset = CFSwapInt32(arch.offset)
            let size = CFSwapInt32(arch.size)
            //dbg("arch:", "offset:", offset, "size:", size)

            let entitlements: [AppEntitlements]

//            if false {
//                // this should work, but it fails at readEntitlementsFromSignature
//                entitlements = try readEntitlements(fromSliceStartingAt: .init(offset))
//            } else {
                try binary.seek(to: .init(offset))
                let slice = try binary.readData(ofLength: .init(size))
                entitlements = try MachOBinary(binary: SeekableDataHandle(slice)).readEntitlements(fromSliceStartingAt: 0)
//            }

            //dbg("fat binary entitlements:", entitlements)
            entitlementList.append(contentsOf: entitlements)
        }

        return entitlementList

    }

    private func readEntitlementsFromSignature(startingAt offset: UInt32) throws -> AppEntitlements? {
        try binary.seek(to: .init(offset))
        let metaBlob: CSSuperBlob = try binary.readBinary()
        //dbg("checking for magic in superblob at:", offset, ":", CFSwapInt32(metaBlob.magic))
        if CFSwapInt32(metaBlob.magic) != CSMagic.embeddedSignature {
            throw Error.badMagicInSignature
        }

        let metaBlobSize = UInt32(MemoryLayout<CSSuperBlob>.size)
        let blobSize = UInt32(MemoryLayout<CSBlob>.size)
        let itemCount = CFSwapInt32(metaBlob.count)
        //dbg("itemCount:", itemCount)
        for index in 0..<itemCount {
            //dbg("checking code index:", index, "/", itemCount)
            let readOffset = Int(offset + metaBlobSize + index * blobSize)
            try binary.seek(to: SeekableData.Offset(readOffset))
            let blob: CSBlob = try binary.readBinary()
            try binary.seek(to: SeekableData.Offset(offset + CFSwapInt32(blob.offset)))
            let blobMagic = CFSwapInt32(try binary.readUInt32())
            if blobMagic == CSMagic.embededEntitlements {
                let signatureLength = CFSwapInt32(try binary.readUInt32())
                let signatureData = try binary.readData(ofLength: .init(signatureLength) - 8)
                return AppEntitlements.readEntitlements(from: signatureData)
            }
        }

        // no entitlements
        return nil
    }
}

enum MachOMagic {
    static let LC_SEGMENT = UInt32(0x01)
    static let LC_SYMTAB = UInt32(0x02)
    static let LC_DYSYMTAB = UInt32(0x0b)
    static let LC_LOAD_DYLIB = UInt32(0x0c)
    static let LC_ID_DYLIB = UInt32(0x0d)
    static let LC_SEGMENT_64 = UInt32(0x19)
    static let LC_UUID = UInt32(0x1b)
    static let LC_CODE_SIGNATURE = UInt32(0x1d) // MachO.LC_CODE_SIGNATURE
    static let LC_SEGMENT_SPLIT_INFO = UInt32(0x1e)
    //static let LC_REEXPORT_DYLIB = UInt32(0x1f | LC_REQ_DYLD)
    static let LC_ENCRYPTION_INFO = UInt32(0x21)
    static let LC_DYLD_INFO = UInt32(0x22)
    //static let LC_DYLD_INFO_ONLY = UInt32(0x22 | LC_REQ_DYLD)
    static let LC_ENCRYPTION_INFO_64 = UInt32(0x2c)

    static var MH_MAGIC: UInt32 {
        0xfeedface /* MachO.MH_MAGIC */
    }

    static var MH_MAGIC_64: UInt32 {
        0xfeedfacf /* MachO.MH_MAGIC_64 */
    }

    static var FAT_MAGIC: UInt32 {
        0xcafebabe /* MachO.FAT_MAGIC */
    }
}

private extension SeekableData {
    func readBinary<T: BinaryReadable>() throws -> T {
        try T(data: self)
    }
}

private protocol BinaryReadable {
    init(data: SeekableData) throws
}

extension UInt32 : BinaryReadable {
    init(data: SeekableData) throws {
        self = try data.readUInt32()
    }
}

struct CSSuperBlob {
    var magic: UInt32
    var length: UInt32
    var count: UInt32
}

extension CSSuperBlob : BinaryReadable {
    init(data: SeekableData) throws {
        self = try CSSuperBlob(magic: data.readUIntX(), length: data.readUIntX(), count: data.readUIntX())
    }
}

struct CSBlob {
    var type: UInt32
    var offset: UInt32
}

extension CSBlob : BinaryReadable {
    init(data: SeekableData) throws {
        self = try CSBlob(type: data.readUIntX(), offset: data.readUIntX())
    }
}

struct CSMagic {
    static let embeddedSignature: UInt32 = 0xfade0cc0
    static let embededEntitlements: UInt32 = 0xfade7171
}

//const cpuType = {
//  0x00000003: 'i386',
//  0x80000003: 'x86_64',
//  0x00000009: 'arm',
//  0x80000009: 'arm64',
//  0x00000000: 'arm64',
//  0x0000000a: 'ppc_32',
//  0x8000000a: 'ppc_64'
//};

typealias cpu_type_t = Int32
typealias cpu_subtype_t = Int32
typealias cpu_threadtype_t = Int32

struct MachOHeader {
    var magic: UInt32 /* mach magic number identifier */
    var cputype: cpu_type_t /* cpu specifier */
    var cpusubtype: cpu_subtype_t /* machine specifier */
    var filetype: UInt32 /* type of file */
    var ncmds: UInt32 /* number of load commands */
    var sizeofcmds: UInt32 /* the size of all the load commands */
    var flags: UInt32 /* flags */
}

extension MachOHeader : BinaryReadable {
    init(data: SeekableData) throws {
        self = try MachOHeader(magic: data.readUIntX(), cputype: data.readInt32(), cpusubtype: data.readInt32(), filetype: data.readUIntX(), ncmds: data.readUIntX(), sizeofcmds: data.readUIntX(), flags: data.readUIntX())
    }
}

/*
 * The 64-bit mach header appears at the very beginning of object files for
 * 64-bit architectures.
 */
struct MachOHeader64 {
    var magic: UInt32 /* mach magic number identifier */
    var cputype: cpu_type_t /* cpu specifier */
    var cpusubtype: cpu_subtype_t /* machine specifier */
    var filetype: UInt32 /* type of file */
    var ncmds: UInt32 /* number of load commands */
    var sizeofcmds: UInt32 /* the size of all the load commands */
    var flags: UInt32 /* flags */
    var reserved: UInt32 /* reserved */
}

struct MachOFatHeader {
    var magic: UInt32 /* FAT_MAGIC or FAT_MAGIC_64 */
    var nfat_arch: UInt32 /* number of structs that follow */
}

extension MachOFatHeader : BinaryReadable {
    init(data: SeekableData) throws {
        self = try MachOFatHeader(magic: data.readUIntX(), nfat_arch: data.readUIntX())
    }
}

// mach-o loader.h `load_command`
struct LoadCommand {
    public var cmd: UInt32 /* type of load command */
    public var cmdsize: UInt32 /* total size of command in bytes */
}

extension LoadCommand : BinaryReadable {
    init(data: SeekableData) throws {
        self = try LoadCommand(cmd: data.readUIntX(), cmdsize: data.readUIntX())
    }
}

/// From mach-o fat.h: `struct fat_arch`222
struct FatArch {
    var cputype: cpu_type_t /* cpu specifier (int) */
    var cpusubtype: cpu_subtype_t /* machine specifier (int) */
    var offset: UInt32 /* file offset to this object file */
    var size: UInt32 /* size of this object file */
    var align: UInt32 /* alignment as a power of 2 */
}

extension FatArch : BinaryReadable {
    init(data: SeekableData) throws {
        self = try FatArch(cputype: data.readInt32(), cpusubtype: data.readInt32(), offset: data.readUIntX(), size: data.readUIntX(), align: data.readUIntX())
    }
}


extension Locale {
    /// The name of the folder for exporting locales
    static let exportedLocaleFolders = [
        "ar": "ar-SA",
        "ca": "ca",
        "cs": "cs",
        "da": "da",
        "de": "de-DE",
        "el": "el",
        "en": "en-US",
        "en_AU": "en-AU",
        "en_CA": "en-CA",
        "en_GB": "en-GB",
        "en_US": "en-US",
        "es": "es-ES",
        "es_ES": "es-ES",
        "es_419": "es-MX",
        "fi": "fi",
        "fr_CA": "fr-CA",
        "fr_FR": "fr-FR",
        "fr": "fr-FR",
        "he": "he",
        "hi": "hi",
        "hr": "hr",
        "hu": "hu",
        "id": "id",
        "it": "it",
        "ja": "ja",
        "ko": "ko",
        "ms": "ms",
        "nl": "nl-NL",
        "no": "no",
        "pl": "pl",
        "pt_BR": "pt-BR",
        "pt_PT": "pt-PT",
        "pt": "pt-BR",
        "ro": "ro",
        "ru": "ru",
        "sk": "sk",
        "sv": "sv",
        "th": "th",
        "tr": "tr",
        "uk": "uk",
        "vi": "vi",
        "zh_Hans": "zh-Hans",
        "zh_Hant": "zh-Hant",
        "zh-Hans": "zh-Hans",
        "zh-Hant": "zh-Hant",
    ]

    /// The name of the folder that would be expected to store the locale information. This is typically the locale identifier with a "-" instead of a `"_"`,
    /// and generally conforms to https://en.wikipedia.org/wiki/IETF_language_tag
    ///
    /// `["ar-SA", "ca", "cs", "da", "de-DE", "el", "en-AU", "en-CA", "en-GB", "en-US", "es-ES", "es-MX", "fi", "fr-CA", "fr-FR", "he", "hi", "hr", "hu", "id", "it", "ja", "ko", "ms", "nl-NL", "no", "pl", "pt-BR", "pt-PT", "ro", "ru", "sk", "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant", "default"]`
    var knownLanguageTag: String? {
        Self.exportedLocaleFolders[self.identifier]
    }

    var exportedMetadataFolderName: String? {
        knownLanguageTag
    }

    /// The  https://en.wikipedia.org/wiki/IETF_language_tag for this locale, if it exists.
    public var languageTag: String {
        knownLanguageTag ?? self.identifier.replacingOccurrences(of: "_", with: "-")
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
