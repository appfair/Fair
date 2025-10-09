import Foundation

/// A handle to some data that maintains its `offset` location and can access subsets of data
public protocol SeekableData : Actor {
    typealias Offset = UInt64

    /// The current offset in the data
    func offset() async throws -> Offset

    /// Jump to the given offset in the data
    func seek(to offset: Offset) async throws

    /// Reads raw underlying bytes
    func readData(ofLength length: Offset?) async throws -> Data

    /// Returns bytes expected to represent numeric data in the expected endianess of the seeker
    func readNumericData(ofLength length: Int) async throws -> Data

    func readUIntX<Result: UnsignedInteger>() async throws -> Result
}

public enum SeekableDataErrors : Error {
    case dataTooSmall
    case dataOutOfBounds
}

public extension SeekableData {
    /// Returns a `SeekableData` instance that reverses the endianness of the underlying data reading options
    func reversedEndian() -> SeekableData {
        ReverseEndianSeekableData(delegate: self)
    }
}

/// SeekableData implementation that flips the data it accesses from big-endian to little endian
private actor ReverseEndianSeekableData : SeekableData {
    let delegate: SeekableData

    init(delegate: SeekableData) {
        self.delegate = delegate
    }

    func readUIntX<Result: UnsignedInteger>() async throws -> Result {
        try await readNumber()
    }

    func readNumericData(ofLength length: Int) async throws -> Data {
        try await Data(delegate.readNumericData(ofLength: length).reversed())
    }

    func offset() async throws -> Offset {
        try await delegate.offset()
    }

    func seek(to offset: Offset) async throws {
        try await delegate.seek(to: offset)
    }

    func readData(ofLength length: Offset?) async throws -> Data {
        try await delegate.readData(ofLength: length)
    }
}

public extension SeekableData {
    func readUIntX<Result: UnsignedInteger>() async throws -> Result {
        try await readNumber()
    }

    /// Reads a number with the given expected memory layout.
    /// - Parameter bigEndian: if true, read in big-endian order, otherwise little-endian
    /// - Returns: the number as read from the data
    fileprivate func readNumber<Result: UnsignedInteger>() async throws -> Result {
        let expected = MemoryLayout<Result>.size
        let slice = try await readNumericData(ofLength: expected)
        if slice.count != expected { throw SeekableDataErrors.dataTooSmall }
        return slice.reduce(0, buildResult)
    }

    func buildResult<Result: UnsignedInteger>(result: Result, element: Data.Element) -> Result {
        (result << 8) | Result(element)
    }

}

/// SeekableData implementation that is backed by a `FileHandle`
public actor SeekableFileHandle : SeekableData {
    let handle: FileHandle

    public init(_ handle: FileHandle) {
        self.handle = handle
    }

    deinit {
        try? self.handle.close()
    }

    public func offset() async throws -> Offset {
        try handle.offset()
    }

    public func seek(to offset: Offset) async throws {
        try handle.seek(toOffset: offset)
    }

    public func readNumericData(ofLength length: Int) async throws -> Data {
        try await readData(ofLength: .init(length))
    }

    public func readData(ofLength length: Offset?) async throws -> Data {
        let d2 = try await readData(ofLength: length, async: false)
        return d2

        // sadly, the truly async form is 200x slower than the sync version in debug builds and 86x slower in release builds
        // let d1 = try await readData(ofLength: length, async: true) // 200x slower!!
        // return d1
        // let o = try offset()
        // try await seek(to: o) // move back to seek
        // assert(d1.count == d2.count, "\(d1.count) != \(d2.count)")
        // assert(d1 == d2)
        // return d1
    }

    private func readData(ofLength length: Offset?, async: Bool) async throws -> Data {
//        if async {
//            var data = Data()
//            if let length = length {
//                data.reserveCapacity(Int(truncatingIfNeeded: length))
//            }
//
//            // 1.8x slower!
////            return try await handle.bytes.prefix(length.flatMap({ Int(truncatingIfNeeded: $0) }) ?? .max).reduce(into: data, { result, element in
////                result.append(element)
////            })
//
//            for try await byte in handle.bytes { // .dropFirst(.init(try handle.offset())) {
//                data.append(byte)
//                if let length = length, data.count >= length {
//                    return data
//                }
//            }
//            return data
//        } else { // asyncAPIs
            if let length = length {
                let data = try handle.read(upToCount: Int(truncatingIfNeeded: length)) ?? Data()
                if data.count != length {
                    throw SeekableDataErrors.dataTooSmall
                }
                return data
            } else {
                return try handle.readToEnd() ?? Data()
            }
//        }
    }
}

/// SeekableData implementation that is backed by a `Data` instance, which may be in-memory or mapped to a file.
public actor SeekableDataHandle : SeekableData {
    let data: Data
    private(set) var off: Offset

    public init(_ data: Data) {
        self.off = 0
        self.data = data
    }

    public func offset() async -> Offset {
        off
    }

    public func readNumericData(ofLength length: Int) async throws -> Data {
        try await readData(ofLength: .init(length))
    }

    public func seek(to offset: Offset) async throws {
        if offset < 0 || offset >= self.data.count {
            throw SeekableDataErrors.dataOutOfBounds
        }
        self.off = offset
    }

    @available(*, deprecated, message: "unsafe; use validating and throwing form instead")
    public func unsafeRead<T>() async throws -> T {
        try await readData(ofLength: Offset(MemoryLayout<T>.size))
            .withUnsafeBytes( { $0.load(as: T.self) })
    }

    public func readData(ofLength length: Offset?) async throws -> Data {
        guard let length = length else {
            let remainder = data[off...]
            off += Offset(remainder.count)
            return remainder
        }

        let startIndex = (Offset(data.startIndex) + off)
        let endIndex = min(.init(data.endIndex), Offset(data.startIndex) + off + length)

        if endIndex <= startIndex {
            throw SeekableDataErrors.dataTooSmall
        }

        defer { off += length }
        let range = startIndex..<endIndex

        // return data.subdata(in: range) // if we don't wrap, we can get a crash when accessing raw memory: 2022-05-27 14:12:22.072709-0400 xctest[26521:9661824] Swift/UnsafeRawPointer.swift:354: Fatal error: load from misaligned raw pointer
        return data[range]
    }
}

public extension SeekableData {
    /// Reads an unsigned little-endian 8-bit integer
    func readUInt8() async throws -> UInt8 {
        try await readUIntX()
    }

    /// Reads a signed little-endian 16-bit integer
    func readInt8() async throws -> Int8 {
        Int8(bitPattern: try await readUInt8())
    }

    /// Reads an unsigned little-endian 16-bit integer
    func readUInt16() async throws -> UInt16 {
        try await readUIntX()
    }

    /// Reads a signed little-endian 16-bit integer
    func readInt16() async throws -> Int16 {
        Int16(bitPattern: try await readUInt16())
    }

    /// Reads an unsigned little-endian 32-bit integer
    func readUInt32() async throws -> UInt32 {
        try await readUIntX()
    }

    /// Reads a signed little-endian 32-bit integer
    func readInt32() async throws -> Int32 {
        Int32(bitPattern: try await readUInt32())
    }

    func readUInt64() async throws -> UInt64 {
        try await readUIntX()
    }

    /// Reads a signed little-endian 64-bit integer
    func readInt64() async throws -> Int64 {
        Int64(bitPattern: try await readUInt64())
    }
}


