// Copyright (c) 2022 - 2026 The App Fair Project <info@appfair.org>
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-or-later
import Swift
import Foundation

@available(macOS 10.14, iOS 12.0, *)
extension Data {
    /// Returns the hex format for this data
    @inlinable public func hex() -> String {
        map { String(format: "%02hhx", $0) }.joined()
    }

    /// Calculate the Adler32 checksum of the data.
    @inlinable public func adler32() -> Adler32 {
        var res = Adler32()
        res.advance(withChunk: self)
        return res
    }

    /// Calculate the Crc32 checksum of the data.
    @inlinable public func crc32z() -> Crc32 {
        var res = Crc32()
        res.advance(withChunk: self)
        return res
    }

    /// Generates a SHA1 digest of this data
    @inlinable public func sha1() -> Data {
        #if canImport(CommonCrypto)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        _ = withUnsafeBytes { CC_SHA1($0.baseAddress, CC_LONG(self.count), &digest) }
        return Data(digest)
        #else
        // on Linux & Windows, fall back to a slower pure swift implementation
        return sha1Uncommon()
        #endif
    }

    /// Generates a SHA1 digest of this data using an internal implementation rather than CommonCrypto's
    @inlinable public func sha1Uncommon() -> Data {
        return Data(SHA1(self).calculate())
    }

    /// Generates a SHA256 digest of this data
    @inlinable public func sha256() -> Data {
        #if canImport(CommonCrypto)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = withUnsafeBytes { CC_SHA256($0.baseAddress, CC_LONG(self.count), &digest) }
        return Data(digest)
        #else
        // on Linux & Windows, fall back to a slower pure swift implementation
        return sha256Uncommon()
        #endif
    }

    /// Generates a SHA256 digest of this data using an internal implementation rather than CommonCrypto's
    @inlinable public func sha256Uncommon() -> Data {
        Data(SHA256(for: self).value)
    }

    @inlinable public func hmacSHA(key: Data, hash variant: HMAC.Variant) -> Data {
        #if canImport(CommonCrypto)
        func digestLength() -> Int {
            switch variant {
            case .sha1:
                return Int(CC_SHA1_DIGEST_LENGTH)
            case .sha256:
                return Int(CC_SHA256_DIGEST_LENGTH)
            }
        }

        func hashAlgorithm() -> CCHmacAlgorithm {
            switch variant {
            case .sha1:
                return CCHmacAlgorithm(kCCHmacAlgSHA1)
            case .sha256:
                return CCHmacAlgorithm(kCCHmacAlgSHA256)
            }
        }

        var digest = [UInt8](repeating: 0, count: digestLength())
        let keylen = key.count
        let datalen = self.count
        withUnsafeBytes { dataptr in
            key.withUnsafeBytes { keyptr in
                CCHmac(hashAlgorithm(), keyptr.baseAddress, keylen, dataptr.baseAddress, datalen, &digest)
            }
        }
        return Data(digest)
        #else
        return hmacSHAUncommon(key: key, hash: variant)
        #endif
    }

    @inlinable public func hmacSHAUncommon(key: Data, hash variant: HMAC.Variant) -> Data {
        Data(HMAC(key: key.array(), variant: variant).authenticate(array()))
    }
}

/// An actor that consumera data, such as a hashing function
public protocol DataConsumer : Actor {
    func update(data: Data)
}

/// A `RandomNumberGenerator` that accepts a seed to provide deterministic values.
public struct SeededRandomNumberGenerator : RandomNumberGenerator {
    var indexM: UInt8 = 0
    var indexN: UInt8 = 0
    var indexState: [UInt8] = Array(0...255)

    public init(seed: [UInt8]) {
        precondition(seed.count > 0 && seed.count <= 256, "seed element count \(seed.count) must range in 0–256")
        var n: UInt8 = 0
        for m: UInt8 in 0...255 {
            n &+= index(m) &+ seed[Int(m) % seed.count]
            swapAt(m, n)
        }
    }

    /// Initializes this generator with the UUIDs argument (up to 16 elememts).
    public init(uuids: UUID...) {
        func byteArray(_ uuid: UUID) -> [UInt8] { [uuid.uuid.0, uuid.uuid.1, uuid.uuid.2, uuid.uuid.3, uuid.uuid.4, uuid.uuid.5, uuid.uuid.6, uuid.uuid.7, uuid.uuid.8, uuid.uuid.9, uuid.uuid.10, uuid.uuid.11, uuid.uuid.12, uuid.uuid.13, uuid.uuid.14, uuid.uuid.15] }
        self.init(seed: (uuids.isEmpty ? [UUID()] : uuids).prefix(16).map(byteArray).joined().array())
    }

