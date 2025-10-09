import Swift
import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif
#if canImport(Glibc)
import Glibc
import var Glibc.S_IFREG
import var Glibc.S_IFDIR
import var Glibc.S_IFLNK
#elseif canImport(Musl)
import Musl
import var Musl.S_IFREG
import var Musl.S_IFDIR
import var Musl.S_IFLNK
#endif
import CZLib
#if canImport(zlib)
import zlib
#endif



extension ZipArchive {

    /// Extracts the data from the given entry
    public func extractData(from entry: ZipArchive.Entry) throws -> Data {
        var data = Data()
        let _ = try extract(entry) { data.append($0) }
        return data
    }

    /// Extracts the data from the entry asynchronously
    public func extractAsync(from entry: ZipArchive.Entry, bufferSize: Int = defaultReadChunkSize, skipCRC32: Bool = false, progress: Progress? = nil) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { c in
//            Task {
                do {
                    _ = try extract(entry, bufferSize: bufferSize, skipCRC32: skipCRC32, progress: progress) {
                        try Task.checkCancellation()
                        c.yield($0)
                    }
                    c.finish()
                } catch {
                    c.finish(throwing: error)
                }
//            }
        }
    }
}

@available(macOS 10.14, iOS 12.0, *)
public extension Data {
    enum CompressionAlgorithm : String, CaseIterable, Codable {
        case zlib
        case lz4
        case lzma
        case lzfse
    }

    /// Compresses the data using the deflate algorithm and makes it comply to the zlib format.
    /// Note that this only creates an individual deflated blob; for multi-file zip support use `ZipArchive` instead.
    /// - Parameters:
    ///   - level: the zip level to encode
    ///   - checksum: if true verify the compression checksum
    ///   - wrap: whether to wrap in zlib headers with the compression level and a suffix as the adler32
    func deflate(level: Int? = nil, checksum: Bool = true, wrap: Bool = false) throws -> (crc: CRC32?, data: Data) {
        func headers(_ source: (crc: CRC32?, data: Data)) -> (crc: CRC32?, data: Data) {
            if !wrap { return source }
            return (source.crc, Data([0x78, level == nil ? 0x9C : (level! <= 5) ? 0x01 : 0xDA]) + source.data + Data.adler32Data(self))
        }

        #if canImport(CZLib)
        if let level = level {
            return try headers(zipZlib(level: level))
        }
        #endif

        #if canImport(XXXCompression)
        // “The Compression library implements the zlib encoder at level 5 only” – https://developer.apple.com/documentation/compression/compression_algorithm/compression_zlib/
        return try headers(zipLegacy(checksum: checksum))
        #endif

        #if canImport(CZLib)
        return try headers(zipZlib(level: 5)) // fall back to zlib default compression level 5
        #endif
    }

    /// Decompresses the data using the zlib deflate algorithm.
    /// Note that this only creates an individual inflated blob; for multi-file zip support use `ZipArchive` instead.
    func inflate(checksum: Bool = true, wrapped header: Bool = false) throws -> (crc: CRC32?, data: Data) {
        let head = self.prefix(header ? 2 : 0)
        if head.count == 2 {
            if head[0] != 0x78 {
                throw Archive.ArchiveError.unreadableArchive
            }
        }

        let data = self.dropFirst(head.count)

        #if canImport(XXXCompression)
        return try data.unzipLegacy(checksum: checksum)
        #endif
        #if canImport(CZLib)
        return try data.unzipZlib(checksum: checksum)
        #endif
    }

    /// Invoke the data provide and consumer
    @inlinable internal func feedData<T>(process: (_ provider: Provider, _ consumer: Consumer) throws -> T) rethrows -> (T, Data) {
        let start = self.startIndex // need to offset by the start index in case this is a slice
        let end = self.endIndex
        var d = Data()

        let result = try process({ position, size in
            self[Swift.max(start, .init(position) + start)..<Swift.min(end, .init(position) + start + size)]
        }, { data in
            d += data
        })
        return (result, d)
    }
}


extension String {
    /// Removes the root path of a string.
    ///
    /// E.g., "x/y/z" -> "y/z"
    public var trimmingBasePath: String {
        let paths = self.split(separator: "/")
        if paths.count > 1, let basePath = paths.first, !basePath.isEmpty {
            return String(self.dropFirst(basePath.count + 1))
        } else {
            return "" // no slashes; trim the whole root
        }
    }
}

#if canImport(CZLib)

@available(macOS 10.14, iOS 12.0, *)
public extension Data {
    @inlinable func zipZlib(level: Int, bufferSize: Int = defaultReadChunkSize, checksum: Bool = true) throws -> (crc: CRC32?, data: Data) {
        try feedData(process: { provider, consumer in
            try Data.zlibCompress(level: level, size: .init(self.count), bufferSize: bufferSize, provider: provider, consumer: consumer)
        })
    }

    @inlinable func unzipZlib(bufferSize: Int = defaultReadChunkSize, checksum: Bool = true) throws -> (crc: CRC32?, data: Data) {
        try feedData(process: { provider, consumer in
            try Data.zlibDecompress(bufferSize: bufferSize, skipCRC32: !checksum, provider: provider, consumer: consumer)
        })
    }
}

@usableFromInline func zlibCRC32(data: Data, checksum: CRC32) -> CRC32 {
    data.withUnsafeBytes { bufferPointer in
        CRC32(crc32(UInt(checksum), bufferPointer.bindMemory(to: UInt8.self).baseAddress, UInt32(data.count)))
    }
}

@usableFromInline func zlibDeflate(_ strm: z_streamp, _ flush: Int32) -> Int32 {
    deflate(strm, flush)
}

/// Cover func
@usableFromInline func zlibInflate(_ strm: z_streamp, _ flush: Int32) -> Int32 {
    inflate(strm, flush)
}

#endif // canImport(CZLib)


extension Data {
    @usableFromInline static let prime = UInt32(65521)

    @inlinable public func decompressInflate() throws -> Data {
        #if canImport(XXXCompression)
        let decompressed = decompressInternal(self)
        #else
        let decompressed = try self.inflate(wrapped: true).data
        #endif
//        #if DEBUG
//        let d2 = try source.unzip(wrapped: true).data
//        //dbg("unzipped:", d2, "vs decompressed:", decompressed, "source:", source)
//        if decompressed != d2 {
////            dbg(decompressed.hex())
////            dbg(d2.hex())
//            assert(decompressed == d2)
//        }
//        #endif
        return decompressed
    }

    @inlinable public static func compressDeflate(_ source: Data, level: Int) throws -> Data {
        try source.deflate(level: level, wrap: true).data
    }

    #if canImport(XXXCompression)
    @available(*, deprecated)
    @usableFromInline static func decompressInternal(_ data: Data) -> Data {
        return data.withUnsafeBytes {
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count * 10)
            let result = Data(bytes: buffer, count: compression_decode_buffer(
                buffer, data.count * 10, $0.baseAddress!.bindMemory(
                    to: UInt8.self, capacity: 1).advanced(by: 2), data.count - 2, nil, COMPRESSION_ZLIB))
            buffer.deallocate()
            return result
        }
    }
    #endif

    @inlinable public static func adler32Data(_ data: Data) -> Data {
        var s1 = UInt32(1 & 0xffff)
        var s2 = UInt32((1 >> 16) & 0xffff)
        data.forEach {
            s1 += UInt32($0)
            if s1 >= prime { s1 = s1 % prime }
            s2 += s1
            if s2 >= prime { s2 = s2 % prime }
        }
        var result = ((s2 << 16) | s1).bigEndian
        return Data(bytes: &result, count: MemoryLayout<UInt32>.size)
    }
}


#if canImport(CompressionXXX)
import Compression // TODO: remove Compression and use zlib

extension Data {
    @available(*, deprecated, message: "remove non-portable import Compression")
    @inlinable static func unpackNonPortable(_ size: Int, data: Data) throws -> (index: Int, result: Data) {
        var index = Swift.max(try compress(data.decompress(), level: wip(5)).count - Swift.max(size / 30, 9), 0)
        let result = try data.withUnsafeBytes {
            var stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1).pointee
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            var status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
            var advance = 2
            var read = index + 1
            var result = Data()
            repeat {
                index += 1
                stream.dst_ptr = buffer
                stream.dst_size = size
                stream.src_size = read
                stream.src_ptr = $0.baseAddress!.bindMemory(to: UInt8.self, capacity: 1).advanced(by: advance)
                status = compression_stream_process(&stream, 0)
                result += Data(bytes: buffer, count: size - stream.dst_size)
                read = 1
                advance = 2 + index
            } while status == COMPRESSION_STATUS_OK
            buffer.deallocate()
            compression_stream_destroy(&stream)
            guard status == COMPRESSION_STATUS_END else { throw Git.Failure.Pack.read }
            guard result.count == size else { throw Git.Failure.Pack.size }
            return result
        } as Data

        let adler = adler32(result)
        var found = false
        var drift = 0
        repeat {
            if drift > 3 { throw Git.Failure.Pack.adler }
            if adler[0] == data[index + drift],
               adler[1] == data[index + drift + 1],
               adler[2] == data[index + drift + 2],
               adler[3] == data[index + drift + 3] {
                found = true
            }
            drift += 1
        } while !found

        index += 6

        return (index, result)
    }

}
#endif



fileprivate typealias Archive = ZipArchive

// ZipArchive is mostly based on ZIPFoundation with some patches (notably https://github.com/weichsel/ZIPFoundation/pull/187 ), which uses the following license:
//
// MIT License
//
// Copyright (c) 2017-2021 Thomas Zoechling (https://www.peakstep.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.


/// The default chunk size when reading entry data from an archive.
public let defaultReadChunkSize = Int(16*1024)
/// The default chunk size when writing entry data to an archive.
public let defaultWriteChunkSize = defaultReadChunkSize
/// The default permissions for newly added entries.
public let defaultFilePermissions = UInt16(0o644)
/// The default permissions for newly added directories.
public let defaultDirectoryPermissions = UInt16(0o755)
let defaultPOSIXBufferSize = defaultReadChunkSize
let defaultDirectoryUnitCount = Int64(1)
let minEndOfCentralDirectoryOffset = Int64(22)
let endOfCentralDirectoryStructSignature = 0x06054b50
let localFileHeaderStructSignature = 0x04034b50
let dataDescriptorStructSignature = 0x08074b50
let centralDirectoryStructSignature = 0x02014b50
let memoryURLScheme = "memory"

/// A sequence of uncompressed or compressed ZIP entries.
///
/// You use an `Archive` to create, read or update ZIP files.
/// To read an existing ZIP file, you have to pass in an existing file `URL` and `AccessMode.read`:
///
///     var archiveURL = URL(fileURLWithPath: "/path/file.zip")
///     var archive = Archive(url: archiveURL, accessMode: .read)
///
/// An `Archive` is a sequence of entries. You can
/// iterate over an archive using a `for`-`in` loop to get access to individual `Entry` objects:
///
///     for entry in archive {
///         print(entry.path)
///     }
///
/// Each `Entry` in an `Archive` is represented by its `path`. You can
/// use `path` to retrieve the corresponding `Entry` from an `Archive` via subscripting:
///
///     let entry = archive['/path/file.txt']
///
/// To create a new `Archive`, pass in a non-existing file URL and `AccessMode.create`. To modify an
/// existing `Archive` use `AccessMode.update`:
///
///     var archiveURL = URL(fileURLWithPath: "/path/file.zip")
///     var archive = Archive(url: archiveURL, accessMode: .update)
///     try archive?.addEntry("test.txt", relativeTo: baseURL, compressionMethod: .deflate)
public final class ZipArchive: Sequence {
    typealias LocalFileHeader = Entry.LocalFileHeader
    typealias DataDescriptor = Entry.DefaultDataDescriptor
    typealias ZIP64DataDescriptor = Entry.ZIP64DataDescriptor
    typealias CentralDirectoryStructure = Entry.CentralDirectoryStructure

    /// An error that occurs during reading, creating or updating a ZIP file.
    public enum ArchiveError: Error {
        /// Thrown when an archive file is either damaged or inaccessible.
        case unreadableArchive
        /// Thrown when an archive is either opened with AccessMode.read or the destination file is unwritable.
        case unwritableArchive
        /// Thrown when the path of an `Entry` cannot be stored in an archive.
        case invalidEntryPath
        /// Thrown when an `Entry` can't be stored in the archive with the proposed compression method.
        case invalidCompressionMethod
        /// Thrown when the stored checksum of an `Entry` doesn't match the checksum during reading.
        case invalidCRC32
        /// Thrown when an extract, add or remove operation was canceled.
        case cancelledOperation
        /// Thrown when an extract operation was called with zero or negative `bufferSize` parameter.
        case invalidBufferSize
        /// Thrown when uncompressedSize/compressedSize exceeds `Int64.max` (Imposed by file API).
        case invalidEntrySize
        /// Thrown when the offset of local header data exceeds `Int64.max` (Imposed by file API).
        case invalidLocalHeaderDataOffset
        /// Thrown when the size of local header exceeds `Int64.max` (Imposed by file API).
        case invalidLocalHeaderSize
        /// Thrown when the offset of central directory exceeds `Int64.max` (Imposed by file API).
        case invalidCentralDirectoryOffset
        /// Thrown when the size of central directory exceeds `UInt64.max` (Imposed by ZIP specification).
        case invalidCentralDirectorySize
        /// Thrown when number of entries in central directory exceeds `UInt64.max` (Imposed by ZIP specification).
        case invalidCentralDirectoryEntryCount
        /// Thrown when an archive does not contain the required End of Central Directory Record.
        case missingEndOfCentralDirectoryRecord
    }

    /// The access mode for an `Archive`.
    public enum AccessMode: UInt {
        /// Indicates that a newly instantiated `Archive` should create its backing file.
        case create
        /// Indicates that a newly instantiated `Archive` should read from an existing backing file.
        case read
        /// Indicates that a newly instantiated `Archive` should update an existing backing file.
        case update
    }

    /// The version of an `Archive`
    enum Version: UInt16 {
        /// The minimum version for deflate compressed archives
        case v20 = 20
        /// The minimum version for archives making use of ZIP64 extensions
        case v45 = 45
    }

    struct EndOfCentralDirectoryRecord: DataSerializable {
        let endOfCentralDirectorySignature = UInt32(endOfCentralDirectoryStructSignature)
        let numberOfDisk: UInt16
        let numberOfDiskStart: UInt16
        let totalNumberOfEntriesOnDisk: UInt16
        let totalNumberOfEntriesInCentralDirectory: UInt16
        let sizeOfCentralDirectory: UInt32
        let offsetToStartOfCentralDirectory: UInt32
        let zipFileCommentLength: UInt16
        let zipFileCommentData: Data
        static let size = 22
    }

    /// URL of an Archive's backing file.
    public let url: URL
    /// Access mode for an archive file.
    public let accessMode: AccessMode
    var archiveFile: FILEPointer
    var endOfCentralDirectoryRecord: EndOfCentralDirectoryRecord
    var zip64EndOfCentralDirectory: ZIP64EndOfCentralDirectory?
    var preferredEncoding: String.Encoding?
    let compressionLevel: Int?

    var totalNumberOfEntriesInCentralDirectory: UInt64 {
        zip64EndOfCentralDirectory?.record.totalNumberOfEntriesInCentralDirectory
            ?? UInt64(endOfCentralDirectoryRecord.totalNumberOfEntriesInCentralDirectory)
    }
    var sizeOfCentralDirectory: UInt64 {
        zip64EndOfCentralDirectory?.record.sizeOfCentralDirectory
            ?? UInt64(endOfCentralDirectoryRecord.sizeOfCentralDirectory)
    }
    var offsetToStartOfCentralDirectory: UInt64 {
        zip64EndOfCentralDirectory?.record.offsetToStartOfCentralDirectory
            ?? UInt64(endOfCentralDirectoryRecord.offsetToStartOfCentralDirectory)
    }

    /// Initializes a new ZIP `Archive`.
    ///
    /// You can use this initalizer to create new archive files or to read and update existing ones.
    /// The `mode` parameter indicates the intended usage of the archive: `.read`, `.create` or `.update`.
    /// - Parameters:
    ///   - url: File URL to the receivers backing file.
    ///   - mode: Access mode of the receiver.
    ///   - preferredEncoding: Encoding for entry paths. Overrides the encoding specified in the archive.
    ///                        This encoding is only used when _decoding_ paths from the receiver.
    ///                        Paths of entries added with `addEntry` are always UTF-8 encoded.
    /// - Returns: An archive initialized with a backing file at the passed in file URL and the given access mode
    ///   or `nil` if the following criteria are not met:
    /// - Note:
    ///   - The file URL _must_ point to an existing file for `AccessMode.read`.
    ///   - The file URL _must_ point to a non-existing file for `AccessMode.create`.
    ///   - The file URL _must_ point to an existing file for `AccessMode.update`.
    public init(url: URL, accessMode mode: AccessMode, compressionLevel: Int? = nil, preferredEncoding: String.Encoding? = nil) throws {
        self.url = url
        self.accessMode = mode
        self.preferredEncoding = preferredEncoding
        self.compressionLevel = compressionLevel
        let config = try Archive.makeBackingConfiguration(for: url, mode: mode)
        self.archiveFile = config.file
        self.endOfCentralDirectoryRecord = config.endOfCentralDirectoryRecord
        self.zip64EndOfCentralDirectory = config.zip64EndOfCentralDirectory
        setvbuf(self.archiveFile, nil, _IOFBF, Int(defaultPOSIXBufferSize))
    }

    #if swift(>=5.0)
    var memoryFile: MemoryFile?

    /// Initializes a new in-memory ZIP `Archive`.
    ///
    /// You can use this initalizer to create new in-memory archive files or to read and update existing ones.
    ///
    /// - Parameters:
    ///   - data: `Data` object used as backing for in-memory archives.
    ///   - mode: Access mode of the receiver.
    ///   - preferredEncoding: Encoding for entry paths. Overrides the encoding specified in the archive.
    ///                        This encoding is only used when _decoding_ paths from the receiver.
    ///                        Paths of entries added with `addEntry` are always UTF-8 encoded.
    /// - Returns: An in-memory archive initialized with passed in backing data.
    /// - Note:
    ///   - The backing `data` _must_ contain a valid ZIP archive for `AccessMode.read` and `AccessMode.update`.
    ///   - The backing `data` _must_ be empty (or omitted) for `AccessMode.create`.
    public init?(data: Data = Data(), accessMode mode: AccessMode, compressionLevel: Int? = nil, preferredEncoding: String.Encoding? = nil) {
        guard let url = URL(string: "\(memoryURLScheme)://"),
            let config = Archive.makeBackingConfiguration(for: data, mode: mode) else {
            return nil
        }

        self.url = url
        self.accessMode = mode
        self.preferredEncoding = preferredEncoding
        self.compressionLevel = compressionLevel
        self.archiveFile = config.file
        self.memoryFile = config.memoryFile
        self.endOfCentralDirectoryRecord = config.endOfCentralDirectoryRecord
        self.zip64EndOfCentralDirectory = config.zip64EndOfCentralDirectory
    }
    #endif