    @inlinable public mutating func next() -> UInt64 {
        var result: UInt64 = 0
        for _ in 0..<UInt64.bitWidth / UInt8.bitWidth {
            result <<= UInt8.bitWidth
            result += UInt64(nextByte())
        }
        return result
    }

    @usableFromInline internal mutating func nextByte() -> UInt8 {
        indexM &+= 1
        indexN &+= index(indexM)
        swapAt(indexM, indexN)
        return index(index(indexM) &+ index(indexN))
    }

    private func index(_ index: UInt8) -> UInt8 {
        return indexState[Int(index)]
    }

    private mutating func swapAt(_ m: UInt8, _ n: UInt8) {
        indexState.swapAt(Int(m), Int(n))
    }
}

extension Bool {
    /// Returns an infinite sequence of boolesns over the given range with a fixed seed.
    ///
    /// - Parameters:
    ///   - seed: the seed for a ``SeededRandomNumberGenerator`` to use for a repeatable seed
    /// - Returns: an infinite random sequence of booleans
    public static func randomSequence(seed: [UInt8]? = nil) -> UnfoldSequence<Self, RandomNumberGenerator> {
        sequence(state: seed != nil ? SeededRandomNumberGenerator(seed: seed!) : SystemRandomNumberGenerator()) { rng in
            Self.random(using: &rng)
        }
    }
}

extension FixedWidthInteger {
    /// Returns an infinite sequence of numbers over the given range with a fixed seed.
    ///
    /// - Parameters:
    ///   - range: the range of fixed width integers to choose from; if nil, the entire range of the number wil be used
    ///   - seed: the seed for a ``SeededRandomNumberGenerator`` to use for a repeatable seed
    /// - Returns: an infinite random sequence of numbers within the given range.
    public static func randomSequence(in range: ClosedRange<Self>? = nil, seed: [UInt8]? = nil) -> UnfoldSequence<Self, RandomNumberGenerator> {
            sequence(state: seed != nil ? SeededRandomNumberGenerator(seed: seed!) : SystemRandomNumberGenerator()) { rng in
                Self.random(in: range ?? ((.min)...(.max)), using: &rng)
            }
    }
}


#if canImport(CommonCrypto)
import CommonCrypto

/// An actor that can keep a running hash of a stream of bytes.
public final actor SHA256Hasher : DataConsumer {
    @usableFromInline var context: CC_SHA256_CTX

    public init() {
        var ctx = CC_SHA256_CTX()
        CC_SHA256_Init(&ctx)
        self.context = ctx
    }

    /// Updates the hash with the given array
    @inlinable public func update(bytes: [UInt8]) {
        CC_SHA256_Update(&context, bytes, CC_LONG(bytes.count))
    }

    /// Updates the hash with the given data
    @inlinable public func update(data: Data) {
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256_Update(&context, bytes.baseAddress, CC_LONG(bytes.count))
        }
    }

    /// Complete the hash and return the digest data
    @inlinable public func final() -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)
        CC_SHA256_Init(&context)
        return Data(digest)
    }

    /// Clear the current hash buffer and ready it for re-use
    @inlinable public func reset() {
        CC_SHA256_Init(&context)
    }
}

#endif // #if canImport(CommonCrypto)



@available(macOS 10.14, iOS 12.0, *)
public struct Crc32: CustomStringConvertible {
    private static let zLibCrc32: ZLibCrc32FuncPtr? = loadCrc32fromZLib()

    public init() {}

    private typealias ZLibCrc32FuncPtr = @convention(c) (
        _ cks:  UInt32,
        _ buf:  UnsafePointer<UInt8>,
        _ len:  UInt32
    ) -> UInt32

    public var checksum: UInt32 = 0

    public mutating func advance(withChunk chunk: Data) {
        if let fastCrc32 = Crc32.zLibCrc32 {
            checksum = chunk.withUnsafeBytes({ (ptr: UnsafePointer<UInt8>) -> UInt32 in
                return fastCrc32(checksum, ptr, UInt32(chunk.count))
            })
        } else {
            checksum = slowCrc32(start: checksum, data: chunk)
        }
    }

    public var description: String {
        return String(format: "%08x", checksum)
    }

    private static func loadCrc32fromZLib() -> ZLibCrc32FuncPtr? {
        #if os(Windows)
        return nil
        #else
        guard let libz = dlopen("/usr/lib/libz.dylib", RTLD_NOW) else { return nil }
        guard let fptr = dlsym(libz, "crc32") else { return nil }
        return unsafeBitCast(fptr, to: ZLibCrc32FuncPtr.self)
        #endif
    }

    private func slowCrc32(start: UInt32, data: Data) -> UInt32 {
        return ~data.reduce(~start) { (crc: UInt32, next: UInt8) -> UInt32 in
            let tableOffset = (crc ^ UInt32(next)) & 0xff
            return lookUpTable[Int(tableOffset)] ^ crc >> 8
        }
    }

    /// Lookup table for faster crc32 calculation.
    /// table source: http://web.mit.edu/freebsd/head/sys/libkern/crc32.c
    private let lookUpTable: [UInt32] = [
        0x00000000, 0x77073096, 0xee0e612c, 0x990951ba, 0x076dc419, 0x706af48f, 0xe963a535, 0x9e6495a3,
        0x0edb8832, 0x79dcb8a4, 0xe0d5e91e, 0x97d2d988, 0x09b64c2b, 0x7eb17cbd, 0xe7b82d07, 0x90bf1d91,
        0x1db71064, 0x6ab020f2, 0xf3b97148, 0x84be41de, 0x1adad47d, 0x6ddde4eb, 0xf4d4b551, 0x83d385c7,
        0x136c9856, 0x646ba8c0, 0xfd62f97a, 0x8a65c9ec, 0x14015c4f, 0x63066cd9, 0xfa0f3d63, 0x8d080df5,
        0x3b6e20c8, 0x4c69105e, 0xd56041e4, 0xa2677172, 0x3c03e4d1, 0x4b04d447, 0xd20d85fd, 0xa50ab56b,
        0x35b5a8fa, 0x42b2986c, 0xdbbbc9d6, 0xacbcf940, 0x32d86ce3, 0x45df5c75, 0xdcd60dcf, 0xabd13d59,
        0x26d930ac, 0x51de003a, 0xc8d75180, 0xbfd06116, 0x21b4f4b5, 0x56b3c423, 0xcfba9599, 0xb8bda50f,
        0x2802b89e, 0x5f058808, 0xc60cd9b2, 0xb10be924, 0x2f6f7c87, 0x58684c11, 0xc1611dab, 0xb6662d3d,
        0x76dc4190, 0x01db7106, 0x98d220bc, 0xefd5102a, 0x71b18589, 0x06b6b51f, 0x9fbfe4a5, 0xe8b8d433,
        0x7807c9a2, 0x0f00f934, 0x9609a88e, 0xe10e9818, 0x7f6a0dbb, 0x086d3d2d, 0x91646c97, 0xe6635c01,
        0x6b6b51f4, 0x1c6c6162, 0x856530d8, 0xf262004e, 0x6c0695ed, 0x1b01a57b, 0x8208f4c1, 0xf50fc457,
        0x65b0d9c6, 0x12b7e950, 0x8bbeb8ea, 0xfcb9887c, 0x62dd1ddf, 0x15da2d49, 0x8cd37cf3, 0xfbd44c65,
        0x4db26158, 0x3ab551ce, 0xa3bc0074, 0xd4bb30e2, 0x4adfa541, 0x3dd895d7, 0xa4d1c46d, 0xd3d6f4fb,
        0x4369e96a, 0x346ed9fc, 0xad678846, 0xda60b8d0, 0x44042d73, 0x33031de5, 0xaa0a4c5f, 0xdd0d7cc9,
        0x5005713c, 0x270241aa, 0xbe0b1010, 0xc90c2086, 0x5768b525, 0x206f85b3, 0xb966d409, 0xce61e49f,
        0x5edef90e, 0x29d9c998, 0xb0d09822, 0xc7d7a8b4, 0x59b33d17, 0x2eb40d81, 0xb7bd5c3b, 0xc0ba6cad,
        0xedb88320, 0x9abfb3b6, 0x03b6e20c, 0x74b1d29a, 0xead54739, 0x9dd277af, 0x04db2615, 0x73dc1683,
        0xe3630b12, 0x94643b84, 0x0d6d6a3e, 0x7a6a5aa8, 0xe40ecf0b, 0x9309ff9d, 0x0a00ae27, 0x7d079eb1,
        0xf00f9344, 0x8708a3d2, 0x1e01f268, 0x6906c2fe, 0xf762575d, 0x806567cb, 0x196c3671, 0x6e6b06e7,
        0xfed41b76, 0x89d32be0, 0x10da7a5a, 0x67dd4acc, 0xf9b9df6f, 0x8ebeeff9, 0x17b7be43, 0x60b08ed5,
        0xd6d6a3e8, 0xa1d1937e, 0x38d8c2c4, 0x4fdff252, 0xd1bb67f1, 0xa6bc5767, 0x3fb506dd, 0x48b2364b,
        0xd80d2bda, 0xaf0a1b4c, 0x36034af6, 0x41047a60, 0xdf60efc3, 0xa867df55, 0x316e8eef, 0x4669be79,
        0xcb61b38c, 0xbc66831a, 0x256fd2a0, 0x5268e236, 0xcc0c7795, 0xbb0b4703, 0x220216b9, 0x5505262f,
        0xc5ba3bbe, 0xb2bd0b28, 0x2bb45a92, 0x5cb36a04, 0xc2d7ffa7, 0xb5d0cf31, 0x2cd99e8b, 0x5bdeae1d,
        0x9b64c2b0, 0xec63f226, 0x756aa39c, 0x026d930a, 0x9c0906a9, 0xeb0e363f, 0x72076785, 0x05005713,
        0x95bf4a82, 0xe2b87a14, 0x7bb12bae, 0x0cb61b38, 0x92d28e9b, 0xe5d5be0d, 0x7cdcefb7, 0x0bdbdf21,
        0x86d3d2d4, 0xf1d4e242, 0x68ddb3f8, 0x1fda836e, 0x81be16cd, 0xf6b9265b, 0x6fb077e1, 0x18b74777,
        0x88085ae6, 0xff0f6a70, 0x66063bca, 0x11010b5c, 0x8f659eff, 0xf862ae69, 0x616bffd3, 0x166ccf45,
        0xa00ae278, 0xd70dd2ee, 0x4e048354, 0x3903b3c2, 0xa7672661, 0xd06016f7, 0x4969474d, 0x3e6e77db,
        0xaed16a4a, 0xd9d65adc, 0x40df0b66, 0x37d83bf0, 0xa9bcae53, 0xdebb9ec5, 0x47b2cf7f, 0x30b5ffe9,
        0xbdbdf21c, 0xcabac28a, 0x53b39330, 0x24b4a3a6, 0xbad03605, 0xcdd70693, 0x54de5729, 0x23d967bf,
        0xb3667a2e, 0xc4614ab8, 0x5d681b02, 0x2a6f2b94, 0xb40bbe37, 0xc30c8ea1, 0x5a05df1b, 0x2d02ef8d,
    ]
}