    deinit {
        fclose(self.archiveFile)
    }

    public func makeIterator() -> AnyIterator<Entry> {
        let totalNumberOfEntriesInCD = self.totalNumberOfEntriesInCentralDirectory
        var directoryIndex = self.offsetToStartOfCentralDirectory
        var index = 0
        return AnyIterator {
            guard index < totalNumberOfEntriesInCD else { return nil }
            guard let centralDirStruct: CentralDirectoryStructure = Data.readStruct(from: self.archiveFile,
                                                                                    at: directoryIndex) else {
                                                                                        return nil
            }
            let offset = UInt64(centralDirStruct.effectiveRelativeOffsetOfLocalHeader)
            guard let localFileHeader: LocalFileHeader = Data.readStruct(from: self.archiveFile,
                                                                         at: offset) else { return nil }
            var dataDescriptor: DataDescriptor?
            var zip64DataDescriptor: ZIP64DataDescriptor?
            if centralDirStruct.usesDataDescriptor {
                let additionalSize = UInt64(localFileHeader.fileNameLength) + UInt64(localFileHeader.extraFieldLength)
                let isCompressed = centralDirStruct.compressionMethod != CompressionMethod.none.rawValue
                let dataSize = isCompressed
                    ? centralDirStruct.effectiveCompressedSize
                    : centralDirStruct.effectiveUncompressedSize
                let descriptorPosition = offset + UInt64(LocalFileHeader.size) + additionalSize + dataSize
                if centralDirStruct.isZIP64 {
                    zip64DataDescriptor = Data.readStruct(from: self.archiveFile, at: descriptorPosition)
                } else {
                    dataDescriptor = Data.readStruct(from: self.archiveFile, at: descriptorPosition)
                }
            }
            defer {
                directoryIndex += UInt64(CentralDirectoryStructure.size)
                directoryIndex += UInt64(centralDirStruct.fileNameLength)
                directoryIndex += UInt64(centralDirStruct.extraFieldLength)
                directoryIndex += UInt64(centralDirStruct.fileCommentLength)
                index += 1
            }
            return Entry(centralDirectoryStructure: centralDirStruct, localFileHeader: localFileHeader,
                         dataDescriptor: dataDescriptor, zip64DataDescriptor: zip64DataDescriptor)
        }
    }

    /// Retrieve the ZIP `Entry` with the given `path` from the receiver.
    ///
    /// - Note: The ZIP file format specification does not enforce unique paths for entries.
    ///   Therefore an archive can contain multiple entries with the same path. This method
    ///   always returns the first `Entry` with the given `path`.
    ///
    /// - Parameter path: A relative file path identifying the corresponding `Entry`.
    /// - Returns: An `Entry` with the given `path`. Otherwise, `nil`.
    public subscript(path: String) -> Entry? {
        if let encoding = preferredEncoding {
            return self.first { $0.path(using: encoding) == path }
        }
        return self.first { $0.path == path }
    }

    // MARK: - Helpers

    static func scanForEndOfCentralDirectoryRecord(in file: FILEPointer)
        -> EndOfCentralDirectoryStructure? {
        var eocdOffset: UInt64 = 0
        var index = minEndOfCentralDirectoryOffset
        fseeko(file, 0, SEEK_END)
        let archiveLength = Int64(ftello(file))
        while eocdOffset == 0 && index <= archiveLength {
            fseeko(file, off_t(archiveLength - index), SEEK_SET)
            var potentialDirectoryEndTag: UInt32 = UInt32()
            fread(&potentialDirectoryEndTag, 1, MemoryLayout<UInt32>.size, file)
            if potentialDirectoryEndTag == UInt32(endOfCentralDirectoryStructSignature) {
                eocdOffset = UInt64(archiveLength - index)
                guard let eocd: EndOfCentralDirectoryRecord = Data.readStruct(from: file, at: eocdOffset) else {
                    return nil
                }
                let zip64EOCD = scanForZIP64EndOfCentralDirectory(in: file, eocdOffset: eocdOffset)
                return (eocd, zip64EOCD)
            }
            index += 1
        }
        return nil
    }

    private static func scanForZIP64EndOfCentralDirectory(in file: FILEPointer, eocdOffset: UInt64)
        -> ZIP64EndOfCentralDirectory? {
        guard UInt64(ZIP64EndOfCentralDirectoryLocator.size) < eocdOffset else {
            return nil
        }
        let locatorOffset = eocdOffset - UInt64(ZIP64EndOfCentralDirectoryLocator.size)

        guard UInt64(ZIP64EndOfCentralDirectoryRecord.size) < locatorOffset else {
            return nil
        }
        let recordOffset = locatorOffset - UInt64(ZIP64EndOfCentralDirectoryRecord.size)
        guard let locator: ZIP64EndOfCentralDirectoryLocator = Data.readStruct(from: file, at: locatorOffset),
              let record: ZIP64EndOfCentralDirectoryRecord = Data.readStruct(from: file, at: recordOffset) else {
            return nil
        }
        return ZIP64EndOfCentralDirectory(record: record, locator: locator)
    }
}

extension ZipArchive.EndOfCentralDirectoryRecord {
    var data: Data {
        var endOfCDSignature = self.endOfCentralDirectorySignature
        var numberOfDisk = self.numberOfDisk
        var numberOfDiskStart = self.numberOfDiskStart
        var totalNumberOfEntriesOnDisk = self.totalNumberOfEntriesOnDisk
        var totalNumberOfEntriesInCD = self.totalNumberOfEntriesInCentralDirectory
        var sizeOfCentralDirectory = self.sizeOfCentralDirectory
        var offsetToStartOfCD = self.offsetToStartOfCentralDirectory
        var zipFileCommentLength = self.zipFileCommentLength
        var data = Data()
        withUnsafePointer(to: &endOfCDSignature, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &numberOfDisk, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &numberOfDiskStart, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &totalNumberOfEntriesOnDisk, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &totalNumberOfEntriesInCD, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &sizeOfCentralDirectory, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &offsetToStartOfCD, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &zipFileCommentLength, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        data.append(self.zipFileCommentData)
        return data
    }

    init?(data: Data, additionalDataProvider provider: (Int) throws -> Data) {
        guard data.count == Archive.EndOfCentralDirectoryRecord.size else { return nil }
        guard data.scanValue(start: 0) == endOfCentralDirectorySignature else { return nil }
        self.numberOfDisk = data.scanValue(start: 4)
        self.numberOfDiskStart = data.scanValue(start: 6)
        self.totalNumberOfEntriesOnDisk = data.scanValue(start: 8)
        self.totalNumberOfEntriesInCentralDirectory = data.scanValue(start: 10)
        self.sizeOfCentralDirectory = data.scanValue(start: 12)
        self.offsetToStartOfCentralDirectory = data.scanValue(start: 16)
        self.zipFileCommentLength = data.scanValue(start: 20)
        guard let commentData = try? provider(Int(self.zipFileCommentLength)) else { return nil }
        guard commentData.count == Int(self.zipFileCommentLength) else { return nil }
        self.zipFileCommentData = commentData
    }

    init(record: ZipArchive.EndOfCentralDirectoryRecord,
         numberOfEntriesOnDisk: UInt16,
         numberOfEntriesInCentralDirectory: UInt16,
         updatedSizeOfCentralDirectory: UInt32,
         startOfCentralDirectory: UInt32) {
        self.numberOfDisk = record.numberOfDisk
        self.numberOfDiskStart = record.numberOfDiskStart
        self.totalNumberOfEntriesOnDisk = numberOfEntriesOnDisk
        self.totalNumberOfEntriesInCentralDirectory = numberOfEntriesInCentralDirectory
        self.sizeOfCentralDirectory = updatedSizeOfCentralDirectory
        self.offsetToStartOfCentralDirectory = startOfCentralDirectory
        self.zipFileCommentLength = record.zipFileCommentLength
        self.zipFileCommentData = record.zipFileCommentData
    }
}

// MARK: Entry.swift

internal typealias Entry = ZipArchive.Entry

extension ZipArchive {

    /// A value that represents a file, a directory or a symbolic link within a ZIP `Archive`.
    ///
    /// You can retrieve instances of `Entry` from an `Archive` via subscripting or iteration.
    /// Entries are identified by their `path`.
    public struct Entry: Equatable {
        /// The type of an `Entry` in a ZIP `Archive`.
        public enum EntryType: Int {
            /// Indicates a regular file.
            case file
            /// Indicates a directory.
            case directory
            /// Indicates a symbolic link.
            case symlink

            init(mode: mode_t) {
                switch mode & S_IFMT {
                case S_IFDIR:
                    self = .directory
                case S_IFLNK:
                    self = .symlink
                default:
                    self = .file
                }
            }
        }

        enum OSType: UInt {
            case msdos = 0
            case unix = 3
            case osx = 19
            case unused = 20
        }

        struct LocalFileHeader: DataSerializable {
            let localFileHeaderSignature = UInt32(localFileHeaderStructSignature)
            let versionNeededToExtract: UInt16
            let generalPurposeBitFlag: UInt16
            let compressionMethod: UInt16
            let lastModFileTime: UInt16
            let lastModFileDate: UInt16
            let crc32: UInt32
            let compressedSize: UInt32
            let uncompressedSize: UInt32
            let fileNameLength: UInt16
            let extraFieldLength: UInt16
            static let size = 30
            let fileNameData: Data
            let extraFieldData: Data
            var extraFields: [ExtensibleDataField]?
        }

        struct DataDescriptor<T: BinaryInteger>: DataSerializable {
            let data: Data
            let dataDescriptorSignature = UInt32(dataDescriptorStructSignature)
            let crc32: UInt32
            // For normal archives, the compressed and uncompressed sizes are 4 bytes each.
            // For ZIP64 format archives, the compressed and uncompressed sizes are 8 bytes each.
            let compressedSize: T
            let uncompressedSize: T
            static var memoryLengthOfSize: Int { MemoryLayout<T>.size }
            static var size: Int { memoryLengthOfSize * 2 + 8 }
        }

        typealias DefaultDataDescriptor = DataDescriptor<UInt32>
        typealias ZIP64DataDescriptor = DataDescriptor<UInt64>

        struct CentralDirectoryStructure: DataSerializable {
            let centralDirectorySignature = UInt32(centralDirectoryStructSignature)
            let versionMadeBy: UInt16
            let versionNeededToExtract: UInt16
            let generalPurposeBitFlag: UInt16
            let compressionMethod: UInt16
            let lastModFileTime: UInt16
            let lastModFileDate: UInt16
            let crc32: UInt32
            let compressedSize: UInt32
            let uncompressedSize: UInt32
            let fileNameLength: UInt16
            let extraFieldLength: UInt16
            let fileCommentLength: UInt16
            let diskNumberStart: UInt16
            let internalFileAttributes: UInt16
            let externalFileAttributes: UInt32
            let relativeOffsetOfLocalHeader: UInt32
            static let size = 46
            let fileNameData: Data
            let extraFieldData: Data
            let fileCommentData: Data

            var extraFields: [ExtensibleDataField]?
            var usesDataDescriptor: Bool { return (self.generalPurposeBitFlag & (1 << 3 )) != 0 }
            var usesUTF8PathEncoding: Bool { return (self.generalPurposeBitFlag & (1 << 11 )) != 0 }
            var isEncrypted: Bool { return (self.generalPurposeBitFlag & (1 << 0)) != 0 }
            var isZIP64: Bool {
                // If ZIP64 extended information is existing, try to treat cd as ZIP64 format
                // even if the version needed to extract is lower than 4.5
                return UInt8(truncatingIfNeeded: self.versionNeededToExtract) >= 45 || zip64ExtendedInformation != nil
            }
        }
        /// Returns the `path` of the receiver within a ZIP `Archive` using a given encoding.
        ///
        /// - Parameters:
        ///   - encoding: `String.Encoding`
        public func path(using encoding: String.Encoding) -> String {
            return String(data: self.centralDirectoryStructure.fileNameData, encoding: encoding) ?? ""
        }
        /// The `path` of the receiver within a ZIP `Archive`.
        public var path: String {
            let dosLatinUS = 0x400
            let dosLatinUSEncoding = CFStringEncoding(dosLatinUS)
            let dosLatinUSStringEncoding = CFStringConvertEncodingToNSStringEncoding(dosLatinUSEncoding)
            let codepage437 = String.Encoding(rawValue: dosLatinUSStringEncoding)
            let encoding = self.centralDirectoryStructure.usesUTF8PathEncoding ? .utf8 : codepage437
            return self.path(using: encoding)
        }
        /// The file attributes of the receiver as key/value pairs.
        ///
        /// Contains the modification date and file permissions.
        public var fileAttributes: [FileAttributeKey: Any] {
            return FileManager.attributes(from: self)
        }
        /// The `CRC32` checksum of the receiver.
        ///
        /// - Note: Always returns `0` for entries of type `EntryType.directory`.
        public var checksum: CRC32 {
            if self.centralDirectoryStructure.usesDataDescriptor {
                return self.zip64DataDescriptor?.crc32 ?? self.dataDescriptor?.crc32 ?? 0
            }
            return self.centralDirectoryStructure.crc32
        }
        /// The `EntryType` of the receiver.
        public var type: EntryType {
            // OS Type is stored in the upper byte of versionMadeBy
            let osTypeRaw = self.centralDirectoryStructure.versionMadeBy >> 8
            let osType = OSType(rawValue: UInt(osTypeRaw)) ?? .unused
            var isDirectory = self.path.hasSuffix("/")
            switch osType {
            case .unix, .osx:
                let mode = mode_t(self.centralDirectoryStructure.externalFileAttributes >> 16) & S_IFMT
                switch mode {
                case S_IFREG:
                    return .file
                case S_IFDIR:
                    return .directory
                case S_IFLNK:
                    return .symlink
                default:
                    return isDirectory ? .directory : .file
                }
            case .msdos:
                isDirectory = isDirectory || ((centralDirectoryStructure.externalFileAttributes >> 4) == 0x01)
                fallthrough // For all other OSes we can only guess based on the directory suffix char
            default: return isDirectory ? .directory : .file
            }
        }
        /// Indicates whether or not the receiver is compressed.
        public var isCompressed: Bool {
            self.localFileHeader.compressionMethod != CompressionMethod.none.rawValue
        }
        /// The size of the receiver's compressed data.
        public var compressedSize: UInt64 {
            if centralDirectoryStructure.isZIP64 {
                return zip64DataDescriptor?.compressedSize ?? centralDirectoryStructure.effectiveCompressedSize
            }
            return UInt64(dataDescriptor?.compressedSize ?? centralDirectoryStructure.compressedSize)
        }
        /// The size of the receiver's uncompressed data.
        public var uncompressedSize: UInt64 {
            if centralDirectoryStructure.isZIP64 {
                return zip64DataDescriptor?.uncompressedSize ?? centralDirectoryStructure.effectiveUncompressedSize
            }
            return UInt64(dataDescriptor?.uncompressedSize ?? centralDirectoryStructure.uncompressedSize)
        }
        /// The combined size of the local header, the data and the optional data descriptor.
        var localSize: UInt64 {
            let localFileHeader = self.localFileHeader
            var extraDataLength = Int(localFileHeader.fileNameLength)
            extraDataLength += Int(localFileHeader.extraFieldLength)
            var size = UInt64(LocalFileHeader.size + extraDataLength)
            size += self.isCompressed ? self.compressedSize : self.uncompressedSize
            if centralDirectoryStructure.isZIP64 {
                size += self.zip64DataDescriptor != nil ? UInt64(ZIP64DataDescriptor.size) : 0
            } else {
                size += self.dataDescriptor != nil ? UInt64(DefaultDataDescriptor.size) : 0
            }
            return size
        }
        var dataOffset: UInt64 {
            var dataOffset = self.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader
            dataOffset += UInt64(LocalFileHeader.size)
            dataOffset += UInt64(self.localFileHeader.fileNameLength)
            dataOffset += UInt64(self.localFileHeader.extraFieldLength)
            return dataOffset
        }
        let centralDirectoryStructure: CentralDirectoryStructure
        let localFileHeader: LocalFileHeader
        let dataDescriptor: DefaultDataDescriptor?
        let zip64DataDescriptor: ZIP64DataDescriptor?

        public static func == (lhs: Entry, rhs: Entry) -> Bool {
            return lhs.path == rhs.path
            && lhs.localFileHeader.crc32 == rhs.localFileHeader.crc32
            && lhs.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader
            == rhs.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader
        }

        init?(centralDirectoryStructure: CentralDirectoryStructure,
              localFileHeader: LocalFileHeader,
              dataDescriptor: DefaultDataDescriptor? = nil,
              zip64DataDescriptor: ZIP64DataDescriptor? = nil) {
            // We currently don't support encrypted archives
            guard !centralDirectoryStructure.isEncrypted else { return nil }
            self.centralDirectoryStructure = centralDirectoryStructure
            self.localFileHeader = localFileHeader
            self.dataDescriptor = dataDescriptor
            self.zip64DataDescriptor = zip64DataDescriptor
        }
    }
}


extension Entry.CentralDirectoryStructure {

    init(localFileHeader: Entry.LocalFileHeader, fileAttributes: UInt32, relativeOffset: UInt32,
         extraField: (length: UInt16, data: Data)) {
        self.versionMadeBy = UInt16(789)
        self.versionNeededToExtract = localFileHeader.versionNeededToExtract
        self.generalPurposeBitFlag = localFileHeader.generalPurposeBitFlag
        self.compressionMethod = localFileHeader.compressionMethod
        self.lastModFileTime = localFileHeader.lastModFileTime
        self.lastModFileDate = localFileHeader.lastModFileDate
        self.crc32 = localFileHeader.crc32
        self.compressedSize = localFileHeader.compressedSize
        self.uncompressedSize = localFileHeader.uncompressedSize
        self.fileNameLength = localFileHeader.fileNameLength
        self.extraFieldLength = extraField.length
        self.fileCommentLength = UInt16(0)
        self.diskNumberStart = UInt16(0)
        self.internalFileAttributes = UInt16(0)
        self.externalFileAttributes = fileAttributes
        self.relativeOffsetOfLocalHeader = relativeOffset
        self.fileNameData = localFileHeader.fileNameData
        self.extraFieldData = extraField.data
        self.fileCommentData = Data()
        if let zip64ExtendedInformation = Entry.ZIP64ExtendedInformation.scanForZIP64Field(in: self.extraFieldData,
                                                                                           fields: self.validFields) {
            self.extraFields = [zip64ExtendedInformation]
        }
    }