@available(macOS 10.14, iOS 12.0, *)
public struct Adler32: CustomStringConvertible {
    private static let zLibAdler32: ZLibAdler32FuncPtr? = loadAdler32fromZLib()

    public init() {}

    // C convention function pointer type matching the signature of `libz::adler32`
    private typealias ZLibAdler32FuncPtr = @convention(c) (
        _ cks:  UInt32,
        _ buf:  UnsafePointer<UInt8>,
        _ len:  UInt32
    ) -> UInt32

    /// Raw checksum. Updated after a every call to `advance(withChunk:)`
    public var checksum: UInt32 = 1

    /// Advance the current checksum with a chunk of data. Designed t be called multiple times.
    /// - parameter chunk: data to advance the checksum
    public mutating func advance(withChunk chunk: Data) {
        if let fastAdler32 = Adler32.zLibAdler32 {
            checksum = chunk.withUnsafeBytes({ (ptr: UnsafePointer<UInt8>) -> UInt32 in
                return fastAdler32(checksum, ptr, UInt32(chunk.count))
            })
        }
        else {
            checksum = slowAdler32(start: checksum, data: chunk)
        }
    }

    public var description: String {
        String(format: "%08x", checksum)
    }

    private static func loadAdler32fromZLib() -> ZLibAdler32FuncPtr? {
        #if os(Windows)
        return nil
        #else
        guard let libz = dlopen("/usr/lib/libz.dylib", RTLD_NOW) else { return nil }
        guard let fptr = dlsym(libz, "adler32") else { return nil }
        return unsafeBitCast(fptr, to: ZLibAdler32FuncPtr.self)
        #endif
    }

    private func slowAdler32(start: UInt32, data: Data) -> UInt32 {
        var s1: UInt32 = start & 0xffff
        var s2: UInt32 = (start >> 16) & 0xffff
        let prime: UInt32 = 65521

        for byte in data {
            s1 += UInt32(byte)
            if s1 >= prime { s1 = s1 % prime }
            s2 += s1
            if s2 >= prime { s2 = s2 % prime }
        }
        return (s2 << 16) | s1
    }
}



@available(macOS 10.14, iOS 12.0, *)
extension Data {
    @usableFromInline func withUnsafeBytes<ResultType, ContentType>(_ body: (UnsafePointer<ContentType>) throws -> ResultType) rethrows -> ResultType {
        try self.withUnsafeBytes({ (rawBufferPointer: UnsafeRawBufferPointer) -> ResultType in
            try body(rawBufferPointer.bindMemory(to: ContentType.self).baseAddress!)
        })
    }
}