    init(centralDirectoryStructure: Entry.CentralDirectoryStructure,
         zip64ExtendedInformation: Entry.ZIP64ExtendedInformation?, relativeOffset: UInt32) {
        if let existingInfo = zip64ExtendedInformation {
            self.extraFieldData = existingInfo.data
            self.versionNeededToExtract = max(centralDirectoryStructure.versionNeededToExtract,
                                              Archive.Version.v45.rawValue)
        } else {
            self.extraFieldData = centralDirectoryStructure.extraFieldData
            let existingVersion = centralDirectoryStructure.versionNeededToExtract
            self.versionNeededToExtract = existingVersion < Archive.Version.v45.rawValue
                ? centralDirectoryStructure.versionNeededToExtract
                : Archive.Version.v20.rawValue
        }
        self.extraFieldLength = UInt16(extraFieldData.count)
        self.relativeOffsetOfLocalHeader = relativeOffset
        self.versionMadeBy = centralDirectoryStructure.versionMadeBy
        self.generalPurposeBitFlag = centralDirectoryStructure.generalPurposeBitFlag
        self.compressionMethod = centralDirectoryStructure.compressionMethod
        self.lastModFileTime = centralDirectoryStructure.lastModFileTime
        self.lastModFileDate = centralDirectoryStructure.lastModFileDate
        self.crc32 = centralDirectoryStructure.crc32
        self.compressedSize = centralDirectoryStructure.compressedSize
        self.uncompressedSize = centralDirectoryStructure.uncompressedSize
        self.fileNameLength = centralDirectoryStructure.fileNameLength
        self.fileCommentLength = centralDirectoryStructure.fileCommentLength
        self.diskNumberStart = centralDirectoryStructure.diskNumberStart
        self.internalFileAttributes = centralDirectoryStructure.internalFileAttributes
        self.externalFileAttributes = centralDirectoryStructure.externalFileAttributes
        self.fileNameData = centralDirectoryStructure.fileNameData
        self.fileCommentData = centralDirectoryStructure.fileCommentData
        if let zip64ExtendedInformation = Entry.ZIP64ExtendedInformation.scanForZIP64Field(in: self.extraFieldData,
                                                                                           fields: self.validFields) {
            self.extraFields = [zip64ExtendedInformation]
        }
    }
}


extension Entry.CentralDirectoryStructure {

    var effectiveCompressedSize: UInt64 {
        if self.isZIP64, let compressedSize = self.zip64ExtendedInformation?.compressedSize, compressedSize > 0 {
            return compressedSize
        }
        return UInt64(compressedSize)
    }
    var effectiveUncompressedSize: UInt64 {
        if self.isZIP64, let uncompressedSize = self.zip64ExtendedInformation?.uncompressedSize, uncompressedSize > 0 {
            return uncompressedSize
        }
        return UInt64(uncompressedSize)
    }
    var effectiveRelativeOffsetOfLocalHeader: UInt64 {
        if self.isZIP64, let offset = self.zip64ExtendedInformation?.relativeOffsetOfLocalHeader, offset > 0 {
            return offset
        }
        return UInt64(relativeOffsetOfLocalHeader)
    }
}


// MARK: FileManager+ZIP.swift

extension FileManager {
    typealias CentralDirectoryStructure = Entry.CentralDirectoryStructure

    /// Zips the file or directory contents at the specified source URL to the destination URL.
    ///
    /// If the item at the source URL is a directory, the directory itself will be
    /// represented within the ZIP `Archive`. Calling this method with a directory URL
    /// `file:///path/directory/` will create an archive with a `directory/` entry at the root level.
    /// You can override this behavior by passing `false` for `shouldKeepParent`. In that case, the contents
    /// of the source directory will be placed at the root of the archive.
    /// - Parameters:
    ///   - sourceURL: The file URL pointing to an existing file or directory.
    ///   - destinationURL: The file URL that identifies the destination of the zip operation.
    ///   - shouldKeepParent: Indicates that the directory name of a source item should be used as root element
    ///                       within the archive. Default is `true`.
    ///   - compressionMethod: Indicates the `CompressionMethod` that should be applied.
    ///                        By default, `zipItem` will create uncompressed archives.
    ///   - progress: A progress object that can be used to track or cancel the zip operation.
    /// - Throws: Throws an error if the source item does not exist or the destination URL is not writable.
    public func zipItem(at sourceURL: URL, to destinationURL: URL,
                        shouldKeepParent: Bool = true, compressionMethod: CompressionMethod = .none,
                        progress: Progress? = nil) throws {
        let fileManager = FileManager()
        guard fileManager.itemExists(at: sourceURL) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: sourceURL.path])
        }
        guard !fileManager.itemExists(at: destinationURL) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: destinationURL.path])
        }
        let archive = try Archive(url: destinationURL, accessMode: .create)
        let isDirectory = try FileManager.typeForItem(at: sourceURL) == .directory
        if isDirectory {
            let subPaths = try self.subpathsOfDirectory(atPath: sourceURL.path)
            var totalUnitCount = Int64(0)
            if let progress = progress {
                totalUnitCount = subPaths.reduce(Int64(0), {
                    let itemURL = sourceURL.appendingPathComponent($1)
                    let itemSize = archive.totalUnitCountForAddingItem(at: itemURL)
                    return $0 + itemSize
                })
                progress.totalUnitCount = totalUnitCount
            }

            // If the caller wants to keep the parent directory, we use the lastPathComponent of the source URL
            // as common base for all entries (similar to macOS' Archive Utility.app)
            let directoryPrefix = sourceURL.lastPathComponent
            for entryPath in subPaths {
                let finalEntryPath = shouldKeepParent ? directoryPrefix + "/" + entryPath : entryPath
                let finalBaseURL = shouldKeepParent ? sourceURL.deletingLastPathComponent() : sourceURL
                if let progress = progress {
                    let itemURL = sourceURL.appendingPathComponent(entryPath)
                    let entryProgress = archive.makeProgressForAddingItem(at: itemURL)
                    progress.addChild(entryProgress, withPendingUnitCount: entryProgress.totalUnitCount)
                    try archive.addEntry(with: finalEntryPath, relativeTo: finalBaseURL,
                                         compressionMethod: compressionMethod, progress: entryProgress)
                } else {
                    try archive.addEntry(with: finalEntryPath, relativeTo: finalBaseURL,
                                         compressionMethod: compressionMethod)
                }
            }
        } else {
            progress?.totalUnitCount = archive.totalUnitCountForAddingItem(at: sourceURL)
            let baseURL = sourceURL.deletingLastPathComponent()
            try archive.addEntry(with: sourceURL.lastPathComponent, relativeTo: baseURL,
                                 compressionMethod: compressionMethod, progress: progress)
        }
    }

    /// Unzips the contents at the specified source URL to the destination URL.
    ///
    /// - Parameters:
    ///   - sourceURL: The file URL pointing to an existing ZIP file.
    ///   - destinationURL: The file URL that identifies the destination directory of the unzip operation.
    ///   - skipCRC32: Optional flag to skip calculation of the CRC32 checksum to improve performance.
    ///   - progress: A progress object that can be used to track or cancel the unzip operation.
    ///   - preferredEncoding: Encoding for entry paths. Overrides the encoding specified in the archive.
    ///   - trimBasePath: if true, trim the first path element, which is useful for unpacking a zip that includes a single root folder
    /// - Throws: Throws an error if the source item does not exist or the destination URL is not writable.
    public func unzipItem(at sourceURL: URL, to destinationURL: URL, skipCRC32: Bool = false,
                          progress: Progress? = nil, preferredEncoding: String.Encoding? = nil, trimBasePath: Bool = false, overwrite: Bool = false) throws {
        let fileManager = FileManager()
        guard fileManager.itemExists(at: sourceURL) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: sourceURL.path])
        }
        let archive = try Archive(url: sourceURL, accessMode: .read, preferredEncoding: preferredEncoding)
        // Defer extraction of symlinks until all files & directories have been created.
        // This is necessary because we can't create links to files that haven't been created yet.
        // FIXME: we need to further sort the symlinks into the order in which they are created; creating a link to a non-existent destination will work, but setting calling setAttributes (below) will throw an error if the destination does noy yet exist. So we need to sort the links such that every link that is created has a destination file/link already created
        let sortedEntries = archive.sorted { (left, right) -> Bool in
            switch (left.type, right.type) {
            case (.directory, .file): return true
            case (.directory, .symlink): return true
            case (.file, .symlink): return true
            default: return false
            }
        }
        var totalUnitCount = Int64(0)
        if let progress = progress {
            totalUnitCount = sortedEntries.reduce(0, { $0 + archive.totalUnitCountForReading($1) })
            progress.totalUnitCount = totalUnitCount
        }

        for entry in sortedEntries {
            var path = preferredEncoding == nil ? entry.path : entry.path(using: preferredEncoding!)
            if trimBasePath == true {
                path = path.trimmingBasePath
                //dbg("trimmed basePath:", basePath, "from path:", path)
            }

            let destinationEntryURL = destinationURL.appendingPathComponent(path)

            guard destinationEntryURL.isContained(in: destinationURL) else {
                throw CocoaError(.fileReadInvalidFileName,
                                 userInfo: [NSFilePathErrorKey: destinationEntryURL.path])
            }
            let crc32: CRC32
            if let progress = progress {
                let entryProgress = archive.makeProgressForReading(entry)
                progress.addChild(entryProgress, withPendingUnitCount: entryProgress.totalUnitCount)
                crc32 = try archive.extract(entry, to: destinationEntryURL, overwrite: overwrite, skipCRC32: skipCRC32, progress: entryProgress)
            } else {
                crc32 = try archive.extract(entry, to: destinationEntryURL, overwrite: overwrite, skipCRC32: skipCRC32)
            }

            func verifyChecksumIfNecessary() throws {
                if skipCRC32 == false, crc32 != entry.checksum {
                    throw Archive.ArchiveError.invalidCRC32
                }
            }
            try verifyChecksumIfNecessary()
        }
    }

    // MARK: - Helpers

    func itemExists(at url: URL) -> Bool {
        // Use `URL.checkResourceIsReachable()` instead of `FileManager.fileExists()` here
        // because we don't want implicit symlink resolution.
        // As per documentation, `FileManager.fileExists()` traverses symlinks and therefore a broken symlink
        // would throw a `.fileReadNoSuchFile` false positive error.
        // For ZIP files it may be intended to archive "broken" symlinks because they might be
        // resolvable again when extracting the archive to a different destination.
        return (try? url.checkResourceIsReachable()) == true
    }

    func createParentDirectoryStructure(for url: URL) throws {
        let parentDirectoryURL = url.deletingLastPathComponent()
        try self.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    }

    class func attributes(from entry: Entry) -> [FileAttributeKey: Any] {
        let centralDirectoryStructure = entry.centralDirectoryStructure
        let entryType = entry.type
        let fileTime = centralDirectoryStructure.lastModFileTime
        let fileDate = centralDirectoryStructure.lastModFileDate
        let defaultPermissions = entryType == .directory ? defaultDirectoryPermissions : defaultFilePermissions
        var attributes = [.posixPermissions: defaultPermissions] as [FileAttributeKey: Any]
        // Certain keys are not yet supported in swift-corelibs
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        attributes[.modificationDate] = Date(dateTime: (fileDate, fileTime))
        #endif
        let versionMadeBy = centralDirectoryStructure.versionMadeBy
        guard let osType = Entry.OSType(rawValue: UInt(versionMadeBy >> 8)) else { return attributes }

        let externalFileAttributes = centralDirectoryStructure.externalFileAttributes
        let permissions = self.permissions(for: externalFileAttributes, osType: osType, entryType: entryType)
        attributes[.posixPermissions] = NSNumber(value: permissions)
        return attributes
    }

    class func permissions(for externalFileAttributes: UInt32, osType: Entry.OSType,
                           entryType: Entry.EntryType) -> UInt16 {
        switch osType {
        case .unix, .osx:
            let permissions = mode_t(externalFileAttributes >> 16) & (~S_IFMT)
            let defaultPermissions = entryType == .directory ? defaultDirectoryPermissions : defaultFilePermissions
            return permissions == 0 ? defaultPermissions : UInt16(permissions)
        default:
            return entryType == .directory ? defaultDirectoryPermissions : defaultFilePermissions
        }
    }

    class func externalFileAttributesForEntry(of type: Entry.EntryType, permissions: UInt16) -> UInt32 {
        var typeInt: UInt16
        switch type {
        case .file:
            typeInt = UInt16(S_IFREG)
        case .directory:
            typeInt = UInt16(S_IFDIR)
        case .symlink:
            typeInt = UInt16(S_IFLNK)
        }
        var externalFileAttributes = UInt32(typeInt|UInt16(permissions))
        externalFileAttributes = (externalFileAttributes << 16)
        return externalFileAttributes
    }

    class func permissionsForItem(at URL: URL) throws -> UInt16 {
        let fileManager = FileManager()
        let entryFileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: URL.path)
        var fileStat = stat()
        lstat(entryFileSystemRepresentation, &fileStat)
        let permissions = fileStat.st_mode
        return UInt16(permissions)
    }

    class func fileModificationDateTimeForItem(at url: URL) throws -> Date {
        let fileManager = FileManager()
        guard fileManager.itemExists(at: url) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        let entryFileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: url.path)
        var fileStat = stat()
        lstat(entryFileSystemRepresentation, &fileStat)
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        let modTimeSpec = fileStat.st_mtimespec
#else
        let modTimeSpec = fileStat.st_mtim
#endif

        let timeStamp = TimeInterval(modTimeSpec.tv_sec) + TimeInterval(modTimeSpec.tv_nsec)/1000000000.0
        let modDate = Date(timeIntervalSince1970: timeStamp)
        return modDate
    }

    class func fileSizeForItem(at url: URL) throws -> Int64 {
        let fileManager = FileManager()
        guard fileManager.itemExists(at: url) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        let entryFileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: url.path)
        var fileStat = stat()
        lstat(entryFileSystemRepresentation, &fileStat)
        guard fileStat.st_size >= 0 else {
            throw CocoaError(.fileReadTooLarge, userInfo: [NSFilePathErrorKey: url.path])
        }
        // `st_size` is a signed int value
        return Int64(fileStat.st_size)
    }

    class func typeForItem(at url: URL) throws -> Entry.EntryType {
        let fileManager = FileManager()
        guard url.isFileURL, fileManager.itemExists(at: url) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        let entryFileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: url.path)
        var fileStat = stat()
        lstat(entryFileSystemRepresentation, &fileStat)
        return Entry.EntryType(mode: mode_t(fileStat.st_mode))
    }
}


extension Date {
    init(dateTime: (UInt16, UInt16)) {
        var msdosDateTime = Int(dateTime.0)
        msdosDateTime <<= 16
        msdosDateTime |= Int(dateTime.1)
        var unixTime = tm()
        unixTime.tm_sec = Int32((msdosDateTime&31)*2)
        unixTime.tm_min = Int32((msdosDateTime>>5)&63)
        unixTime.tm_hour = Int32((Int(dateTime.1)>>11)&31)
        unixTime.tm_mday = Int32((msdosDateTime>>16)&31)
        unixTime.tm_mon = Int32((msdosDateTime>>21)&15)
        unixTime.tm_mon -= 1 // UNIX time struct month entries are zero based.
        unixTime.tm_year = Int32(1980+(msdosDateTime>>25))
        unixTime.tm_year -= 1900 // UNIX time structs count in "years since 1900".
        let time = timegm(&unixTime)
        self = Date(timeIntervalSince1970: TimeInterval(time))
    }

    var fileModificationDateTime: (UInt16, UInt16) {
        return (self.fileModificationDate, self.fileModificationTime)
    }

    var fileModificationDate: UInt16 {
        var time = time_t(self.timeIntervalSince1970)
        guard let unixTime = gmtime(&time) else {
            return 0
        }
        var year = unixTime.pointee.tm_year + 1900 // UNIX time structs count in "years since 1900".
        // ZIP uses the MSDOS date format which has a valid range of 1980 - 2099.
        year = year >= 1980 ? year : 1980
        year = year <= 2099 ? year : 2099
        let month = unixTime.pointee.tm_mon + 1 // UNIX time struct month entries are zero based.
        let day = unixTime.pointee.tm_mday
        return (UInt16)(day + ((month) * 32) +  ((year - 1980) * 512))
    }

    var fileModificationTime: UInt16 {
        var time = time_t(self.timeIntervalSince1970)
        guard let unixTime = gmtime(&time) else {
            return 0
        }
        let hour = unixTime.pointee.tm_hour
        let minute = unixTime.pointee.tm_min
        let second = unixTime.pointee.tm_sec
        return (UInt16)((second/2) + (minute * 32) + (hour * 2048))
    }
}



#if swift(>=4.2)
#else

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
#else

// The swift-corelibs-foundation version of NSError.swift was missing a convenience method to create
// error objects from error codes. (https://github.com/apple/swift-corelibs-foundation/pull/1420)
// We have to provide an implementation for non-Darwin platforms using Swift versions < 4.2.

public extension CocoaError {
    public static func error(_ code: CocoaError.Code, userInfo: [AnyHashable: Any]? = nil, url: URL? = nil) -> Error {
        var info: [String: Any] = userInfo as? [String: Any] ?? [:]
        if let url = url {
            info[NSURLErrorKey] = url
        }
        return NSError(domain: NSCocoaErrorDomain, code: code.rawValue, userInfo: info)
    }
}

#endif
#endif



public extension URL {
    func isContained(in parentDirectoryURL: URL) -> Bool {
        // Ensure this URL is contained in the passed in URL
        let parentDirectoryURL = URL(fileURLWithPath: parentDirectoryURL.path, isDirectory: true).standardized
        return self.standardized.absoluteString.hasPrefix(parentDirectoryURL.absoluteString)
    }
}


// MARK: URL+ZIP.swift

extension URL {

    static func temporaryReplacementDirectoryURL(for archive: ZipArchive) -> URL {
        #if swift(>=5.0) || os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        if archive.url.isFileURL,
           let tempDir = try? FileManager().url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                appropriateFor: archive.url, create: true) {
            return tempDir
        }
        #endif

        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
            ProcessInfo.processInfo.globallyUniqueString)
    }
}


// MARK: Entry+ZIP64.swift

protocol ExtensibleDataField {
    var headerID: UInt16 { get }
    var dataSize: UInt16 { get }
}