/// Pure-swift SHA1 implementation
@usableFromInline final class SHA1 {
    private static let table: [UInt32] = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0]
    private var message: [UInt8]

    @usableFromInline init(_ message: Data) {
        self.message = message.array()
    }

    @usableFromInline init(_ message: [UInt8]) {
        self.message = message
    }

    func prepare(_ message: [UInt8], _ blockSize: Int, _ allowance: Int) -> [UInt8] {
        var tmp = message
        tmp.append(0x80) // append one bit (byte with one bit) to message

        // append "0" bit until message length in bits ≡ 448 (mod 512)
        var msgLength = tmp.count
        var counter = 0

        while msgLength % blockSize != (blockSize - allowance) {
            counter += 1
            msgLength += 1
        }
        tmp += [UInt8](repeating: 0, count: counter)
        return tmp
    }

    @usableFromInline func calculate() -> [UInt8] {
        var tmp = self.prepare(self.message, 64, 64 / 8)
        var hh = Self.table

        tmp += (self.message.count * 8).bytes(64 / 8)

        // Process the message in successive 512-bit chunks:
        let chunkSizeBytes = 512 / 8 // 64
        for chunk in ChunkSequence(data: tmp, chunkSize: chunkSizeBytes) {
            // break chunk into sixteen 32-bit words M[j], 0 ≤ j ≤ 15, big-endian
            // Extend the sixteen 32-bit words into eighty 32-bit words:
            var M: [UInt32] = [UInt32](repeating: 0, count: 80)
            for x in 0..<M.count {
                switch x {
                case 0...15:

                    let memorySize = MemoryLayout<UInt32>.size
                    let start = chunk.startIndex + (x * memorySize)
                    let end = start + memorySize
                    let le = chunk[start..<end].toUInt32
                    M[x] = le.bigEndian
                default:
                    M[x] = rotateLeft(M[x-3] ^ M[x-8] ^ M[x-14] ^ M[x-16], n: 1)
                }
            }

            var A = hh[0]
            var B = hh[1]
            var C = hh[2]
            var D = hh[3]
            var E = hh[4]

            // Main loop
            for j in 0...79 {
                var f: UInt32 = 0
                var k: UInt32 = 0

                switch j {
                case 0...19:
                    f = (B & C) | ((~B) & D)
                    k = 0x5A827999
                case 20...39:
                    f = B ^ C ^ D
                    k = 0x6ED9EBA1
                case 40...59:
                    f = (B & C) | (B & D) | (C & D)
                    k = 0x8F1BBCDC
                case 60...79:
                    f = B ^ C ^ D
                    k = 0xCA62C1D6
                default:
                    break
                }

                let temp = (rotateLeft(A, n: 5) &+ f &+ E &+ M[j] &+ k) & 0xffffffff
                E = D
                D = C
                C = rotateLeft(B, n: 30)
                B = A
                A = temp
            }

            hh[0] = (hh[0] &+ A) & 0xffffffff
            hh[1] = (hh[1] &+ B) & 0xffffffff
            hh[2] = (hh[2] &+ C) & 0xffffffff
            hh[3] = (hh[3] &+ D) & 0xffffffff
            hh[4] = (hh[4] &+ E) & 0xffffffff
        }

        // Produce the final hash value (big-endian) as a 160 bit number:
        var result = [UInt8]()
        result.reserveCapacity(hh.count / 4)
        hh.forEach {
            let item = $0.bigEndian
            result += [UInt8(item & 0xff), UInt8((item >> 8) & 0xff), UInt8((item >> 16) & 0xff), UInt8((item >> 24) & 0xff)]
        }

        return result
    }

    private func rotateLeft(_ v: UInt32, n: UInt32) -> UInt32 {
        return ((v << n) & 0xFFFFFFFF) | (v >> (32 - n))
    }

    private struct ChunkSequence<D: RandomAccessCollection>: Sequence where D.Index == Int {
        let data: D
        let chunkSize: Int

        func makeIterator() -> AnyIterator<D.SubSequence> {
            var offset = data.startIndex
            return AnyIterator {
                let end = Swift.min(self.chunkSize, self.data.count - offset)
                let result = self.data[offset..<offset + end]
                offset = offset.advanced(by: result.count)
                if result.isEmpty {
                    return nil
                } else {
                    return result
                }
            }
        }
    }
}

/// Pure-swift SHA256 implementation
@usableFromInline struct SHA256 {
    private typealias UInt32x8 = (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)
    private static let table: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    private var h: UInt32x8

    @usableFromInline var value: [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(32)
        for word: UInt32 in [h.0, h.1, h.2, h.3, h.4, h.5, h.6, h.7] {
            withUnsafeBytes(of: word.bigEndian) {
                for byte: UInt8 in $0 {
                    bytes.append(byte)
                }
            }
        }
        return bytes
    }

    @usableFromInline init() {
        self.h = (0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19)
    }