extension Entry {
    enum EntryError: Error {
        case invalidDataError
    }

    struct ZIP64ExtendedInformation: ExtensibleDataField {
        let headerID: UInt16 = ExtraFieldHeaderID.zip64ExtendedInformation.rawValue
        let dataSize: UInt16
        static let headerSize: UInt16 = 4
        let uncompressedSize: UInt64
        let compressedSize: UInt64
        let relativeOffsetOfLocalHeader: UInt64
        let diskNumberStart: UInt32
    }

    var zip64ExtendedInformation: ZIP64ExtendedInformation? {
        self.centralDirectoryStructure.zip64ExtendedInformation
    }
}

typealias Field = Entry.ZIP64ExtendedInformation.Field

extension Entry.LocalFileHeader {
    var validFields: [Field] {
        var fields: [Field] = []
        if self.uncompressedSize == .max { fields.append(.uncompressedSize) }
        if self.compressedSize == .max { fields.append(.compressedSize) }
        return fields
    }
}

extension Entry.CentralDirectoryStructure {
    var validFields: [Field] {
        var fields: [Field] = []
        if self.uncompressedSize == .max { fields.append(.uncompressedSize) }
        if self.compressedSize == .max { fields.append(.compressedSize) }
        if self.relativeOffsetOfLocalHeader == .max { fields.append(.relativeOffsetOfLocalHeader) }
        if self.diskNumberStart == .max { fields.append(.diskNumberStart) }
        return fields
    }
    var zip64ExtendedInformation: Entry.ZIP64ExtendedInformation? {
        self.extraFields?.compactMap { $0 as? Entry.ZIP64ExtendedInformation }.first
    }
}

extension Entry.ZIP64ExtendedInformation {
    enum Field {
        case uncompressedSize
        case compressedSize
        case relativeOffsetOfLocalHeader
        case diskNumberStart

        var size: Int {
            switch self {
            case .uncompressedSize, .compressedSize, .relativeOffsetOfLocalHeader:
                return 8
            case .diskNumberStart:
                return 4
            }
        }
    }