    @usableFromInline init<S>(for input: S) where S: Sequence, S.Element == UInt8 {
        self.init()

        var message: [UInt8] = .init(input)
        let length: UInt64 = .init(message.count << 3)

        message.append(0x80)
        while message.count & 63 != 56 {
            message.append(0x00)
        }
        withUnsafeBytes(of: length.bigEndian) {
            for byte: UInt8 in $0 {
                message.append(byte)
            }
        }

        for start: Int in stride(from: message.startIndex, to: message.endIndex, by: 64) {
            self.update(with: message.dropFirst(start).prefix(64))
        }
    }

    private mutating func update(with chunk: ArraySlice<UInt8>) {
        assert(chunk.count == 64)

        let schedule: [UInt32] = .init(unsafeUninitializedCapacity: 64) { (buffer: inout UnsafeMutableBufferPointer<UInt32>, count: inout Int) in
            count = 64
            chunk.withUnsafeBytes {
                for (i, value): (Int, UInt32) in zip(buffer.indices, $0.bindMemory(to: UInt32.self)) {
                    buffer[i] = .init(bigEndian: value)
                }
            }

            for i: Int in 16 ..< count {
                let s: (UInt32, UInt32)
                s.0 = Self.rotate(buffer[i - 15], right: 7) ^
                    Self.rotate(buffer[i - 15], right: 18) ^
                    (buffer[i - 15] >>  3 as UInt32)
                s.1 = Self.rotate(buffer[i -  2], right: 17) ^
                    Self.rotate(buffer[i -  2], right: 19) ^
                    (buffer[i - 2] >> 10 as UInt32)
                let t: UInt32 = s.0 &+ s.1
                buffer[i] = buffer[i - 16] &+ buffer[i - 7] &+ t
            }
        }

        var (a, b, c, d, e, f, g, h): UInt32x8 = self.h

        for i: Int in 0..<64 {
            let s: (UInt32, UInt32)
            s.1 = Self.rotate(e, right: 6) ^
                Self.rotate(e, right: 11) ^
                Self.rotate(e, right: 25)
            s.0 = Self.rotate(a, right: 2) ^
                Self.rotate(a, right: 13) ^
                Self.rotate(a, right: 22)
            let ch: UInt32 = (e & f) ^ (~e & g)
            let temp: (UInt32, UInt32)
            temp.0 = h &+ s.1 &+ ch &+ Self.table[i] &+ schedule[i]
            let maj: UInt32 = (a & b) ^ (a & c) ^ (b & c)
            temp.1 = maj &+ s.0

            h = g
            g = f
            f = e
            e = d &+ temp.0
            d = c
            c = b
            b = a
            a = temp.0 &+ temp.1
        }

        self.h.0 &+= a
        self.h.1 &+= b
        self.h.2 &+= c
        self.h.3 &+= d
        self.h.4 &+= e
        self.h.5 &+= f
        self.h.6 &+= g
        self.h.7 &+= h
    }

    private static func rotate(_ value: UInt32, right shift: Int) -> UInt32 {
        (value >> shift) | (value << (UInt32.bitWidth - shift))
    }
}


public final class HMAC {
    public enum Variant {
        case sha1
        case sha256

        var digestLength: Int {
            switch self {
            case .sha1: return 160 / 8
            case .sha256: return 256
            }
        }

        func calculateHash(_ bytes: Array<UInt8>) -> Array<UInt8> {
            switch self {
            case .sha1: return Data(bytes).sha1().array()
            case .sha256: return Data(bytes).sha256().array()
            }
        }

        func blockSize() -> Int {
            switch self {
            case .sha1: return 64
            case .sha256: return 64
            //case .sha512: return 128
            }
        }
    }

    var key: Array<UInt8>
    let variant: Variant

    public init(key: Array<UInt8>, variant: HMAC.Variant = .sha1) {
        self.variant = variant
        self.key = key

        if key.count > variant.blockSize() {
            let hash = variant.calculateHash(key)
            self.key = hash
        }

        if key.count < variant.blockSize() {
            self.key = zeropad(to: key, blockSize: variant.blockSize())
        }
    }

    @inlinable func zeropad(to bytes: Array<UInt8>, blockSize: Int) -> Array<UInt8> {
        let paddingCount = blockSize - (bytes.count % blockSize)
        if paddingCount > 0 {
            return bytes + Array<UInt8>(repeating: 0, count: paddingCount)
        } else {
            return bytes
        }
    }

    public func authenticate(_ bytes: Array<UInt8>) -> Array<UInt8> {
        var opad = Array<UInt8>(repeating: 0x5c, count: variant.blockSize())
        for idx in self.key.indices {
            opad[idx] = self.key[idx] ^ opad[idx]
        }
        var ipad = Array<UInt8>(repeating: 0x36, count: variant.blockSize())
        for idx in self.key.indices {
            ipad[idx] = self.key[idx] ^ ipad[idx]
        }

        let hash = self.variant.calculateHash(ipad + bytes)
        return self.variant.calculateHash(opad + hash)
    }
}