    var data: Data {
        var headerID = self.headerID
        var dataSize = self.dataSize
        var uncompressedSize = self.uncompressedSize
        var compressedSize = self.compressedSize
        var relativeOffsetOfLFH = self.relativeOffsetOfLocalHeader
        var diskNumberStart = self.diskNumberStart
        var data = Data()
        withUnsafePointer(to: &headerID, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &dataSize, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        if uncompressedSize != 0 || compressedSize != 0 {
            withUnsafePointer(to: &uncompressedSize, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
            withUnsafePointer(to: &compressedSize, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        }
        if relativeOffsetOfLocalHeader != 0 {
            withUnsafePointer(to: &relativeOffsetOfLFH, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        }
        if diskNumberStart != 0 {
            withUnsafePointer(to: &diskNumberStart, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        }
        return data
    }

    init?(data: Data, fields: [Field]) {
        let headerLength = 4
        guard fields.reduce(0, { $0 + $1.size }) + headerLength == data.count else { return nil }
        var readOffset = headerLength
        func value<T>(of field: Field) throws -> T where T: BinaryInteger {
            if fields.contains(field) {
                defer {
                    readOffset += MemoryLayout<T>.size
                }
                guard readOffset + field.size <= data.count else {
                    throw Entry.EntryError.invalidDataError
                }
                return data.scanValue(start: readOffset)
            } else {
                return 0
            }
        }
        do {
            dataSize = data.scanValue(start: 2)
            uncompressedSize = try value(of: .uncompressedSize)
            compressedSize = try value(of: .compressedSize)
            relativeOffsetOfLocalHeader = try value(of: .relativeOffsetOfLocalHeader)
            diskNumberStart = try value(of: .diskNumberStart)
        } catch {
            return nil
        }
    }

    init?(zip64ExtendedInformation: Entry.ZIP64ExtendedInformation?, offset: UInt64) {
        // Only used when removing entry, if no ZIP64 extended information exists,
        // then this information will not be newly added either
        guard let existingInfo = zip64ExtendedInformation else { return nil }
        relativeOffsetOfLocalHeader = offset >= maxOffsetOfLocalFileHeader ? offset : 0
        uncompressedSize = existingInfo.uncompressedSize
        compressedSize = existingInfo.compressedSize
        diskNumberStart = existingInfo.diskNumberStart
        let tempDataSize = [relativeOffsetOfLocalHeader, uncompressedSize, compressedSize]
            .filter { $0 != 0 }
            .reduce(UInt16(0), { $0 + UInt16(MemoryLayout.size(ofValue: $1))})
        dataSize = tempDataSize + (diskNumberStart > 0 ? UInt16(MemoryLayout.size(ofValue: diskNumberStart)) : 0)
        if dataSize == 0 { return nil }
    }

    static func scanForZIP64Field(in data: Data, fields: [Field]) -> Entry.ZIP64ExtendedInformation? {
        guard data.isEmpty == false else { return nil }
        var offset = 0
        var headerID: UInt16
        var dataSize: UInt16
        let extraFieldLength = data.count
        let headerSize = Int(Entry.ZIP64ExtendedInformation.headerSize)
        while offset < extraFieldLength - headerSize {
            headerID = data.scanValue(start: offset)
            dataSize = data.scanValue(start: offset + 2)
            let nextOffset = offset + headerSize + Int(dataSize)
            guard nextOffset <= extraFieldLength else { return nil }
            if headerID == ExtraFieldHeaderID.zip64ExtendedInformation.rawValue {
                return Entry.ZIP64ExtendedInformation(data: data.subdata(in: offset..<nextOffset), fields: fields)
            }
            offset = nextOffset
        }
        return nil
    }
}


// MARK: Entry+Serialization.swift

extension Entry.LocalFileHeader {
    var data: Data {
        var localFileHeaderSignature = self.localFileHeaderSignature
        var versionNeededToExtract = self.versionNeededToExtract
        var generalPurposeBitFlag = self.generalPurposeBitFlag
        var compressionMethod = self.compressionMethod
        var lastModFileTime = self.lastModFileTime
        var lastModFileDate = self.lastModFileDate
        var crc32 = self.crc32
        var compressedSize = self.compressedSize
        var uncompressedSize = self.uncompressedSize
        var fileNameLength = self.fileNameLength
        var extraFieldLength = self.extraFieldLength
        var data = Data()
        withUnsafePointer(to: &localFileHeaderSignature, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &versionNeededToExtract, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &generalPurposeBitFlag, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &compressionMethod, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &lastModFileTime, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &lastModFileDate, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &crc32, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &compressedSize, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &uncompressedSize, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &fileNameLength, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &extraFieldLength, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        data.append(self.fileNameData)
        data.append(self.extraFieldData)
        return data
    }

    init?(data: Data, additionalDataProvider provider: (Int) throws -> Data) {
        guard data.count == Entry.LocalFileHeader.size else { return nil }
        guard data.scanValue(start: 0) == localFileHeaderSignature else { return nil }
        self.versionNeededToExtract = data.scanValue(start: 4)
        self.generalPurposeBitFlag = data.scanValue(start: 6)
        self.compressionMethod = data.scanValue(start: 8)
        self.lastModFileTime = data.scanValue(start: 10)
        self.lastModFileDate = data.scanValue(start: 12)
        self.crc32 = data.scanValue(start: 14)
        self.compressedSize = data.scanValue(start: 18)
        self.uncompressedSize = data.scanValue(start: 22)
        self.fileNameLength = data.scanValue(start: 26)
        self.extraFieldLength = data.scanValue(start: 28)
        let additionalDataLength = Int(self.fileNameLength) + Int(self.extraFieldLength)
        guard let additionalData = try? provider(additionalDataLength) else { return nil }
        guard additionalData.count == additionalDataLength else { return nil }
        var subRangeStart = 0
        var subRangeEnd = Int(self.fileNameLength)
        self.fileNameData = additionalData.subdata(in: subRangeStart..<subRangeEnd)
        subRangeStart += Int(self.fileNameLength)
        subRangeEnd = subRangeStart + Int(self.extraFieldLength)
        self.extraFieldData = additionalData.subdata(in: subRangeStart..<subRangeEnd)
        if let zip64ExtendedInformation = Entry.ZIP64ExtendedInformation.scanForZIP64Field(in: self.extraFieldData,
                                                                                           fields: self.validFields) {
            self.extraFields = [zip64ExtendedInformation]
        }
    }
}


extension Entry.CentralDirectoryStructure {
    var data: Data {
        var centralDirectorySignature = self.centralDirectorySignature
        var versionMadeBy = self.versionMadeBy
        var versionNeededToExtract = self.versionNeededToExtract
        var generalPurposeBitFlag = self.generalPurposeBitFlag
        var compressionMethod = self.compressionMethod
        var lastModFileTime = self.lastModFileTime
        var lastModFileDate = self.lastModFileDate
        var crc32 = self.crc32
        var compressedSize = self.compressedSize
        var uncompressedSize = self.uncompressedSize
        var fileNameLength = self.fileNameLength
        var extraFieldLength = self.extraFieldLength
        var fileCommentLength = self.fileCommentLength
        var diskNumberStart = self.diskNumberStart
        var internalFileAttributes = self.internalFileAttributes
        var externalFileAttributes = self.externalFileAttributes
        var relativeOffsetOfLocalHeader = self.relativeOffsetOfLocalHeader
        var data = Data()
        withUnsafePointer(to: &centralDirectorySignature, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &versionMadeBy, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &versionNeededToExtract, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &generalPurposeBitFlag, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &compressionMethod, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &lastModFileTime, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &lastModFileDate, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &crc32, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &compressedSize, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &uncompressedSize, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &fileNameLength, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &extraFieldLength, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &fileCommentLength, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &diskNumberStart, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &internalFileAttributes, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &externalFileAttributes, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &relativeOffsetOfLocalHeader, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        data.append(self.fileNameData)
        data.append(self.extraFieldData)
        data.append(self.fileCommentData)
        return data
    }

    init?(data: Data, additionalDataProvider provider: (Int) throws -> Data) {
        guard data.count == Entry.CentralDirectoryStructure.size else { return nil }
        guard data.scanValue(start: 0) == centralDirectorySignature else { return nil }
        self.versionMadeBy = data.scanValue(start: 4)
        self.versionNeededToExtract = data.scanValue(start: 6)
        self.generalPurposeBitFlag = data.scanValue(start: 8)
        self.compressionMethod = data.scanValue(start: 10)
        self.lastModFileTime = data.scanValue(start: 12)
        self.lastModFileDate = data.scanValue(start: 14)
        self.crc32 = data.scanValue(start: 16)
        self.compressedSize = data.scanValue(start: 20)
        self.uncompressedSize = data.scanValue(start: 24)
        self.fileNameLength = data.scanValue(start: 28)
        self.extraFieldLength = data.scanValue(start: 30)
        self.fileCommentLength = data.scanValue(start: 32)
        self.diskNumberStart = data.scanValue(start: 34)
        self.internalFileAttributes = data.scanValue(start: 36)
        self.externalFileAttributes = data.scanValue(start: 38)
        self.relativeOffsetOfLocalHeader = data.scanValue(start: 42)
        let additionalDataLength = Int(self.fileNameLength) + Int(self.extraFieldLength) + Int(self.fileCommentLength)
        guard let additionalData = try? provider(additionalDataLength) else { return nil }
        guard additionalData.count == additionalDataLength else { return nil }
        var subRangeStart = 0
        var subRangeEnd = Int(self.fileNameLength)
        self.fileNameData = additionalData.subdata(in: subRangeStart..<subRangeEnd)
        subRangeStart += Int(self.fileNameLength)
        subRangeEnd = subRangeStart + Int(self.extraFieldLength)
        self.extraFieldData = additionalData.subdata(in: subRangeStart..<subRangeEnd)
        subRangeStart += Int(self.extraFieldLength)
        subRangeEnd = subRangeStart + Int(self.fileCommentLength)
        self.fileCommentData = additionalData.subdata(in: subRangeStart..<subRangeEnd)
        if let zip64ExtendedInformation = Entry.ZIP64ExtendedInformation.scanForZIP64Field(in: self.extraFieldData,
                                                                                           fields: self.validFields) {
            self.extraFields = [zip64ExtendedInformation]
        }
    }
}


extension Entry.DataDescriptor {
    init?(data: Data, additionalDataProvider provider: (Int) throws -> Data) {
        guard data.count == Self.size else { return nil }
        let signature: UInt32 = data.scanValue(start: 0)
        // The DataDescriptor signature is not mandatory so we have to re-arrange the input data if it is missing.
        var readOffset = 0
        if signature == self.dataDescriptorSignature { readOffset = 4 }
        self.crc32 = data.scanValue(start: readOffset)
        readOffset += MemoryLayout<UInt32>.size
        self.compressedSize = data.scanValue(start: readOffset)
        readOffset += Self.memoryLengthOfSize
        self.uncompressedSize = data.scanValue(start: readOffset)
        // Our add(_ entry:) methods always maintain compressed & uncompressed
        // sizes and so we don't need a data descriptor for newly added entries.
        // Data descriptors of already existing entries are manually preserved
        // when copying those entries to the tempArchive during remove(_ entry:).
        self.data = Data()
    }
}



// MARK: Data+Serialization.swift

#if os(Android)
public typealias FILEPointer = OpaquePointer
#else
public typealias FILEPointer = UnsafeMutablePointer<FILE>
#endif

protocol DataSerializable {
    static var size: Int { get }
    init?(data: Data, additionalDataProvider: (Int) throws -> Data)
    var data: Data { get }
}

extension Data {
    enum DataError: Error {
        case unreadableFile
        case unwritableFile
    }

    func scanValue<T>(start: Int) -> T {
        let subdata = self.subdata(in: start..<start+MemoryLayout<T>.size)
        #if swift(>=5.0)
        return subdata.withUnsafeBytes { $0.load(as: T.self) }
        #else
        return subdata.withUnsafeBytes { $0.pointee }
        #endif
    }

    static func readStruct<T>(from file: FILEPointer, at offset: UInt64)
    -> T? where T: DataSerializable {
        guard offset <= .max else { return nil }
        fseeko(file, off_t(offset), SEEK_SET)
        guard let data = try? self.readChunk(of: T.size, from: file) else {
            return nil
        }
        let structure = T(data: data, additionalDataProvider: { (additionalDataSize) -> Data in
            return try self.readChunk(of: additionalDataSize, from: file)
        })
        return structure
    }

    static func consumePart(of size: Int64, chunkSize: Int, skipCRC32: Bool = false,
                            provider: Provider, consumer: Consumer) throws -> CRC32 {
        var checksum = CRC32(0)
        guard size > 0 else {
            try consumer(Data())
            return checksum
        }

        let readInOneChunk = (size < chunkSize)
        var chunkSize = readInOneChunk ? Int(size) : chunkSize
        var bytesRead: Int64 = 0
        while bytesRead < size {
            let remainingSize = size - bytesRead
            chunkSize = remainingSize < chunkSize ? Int(remainingSize) : chunkSize
            let data = try provider(bytesRead, chunkSize)
            try consumer(data)
            if !skipCRC32 {
                checksum = data.crc32(checksum: checksum)
            }
            bytesRead += Int64(chunkSize)
        }
        return checksum
    }

    static func readChunk(of size: Int, from file: FILEPointer) throws -> Data {
        let alignment = MemoryLayout<UInt>.alignment
        #if swift(>=4.1)
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: alignment)
        #else
        let bytes = UnsafeMutableRawPointer.allocate(bytes: size, alignedTo: alignment)
        #endif
        let bytesRead = fread(bytes, 1, size, file)
        let error = ferror(file)
        if error > 0 {
            throw DataError.unreadableFile
        }
        #if swift(>=4.1)
        return Data(bytesNoCopy: bytes, count: bytesRead, deallocator: .custom({ buf, _ in buf.deallocate() }))
        #else
        let deallocator = Deallocator.custom({ buf, _ in buf.deallocate(bytes: size, alignedTo: 1) })
        return Data(bytesNoCopy: bytes, count: bytesRead, deallocator: deallocator)
        #endif
    }

    static func write(chunk: Data, to file: FILEPointer) throws -> Int {
        var sizeWritten: Int = 0
        chunk.withUnsafeBytes { (rawBufferPointer) in
            if let baseAddress = rawBufferPointer.baseAddress, rawBufferPointer.count > 0 {
                let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
                sizeWritten = fwrite(pointer, 1, chunk.count, file)
            }
        }
        let error = ferror(file)
        if error > 0 {
            throw DataError.unwritableFile
        }
        return sizeWritten
    }

    static func writeLargeChunk(_ chunk: Data, size: UInt64, bufferSize: Int,
                                to file: FILEPointer) throws -> UInt64 {
        var sizeWritten: UInt64 = 0
        chunk.withUnsafeBytes { (rawBufferPointer) in
            if let baseAddress = rawBufferPointer.baseAddress, rawBufferPointer.count > 0 {
                let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)

                while sizeWritten < size {
                    let remainingSize = size - sizeWritten
                    let chunkSize = Swift.min(Int(remainingSize), bufferSize)
                    let curPointer = pointer.advanced(by: Int(sizeWritten))
                    fwrite(curPointer, 1, chunkSize, file)
                    sizeWritten += UInt64(chunkSize)
                }
            }
        }
        let error = ferror(file)
        if error > 0 {
            throw DataError.unwritableFile
        }
        return sizeWritten
    }
}


// MARK: Archive+MemoryFile.swift

extension ZipArchive {
    var isMemoryArchive: Bool { return self.url.scheme == memoryURLScheme }
}

#if swift(>=5.0)

extension ZipArchive {
    /// Returns a `Data` object containing a representation of the receiver.
    public var data: Data? { return self.memoryFile?.data }
}

class MemoryFile {
    private(set) var data: Data
    private var offset = 0

    init(data: Data = Data()) {
        self.data = data
    }

    func open(mode: String) -> FILEPointer? {
        let cookie = Unmanaged.passRetained(self)
        let writable = mode.count > 0 && (mode.first! != "r" || mode.last! == "+")
        let append = mode.count > 0 && mode.first! == "a"
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(Android)
        let result = writable
            ? funopen(cookie.toOpaque(), readStub, writeStub, seekStub, closeStub)
            : funopen(cookie.toOpaque(), readStub, nil, seekStub, closeStub)
        #else
        let stubs = cookie_io_functions_t(read: readStub, write: writeStub, seek: seekStub, close: closeStub)
        let result = fopencookie(cookie.toOpaque(), mode, stubs)
        #endif
        if append, let result {
            fseeko(result, 0, SEEK_END)
        }
        return result
    }
}

private extension MemoryFile {
    func readData(buffer: UnsafeMutableRawBufferPointer) -> Int {
        let size = min(buffer.count, data.count-offset)
        let start = data.startIndex
        data.copyBytes(to: buffer.bindMemory(to: UInt8.self), from: start+offset..<start+offset+size)
        offset += size
        return size
    }

    func writeData(buffer: UnsafeRawBufferPointer) -> Int {
        let start = data.startIndex
        if offset < data.count && offset+buffer.count > data.count {
            data.removeSubrange(start+offset..<start+data.count)
        } else if offset > data.count {
            data.append(Data(count: offset-data.count))
        }
        if offset == data.count {
            data.append(buffer.bindMemory(to: UInt8.self))
        } else {
            let start = data.startIndex // May have changed in earlier mutation
            data.replaceSubrange(start+offset..<start+offset+buffer.count, with: buffer.bindMemory(to: UInt8.self))
        }
        offset += buffer.count
        return buffer.count
    }

    func seek(offset: Int, whence: Int32) -> Int {
        var result = -1
        if whence == SEEK_SET {
            result = offset
        } else if whence == SEEK_CUR {
            result = self.offset + offset
        } else if whence == SEEK_END {
            result = data.count + offset
        }
        self.offset = result
        return self.offset
    }
}

private func fileFromCookie(cookie: UnsafeRawPointer) -> MemoryFile {
    return Unmanaged<MemoryFile>.fromOpaque(cookie).takeUnretainedValue()
}

private func closeStub(_ cookie: UnsafeMutableRawPointer?) -> Int32 {
    if let cookie = cookie {
        Unmanaged<MemoryFile>.fromOpaque(cookie).release()
    }
    return 0
}

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(Android)
private func readStub(_ cookie: UnsafeMutableRawPointer?,
                      _ bytePtr: UnsafeMutablePointer<Int8>?,
                      _ count: Int32) -> Int32 {
    guard let cookie = cookie, let bytePtr = bytePtr else { return 0 }
    return Int32(fileFromCookie(cookie: cookie).readData(
                    buffer: UnsafeMutableRawBufferPointer(start: bytePtr, count: Int(count))))
}

private func writeStub(_ cookie: UnsafeMutableRawPointer?,
                       _ bytePtr: UnsafePointer<Int8>?,
                       _ count: Int32) -> Int32 {
    guard let cookie = cookie, let bytePtr = bytePtr else { return 0 }
    return Int32(fileFromCookie(cookie: cookie).writeData(
                    buffer: UnsafeRawBufferPointer(start: bytePtr, count: Int(count))))
}

private func seekStub(_ cookie: UnsafeMutableRawPointer?,
                      _ offset: fpos_t,
                      _ whence: Int32) -> fpos_t {
    guard let cookie = cookie else { return 0 }
    return fpos_t(fileFromCookie(cookie: cookie).seek(offset: Int(offset), whence: whence))
}

#else
private func readStub(_ cookie: UnsafeMutableRawPointer?,
                      _ bytePtr: UnsafeMutablePointer<Int8>?,
                      _ count: Int) -> Int {
    guard let cookie = cookie, let bytePtr = bytePtr else { return 0 }
    return fileFromCookie(cookie: cookie).readData(
        buffer: UnsafeMutableRawBufferPointer(start: bytePtr, count: count))
}

private func writeStub(_ cookie: UnsafeMutableRawPointer?,
                       _ bytePtr: UnsafePointer<Int8>?,
                       _ count: Int) -> Int {
    guard let cookie = cookie, let bytePtr = bytePtr else { return 0 }
    return fileFromCookie(cookie: cookie).writeData(
        buffer: UnsafeRawBufferPointer(start: bytePtr, count: count))
}

private func seekStub(_ cookie: UnsafeMutableRawPointer?,
                      _ offset: UnsafeMutablePointer<Int>?,
                      _ whence: Int32) -> Int32 {
    guard let cookie = cookie, let offset = offset else { return 0 }
    let result = fileFromCookie(cookie: cookie).seek(offset: Int(offset.pointee), whence: whence)
    if result >= 0 {
        offset.pointee = result
        return 0
    } else {
        return -1
    }
}
#endif
#endif

// MARK: Archive+Progress.swift

extension ZipArchive {
    /// The number of the work units that have to be performed when
    /// removing `entry` from the receiver.
    ///
    /// - Parameter entry: The entry that will be removed.
    /// - Returns: The number of the work units.
    public func totalUnitCountForRemoving(_ entry: Entry) -> Int64 {
        return Int64(self.offsetToStartOfCentralDirectory - entry.localSize)
    }

    func makeProgressForRemoving(_ entry: Entry) -> Progress {
        return Progress(totalUnitCount: self.totalUnitCountForRemoving(entry))
    }

    /// The number of the work units that have to be performed when
    /// reading `entry` from the receiver.
    ///
    /// - Parameter entry: The entry that will be read.
    /// - Returns: The number of the work units.
    public func totalUnitCountForReading(_ entry: Entry) -> Int64 {
        switch entry.type {
        case .file, .symlink:
            return Int64(entry.uncompressedSize)
        case .directory:
            return defaultDirectoryUnitCount
        }
    }

    func makeProgressForReading(_ entry: Entry) -> Progress {
        return Progress(totalUnitCount: self.totalUnitCountForReading(entry))
    }

    /// The number of the work units that have to be performed when
    /// adding the file at `url` to the receiver.
    /// - Parameter entry: The entry that will be removed.
    /// - Returns: The number of the work units.
    public func totalUnitCountForAddingItem(at url: URL) -> Int64 {
        var count = Int64(0)
        do {
            let type = try FileManager.typeForItem(at: url)
            switch type {
            case .file, .symlink:
                count = Int64(try FileManager.fileSizeForItem(at: url))
            case .directory:
                count = defaultDirectoryUnitCount
            }
        } catch { count = -1 }
        return count
    }

    func makeProgressForAddingItem(at url: URL) -> Progress {
        return Progress(totalUnitCount: self.totalUnitCountForAddingItem(at: url))
    }
}




// MARK: Data+Compression.swift


/// The compression method of an `Entry` in a ZIP `Archive`.
public enum CompressionMethod: UInt16 {
    /// Indicates that an `Entry` has no compression applied to its contents.
    case none = 0
    /// Indicates that contents of an `Entry` have been compressed with a zlib compatible Deflate algorithm.
    case deflate = 8
}

/// An unsigned 32-Bit Integer representing a checksum.
public typealias CRC32 = UInt32
/// A custom handler that consumes a `Data` object containing partial entry data.
/// - Parameters:
///   - data: A chunk of `Data` to consume.
/// - Throws: Can throw to indicate errors during data consumption.
public typealias Consumer = (_ data: Data) throws -> Void
/// A custom handler that receives a position and a size that can be used to provide data from an arbitrary source.
/// - Parameters:
///   - position: The current read position.
///   - size: The size of the chunk to provide.
/// - Returns: A chunk of `Data`.
/// - Throws: Can throw to indicate errors in the data source.
public typealias Provider = (_ position: Int64, _ size: Int) throws -> Data


extension Data {
    public enum CompressionError: Error {
        case invalidStream
        case corruptedData
    }

    /// Calculate the `CRC32` checksum of the receiver.
    ///
    /// - Parameter checksum: The starting seed.
    /// - Returns: The checksum calculated from the bytes of the receiver and the starting seed.
    public func crc32(checksum: CRC32) -> CRC32 {
        #if canImport(CZLib)
        zlibCRC32(data: self, checksum: checksum)
        #else
        return self.builtInCRC32(checksum: checksum)
        #endif
    }

    /// Compress the output of `provider` and pass it to `consumer`.
    /// - Parameters:
    ///   - size: The uncompressed size of the data to be compressed.
    ///   - bufferSize: The maximum size of the compression buffer.
    ///   - provider: A closure that accepts a position and a chunk size. Returns a `Data` chunk.
    ///   - consumer: A closure that processes the result of the compress operation.
    /// - Returns: The checksum of the processed content.
    public static func compress(level: Int?, size: Int64, bufferSize: Int, provider: Provider, consumer: Consumer) throws -> CRC32 {
        #if canImport(XXXCompression)
        return try self.process(operation: COMPRESSION_STREAM_ENCODE, size: size, bufferSize: bufferSize,
                                provider: provider, consumer: consumer)
        #else
        return try self.zlibCompress(level: level, size: size, bufferSize: bufferSize, provider: provider, consumer: consumer)
        #endif
    }

    /// Decompress the output of `provider` and pass it to `consumer`.
    /// - Parameters:
    ///   - size: The compressed size of the data to be decompressed.
    ///   - bufferSize: The maximum size of the decompression buffer.
    ///   - skipCRC32: Optional flag to skip calculation of the CRC32 checksum to improve performance.
    ///   - provider: A closure that accepts a position and a chunk size. Returns a `Data` chunk.
    ///   - consumer: A closure that processes the result of the decompress operation.
    /// - Returns: The checksum of the processed content.
    public static func decompress(size: Int64, bufferSize: Int, skipCRC32: Bool,
                                  provider: Provider, consumer: Consumer) throws -> CRC32? {
        #if canImport(XXXCompression)
        return try self.process(operation: COMPRESSION_STREAM_DECODE, size: size, bufferSize: bufferSize,
                                skipCRC32: skipCRC32, provider: provider, consumer: consumer)
        #else
        return try self.zlibDecompress(bufferSize: bufferSize, skipCRC32: skipCRC32, provider: provider, consumer: consumer)
        #endif
    }
}

// MARK: - Apple Platforms

#if canImport(XXXCompression)

extension Data {

    @inlinable static func process(operation: compression_stream_operation, size: Int64, bufferSize: Int, skipCRC32: Bool = false, provider: Provider, consumer: Consumer) throws -> CRC32? {
        var crc32 = CRC32(0)
        let destPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destPointer.deallocate() }
        let streamPointer = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPointer.deallocate() }
        var stream = streamPointer.pointee
        var status = compression_stream_init(&stream, operation, COMPRESSION_ZLIB)
        guard status != COMPRESSION_STATUS_ERROR else { throw CompressionError.invalidStream }
        defer { compression_stream_destroy(&stream) }
        stream.src_size = 0
        stream.dst_ptr = destPointer
        stream.dst_size = bufferSize
        var position: Int64 = 0
        var sourceData: Data?
        repeat {
            let isExhausted = stream.src_size == 0
            if isExhausted {
                do {
                    sourceData = try provider(position, Int(Swift.min((size - position), Int64(bufferSize))))
                    position += Int64(stream.prepare(for: sourceData))
                } catch { throw error }
            }
            if let sourceData = sourceData {
                sourceData.withUnsafeBytes { rawBufferPointer in
                    if let baseAddress = rawBufferPointer.baseAddress {
                        let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
                        stream.src_ptr = pointer.advanced(by: sourceData.count - stream.src_size)
                        let flags = sourceData.count < bufferSize ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
                        status = compression_stream_process(&stream, flags)
                    }
                }
                if operation == COMPRESSION_STREAM_ENCODE &&
                    isExhausted && skipCRC32 == false { crc32 = sourceData.crc32(checksum: crc32) }
            }
            switch status {
            case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                let outputData = Data(bytesNoCopy: destPointer, count: bufferSize - stream.dst_size, deallocator: .none)
                try consumer(outputData)
                if operation == COMPRESSION_STREAM_DECODE && !skipCRC32 { crc32 = outputData.crc32(checksum: crc32) }
                stream.dst_ptr = destPointer
                stream.dst_size = bufferSize
            default: throw CompressionError.corruptedData
            }
        } while status == COMPRESSION_STATUS_OK
        return crc32
    }
}

extension compression_stream {

    @inlinable mutating func prepare(for sourceData: Data?) -> Int {
        guard let sourceData = sourceData else { return 0 }

        self.src_size = sourceData.count
        return sourceData.count
    }
}
#endif // canImport(XXXCompression)

#if canImport(CZLib)

extension Data {
    @inlinable static func zlibCompress(level: Int?, size: Int64, bufferSize: Int, provider: Provider, consumer: Consumer) throws -> CRC32 {
        let compressionLevel = level == nil ? Z_DEFAULT_COMPRESSION : Swift.max(-1, Swift.min(9, Int32((level ?? -1))))

        var stream = z_stream()
        let streamSize = Int32(MemoryLayout<z_stream>.size)
        var result = deflateInit2_(&stream, compressionLevel,
                                   Z_DEFLATED, -MAX_WBITS, 9, Z_DEFAULT_STRATEGY, ZLIB_VERSION, streamSize)
        defer { deflateEnd(&stream) }
        guard result == Z_OK else { throw CompressionError.invalidStream }
        var flush = Z_NO_FLUSH
        var position: Int64 = 0
        var zipCRC32 = CRC32(0)
        repeat {
            let readSize = Int(Swift.min((size - position), Int64(bufferSize)))
            var inputChunk = try provider(position, readSize)
            zipCRC32 = inputChunk.crc32(checksum: zipCRC32)
            stream.avail_in = UInt32(inputChunk.count)
            try inputChunk.withUnsafeMutableBytes { (rawBufferPointer) in
                if let baseAddress = rawBufferPointer.baseAddress {
                    let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
                    stream.next_in = pointer
                    flush = position + Int64(bufferSize) >= size ? Z_FINISH : Z_NO_FLUSH
                } else if rawBufferPointer.count > 0 {
                    throw CompressionError.corruptedData
                } else {
                    stream.next_in = nil
                    flush = Z_FINISH
                }
                var outputChunk = Data(count: bufferSize)
                repeat {
                    stream.avail_out = UInt32(bufferSize)
                    try outputChunk.withUnsafeMutableBytes { (rawBufferPointer) in
                        guard let baseAddress = rawBufferPointer.baseAddress, rawBufferPointer.count > 0 else {
                            throw CompressionError.corruptedData
                        }
                        let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
                        stream.next_out = pointer
                        result = zlibDeflate(&stream, flush)
                    }
                    guard result >= Z_OK else { throw CompressionError.corruptedData }

                    outputChunk.count = bufferSize - Int(stream.avail_out)
                    try consumer(outputChunk)
                } while stream.avail_out == 0
            }
            position += Int64(readSize)
        } while flush != Z_FINISH
        return zipCRC32
    }

    @inlinable static func zlibUnpackSegment(_ rawBufferPointer: UnsafeMutableRawBufferPointer, stream: inout z_stream, result: inout Int32, size: Int, unzipCRC32: CRC32?, consumer: Consumer) throws -> CRC32? {
        var unzipCRC32 = unzipCRC32
        if let baseAddress = rawBufferPointer.baseAddress, rawBufferPointer.count > 0 {
            let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
            stream.next_in = pointer
            repeat {
                var outputData = Data(count: size)
                stream.avail_out = UInt32(size)
                try outputData.withUnsafeMutableBytes { (rawBufferPointer) in
                    if let baseAddress = rawBufferPointer.baseAddress, rawBufferPointer.count > 0 {
                        let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
                        stream.next_out = pointer
                    } else {
                        throw CompressionError.corruptedData
                    }
                    result = zlibInflate(&stream, Z_NO_FLUSH)
                    guard result != Z_NEED_DICT &&
                        result != Z_DATA_ERROR &&
                        result != Z_MEM_ERROR else {
                        throw CompressionError.corruptedData
                    }
                }
                let remainingLength = UInt32(size) - stream.avail_out
                outputData.count = Int(remainingLength)
                try consumer(outputData)
                if unzipCRC32 != nil {
                    unzipCRC32 = outputData.crc32(checksum: unzipCRC32!)
                }
            } while stream.avail_out == 0
        }
        return unzipCRC32
    }

    @inlinable static func zlibDecompress(bufferSize: Int, skipCRC32: Bool, provider: Provider, consumer: Consumer) throws -> CRC32? {
        var stream = z_stream()
        let streamSize = Int32(MemoryLayout<z_stream>.size)
        var result = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, streamSize)
        defer { inflateEnd(&stream) }

        guard result == Z_OK else {
            throw CompressionError.invalidStream
        }

        var unzipCRC32: CRC32? = skipCRC32 ? nil : CRC32(0)
        var position: Int64 = 0

        repeat {
            stream.avail_in = UInt32(bufferSize)
            var chunk = try provider(position, bufferSize)
            position += Int64(chunk.count)
            try chunk.withUnsafeMutableBytes {
                unzipCRC32 = try zlibUnpackSegment($0, stream: &stream, result: &result, size: bufferSize, unzipCRC32: unzipCRC32, consumer: consumer)
            }
        } while result != Z_STREAM_END

        return unzipCRC32
    }
}

#endif // canImport(CZLib)

/// The lookup table used to calculate `CRC32` checksums when using the built-in
/// CRC32 implementation.
private let crcTable: [CRC32] = [
    0x00000000, 0x77073096, 0xee0e612c, 0x990951ba, 0x076dc419, 0x706af48f, 0xe963a535, 0x9e6495a3, 0x0edb8832,
    0x79dcb8a4, 0xe0d5e91e, 0x97d2d988, 0x09b64c2b, 0x7eb17cbd, 0xe7b82d07, 0x90bf1d91, 0x1db71064, 0x6ab020f2,
    0xf3b97148, 0x84be41de, 0x1adad47d, 0x6ddde4eb, 0xf4d4b551, 0x83d385c7, 0x136c9856, 0x646ba8c0, 0xfd62f97a,
    0x8a65c9ec, 0x14015c4f, 0x63066cd9, 0xfa0f3d63, 0x8d080df5, 0x3b6e20c8, 0x4c69105e, 0xd56041e4, 0xa2677172,
    0x3c03e4d1, 0x4b04d447, 0xd20d85fd, 0xa50ab56b, 0x35b5a8fa, 0x42b2986c, 0xdbbbc9d6, 0xacbcf940, 0x32d86ce3,
    0x45df5c75, 0xdcd60dcf, 0xabd13d59, 0x26d930ac, 0x51de003a, 0xc8d75180, 0xbfd06116, 0x21b4f4b5, 0x56b3c423,
    0xcfba9599, 0xb8bda50f, 0x2802b89e, 0x5f058808, 0xc60cd9b2, 0xb10be924, 0x2f6f7c87, 0x58684c11, 0xc1611dab,
    0xb6662d3d, 0x76dc4190, 0x01db7106, 0x98d220bc, 0xefd5102a, 0x71b18589, 0x06b6b51f, 0x9fbfe4a5, 0xe8b8d433,
    0x7807c9a2, 0x0f00f934, 0x9609a88e, 0xe10e9818, 0x7f6a0dbb, 0x086d3d2d, 0x91646c97, 0xe6635c01, 0x6b6b51f4,
    0x1c6c6162, 0x856530d8, 0xf262004e, 0x6c0695ed, 0x1b01a57b, 0x8208f4c1, 0xf50fc457, 0x65b0d9c6, 0x12b7e950,
    0x8bbeb8ea, 0xfcb9887c, 0x62dd1ddf, 0x15da2d49, 0x8cd37cf3, 0xfbd44c65, 0x4db26158, 0x3ab551ce, 0xa3bc0074,
    0xd4bb30e2, 0x4adfa541, 0x3dd895d7, 0xa4d1c46d, 0xd3d6f4fb, 0x4369e96a, 0x346ed9fc, 0xad678846, 0xda60b8d0,
    0x44042d73, 0x33031de5, 0xaa0a4c5f, 0xdd0d7cc9, 0x5005713c, 0x270241aa, 0xbe0b1010, 0xc90c2086, 0x5768b525,
    0x206f85b3, 0xb966d409, 0xce61e49f, 0x5edef90e, 0x29d9c998, 0xb0d09822, 0xc7d7a8b4, 0x59b33d17, 0x2eb40d81,
    0xb7bd5c3b, 0xc0ba6cad, 0xedb88320, 0x9abfb3b6, 0x03b6e20c, 0x74b1d29a, 0xead54739, 0x9dd277af, 0x04db2615,
    0x73dc1683, 0xe3630b12, 0x94643b84, 0x0d6d6a3e, 0x7a6a5aa8, 0xe40ecf0b, 0x9309ff9d, 0x0a00ae27, 0x7d079eb1,
    0xf00f9344, 0x8708a3d2, 0x1e01f268, 0x6906c2fe, 0xf762575d, 0x806567cb, 0x196c3671, 0x6e6b06e7, 0xfed41b76,
    0x89d32be0, 0x10da7a5a, 0x67dd4acc, 0xf9b9df6f, 0x8ebeeff9, 0x17b7be43, 0x60b08ed5, 0xd6d6a3e8, 0xa1d1937e,
    0x38d8c2c4, 0x4fdff252, 0xd1bb67f1, 0xa6bc5767, 0x3fb506dd, 0x48b2364b, 0xd80d2bda, 0xaf0a1b4c, 0x36034af6,
    0x41047a60, 0xdf60efc3, 0xa867df55, 0x316e8eef, 0x4669be79, 0xcb61b38c, 0xbc66831a, 0x256fd2a0, 0x5268e236,
    0xcc0c7795, 0xbb0b4703, 0x220216b9, 0x5505262f, 0xc5ba3bbe, 0xb2bd0b28, 0x2bb45a92, 0x5cb36a04, 0xc2d7ffa7,
    0xb5d0cf31, 0x2cd99e8b, 0x5bdeae1d, 0x9b64c2b0, 0xec63f226, 0x756aa39c, 0x026d930a, 0x9c0906a9, 0xeb0e363f,
    0x72076785, 0x05005713, 0x95bf4a82, 0xe2b87a14, 0x7bb12bae, 0x0cb61b38, 0x92d28e9b, 0xe5d5be0d, 0x7cdcefb7,
    0x0bdbdf21, 0x86d3d2d4, 0xf1d4e242, 0x68ddb3f8, 0x1fda836e, 0x81be16cd, 0xf6b9265b, 0x6fb077e1, 0x18b74777,
    0x88085ae6, 0xff0f6a70, 0x66063bca, 0x11010b5c, 0x8f659eff, 0xf862ae69, 0x616bffd3, 0x166ccf45, 0xa00ae278,
    0xd70dd2ee, 0x4e048354, 0x3903b3c2, 0xa7672661, 0xd06016f7, 0x4969474d, 0x3e6e77db, 0xaed16a4a, 0xd9d65adc,
    0x40df0b66, 0x37d83bf0, 0xa9bcae53, 0xdebb9ec5, 0x47b2cf7f, 0x30b5ffe9, 0xbdbdf21c, 0xcabac28a, 0x53b39330,
    0x24b4a3a6, 0xbad03605, 0xcdd70693, 0x54de5729, 0x23d967bf, 0xb3667a2e, 0xc4614ab8, 0x5d681b02, 0x2a6f2b94,
    0xb40bbe37, 0xc30c8ea1, 0x5a05df1b, 0x2d02ef8d]

extension Data {

    /// Lookup table-based CRC32 implenetation that is used
    /// if `zlib` isn't available.
    /// - Parameter checksum: Running checksum or `0` for the initial run.
    /// - Returns: The calculated checksum of the receiver.
    func builtInCRC32(checksum: CRC32) -> CRC32 {
        // The typecast is necessary on 32-bit platforms because of
        // https://bugs.swift.org/browse/SR-1774
        let mask = 0xffffffff as CRC32
        var result = checksum ^ mask
#if swift(>=5.0)
        crcTable.withUnsafeBufferPointer { crcTablePointer in
            self.withUnsafeBytes { bufferPointer in
                var bufferIndex = 0
                while bufferIndex < self.count {
                    let byte = bufferPointer[bufferIndex]
                    let index = Int((result ^ CRC32(byte)) & 0xff)
                    result = (result >> 8) ^ crcTablePointer[index]
                    bufferIndex += 1
                }
            }
        }
#else
        self.withUnsafeBytes { (bytes) in
            let bins = stride(from: 0, to: self.count, by: 256)
            for bin in bins {
                for binIndex in 0..<256 {
                    let byteIndex = bin + binIndex
                    guard byteIndex < self.count else { break }

                    let byte = bytes[byteIndex]
                    let index = Int((result ^ CRC32(byte)) & 0xff)
                    result = (result >> 8) ^ crcTable[index]
                }
            }
        }
#endif
        return result ^ mask
    }
}

#if !swift(>=5.0)

// Since Swift 5.0, `Data.withUnsafeBytes()` passes an `UnsafeRawBufferPointer` instead of an `UnsafePointer<UInt8>`
// into `body`.
// We provide a compatible method for targets that use Swift 4.x so that we can use the new version
// across all language versions.

extension Data {
    func withUnsafeBytes<T>(_ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T {
        let count = self.count
        return try withUnsafeBytes { (pointer: UnsafePointer<UInt8>) throws -> T in
            try body(UnsafeRawBufferPointer(start: pointer, count: count))
        }
    }

    #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
    #else
    mutating func withUnsafeMutableBytes<T>(_ body: (UnsafeMutableRawBufferPointer) throws -> T) rethrows -> T {
        let count = self.count
        guard count > 0 else {
            return try body(UnsafeMutableRawBufferPointer(start: nil, count: count))
        }
        return try withUnsafeMutableBytes { (pointer: UnsafeMutablePointer<UInt8>) throws -> T in
            try body(UnsafeMutableRawBufferPointer(start: pointer, count: count))
        }
    }
    #endif
}
#endif


// MARK: Archive+ZIP64.swift

let zip64EOCDRecordStructSignature = 0x06064b50
let zip64EOCDLocatorStructSignature = 0x07064b50

enum ExtraFieldHeaderID: UInt16 {
    case zip64ExtendedInformation = 0x0001
}

extension ZipArchive {
    struct ZIP64EndOfCentralDirectory {
        let record: ZIP64EndOfCentralDirectoryRecord
        let locator: ZIP64EndOfCentralDirectoryLocator
    }

    struct ZIP64EndOfCentralDirectoryRecord: DataSerializable {
        let zip64EOCDRecordSignature = UInt32(zip64EOCDRecordStructSignature)
        let sizeOfZIP64EndOfCentralDirectoryRecord: UInt64
        let versionMadeBy: UInt16
        let versionNeededToExtract: UInt16
        let numberOfDisk: UInt32
        let numberOfDiskStart: UInt32
        let totalNumberOfEntriesOnDisk: UInt64
        let totalNumberOfEntriesInCentralDirectory: UInt64
        let sizeOfCentralDirectory: UInt64
        let offsetToStartOfCentralDirectory: UInt64
        let zip64ExtensibleDataSector: Data
        static let size = 56
    }

    struct ZIP64EndOfCentralDirectoryLocator: DataSerializable {
        let zip64EOCDLocatorSignature = UInt32(zip64EOCDLocatorStructSignature)
        let numberOfDiskWithZIP64EOCDRecordStart: UInt32
        let relativeOffsetOfZIP64EOCDRecord: UInt64
        let totalNumberOfDisk: UInt32
        static let size = 20
    }
}

extension ZipArchive.ZIP64EndOfCentralDirectoryRecord {
    var data: Data {
        var zip64EOCDRecordSignature = self.zip64EOCDRecordSignature
        var sizeOfZIP64EOCDRecord = self.sizeOfZIP64EndOfCentralDirectoryRecord
        var versionMadeBy = self.versionMadeBy
        var versionNeededToExtract = self.versionNeededToExtract
        var numberOfDisk = self.numberOfDisk
        var numberOfDiskStart = self.numberOfDiskStart
        var totalNumberOfEntriesOnDisk = self.totalNumberOfEntriesOnDisk
        var totalNumberOfEntriesInCD = self.totalNumberOfEntriesInCentralDirectory
        var sizeOfCD = self.sizeOfCentralDirectory
        var offsetToStartOfCD = self.offsetToStartOfCentralDirectory
        var data = Data()
        withUnsafePointer(to: &zip64EOCDRecordSignature, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &sizeOfZIP64EOCDRecord, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &versionMadeBy, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &versionNeededToExtract, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &numberOfDisk, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &numberOfDiskStart, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &totalNumberOfEntriesOnDisk, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &totalNumberOfEntriesInCD, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &sizeOfCD, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &offsetToStartOfCD, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        data.append(self.zip64ExtensibleDataSector)
        return data
    }

    init?(data: Data, additionalDataProvider provider: (Int) throws -> Data) {
        guard data.count == Archive.ZIP64EndOfCentralDirectoryRecord.size else { return nil }
        guard data.scanValue(start: 0) == zip64EOCDRecordSignature else { return nil }
        self.sizeOfZIP64EndOfCentralDirectoryRecord = data.scanValue(start: 4)
        self.versionMadeBy = data.scanValue(start: 12)
        self.versionNeededToExtract = data.scanValue(start: 14)
        // Version Needed to Extract: 4.5 - File uses ZIP64 format extensions
        guard self.versionNeededToExtract >= Archive.Version.v45.rawValue else { return nil }
        self.numberOfDisk = data.scanValue(start: 16)
        self.numberOfDiskStart = data.scanValue(start: 20)
        self.totalNumberOfEntriesOnDisk = data.scanValue(start: 24)
        self.totalNumberOfEntriesInCentralDirectory = data.scanValue(start: 32)
        self.sizeOfCentralDirectory = data.scanValue(start: 40)
        self.offsetToStartOfCentralDirectory = data.scanValue(start: 48)
        self.zip64ExtensibleDataSector = Data()
    }

    init(record: ZipArchive.ZIP64EndOfCentralDirectoryRecord,
         numberOfEntriesOnDisk: UInt64,
         numberOfEntriesInCD: UInt64,
         sizeOfCentralDirectory: UInt64,
         offsetToStartOfCD: UInt64) {
        self.sizeOfZIP64EndOfCentralDirectoryRecord = record.sizeOfZIP64EndOfCentralDirectoryRecord
        self.versionMadeBy = record.versionMadeBy
        self.versionNeededToExtract = record.versionNeededToExtract
        self.numberOfDisk = record.numberOfDisk
        self.numberOfDiskStart = record.numberOfDiskStart
        self.totalNumberOfEntriesOnDisk = numberOfEntriesOnDisk
        self.totalNumberOfEntriesInCentralDirectory = numberOfEntriesInCD
        self.sizeOfCentralDirectory = sizeOfCentralDirectory
        self.offsetToStartOfCentralDirectory = offsetToStartOfCD
        self.zip64ExtensibleDataSector = record.zip64ExtensibleDataSector
    }
}

extension ZipArchive.ZIP64EndOfCentralDirectoryLocator {
    var data: Data {
        var zip64EOCDLocatorSignature = self.zip64EOCDLocatorSignature
        var numberOfDiskWithZIP64EOCD = self.numberOfDiskWithZIP64EOCDRecordStart
        var offsetOfZIP64EOCDRecord = self.relativeOffsetOfZIP64EOCDRecord
        var totalNumberOfDisk = self.totalNumberOfDisk
        var data = Data()
        withUnsafePointer(to: &zip64EOCDLocatorSignature, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &numberOfDiskWithZIP64EOCD, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &offsetOfZIP64EOCDRecord, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        withUnsafePointer(to: &totalNumberOfDisk, { data.append(UnsafeBufferPointer(start: $0, count: 1))})
        return data
    }

    init?(data: Data, additionalDataProvider provider: (Int) throws -> Data) {
        guard data.count == Archive.ZIP64EndOfCentralDirectoryLocator.size else { return nil }
        guard data.scanValue(start: 0) == zip64EOCDLocatorSignature else { return nil }
        self.numberOfDiskWithZIP64EOCDRecordStart = data.scanValue(start: 4)
        self.relativeOffsetOfZIP64EOCDRecord = data.scanValue(start: 8)
        self.totalNumberOfDisk = data.scanValue(start: 16)
    }

    init(locator: ZipArchive.ZIP64EndOfCentralDirectoryLocator, offsetOfZIP64EOCDRecord: UInt64) {
        self.numberOfDiskWithZIP64EOCDRecordStart = locator.numberOfDiskWithZIP64EOCDRecordStart
        self.relativeOffsetOfZIP64EOCDRecord = offsetOfZIP64EOCDRecord
        self.totalNumberOfDisk = locator.totalNumberOfDisk
    }
}

extension ZipArchive.ZIP64EndOfCentralDirectory {
    var data: Data { record.data + locator.data }
}

/// Properties that represent the maximum value of each field
var maxUInt32 = UInt32.max
var maxUInt16 = UInt16.max

var maxCompressedSize: UInt32 { maxUInt32 }
var maxUncompressedSize: UInt32 { maxUInt32 }
var maxOffsetOfLocalFileHeader: UInt32 { maxUInt32 }
var maxOffsetOfCentralDirectory: UInt32 { maxUInt32 }
var maxSizeOfCentralDirectory: UInt32 { maxUInt32 }
var maxTotalNumberOfEntries: UInt16 { maxUInt16 }


// MARK: Archive+Writing.swift

extension ZipArchive {
    enum ModifyOperation: Int {
        case remove = -1
        case add = 1
    }

    typealias EndOfCentralDirectoryStructure = (EndOfCentralDirectoryRecord, ZIP64EndOfCentralDirectory?)

    /// Write files, directories or symlinks to the receiver.
    ///
    /// - Parameters:
    ///   - path: The path that is used to identify an `Entry` within the `Archive` file.
    ///   - baseURL: The base URL of the resource to add.
    ///              The `baseURL` combined with `path` must form a fully qualified file URL.
    ///   - compressionMethod: Indicates the `CompressionMethod` that should be applied to `Entry`.
    ///                        By default, no compression will be applied.
    ///   - bufferSize: The maximum size of the write buffer and the compression buffer (if needed).
    ///   - progress: A progress object that can be used to track or cancel the add operation.
    /// - Throws: An error if the source file cannot be read or the receiver is not writable.
    public func addEntry(with path: String, relativeTo baseURL: URL,
                         compressionMethod: CompressionMethod = .none,
                         bufferSize: Int = defaultWriteChunkSize, progress: Progress? = nil) throws {
        let fileURL = baseURL.appendingPathComponent(path)

        try self.addEntry(with: path, fileURL: fileURL, compressionMethod: compressionMethod,
                          bufferSize: bufferSize, progress: progress)
    }

    /// Write files, directories or symlinks to the receiver.
    ///
    /// - Parameters:
    ///   - path: The path that is used to identify an `Entry` within the `Archive` file.
    ///   - fileURL: An absolute file URL referring to the resource to add.
    ///   - compressionMethod: Indicates the `CompressionMethod` that should be applied to `Entry`.
    ///                        By default, no compression will be applied.
    ///   - bufferSize: The maximum size of the write buffer and the compression buffer (if needed).
    ///   - progress: A progress object that can be used to track or cancel the add operation.
    /// - Throws: An error if the source file cannot be read or the receiver is not writable.
    public func addEntry(with path: String, fileURL: URL, compressionMethod: CompressionMethod = .none,
                         bufferSize: Int = defaultWriteChunkSize, progress: Progress? = nil) throws {
        let fileManager = FileManager()
        guard fileManager.itemExists(at: fileURL) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: fileURL.path])
        }
        let type = try FileManager.typeForItem(at: fileURL)
        // symlinks do not need to be readable
        guard type == .symlink || fileManager.isReadableFile(atPath: fileURL.path) else {
            throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: url.path])
        }
        let modDate = try FileManager.fileModificationDateTimeForItem(at: fileURL)
        let uncompressedSize = type == .directory ? 0 : try FileManager.fileSizeForItem(at: fileURL)
        let permissions = try FileManager.permissionsForItem(at: fileURL)
        var provider: Provider
        switch type {
        case .file:
            let entryFileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: fileURL.path)
            guard let entryFile: FILEPointer = fopen(entryFileSystemRepresentation, "rb") else {
                throw CocoaError(.fileNoSuchFile)
            }
            defer { fclose(entryFile) }
            provider = { _, _ in return try Data.readChunk(of: bufferSize, from: entryFile) }
            try self.addEntry(with: path, type: type, uncompressedSize: uncompressedSize,
                              modificationDate: modDate, permissions: permissions,
                              compressionMethod: compressionMethod, bufferSize: bufferSize,
                              progress: progress, provider: provider)
        case .directory:
            provider = { _, _ in return Data() }
            try self.addEntry(with: path.hasSuffix("/") ? path : path + "/",
                              type: type, uncompressedSize: uncompressedSize,
                              modificationDate: modDate, permissions: permissions,
                              compressionMethod: compressionMethod, bufferSize: bufferSize,
                              progress: progress, provider: provider)
        case .symlink:
            provider = { _, _ -> Data in
                let linkDestination = try fileManager.destinationOfSymbolicLink(atPath: fileURL.path)
                let linkFileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: linkDestination)
                let linkLength = Int(strlen(linkFileSystemRepresentation))
                let linkBuffer = UnsafeBufferPointer(start: linkFileSystemRepresentation, count: linkLength)
                return Data(buffer: linkBuffer)
            }
            try self.addEntry(with: path, type: type, uncompressedSize: uncompressedSize,
                              modificationDate: modDate, permissions: permissions,
                              compressionMethod: compressionMethod, bufferSize: bufferSize,
                              progress: progress, provider: provider)
        }
    }

    /// Write files, directories or symlinks to the receiver.
    ///
    /// - Parameters:
    ///   - path: The path that is used to identify an `Entry` within the `Archive` file.
    ///   - type: Indicates the `Entry.EntryType` of the added content.
    ///   - uncompressedSize: The uncompressed size of the data that is going to be added with `provider`.
    ///   - modificationDate: A `Date` describing the file modification date of the `Entry`.
    ///                       Default is the current `Date`.
    ///   - permissions: POSIX file permissions for the `Entry`.
    ///                  Default is `0`o`644` for files and symlinks and `0`o`755` for directories.
    ///   - compressionMethod: Indicates the `CompressionMethod` that should be applied to `Entry`.
    ///                        By default, no compression will be applied.
    ///   - bufferSize: The maximum size of the write buffer and the compression buffer (if needed).
    ///   - progress: A progress object that can be used to track or cancel the add operation.
    ///   - provider: A closure that accepts a position and a chunk size. Returns a `Data` chunk.
    /// - Throws: An error if the source data is invalid or the receiver is not writable.
    public func addEntry(with path: String, type: Entry.EntryType, uncompressedSize: Int64,
                         modificationDate: Date = Date(), permissions: UInt16? = nil,
                         compressionMethod: CompressionMethod = .none, bufferSize: Int = defaultWriteChunkSize,
                         progress: Progress? = nil, provider: Provider) throws {
        guard self.accessMode != .read else { throw ArchiveError.unwritableArchive }
        // Directories and symlinks cannot be compressed
        let compressionMethod = type == .file ? compressionMethod : .none
        progress?.totalUnitCount = type == .directory ? defaultDirectoryUnitCount : uncompressedSize
        let (eocdRecord, zip64EOCD) = (self.endOfCentralDirectoryRecord, self.zip64EndOfCentralDirectory)
        guard self.offsetToStartOfCentralDirectory <= .max else { throw ArchiveError.invalidCentralDirectoryOffset }
        var startOfCD = Int64(self.offsetToStartOfCentralDirectory)
        fseeko(self.archiveFile, off_t(startOfCD), SEEK_SET)
        let existingSize = self.sizeOfCentralDirectory
        let existingData = try Data.readChunk(of: Int(existingSize), from: self.archiveFile)
        fseeko(self.archiveFile, off_t(startOfCD), SEEK_SET)
        let fileHeaderStart = Int64(ftello(self.archiveFile))
        let modDateTime = modificationDate.fileModificationDateTime
        defer { fflush(self.archiveFile) }
        do {
            // Local File Header
            var localFileHeader = try self.writeLocalFileHeader(path: path, compressionMethod: compressionMethod,
                                                                size: (UInt64(uncompressedSize), 0), checksum: 0,
                                                                modificationDateTime: modDateTime)
            // File Data
            let (written, checksum) = try self.writeEntry(uncompressedSize: uncompressedSize, type: type,
                                                          compressionMethod: compressionMethod, bufferSize: bufferSize,
                                                          progress: progress, provider: provider)
            startOfCD = Int64(ftello(self.archiveFile))
            // Write the local file header a second time. Now with compressedSize (if applicable) and a valid checksum.
            fseeko(self.archiveFile, off_t(fileHeaderStart), SEEK_SET)
            localFileHeader = try self.writeLocalFileHeader(path: path, compressionMethod: compressionMethod,
                                                            size: (UInt64(uncompressedSize), UInt64(written)),
                                                            checksum: checksum, modificationDateTime: modDateTime)
            // Central Directory
            fseeko(self.archiveFile, off_t(startOfCD), SEEK_SET)
            _ = try Data.writeLargeChunk(existingData, size: existingSize, bufferSize: bufferSize, to: archiveFile)
            let permissions = permissions ?? (type == .directory ? defaultDirectoryPermissions : defaultFilePermissions)
            let externalAttributes = FileManager.externalFileAttributesForEntry(of: type, permissions: permissions)
            let centralDir = try self.writeCentralDirectoryStructure(localFileHeader: localFileHeader,
                                                                     relativeOffset: UInt64(fileHeaderStart),
                                                                     externalFileAttributes: externalAttributes)
            // End of Central Directory Record (including ZIP64 End of Central Directory Record/Locator)
            let startOfEOCD = UInt64(ftello(self.archiveFile))
            let eocd = try self.writeEndOfCentralDirectory(centralDirectoryStructure: centralDir,
                                                           startOfCentralDirectory: UInt64(startOfCD),
                                                           startOfEndOfCentralDirectory: startOfEOCD, operation: .add)
            (self.endOfCentralDirectoryRecord, self.zip64EndOfCentralDirectory) = eocd
        } catch ArchiveError.cancelledOperation {
            try rollback(UInt64(fileHeaderStart), (existingData, existingSize), bufferSize, eocdRecord, zip64EOCD)
            throw ArchiveError.cancelledOperation
        }
    }

    /// Remove a ZIP `Entry` from the receiver.
    ///
    /// - Parameters:
    ///   - entry: The `Entry` to remove.
    ///   - bufferSize: The maximum size for the read and write buffers used during removal.
    ///   - progress: A progress object that can be used to track or cancel the remove operation.
    /// - Throws: An error if the `Entry` is malformed or the receiver is not writable.
    public func remove(_ entry: Entry, bufferSize: Int = defaultReadChunkSize, progress: Progress? = nil) throws {
        guard self.accessMode != .read else { throw ArchiveError.unwritableArchive }
        let (tempArchive, tempDir) = try self.makeTempArchive()
        defer { tempDir.map { try? FileManager().removeItem(at: $0) } }
        progress?.totalUnitCount = self.totalUnitCountForRemoving(entry)
        var centralDirectoryData = Data()
        var offset: UInt64 = 0
        for currentEntry in self {
            let cds = currentEntry.centralDirectoryStructure
            if currentEntry != entry {
                let entryStart = cds.effectiveRelativeOffsetOfLocalHeader
                fseeko(self.archiveFile, off_t(entryStart), SEEK_SET)
                let provider: Provider = { (_, chunkSize) -> Data in
                    return try Data.readChunk(of: chunkSize, from: self.archiveFile)
                }
                let consumer: Consumer = {
                    if progress?.isCancelled == true { throw ArchiveError.cancelledOperation }
                    _ = try Data.write(chunk: $0, to: tempArchive.archiveFile)
                    progress?.completedUnitCount += Int64($0.count)
                }
                guard currentEntry.localSize <= .max else { throw ArchiveError.invalidLocalHeaderSize }
                _ = try Data.consumePart(of: Int64(currentEntry.localSize), chunkSize: bufferSize,
                                         provider: provider, consumer: consumer)
                let updatedCentralDirectory = updateOffsetInCentralDirectory(centralDirectoryStructure: cds,
                                                                             updatedOffset: entryStart - offset)
                centralDirectoryData.append(updatedCentralDirectory.data)
            } else { offset = currentEntry.localSize }
        }
        let startOfCentralDirectory = UInt64(ftello(tempArchive.archiveFile))
        _ = try Data.write(chunk: centralDirectoryData, to: tempArchive.archiveFile)
        let startOfEndOfCentralDirectory = UInt64(ftello(tempArchive.archiveFile))
        tempArchive.endOfCentralDirectoryRecord = self.endOfCentralDirectoryRecord
        tempArchive.zip64EndOfCentralDirectory = self.zip64EndOfCentralDirectory
        let ecodStructure = try
            tempArchive.writeEndOfCentralDirectory(centralDirectoryStructure: entry.centralDirectoryStructure,
                                                   startOfCentralDirectory: startOfCentralDirectory,
                                                   startOfEndOfCentralDirectory: startOfEndOfCentralDirectory,
                                                   operation: .remove)
        (tempArchive.endOfCentralDirectoryRecord, tempArchive.zip64EndOfCentralDirectory) = ecodStructure
        (self.endOfCentralDirectoryRecord, self.zip64EndOfCentralDirectory) = ecodStructure
        fflush(tempArchive.archiveFile)
        try self.replaceCurrentArchive(with: tempArchive)
    }

    func replaceCurrentArchive(with archive: ZipArchive) throws {
        fclose(self.archiveFile)
        if self.isMemoryArchive {
            #if swift(>=5.0)
            guard let data = archive.data,
                  let config = Archive.makeBackingConfiguration(for: data, mode: .update) else {
                throw ArchiveError.unwritableArchive
            }
            self.archiveFile = config.file
            self.memoryFile = config.memoryFile
            self.endOfCentralDirectoryRecord = config.endOfCentralDirectoryRecord
            self.zip64EndOfCentralDirectory = config.zip64EndOfCentralDirectory
            #endif
        } else {
            let fileManager = FileManager()
            #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
            do {
                _ = try fileManager.replaceItemAt(self.url, withItemAt: archive.url)
            } catch {
                _ = try fileManager.removeItem(at: self.url)
                _ = try fileManager.moveItem(at: archive.url, to: self.url)
            }
            #else
            _ = try fileManager.removeItem(at: self.url)
            _ = try fileManager.moveItem(at: archive.url, to: self.url)
            #endif
            let fileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: self.url.path)
            guard let file = fopen(fileSystemRepresentation, "rb+") else { throw ArchiveError.unreadableArchive }
            self.archiveFile = file
        }
    }
}

// MARK: - Private

private extension ZipArchive {

    func updateOffsetInCentralDirectory(centralDirectoryStructure: CentralDirectoryStructure,
                                        updatedOffset: UInt64) -> CentralDirectoryStructure {
        let zip64ExtendedInformation = Entry.ZIP64ExtendedInformation(
            zip64ExtendedInformation: centralDirectoryStructure.zip64ExtendedInformation, offset: updatedOffset)
        let offsetInCD = updatedOffset < maxOffsetOfLocalFileHeader ? UInt32(updatedOffset) : UInt32.max
        return CentralDirectoryStructure(centralDirectoryStructure: centralDirectoryStructure,
                                         zip64ExtendedInformation: zip64ExtendedInformation,
                                         relativeOffset: offsetInCD)
    }

    func rollback(_ localFileHeaderStart: UInt64, _ existingCentralDirectory: (data: Data, size: UInt64),
                  _ bufferSize: Int, _ endOfCentralDirRecord: EndOfCentralDirectoryRecord,
                  _ zip64EndOfCentralDirectory: ZIP64EndOfCentralDirectory?) throws {
        fflush(self.archiveFile)
        ftruncate(fileno(self.archiveFile), off_t(localFileHeaderStart))
        fseeko(self.archiveFile, off_t(localFileHeaderStart), SEEK_SET)
        _ = try Data.writeLargeChunk(existingCentralDirectory.data, size: existingCentralDirectory.size,
                                     bufferSize: bufferSize, to: archiveFile)
        _ = try Data.write(chunk: existingCentralDirectory.data, to: self.archiveFile)
        if let zip64EOCD = zip64EndOfCentralDirectory {
            _ = try Data.write(chunk: zip64EOCD.data, to: self.archiveFile)
        }
        _ = try Data.write(chunk: endOfCentralDirRecord.data, to: self.archiveFile)
    }