private extension Collection where Self.Iterator.Element == UInt8, Self.Index == Int {
    var toUInt32: UInt32 {
        assert(self.count > 3)
        // XXX optimize do the job only for the first one...
        return toUInt32Array()[0]
    }

    func toUInt32Array() -> [UInt32] {
        var result = [UInt32]()
        result.reserveCapacity(16)
        for idx in stride(from: self.startIndex, to: self.endIndex, by: MemoryLayout<UInt32>.size) {
            var val: UInt32 = 0
            val |= self.count > 3 ? UInt32(self[idx.advanced(by: 3)]) << 24 : 0
            val |= self.count > 2 ? UInt32(self[idx.advanced(by: 2)]) << 16 : 0
            val |= self.count > 1 ? UInt32(self[idx.advanced(by: 1)]) << 8  : 0
            //swiftlint:disable:next empty_count
            val |= self.count > 0 ? UInt32(self[idx]) : 0
            result.append(val)
        }

        return result
    }

}

private extension Int {
    func bytes(_ totalBytes: Int = MemoryLayout<Int>.size) -> [UInt8] {
        arrayOfBytes(self, length: totalBytes)
    }

    func arrayOfBytes<T>(_ value: T, length: Int? = nil) -> [UInt8] {
        let totalBytes = length ?? MemoryLayout<T>.size

        let valuePointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        valuePointer.pointee = value

        let bytesPointer = UnsafeMutablePointer<UInt8>(OpaquePointer(valuePointer))
        var bytes = [UInt8](repeating: 0, count: totalBytes)
        for j in 0..<Swift.min(MemoryLayout<T>.size, totalBytes) {
            bytes[totalBytes - 1 - j] = (bytesPointer + j).pointee
        }

        valuePointer.deinitialize(count: 1)
        valuePointer.deallocate()

        return bytes
    }
}


/// A simple OAuth1 header generator
public enum OAuth1 {
    private static let oauthVersion = "1.0"
    private static let oauthSignatureMethod = "HMAC-SHA1"

    public struct Info : Hashable {
        public var consumerKey: String
        public var consumerSecret: String
        public var oauthToken: String?
        public var oauthTokenSecret: String?
        public var oauthTimestamp: Date?
        public var oauthNonce: String?

        public init(consumerKey: String, consumerSecret: String, oauthToken: String? = nil, oauthTokenSecret: String? = nil, oauthTimestamp: Date? = nil, oauthNonce: String? = nil) {
            self.consumerKey = consumerKey
            self.consumerSecret = consumerSecret
            self.oauthToken = oauthToken
            self.oauthTokenSecret = oauthTokenSecret
            self.oauthTimestamp = oauthTimestamp
            self.oauthNonce = oauthNonce
        }

        /// The map of parameters for this auth request
        var parameterMap: [String: String] {
            var params: [String: String] = [:]
            params["oauth_version"] = oauthVersion
            params["oauth_signature_method"] = oauthSignatureMethod
            params["oauth_consumer_key"] = self.consumerKey
            params["oauth_timestamp"] = String(Int((self.oauthTimestamp ?? Date()).timeIntervalSince1970))
            params["oauth_nonce"] = self.oauthNonce ?? UUID().uuidString

            if let oauthToken = self.oauthToken {
                params["oauth_token"] = oauthToken
            }
            return params
        }
    }

    /// Creates an authorization header that can be set in the "Authorization" header of a request
    public static func authHeader(for method: String, url: URL, parameters: [String: String] = [:], info: Info) -> String {
        var params = info.parameterMap
        for (key, value) in parameters where key.hasPrefix("oauth_") {
            params.updateValue(value, forKey: key)
        }

        let allParams = params.merging(parameters) { $1 }

        params["oauth_signature"] = oauthSignature(for: method, url: url, parameters: allParams, consumerSecret: info.consumerSecret, oauthTokenSecret: info.oauthTokenSecret)

        let authComponents = params.asQueryString.components(separatedBy: "&").sorted()

        var headerParts = [String]()
        for component in authComponents {
            let subcomponent = component.components(separatedBy: "=")
            if subcomponent.count == 2 {
                headerParts.append("\(subcomponent[0])=\"\(subcomponent[1])\"")
            }
        }

        return "OAuth " + headerParts.joined(separator: ", ")
    }

    private static func oauthSignature(for method: String, url: URL, parameters: [String: String], consumerSecret: String, oauthTokenSecret: String?) -> String {
        let tokenSecret = oauthTokenSecret?.urlEncoded ?? ""
        let signingKey = consumerSecret.urlEncoded + "&" + tokenSecret
        let params = parameters.asQueryString.components(separatedBy: "&").sorted()
        let paramStr = params.joined(separator: "&")
        let encodedParamStr = paramStr.urlEncoded
        let encodedURL = url.absoluteString.urlEncoded
        let sig = method + "&" + encodedURL + "&" + encodedParamStr
        let sha1 = sig.utf8Data.hmacSHA(key: signingKey.utf8Data, hash: .sha1)
        return sha1.base64EncodedString(options: [])
    }
}