    func makeTempArchive() throws -> (Archive, URL?) {
        var archive: Archive
        var url: URL?
        if self.isMemoryArchive {
            #if swift(>=5.0)
            guard let tempArchive = Archive(data: Data(), accessMode: .create,
                                            preferredEncoding: self.preferredEncoding) else {
                throw ArchiveError.unwritableArchive
            }
            archive = tempArchive
            #else
            fatalError("Memory archives are unsupported.")
            #endif
        } else {
            let manager = FileManager()
            let tempDir = URL.temporaryReplacementDirectoryURL(for: self)
            let uniqueString = ProcessInfo.processInfo.globallyUniqueString
            let tempArchiveURL = tempDir.appendingPathComponent(uniqueString)
            try manager.createParentDirectoryStructure(for: tempArchiveURL)
            let tempArchive = try Archive(url: tempArchiveURL, accessMode: .create)
            archive = tempArchive
            url = tempDir
        }
        return (archive, url)
    }
}


// MARK: Archive.swift


// MARK: Archive+Reading.swift

extension ZipArchive {
    /// Read a ZIP `Entry` from the receiver and write it to `url`.
    ///
    /// - Parameters:
    ///   - entry: The ZIP `Entry` to read.
    ///   - url: The destination file URL.
    ///   - bufferSize: The maximum size of the read buffer and the decompression buffer (if needed).
    ///   - skipCRC32: Optional flag to skip calculation of the CRC32 checksum to improve performance.
    ///   - progress: A progress object that can be used to track or cancel the extract operation.
    /// - Returns: The checksum of the processed content or 0 if the `skipCRC32` flag was set to `true`.
    /// - Throws: An error if the destination file cannot be written or the entry contains malformed content.
    public func extract(_ entry: Entry, to url: URL, bufferSize: Int = defaultReadChunkSize, overwrite: Bool = false, skipCRC32: Bool = false,
                        progress: Progress? = nil) throws -> CRC32 {
        guard bufferSize > 0 else {
            throw ArchiveError.invalidBufferSize
        }
        let fileManager = FileManager()
        var checksum = CRC32(0)
        switch entry.type {
        case .file:
            guard !fileManager.itemExists(at: url) else {
                throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: url.path])
            }
            try fileManager.createParentDirectoryStructure(for: url)
            let destinationRepresentation = fileManager.fileSystemRepresentation(withPath: url.path)
            guard let destinationFile: FILEPointer = fopen(destinationRepresentation, "wb+") else {
                throw CocoaError(.fileNoSuchFile)
            }
            defer { fclose(destinationFile) }
            let consumer = { _ = try Data.write(chunk: $0, to: destinationFile) }
            checksum = try self.extract(entry, bufferSize: bufferSize, skipCRC32: skipCRC32,
                                        progress: progress, consumer: consumer)
        case .directory:
            let consumer = { (_: Data) in
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            }
            checksum = try self.extract(entry, bufferSize: bufferSize, skipCRC32: skipCRC32,
                                        progress: progress, consumer: consumer)
        case .symlink:
            //dbg("linking:", entry.path)
            if fileManager.itemExists(at: url) {
                if overwrite == true {
                    try fileManager.removeItem(at: url) // otherwise `createSymbolicLink` will fail
                } else {
                    throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: url.path])
                }
            }
            let consumer = { (data: Data) in
                guard let linkPath = String(data: data, encoding: .utf8) else { throw ArchiveError.invalidEntryPath }
                try fileManager.createParentDirectoryStructure(for: url)
                try fileManager.createSymbolicLink(atPath: url.path, withDestinationPath: linkPath)
            }
            checksum = try self.extract(entry, bufferSize: bufferSize, skipCRC32: skipCRC32,
                                        progress: progress, consumer: consumer)
        }
        let attributes = FileManager.attributes(from: entry)
        do {
            try fileManager.setAttributes(attributes, ofItemAtPath: url.path)
        } catch {
            // TODO: symlinks seem to throw errors when setting attributes for links whose destination does not yet exist, which can happen here because we don't sort symlinks against each other; need to fix this in the sorting (above)
            if entry.type != .symlink {
                throw error
            }
        }
        return checksum
    }

    /// Read a ZIP `Entry` from the receiver and forward its contents to a `Consumer` closure.
    ///
    /// - Parameters:
    ///   - entry: The ZIP `Entry` to read.
    ///   - bufferSize: The maximum size of the read buffer and the decompression buffer (if needed).
    ///   - skipCRC32: Optional flag to skip calculation of the CRC32 checksum to improve performance.
    ///   - progress: A progress object that can be used to track or cancel the extract operation.
    ///   - consumer: A closure that consumes contents of `Entry` as `Data` chunks.
    /// - Returns: The checksum of the processed content or 0 if the `skipCRC32` flag was set to `true`..
    /// - Throws: An error if the destination file cannot be written or the entry contains malformed content.
    public func extract(_ entry: Entry, bufferSize: Int = defaultReadChunkSize, skipCRC32: Bool = false,
                        progress: Progress? = nil, consumer: Consumer) throws -> CRC32 {
        guard bufferSize > 0 else {
            throw ArchiveError.invalidBufferSize
        }
        var checksum = CRC32(0)
        let localFileHeader = entry.localFileHeader
        guard entry.dataOffset <= .max else { throw ArchiveError.invalidLocalHeaderDataOffset }
        fseeko(self.archiveFile, off_t(entry.dataOffset), SEEK_SET)
        progress?.totalUnitCount = self.totalUnitCountForReading(entry)
        switch entry.type {
        case .file:
            guard let compressionMethod = CompressionMethod(rawValue: localFileHeader.compressionMethod) else {
                throw ArchiveError.invalidCompressionMethod
            }
            switch compressionMethod {
            case .none: checksum = try self.readUncompressed(entry: entry, bufferSize: bufferSize,
                                                             skipCRC32: skipCRC32, progress: progress, with: consumer)
            case .deflate: checksum = try self.readCompressed(entry: entry, bufferSize: bufferSize,
                                                              skipCRC32: skipCRC32, progress: progress, with: consumer) ?? checksum
            }
        case .directory:
            try consumer(Data())
            progress?.completedUnitCount = self.totalUnitCountForReading(entry)
        case .symlink:
            let localFileHeader = entry.localFileHeader
            let size = Int(localFileHeader.compressedSize)
            let data = try Data.readChunk(of: size, from: self.archiveFile)
            checksum = data.crc32(checksum: 0)
            try consumer(data)
            progress?.completedUnitCount = self.totalUnitCountForReading(entry)
        }
        return checksum
    }
}

// MARK: Archive+Helpers.swift

extension ZipArchive {

    // MARK: - Reading

    func readUncompressed(entry: Entry, bufferSize: Int, skipCRC32: Bool,
                          progress: Progress? = nil, with consumer: Consumer) throws -> CRC32 {
        let size = entry.centralDirectoryStructure.effectiveUncompressedSize
        guard size <= .max else { throw ArchiveError.invalidEntrySize }
        return try Data.consumePart(of: Int64(size), chunkSize: bufferSize, skipCRC32: skipCRC32,
                                    provider: { (_, chunkSize) -> Data in
                                        return try Data.readChunk(of: chunkSize, from: self.archiveFile)
                                    }, consumer: { (data) in
                                        if progress?.isCancelled == true { throw ArchiveError.cancelledOperation }
                                        try consumer(data)
                                        progress?.completedUnitCount += Int64(data.count)
                                    })
    }

    func readCompressed(entry: Entry, bufferSize: Int, skipCRC32: Bool, progress: Progress? = nil, with consumer: Consumer) throws -> CRC32? {
        let size = entry.centralDirectoryStructure.effectiveCompressedSize
        guard size <= .max else { throw ArchiveError.invalidEntrySize }
        return try Data.decompress(size: Int64(size), bufferSize: bufferSize, skipCRC32: skipCRC32,
                                   provider: { (_, chunkSize) -> Data in
                                    return try Data.readChunk(of: chunkSize, from: self.archiveFile)
                                   }, consumer: { (data) in
                                    if progress?.isCancelled == true { throw ArchiveError.cancelledOperation }
                                    try consumer(data)
                                    progress?.completedUnitCount += Int64(data.count)
                                   })
    }

    // MARK: - Writing

    func writeEntry(uncompressedSize: Int64, type: Entry.EntryType,
                    compressionMethod: CompressionMethod, bufferSize: Int, progress: Progress? = nil,
                    provider: Provider) throws -> (sizeWritten: Int64, crc32: CRC32) {
        var checksum = CRC32(0)
        var sizeWritten = Int64(0)
        switch type {
        case .file:
            switch compressionMethod {
            case .none:
                (sizeWritten, checksum) = try self.writeUncompressed(size: uncompressedSize,
                                                                     bufferSize: bufferSize,
                                                                     progress: progress, provider: provider)
            case .deflate:
                (sizeWritten, checksum) = try self.writeCompressed(size: uncompressedSize,
                                                                   bufferSize: bufferSize,
                                                                   level: compressionLevel,
                                                                   progress: progress, provider: provider)
            }
        case .directory:
            _ = try provider(0, 0)
            if let progress = progress { progress.completedUnitCount = progress.totalUnitCount }
        case .symlink:
            let (linkSizeWritten, linkChecksum) = try self.writeSymbolicLink(size: Int(uncompressedSize),
                                                                             provider: provider)
            (sizeWritten, checksum) = (Int64(linkSizeWritten), linkChecksum)
            if let progress = progress { progress.completedUnitCount = progress.totalUnitCount }
        }
        return (sizeWritten, checksum)
    }

    func writeLocalFileHeader(path: String, compressionMethod: CompressionMethod,
                              size: (uncompressed: UInt64, compressed: UInt64), checksum: CRC32,
                              modificationDateTime: (UInt16, UInt16)) throws -> LocalFileHeader {
        // We always set Bit 11 in generalPurposeBitFlag, which indicates an UTF-8 encoded path.
        guard let fileNameData = path.data(using: .utf8) else { throw ArchiveError.invalidEntryPath }

        var uncompressedSizeOfLFH = UInt32(0)
        var compressedSizeOfLFH = UInt32(0)
        var extraFieldLength = UInt16(0)
        var zip64ExtendedInformation: Entry.ZIP64ExtendedInformation?
        var versionNeededToExtract = Version.v20.rawValue
        // ZIP64 Extended Information in the Local header MUST include BOTH original and compressed file size fields.
        if size.uncompressed >= maxUncompressedSize || size.compressed >= maxCompressedSize {
            uncompressedSizeOfLFH = .max
            compressedSizeOfLFH = .max
            extraFieldLength = UInt16(20) // 2 + 2 + 8 + 8
            versionNeededToExtract = Version.v45.rawValue
            zip64ExtendedInformation = Entry.ZIP64ExtendedInformation(dataSize: extraFieldLength - 4,
                                                                      uncompressedSize: size.uncompressed,
                                                                      compressedSize: size.compressed,
                                                                      relativeOffsetOfLocalHeader: 0,
                                                                      diskNumberStart: 0)
        } else {
            uncompressedSizeOfLFH = UInt32(size.uncompressed)
            compressedSizeOfLFH = UInt32(size.compressed)
        }

        let localFileHeader = LocalFileHeader(versionNeededToExtract: versionNeededToExtract,
                                              generalPurposeBitFlag: UInt16(2048),
                                              compressionMethod: compressionMethod.rawValue,
                                              lastModFileTime: modificationDateTime.1,
                                              lastModFileDate: modificationDateTime.0, crc32: checksum,
                                              compressedSize: compressedSizeOfLFH,
                                              uncompressedSize: uncompressedSizeOfLFH,
                                              fileNameLength: UInt16(fileNameData.count),
                                              extraFieldLength: extraFieldLength, fileNameData: fileNameData,
                                              extraFieldData: zip64ExtendedInformation?.data ?? Data())
        _ = try Data.write(chunk: localFileHeader.data, to: self.archiveFile)
        return localFileHeader
    }

    func writeCentralDirectoryStructure(localFileHeader: LocalFileHeader, relativeOffset: UInt64,
                                        externalFileAttributes: UInt32) throws -> CentralDirectoryStructure {
        var extraUncompressedSize: UInt64?
        var extraCompressedSize: UInt64?
        var extraOffset: UInt64?
        var relativeOffsetOfCD = UInt32(0)
        var extraFieldLength = UInt16(0)
        var zip64ExtendedInformation: Entry.ZIP64ExtendedInformation?
        if localFileHeader.uncompressedSize == .max || localFileHeader.compressedSize == .max {
            let zip64Field = Entry.ZIP64ExtendedInformation
                .scanForZIP64Field(in: localFileHeader.extraFieldData, fields: [.uncompressedSize, .compressedSize])
            extraUncompressedSize = zip64Field?.uncompressedSize
            extraCompressedSize = zip64Field?.compressedSize
        }
        if relativeOffset >= maxOffsetOfLocalFileHeader {
            extraOffset = relativeOffset
            relativeOffsetOfCD = .max
        } else {
            relativeOffsetOfCD = UInt32(relativeOffset)
        }
        extraFieldLength = [extraUncompressedSize, extraCompressedSize, extraOffset]
            .compactMap { $0 }
            .reduce(UInt16(0), { $0 + UInt16(MemoryLayout.size(ofValue: $1)) })
        if extraFieldLength > 0 {
            // Size of extra fields, shouldn't include the leading 4 bytes
            zip64ExtendedInformation = Entry.ZIP64ExtendedInformation(dataSize: extraFieldLength,
                                                                      uncompressedSize: extraUncompressedSize ?? 0,
                                                                      compressedSize: extraCompressedSize ?? 0,
                                                                      relativeOffsetOfLocalHeader: extraOffset ?? 0,
                                                                      diskNumberStart: 0)
            extraFieldLength += Entry.ZIP64ExtendedInformation.headerSize
        }
        let centralDirectory = CentralDirectoryStructure(localFileHeader: localFileHeader,
                                                         fileAttributes: externalFileAttributes,
                                                         relativeOffset: relativeOffsetOfCD,
                                                         extraField: (extraFieldLength,
                                                                      zip64ExtendedInformation?.data ?? Data()))
        _ = try Data.write(chunk: centralDirectory.data, to: self.archiveFile)
        return centralDirectory
    }

    func writeEndOfCentralDirectory(centralDirectoryStructure: CentralDirectoryStructure,
                                    startOfCentralDirectory: UInt64,
                                    startOfEndOfCentralDirectory: UInt64,
                                    operation: ModifyOperation) throws -> EndOfCentralDirectoryStructure {
        var record = self.endOfCentralDirectoryRecord
        let sizeOfCD = self.sizeOfCentralDirectory
        let numberOfTotalEntries = self.totalNumberOfEntriesInCentralDirectory
        let countChange = operation.rawValue
        var dataLength = centralDirectoryStructure.extraFieldLength
        dataLength += centralDirectoryStructure.fileNameLength
        dataLength += centralDirectoryStructure.fileCommentLength
        let cdDataLengthChange = countChange * (Int(dataLength) + CentralDirectoryStructure.size)
        let (updatedSizeOfCD, updatedNumberOfEntries): (UInt64, UInt64) = try {
            switch operation {
            case .add:
                guard .max - sizeOfCD >= cdDataLengthChange else {
                    throw ArchiveError.invalidCentralDirectorySize
                }
                guard .max - numberOfTotalEntries >= countChange else {
                    throw ArchiveError.invalidCentralDirectoryEntryCount
                }
                return (sizeOfCD + UInt64(cdDataLengthChange), numberOfTotalEntries + UInt64(countChange))
            case .remove:
                return (sizeOfCD - UInt64(-cdDataLengthChange), numberOfTotalEntries - UInt64(-countChange))
            }
        }()
        let sizeOfCDForEOCD = updatedSizeOfCD >= maxSizeOfCentralDirectory
            ? UInt32.max
            : UInt32(updatedSizeOfCD)
        let numberOfTotalEntriesForEOCD = updatedNumberOfEntries >= maxTotalNumberOfEntries
            ? UInt16.max
            : UInt16(updatedNumberOfEntries)
        let offsetOfCDForEOCD = startOfCentralDirectory >= maxOffsetOfCentralDirectory
            ? UInt32.max
            : UInt32(startOfCentralDirectory)
        // ZIP64 End of Central Directory
        var zip64EOCD: ZIP64EndOfCentralDirectory?
        if numberOfTotalEntriesForEOCD == .max || offsetOfCDForEOCD == .max || sizeOfCDForEOCD == .max {
            zip64EOCD = try self.writeZIP64EOCD(totalNumberOfEntries: updatedNumberOfEntries,
                                                sizeOfCentralDirectory: updatedSizeOfCD,
                                                offsetOfCentralDirectory: startOfCentralDirectory,
                                                offsetOfEndOfCentralDirectory: startOfEndOfCentralDirectory)
        }
        record = EndOfCentralDirectoryRecord(record: record, numberOfEntriesOnDisk: numberOfTotalEntriesForEOCD,
                                             numberOfEntriesInCentralDirectory: numberOfTotalEntriesForEOCD,
                                             updatedSizeOfCentralDirectory: sizeOfCDForEOCD,
                                             startOfCentralDirectory: offsetOfCDForEOCD)
        _ = try Data.write(chunk: record.data, to: self.archiveFile)
        return (record, zip64EOCD)
    }

    func writeUncompressed(size: Int64, bufferSize: Int, progress: Progress? = nil,
                           provider: Provider) throws -> (sizeWritten: Int64, checksum: CRC32) {
        var position: Int64 = 0
        var sizeWritten: Int64 = 0
        var checksum = CRC32(0)
        while position < size {
            if progress?.isCancelled == true { throw ArchiveError.cancelledOperation }
            let readSize = (size - position) >= bufferSize ? bufferSize : Int(size - position)
            let entryChunk = try provider(position, readSize)
            checksum = entryChunk.crc32(checksum: checksum)
            sizeWritten += Int64(try Data.write(chunk: entryChunk, to: self.archiveFile))
            position += Int64(bufferSize)
            progress?.completedUnitCount = sizeWritten
        }
        return (sizeWritten, checksum)
    }

    func writeCompressed(size: Int64, bufferSize: Int, level: Int?, progress: Progress? = nil,
                         provider: Provider) throws -> (sizeWritten: Int64, checksum: CRC32) {
        var sizeWritten: Int64 = 0
        let consumer: Consumer = { data in sizeWritten += Int64(try Data.write(chunk: data, to: self.archiveFile)) }
        let checksum = try Data.compress(level: level, size: size, bufferSize: bufferSize,
                                         provider: { (position, size) -> Data in
                                            if progress?.isCancelled == true { throw ArchiveError.cancelledOperation }
                                            let data = try provider(position, size)
                                            progress?.completedUnitCount += Int64(data.count)
                                            return data
                                         }, consumer: consumer)
        return(sizeWritten, checksum)
    }

    func writeSymbolicLink(size: Int, provider: Provider) throws -> (sizeWritten: Int, checksum: CRC32) {
        // The reported size of a symlink is the number of characters in the path it points to.
        let linkData = try provider(0, size)
        let checksum = linkData.crc32(checksum: 0)
        let sizeWritten = try Data.write(chunk: linkData, to: self.archiveFile)
        return (sizeWritten, checksum)
    }

    func writeZIP64EOCD(totalNumberOfEntries: UInt64,
                        sizeOfCentralDirectory: UInt64,
                        offsetOfCentralDirectory: UInt64,
                        offsetOfEndOfCentralDirectory: UInt64) throws -> ZIP64EndOfCentralDirectory {
        var zip64EOCD: ZIP64EndOfCentralDirectory = self.zip64EndOfCentralDirectory ?? {
            // Shouldn't include the leading 12 bytes: (size - 12 = 44)
            let record = ZIP64EndOfCentralDirectoryRecord(sizeOfZIP64EndOfCentralDirectoryRecord: UInt64(44),
                                                          versionMadeBy: UInt16(789),
                                                          versionNeededToExtract: Version.v45.rawValue,
                                                          numberOfDisk: 0, numberOfDiskStart: 0,
                                                          totalNumberOfEntriesOnDisk: 0,
                                                          totalNumberOfEntriesInCentralDirectory: 0,
                                                          sizeOfCentralDirectory: 0,
                                                          offsetToStartOfCentralDirectory: 0,
                                                          zip64ExtensibleDataSector: Data())
            let locator = ZIP64EndOfCentralDirectoryLocator(numberOfDiskWithZIP64EOCDRecordStart: 0,
                                                            relativeOffsetOfZIP64EOCDRecord: 0,
                                                            totalNumberOfDisk: 1)
            return ZIP64EndOfCentralDirectory(record: record, locator: locator)
        }()

        let updatedRecord = ZIP64EndOfCentralDirectoryRecord(record: zip64EOCD.record,
                                                             numberOfEntriesOnDisk: totalNumberOfEntries,
                                                             numberOfEntriesInCD: totalNumberOfEntries,
                                                             sizeOfCentralDirectory: sizeOfCentralDirectory,
                                                             offsetToStartOfCD: offsetOfCentralDirectory)
        let updatedLocator = ZIP64EndOfCentralDirectoryLocator(locator: zip64EOCD.locator,
                                                               offsetOfZIP64EOCDRecord: offsetOfEndOfCentralDirectory)
        zip64EOCD = ZIP64EndOfCentralDirectory(record: updatedRecord, locator: updatedLocator)
        _ = try Data.write(chunk: zip64EOCD.data, to: self.archiveFile)
        return zip64EOCD
    }
}


// MARK: Archive+BackingConfiguration.swift

extension ZipArchive {

    struct BackingConfiguration {
        let file: FILEPointer
        let endOfCentralDirectoryRecord: EndOfCentralDirectoryRecord
        let zip64EndOfCentralDirectory: ZIP64EndOfCentralDirectory?
        #if swift(>=5.0)
        let memoryFile: MemoryFile?

        init(file: FILEPointer,
             endOfCentralDirectoryRecord: EndOfCentralDirectoryRecord,
             zip64EndOfCentralDirectory: ZIP64EndOfCentralDirectory? = nil,
             memoryFile: MemoryFile? = nil) {
            self.file = file
            self.endOfCentralDirectoryRecord = endOfCentralDirectoryRecord
            self.zip64EndOfCentralDirectory = zip64EndOfCentralDirectory
            self.memoryFile = memoryFile
        }
        #else

        init(file: FILEPointer,
             endOfCentralDirectoryRecord: EndOfCentralDirectoryRecord,
             zip64EndOfCentralDirectory: ZIP64EndOfCentralDirectory?) {
            self.file = file
            self.endOfCentralDirectoryRecord = endOfCentralDirectoryRecord
            self.zip64EndOfCentralDirectory = zip64EndOfCentralDirectory
        }
        #endif
    }

    static func makeBackingConfiguration(for url: URL, mode: AccessMode) throws
    -> BackingConfiguration {
        let fileManager = FileManager()
        switch mode {
        case .read:
            let fileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: url.path)
            guard let archiveFile = fopen(fileSystemRepresentation, "rb"),
                  let (eocdRecord, zip64EOCD) = Archive.scanForEndOfCentralDirectoryRecord(in: archiveFile) else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            return BackingConfiguration(file: archiveFile,
                                        endOfCentralDirectoryRecord: eocdRecord,
                                        zip64EndOfCentralDirectory: zip64EOCD)
        case .create:
            let endOfCentralDirectoryRecord = EndOfCentralDirectoryRecord(numberOfDisk: 0, numberOfDiskStart: 0,
                                                                          totalNumberOfEntriesOnDisk: 0,
                                                                          totalNumberOfEntriesInCentralDirectory: 0,
                                                                          sizeOfCentralDirectory: 0,
                                                                          offsetToStartOfCentralDirectory: 0,
                                                                          zipFileCommentLength: 0,
                                                                          zipFileCommentData: Data())
            try endOfCentralDirectoryRecord.data.write(to: url, options: .withoutOverwriting)
            fallthrough
        case .update:
            let fileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: url.path)
            guard let archiveFile = fopen(fileSystemRepresentation, "rb+"),
                  let (eocdRecord, zip64EOCD) = Archive.scanForEndOfCentralDirectoryRecord(in: archiveFile) else {
                throw ArchiveError.unwritableArchive
            }
            fseeko(archiveFile, 0, SEEK_SET)
            return BackingConfiguration(file: archiveFile,
                                        endOfCentralDirectoryRecord: eocdRecord,
                                        zip64EndOfCentralDirectory: zip64EOCD)
        }
    }

    #if swift(>=5.0)
    static func makeBackingConfiguration(for data: Data, mode: AccessMode)
    -> BackingConfiguration? {
        let posixMode: String
        switch mode {
        case .read: posixMode = "rb"
        case .create: posixMode = "wb+"
        case .update: posixMode = "rb+"
        }
        let memoryFile = MemoryFile(data: data)
        guard let archiveFile = memoryFile.open(mode: posixMode) else { return nil }

        switch mode {
        case .read:
            guard let (eocdRecord, zip64EOCD) = Archive.scanForEndOfCentralDirectoryRecord(in: archiveFile) else {
                return nil
            }

            return BackingConfiguration(file: archiveFile,
                                        endOfCentralDirectoryRecord: eocdRecord,
                                        zip64EndOfCentralDirectory: zip64EOCD,
                                        memoryFile: memoryFile)
        case .create:
            let endOfCentralDirectoryRecord = EndOfCentralDirectoryRecord(numberOfDisk: 0, numberOfDiskStart: 0,
                                                                          totalNumberOfEntriesOnDisk: 0,
                                                                          totalNumberOfEntriesInCentralDirectory: 0,
                                                                          sizeOfCentralDirectory: 0,
                                                                          offsetToStartOfCentralDirectory: 0,
                                                                          zipFileCommentLength: 0,
                                                                          zipFileCommentData: Data())
            _ = endOfCentralDirectoryRecord.data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                fwrite(buffer.baseAddress, buffer.count, 1, archiveFile) // Errors handled during read
            }
            fallthrough
        case .update:
            guard let (eocdRecord, zip64EOCD) = Archive.scanForEndOfCentralDirectoryRecord(in: archiveFile) else {
                return nil
            }

            fseeko(archiveFile, 0, SEEK_SET)
            return BackingConfiguration(file: archiveFile,
                                        endOfCentralDirectoryRecord: eocdRecord,
                                        zip64EndOfCentralDirectory: zip64EOCD,
                                        memoryFile: memoryFile)
        }
    }
    #endif
}