private extension Dictionary where Key == String, Value == String {
    var asQueryString: String {
        var parts = [String]()
        for (key, value) in self {
            let keyString = key.urlEncoded
            let valueString = value.urlEncoded
            let query: String = "\(keyString)=\(valueString)"
            parts.append(query)
        }

        return parts.joined(separator: "&")
    }
}

private extension String {
    private static let urlEncodedCharacterSet: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    var urlEncoded: String {
        return addingPercentEncoding(withAllowedCharacters: Self.urlEncodedCharacterSet)!
    }
}


/// A signable instance can be serialized along with a signature of the serialized form,
/// allowing authentication of an arbitrary payload.
public protocol SigningContainer : Encodable {
    /// The JSON encoder that is used to generate the signature.
    ///
    /// Since the signature is dependent on the formatting and key ordering options used in the encoder, the same payload can generate different signature for different encoding options.
    static var signatureEncoder: JSONEncoder { get }

    /// The vairant to use, defaulting to .sha256
    static var signatureHash: HMAC.Variant { get }
}

/// An encoder that replicates JSON Canonical form [JSON Canonicalization Scheme (JCS)](https://tools.ietf.org/id/draft-rundgren-json-canonicalization-scheme-05.html)
private let canonicalJSONEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys] // must not use .withoutEscapingSlashes
    encoder.dateEncodingStrategy = .iso8601
    encoder.dataEncodingStrategy = .base64
    return encoder
}()

extension SigningContainer {
    /// The default signature encoder uses the instance's [JSON Canonicalization Scheme (JCS)](https://tools.ietf.org/id/draft-rundgren-json-canonicalization-scheme-05.html)
    public static var signatureEncoder: JSONEncoder {
        canonicalJSONEncoder
    }

    public static var signatureHash: HMAC.Variant {
        .sha256
    }

    /// Signs the JSON-serialized form of this data using the default encoding properties for this type
    public func sign(key: Data) throws -> Data {
        try Self.signatureEncoder.encode(self).hmacSHA(key: key, hash: Self.signatureHash)
    }

    public func verify(signature: Data, key: Data) throws {
        if try sign(key: key) != signature {
            throw SignableError.signatureMismatch//(signature, signed)
        }
    }
}

/// A Signable instance is capable of storing a signature of the serialized
/// contents of the remainder of the structure. This can be used to
/// authenticate the contents of an untrusted JSON payload by
/// validating it against one or more trusted signing keys.
///
/// The signing will serialize the instance (minus any pre-existing signature)
/// to compact and key-ordered JSON with ISO-8601 date fomatting,
/// then generates a hash-based message authentication code
/// (HMAC with SHA256) of the UTF-8 JSON data.
///
/// The signature will then be embedded within the instance's
/// ``signatureData`` field, which can be used to later
/// authenticate the instance with the ``authenticateSignature``
/// method.
///
/// A compatible a signature creation method can be achieved by
/// using `jq` to format the JSON compactly with ordered keys
/// and then use `openssl` to generate an HMAC-SHA256 code
/// from the bytes, then then base64 encode the code.
///
/// ```
/// % cat file.json | jq -cjS | openssl dgst -sha256 -hmac "secret-key-here" -binary | openssl enc -base64 -A
/// ```
///
///
/// It is important to note that neither signing nor authentication
/// is performed automatically upon codable serialization or deserialization.
/// JSON can be validly deserialized to an instance with an invalid signature,
/// since the signature cannot be authenticated until a key is provided.
public protocol JSONSignable : SigningContainer {
    /// The field that will store the signature of this codable instance
    var signatureData: Data? { get set }
}


extension JSONSignable {
    /// This will clear the current signature, generate a signature for the payload,
    /// and them embed the signature back into the type.
    public mutating func embedSignature(key: Data) throws {
        self.signatureData = nil // clear the embedded signature beforing signing
        self.signatureData = try sign(key: key) // then re-embed the signed payload
    }

    /// Verifies that this payload was signed with the given key
    public func authenticateSignature(key: Data) throws {
        guard let embeddedSignature = self.signatureData else {
            throw SignableError.noEmbeddedSignature
        }
        var payload = self
        payload.signatureData = nil
        try payload.verify(signature: embeddedSignature, key: key)
    }
}

public enum SignableError : Error {
    case noEmbeddedSignature
    case signatureMismatch // (Data, Data) // don't payload the valid signature
}
