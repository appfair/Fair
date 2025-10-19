import Foundation
@_exported import Either
@_exported import JSON
@_exported import YAML
@_exported import XML

// MARK: Result Extensions

public extension Result {
    /// Returns the successful value, or nil if unset
    @inlinable var successValue: Success? {
        switch self {
        case .success(let value): return value
        case .failure: return nil
        }
    }

    /// Returns the failure value, or nil if unset
    @inlinable var failureValue: Failure? {
        switch self {
        case .success: return nil
        case .failure(let value): return value
        }
    }
}

extension Result {
    /// Equivalent of ``Result.init(catching:)``, but allowing an async block
    public init(catchingAsync block: () async throws -> Success) async where Failure == Error {
        do {
            self = .success(try await block())
        } catch {
            self = .failure(error)
        }
    }
}

// MARK: Sequence Extensions

extension Sequence {
    /// Derives an array from this sequence ensuring that the value at the `Hashable` `keyPath` has not yet been uniquely seen.
    @inlinable public func uniquing<T: Hashable>(by keyPath: KeyPath<Element, T>) -> LazyFilterSequence<Self> {
        var seen = Set<T>()
        return self.lazy.filter { element in
            if seen.insert(element[keyPath: keyPath]).inserted {
                return true
            } else {
                return false
            }
        }
    }
}

extension Collection {
    /// Returns the substring of the given string, safely handling index bounds
    public func slice(_ i1: Int, _ i2: Int? = nil) -> SubSequence {
        guard let start = index(startIndex, offsetBy: i1, limitedBy: endIndex) else {
            return self[startIndex..<startIndex]
        }

        let end = i2.flatMap { index(startIndex, offsetBy: $0, limitedBy: endIndex) } ?? endIndex

        return self[start..<end]
    }
}

extension Sequence where Element : Hashable {
    /// Returns a dictionary with the counts of each of the elements.
    /// - Returns: a dictionary with keys for each of the unique elements in the set, along with counts
    @inlinable public func countedSet() -> Dictionary<Element, Int> {
        var dict = Dictionary<Element, Int>()
        for element in self {
            dict[element, default: 0] += 1
        }
        return dict
    }
}

public extension Sequence {
    /// Returns this sequence sorted by the given keypath of the element, either ascending (the default) or descending.
    @inlinable func sorting<T: Comparable>(by keyPath: KeyPath<Element, T>, ascending: Bool = true) -> [Element] {
        sorted(by: { ascending ? ($0[keyPath: keyPath] < $1[keyPath: keyPath]) : ($1[keyPath: keyPath] < $0[keyPath: keyPath]) })
    }

    /// Returns this sequence sorted by the given optional keypath of the element, either ascending (the default) or descending
    /// with `Optional.none` elements sorted in the specified order.
    ///
    /// - Parameter by: the block or keyPath to use for accessing a comparable
    /// - Parameter ascending: whether to sort in ascending (`true`) or descending (`false`) order
    /// - Parameter noneFirst: whether `Optional.none` elements should be sorted at the beginning of the list (the default) or the end.
    ///
    /// - Returns: the sorted elements
    @inlinable func sorting<T: Comparable>(by keyPath: KeyPath<Element, T?>, ascending: Bool = true, noneFirst: Bool = true) -> [Element] {
        sorted(by: {
            switch ($0[keyPath: keyPath], $1[keyPath: keyPath]) {
            case (.none, .none): return noneFirst
            case (.some(let lhs), .some(let rhs)): return ascending ? lhs < rhs : rhs < lhs
            case (.none, .some): return noneFirst == ascending
            case (.some, .none): return noneFirst != ascending
            }
        })
    }
}

public extension Sequence {
    /// Wraps this sequence in a new `Array`
    @inlinable func array() -> Array<Element> {
        Array(self)
    }

    /// Filters out empty elements, equivalent to calling `compactMap({ $0 })`.
    @inlinable func compacted<T>() -> Array<T> where Element == Optional<T> {
        compactMap({ $0 })
    }
}

public extension Sequence where Element : Hashable {
    /// Wraps this sequence of `Hashable` elements in a new `Set`
    @inlinable func set() -> Set<Element> {
        Set(self)
    }

    /// Returns the elements of this sequence by filtering out elements that are equatable to any earlier instance.
    @inlinable func distinct() -> [Element] {
        var set = Set<Element>()
        return filter { set.insert($0).inserted }
    }
}


public extension Sequence {
    /// Creates a dictionary keying on the given `key`.
    @inlinable func dictionary<Key: Hashable>(latterPrecedence: Bool = true, keyedBy key: (Element) -> Key) -> Dictionary<Key, Element> {
        Dictionary(self.map({ element in (key(element), element) }), uniquingKeysWith: { key0, key1 in latterPrecedence ? key1 : key0 })
    }
}


public extension Sequence {
    /// Groups the sequence by the given hash key
    ///
    /// This merely invokes `Dictionary.init(grouping:by:)`
    @inlinable func grouping<T: Hashable>(by key: (Element) -> T) -> Dictionary<T, [Element]> {
        Dictionary(grouping: self, by: key)
    }
}

// MARK: Misc

extension Optional where Wrapped : Equatable {
    /// Subscript to default in the specified value if the current value is `.none`
    @inlinable public subscript(default defaultValue: Wrapped, preserveNil: Bool = false) -> Either<Wrapped>.Or<Wrapped> {
        get {
            flatMap(Either.Or.a) ?? Either.Or.b(defaultValue)
        }

        set {
            self = preserveNil && newValue.avalue == defaultValue ? .none : .some(newValue.avalue)
        }
    }
}

public extension UUID {
    /// Creates a UUID with the given random number generator.
    init<R: RandomNumberGenerator>(rnd: inout R) {
        self.init { UInt8.random(in: .min...(.max), using: &rnd) }
    }

    /// Creates a UUID by populating the bytes with the given block.
    init(bytes: () -> UInt8) {
        self.init(uuid: (bytes(), bytes(), bytes(), bytes(), bytes(), bytes(), bytes(), bytes(), bytes(), bytes(), bytes(), bytes(), bytes(), bytes(), bytes(), bytes()))
    }
}


/// An array of ``Value`` elements that support indexing by keypath.
///
/// This is tantamount to an OrderedDictionary.
public struct IndexedCollection<Key: Hashable, Value> : RandomAccessCollection {
    public let keyPath: KeyPath<Value, Key>
    private var map: Dictionary<Key, Value> = [:]
    private var keys: Array<Key> = []

    public init(indexKeyPath keyPath: KeyPath<Value, Key>) {
        self.keyPath = keyPath
    }

    public subscript(key: Key) -> Value? {
        get {
            map[key]
        }

        set {
            if let newValue = newValue {
                map[key] = newValue
                // duplcate keys are moved to the end of the array
                keys = (keys + [key]).reversed().uniquing(by: \.self).reversed()
            } else {
                keys = keys.filter({ x in x != key })
            }
        }
    }

    public subscript(position: Int) -> Value {
        map[keys[position]]!
    }

    public var startIndex: Int {
        keys.startIndex
    }

    public var endIndex: Int {
        keys.endIndex
    }

    public func index(after i: Int) -> Int {
        keys.index(after: i)
    }

    public func index(before i: Int) -> Int {
        keys.index(before: i)
    }

    public func distance(from start: Int, to end: Int) -> Int {
        keys.distance(from: start, to: end)
    }

    @discardableResult public mutating func removeFirst() -> Key {
        let key = keys.removeFirst()
        map[key] = nil
        return key
    }

    @discardableResult public mutating func removeLast() -> Key {
        let key = keys.removeLast()
        map[key] = nil
        return key
    }

    public mutating func remove(at index: Int) {
        let key = keys.remove(at: index)
        map[key] = nil
    }

    public mutating func removeAll() {
        keys.removeAll()
        map.removeAll()
    }

    public mutating func append(_ element: Element) {
        self[element[keyPath: keyPath]] = element
    }

    /// Exchanges the values at the specified indices of the collection.
    public mutating func swapAt(_ i: Int, _ j: Int) {
        keys.swapAt(i, j)
    }
}


#if canImport(OSLog)
import OSLog
#endif

#if os(macOS) || os(tvOS) || os(iOS) || os(watchOS)
let systemStderr = Darwin.stderr
let systemStdout = Darwin.stdout
#elseif os(Windows)
let systemStderr = CRT.stderr
let systemStdout = CRT.stdout
#elseif canImport(Glibc)
let systemStderr = Glibc.stderr!
let systemStdout = Glibc.stdout!
#elseif canImport(Musl)
let systemStderr = Musl.stderr!
let systemStdout = Musl.stdout!
#elseif canImport(WASILibc)
let systemStderr = WASILibc.stderr!
let systemStdout = WASILibc.stdout!
#else
#error("Unsupported runtime")
#endif

#if canImport(WASILibc) || os(Android)
@usableFromInline internal typealias CFilePointer = OpaquePointer
#else
@usableFromInline internal typealias CFilePointer = UnsafeMutablePointer<FILE>
#endif

@usableFromInline struct StdioOutputStream: TextOutputStream {
    @usableFromInline let file: CFilePointer
    @usableFromInline let flushMode: FlushMode

    @usableFromInline func write(_ string: String) {
        self.contiguousUTF8(string).withContiguousStorageIfAvailable { utf8Bytes in
            #if os(Windows)
            _lock_file(self.file)
            #elseif canImport(WASILibc)
            // no file locking on WASI
            #else
            flockfile(self.file)
            #endif
            defer {
                #if os(Windows)
                _unlock_file(self.file)
                #elseif canImport(WASILibc)
                // no file locking on WASI
                #else
                funlockfile(self.file)
                #endif
            }
            _ = fwrite(utf8Bytes.baseAddress!, 1, utf8Bytes.count, self.file)
            if case .always = self.flushMode {
                self.flush()
            }
        }!
    }

    /// Flush the underlying stream.
    /// This has no effect when using the `.always` flush mode, which is the default
    @usableFromInline func flush() {
        _ = fflush(self.file)
    }

    @usableFromInline func contiguousUTF8(_ string: String) -> String.UTF8View {
        var contiguousString = string
        #if compiler(>=5.1)
        contiguousString.makeContiguousUTF8()
        #else
        contiguousString = string + ""
        #endif
        return contiguousString.utf8
    }

    @usableFromInline static var stderr = StdioOutputStream(file: systemStderr, flushMode: .always)
    @usableFromInline static var stdout = StdioOutputStream(file: systemStdout, flushMode: .always)

    /// Defines the flushing strategy for the underlying stream.
    @usableFromInline enum FlushMode {
        case undefined
        case always
    }
}

/// Logs the given items to `os_log` if `DEBUG` is set
/// - Parameters:
///   - level: the level: 0 for default, 1 for debug, 2 for info, 3 for error, 4+ for fault
@inlinable public func dbg(level: UInt8 = 0, _ arg1: @autoclosure () -> Any? = nil, _ arg2: @autoclosure () -> Any? = nil, _ arg3: @autoclosure () -> Any? = nil, _ arg4: @autoclosure () -> Any? = nil, _ arg5: @autoclosure () -> Any? = nil, _ arg6: @autoclosure () -> Any? = nil, _ arg7: @autoclosure () -> Any? = nil, _ arg8: @autoclosure () -> Any? = nil, _ arg9: @autoclosure () -> Any? = nil, _ arg10: @autoclosure () -> Any? = nil, _ arg11: @autoclosure () -> Any? = nil, _ arg12: @autoclosure () -> Any? = nil, functionName: StaticString = #function, fileName: StaticString = #file, lineNumber: Int = #line) {
    //#if DEBUG
    // log .debug level only in debug mode
    let logit: Bool = assertionsEnabled || (level > 1)
    if logit {
        let items = [arg1(), arg2(), arg3(), arg4(), arg5(), arg6(), arg7(), arg8(), arg9(), arg10(), arg11(), arg12()]
        let msg = items.compactMap({ $0 }).map(String.init(describing:)).joined(separator: " ")

        let funcName = functionName.description.split(separator: "(").first?.description ?? functionName.description

        // use just the last path component
        let filePath = fileName.description
            .split(separator: "/").last?.description
            .split(separator: ".").first?.description
            ?? fileName.description

        let message = "\(filePath):\(lineNumber) \(funcName): \(msg)"
        #if canImport(OSLog)
        os_log(level == 0 ? .debug : level == 1 ? .default : level == 2 ? .info : level == 3 ? .error : .fault, "%{public}@", message)
        #else
        print(level == 0 ? "debug" : level == 1 ? "default" : level == 2 ? "info" : level == 3 ? "error" : "fault", message, to: &StdioOutputStream.stderr)
        #endif
    }
    //#endif
}


@inlinable public func nanos() -> UInt64 {
    DispatchTime.now().uptimeNanoseconds
}

@usableFromInline internal func fmtnanos(from: UInt64, to: UInt64 = nanos()) -> String {
    let ms = Double(to - from) / 1_000_000
    if ms >= 1 {
        // round when over 1ms for formatting
        return "\(Int64(ceil(ms)))ms"
    } else {
        return "\(ms)ms"
    }
}

#if canImport(OSLog)
import OSLog

@usableFromInline let signpostLog = OSLog(subsystem: "fair-ground", category: .pointsOfInterest)
#endif

/// Output a message with the amount of time the given block took to exeucte
/// - Parameter message: the static message to log
/// - Parameter messageBlock: the dynamic message to log; the parameter to the closure is the result of the `block`
/// - Parameter level: the log level fot `dbg`
/// - Parameter threshold: the threshold below which a message will not be printed
/// - Parameter functionName: the name of the calling function
/// - Parameter fileName: the fileName containg the calling function
/// - Parameter lineNumber: the line on which the function was called
/// - Parameter block: the block to execute
///
/// Note that there are two nearly-identical `prf` funcs that vary only in the `async` keyword (see: https://github.com/apple/swift-evolution/blob/main/proposals/0296-async-await.md#reasync).
@inlinable public func prf<T>(_ message: @autoclosure () -> String? = nil, msg messageBlock: ((T) -> String)? = nil, level: UInt8 = 0, threshold: Double = -0.0, functionName: StaticString = #function, fileName: StaticString = #file, lineNumber: Int = #line, block: () throws -> T) rethrows -> T {
    let start = prfstart(functionName: functionName)
    let result = try block()
    if let timeStr = prfend(start: start, threshold: threshold) {
        dbg(level: level, message(), messageBlock?(result), "time: \(timeStr)", functionName: functionName, fileName: fileName, lineNumber: lineNumber)
    }
    return result
}

/// Output a message with the amount of time the given async block took to exeucte
/// - Parameter message: the static message to log
/// - Parameter messageBlock: the dynamic message to log; the parameter to the closure is the result of the `block`
/// - Parameter level: the log level fot `dbg`
/// - Parameter threshold: the threshold below which a message will not be printed
/// - Parameter functionName: the name of the calling function
/// - Parameter fileName: the fileName containg the calling function
/// - Parameter lineNumber: the line on which the function was called
/// - Parameter block: the block to execute
///
/// Note that there are two nearly-identical `prf` funcs that vary only in the `async` keyword (see: https://github.com/apple/swift-evolution/blob/main/proposals/0296-async-await.md#reasync).
@inlinable public func prf<T>(_ message: @autoclosure () -> String? = nil, msg messageBlock: ((T) -> String)? = nil, level: UInt8 = 0, threshold: Double = -0.0, functionName: StaticString = #function, fileName: StaticString = #file, lineNumber: Int = #line, block: () async throws -> T) async rethrows -> T {
    let start = prfstart(functionName: functionName)
    let result = try await block()
    if let timeStr = prfend(start: start, threshold: threshold) {
        dbg(level: level, message(), messageBlock?(result), "time: \(timeStr)", functionName: functionName, fileName: fileName, lineNumber: lineNumber)
    }
    return result
}

@usableFromInline func prfstart(functionName: StaticString) -> UInt64 {
    let start: UInt64 = nanos()

    #if canImport(OSLog)
    os_signpost(.begin, log: signpostLog, name: functionName)
    #endif
    defer {
        #if canImport(OSLog)
        os_signpost(.end, log: signpostLog, name: functionName)
        #endif
    }

    return start
}

@usableFromInline func prfend(start: UInt64, threshold: Double) -> String? {
    let end: UInt64 = max(nanos(), start)
    let secs = Double(end - start) / 1_000_000_000.0

    if secs >= threshold {
        return fmtnanos(from: start, to: end)
    } else {
        return nil
    }
}

public extension BinaryInteger {
    /// Returns this integer formatted as byte counts
    func localizedByteCount(countStyle: ByteCountFormatter.CountStyle = .file) -> String {
        ByteCountFormatter.string(fromByteCount: .init(self), countStyle: countStyle)
    }

    func localizedNumber(style: NumberFormatter.Style = .decimal) -> String {
        NumberFormatter.localizedString(from: NSNumber(integerLiteral: .init(self)), number: style)
    }
}

public extension StringProtocol {
    /// The total span of this string expressed as an NSRange
    var span: NSRange {
        NSRange(startIndex..<endIndex, in: self)
    }

    @inlinable func enquote(with char: Character = "\"") -> String {
        String(char) + String(self) + String(char)
    }

    /// Replaces all the hyphens in the string with a space
    @inlinable func dehyphenated() -> String {
        replacingOccurrences(of: "-", with: " ")
    }

    /// Replaces all the spaces in the string with a hyphen
    @inlinable func rehyphenated() -> String {
        replacingOccurrences(of: " ", with: "-")
    }

    /// Trims whitespace and newlines from either end of this string.
    @inlinable func trimmed(_ characters: CharacterSet = .whitespacesAndNewlines) -> String {
        trimmingCharacters(in: characters)
    }

    /// Trim the given characters from either side of the string, but only if both sides contain the character
    /// Only a single trimming operation will take place; subsequent character matches will be ignored.
    /// This is suitable for de-quoting strings, but preserving any internal quotes. For example:
    ///
    /// ```
    /// "'dog'".trimmedEvenly(["'"]) // returns: dog
    /// "''dog''".trimmedEvenly(["'"]) // returns: 'dog'
    /// "\"'dog'\"".trimmedEvenly(["'"]) // returns: 'dog'
    /// "'\"'dog'\"'".trimmedEvenly(["'"]) // returns: "'dog'"
    /// ```
    @inlinable func trimmedEvenly(_ characters: Array<Character>) -> Self {
        if first == last {
            for char in characters {
                if first == char && count > 1 {
                    return Self(stringLiteral: String(dropLast().dropFirst()))
                }
            }
        }
        return self
    }

}

#if os(macOS) || os(iOS)
extension String {
    /// Parses the attributed text string into an `AttributedString`
    @inlinable public func atx(interpret: AttributedString.MarkdownParsingOptions.InterpretedSyntax = .inlineOnlyPreservingWhitespace, allowsExtendedAttributes: Bool = true, languageCode: String? = nil) throws -> AttributedString {
        try AttributedString(markdown: self, options: .init(allowsExtendedAttributes: allowsExtendedAttributes, interpretedSyntax: interpret, failurePolicy: .returnPartiallyParsedIfPossible, languageCode: languageCode))
    }
}
#endif

fileprivate extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        let generalDelimitersToEncode = ":#[]@" // does not include "?" or "/" due to RFC 3986 - Section 3.4
        let subDelimitersToEncode = "!$&'()*+,;="

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "\(generalDelimitersToEncode)\(subDelimitersToEncode)")
        return allowed
    }()
}

extension String {
    /// `addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed)`
    public var escapedURLTerm: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? self
    }
}

extension String {
    /// Replaces the variables by substituting `#(key)` instances with the corresponding value in the `variables` map.
    public func replacing(variables: [String: String], varPrefix: String = "#(", varSuffix: String = ")") -> String {
        var str = self
        for (key, value) in variables.sorted(by: { $0.key < $1.key }) {
            str = str.replacingOccurrences(of: varPrefix + key + varSuffix, with: value)
        }
        return str
    }
}

public extension Data {
    /// The UTF8-encoded String for this data
    @inlinable var utf8String: String? {
        String(data: self, encoding: .utf8)
    }

    /// Saves the data to the given file URL, unless the contents of the file exactly match this `Data`, in which case it will be left unchanged.
    /// - Parameters:
    ///   - url: the URL to write to
    ///   - options: the writing options
    /// - Returns: true if the URL was written to successfully
    @discardableResult @inlinable func overwrite(to url: URL, options: WritingOptions = []) throws -> Bool {
        var fileSize: Int? = nil
        let isSymLink: Bool
        do {
            let sizeLinkKeys = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            if sizeLinkKeys.isSymbolicLink == true {
                let dest = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                fileSize = try URL(fileURLWithPath: dest).resourceValues(forKeys: [.fileSizeKey]).fileSize
                isSymLink = true
            } else { // regular file? TODO: handle directories (probably with an error)
                fileSize = sizeLinkKeys.fileSize
                isSymLink = false
            }
        } catch {
            // a file that doens't exist will throw an error from resourceValues, so just ignore it
            //dbg("error checking size of file at:", url.path, error)
            isSymLink = false
        }

        if self.count > 0, fileSize == self.count {
            // file exists and it is the same size; read it in to verify the contents
            if try Data(contentsOf: url, options: .mappedIfSafe) == self {
                return false // contents are the same; do not write
            }
        }

        if isSymLink {
            // the behavior of Data.write to a URL that is a symlink appears to be to overwrite the destination of the symbolic link; instead, we remove the link first and write the data
            try FileManager.default.removeItem(at: url)
        }

        try self.write(to: url, options: options)
        return true
    }
}

public extension Date {
    /// Formats the date string for display
    func localizedDate(dateStyle: DateFormatter.Style = .medium, timeStyle: DateFormatter.Style = .medium) -> String {
        DateFormatter.localizedString(from: self, dateStyle: dateStyle, timeStyle: timeStyle)
    }

    #if os(Linux)
    /// Shim for missing `ISO8601Format` on Linux; note that it does not take the `Date.ISO8601FormatStyle` argument.
    func ISO8601Format() -> String {
        iso8601.string(from: self)
    }
    #endif
}

public extension URL {
    /// Initialize this URL with either a full URL with a protocol, or else use the string as a file path.
    /// - Parameter fileOrScheme: either a full URL like `https://www.example.org` or a file path like `/etc/hosts` or `~/Downloads/`.
    init(fileOrScheme: String) {
        if fileOrScheme.hasPrefix("~") || fileOrScheme.hasPrefix("/") {
            self = URL(fileURLWithPath: (fileOrScheme as NSString).expandingTildeInPath)
            return
        }

        guard let url = URL(string: fileOrScheme) else {
            self = URL(fileURLWithPath: fileOrScheme)
            return
        }

        if url.scheme == nil {
            self = URL(fileURLWithPath: fileOrScheme)
        } else {
            self = url
        }
    }
}


public extension URL {
    /// The temporary directory for this process; note that this will probably vary between launches for sandboxed apps
    static let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

    /// If this is a file URL and a directory, return the URL itself, otherwise nil
    var asDirectory: URL? {
        FileManager.default.isDirectory(url: self) == true ? self : nil
    }

    /// Returns the value for a single resource key.
    private func singleResourceValue(forKey key: URLResourceKey) -> Any? {
        try? resourceValues(forKeys: [key]).allValues[key]
    }

    /// The size represented by this file URL, or nil if it is not a file URL.
    func fileSize(includeMetadata: Bool = false, allocated: Bool = false) -> Int? {
        switch (includeMetadata, allocated) {
        case (false, false):
            return singleResourceValue(forKey: .fileSizeKey) as? Int
        case (false, true):
            return singleResourceValue(forKey: .fileAllocatedSizeKey) as? Int
        case (true, false):
            return singleResourceValue(forKey: .totalFileSizeKey) as? Int
        case (true, true):
            return singleResourceValue(forKey: .totalFileAllocatedSizeKey) as? Int
        }
    }
    
    /// The date this file URL was created
    var creationDate: Date? {
        singleResourceValue(forKey: .creationDateKey) as? Date
    }

    /// The date this file URL was last modified
    var modificationDate: Date? {
        contentModificationDateKey
    }

    var attributeModificationDate: Date? {
        singleResourceValue(forKey: .attributeModificationDateKey) as? Date
    }

    /// The date the contents of the URL changed
    var contentModificationDateKey: Date? {
        singleResourceValue(forKey: .contentModificationDateKey) as? Date
    }

    /// A unique name of the cache file, which can be used for storing local caches of URLs
    var cachePathName: String {
        let urlHash = self.absoluteString.utf8Data.sha256().hex()
        let baseName = self.lastPathComponent
        return urlHash + "--" + baseName
    }
}

extension FileManager {
    /// Creates a link from the given URL to the destination URL, optionally creating a relative link between the paths.
    /// - Parameters:
    ///   - url: The file URL at which to create the new symbolic link. The last path component of the URL issued as the name of the link.
    ///   - destURL: the destination URL
    ///   - relative: if `true`, attempts to create a relative link between URLs with the same `baseURL`.
    public func createSymbolicLink(at url: URL, withDestinationURL destURL: URL, relative: Bool) throws {
        if relative, let relativeDestination = url.pathRelative(to: destURL) {
            try createSymbolicLink(atPath: url.path, withDestinationPath: relativeDestination)
        } else {
            try createSymbolicLink(at: url, withDestinationURL: destURL)
        }

    }

    /// Remove the given file URL, attempting to trash it when on macOS, otherwise just deleting it
    public func trash(fileURL: URL, trash: Bool) throws {
        if trash {
            #if os(macOS)
            do {
                // make sure it is writeable, since trashItem will fail if it is not
                //try? localFileSystem.chmod(.userWritable, path: fileURL.absolutePath)

                // trash it on macOS so the user can recover it from the trash
                try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)

                return
            } catch {
                // tolerate failures and fall back to removing the item
            }
            #endif
        }

        // trash not supported or requested
        try FileManager.default.removeItem(at: fileURL)
    }

    /// Returns the deep contents of a given directory URL.
    public func enumeratedURLs(of folderURL: URL) throws -> [URL] {
        var childFileURLs: [URL] = []

        if let fileURLs = self.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let fileURL as URL in fileURLs {
                let attrs = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if attrs.isRegularFile == true || attrs.isSymbolicLink == true {
                    childFileURLs.append(fileURL)
                }
            }
        }

        return childFileURLs
    }

    public func withTemporaryFile<T>(named: String = UUID().uuidString, contents: Data? = nil, perform: (URL) async throws -> T) async throws -> T {
        let tmpFolder = self.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try self.createDirectory(at: tmpFolder, withIntermediateDirectories: true)
        defer { try? self.removeItem(at: tmpFolder) }
        let url = tmpFolder.appendingPathComponent(named)
        if let contents {
            try contents.write(to: url)
        }

        return try await perform(url)
    }
}



extension URL {
    /// When the two URLs have the same base, returns a relative path linking the two URLs.
    ///
    /// This is intended to be used with creating creating relative symbolic links.
    ///
    /// Note that the relative path is formed only from the shared root,
    /// so `a/b/c.txt` and `a/x/y.txt`
    /// are linked as `a/b/c.txt->../../a/x/y.txt`,
    /// rather than the more optimal: `a/b/c.txt->../x/y.txt`.
    ///
    /// - Parameter url: the target URL to check against
    /// - Returns: the relative path between the two URLs, suitable for linking
    public func pathRelative(to url: URL) -> String? {
        // TODO: use FileManager.findCommonRelative() to identify more than a single level up

        guard let fromBaseURL = self.baseURL,
              let toBaseURL = url.baseURL,
              fromBaseURL == toBaseURL else {
            //dbg("uncommon ancestor between:", self, url)
            return nil
        }

        let commonRelative = self.relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .dropLast(1)
            .map({ _ in ".." })
            .joined(separator: "/")
        return commonRelative + "/" + url.relativePath
    }
}

extension FileHandle {
    /// Reads the data in asynchronous chunks from the ``NSFileHandle``.
    ///
    /// Note: “You must call this method from a thread that has an active run loop.”
//    public func readDataAsync(queue: OperationQueue?, forModes modes: [RunLoop.Mode]?) -> AsyncThrowingStream<Data, Error> {
//        return AsyncThrowingStream { c in
//            var observer: NSObjectProtocol?
//
//            func removeObserver() {
//                NotificationCenter.default.removeObserver(self, name: FileHandle.readCompletionNotification, object: observer)
//            }
//
//            observer = NotificationCenter.default.addObserver(forName: FileHandle.readCompletionNotification, object: self, queue: queue) { [weak self] note in
//                guard let self = self else { return }
//
//                if let errorNumber = note.userInfo?["NSFileHandleError"] as? NSNumber {
//                    removeObserver()
//                    c.finish(throwing: CocoaError(CocoaError.Code(rawValue: errorNumber.intValue)))
//                } else if let data = note.userInfo?[NSFileHandleNotificationDataItem] as? Data {
//                    c.yield(data)
//                    self.readInBackgroundAndNotify(forModes: modes) // “Note that this method does not cause a continuous stream of notifications to be sent. If you wish to keep getting notified, you’ll also need to call readInBackgroundAndNotify() in your observer method.”
//                } else {
//                    removeObserver()
//                    observer = nil
//                    c.finish()
//                }
//            }
//
//            // note: “You must call this method from a thread that has an active run loop.”
//            readInBackgroundAndNotify(forModes: modes)
//        }
//    }
}

/// Performs the given block and, if an error occurs, enhances the error description with the given value.
/// The string should be the name of the action that was being taken, and will be prefixed with "Error".
///
/// For example:
///
/// ```
/// let data = try withErrorContext("opening URL: \(url.absoluteString)") { try Data(contentsOf: url) }
/// ```
public func withErrorContext<T>(_ info: @autoclosure () -> String, key: String = NSLocalizedFailureReasonErrorKey, block: () throws -> T) throws -> T {
    do {
        return try block()
    } catch {
        throw error.withInfo(for: key, "Error " + info(), prefix: true)
    }
}


public extension Error {
    /// Insert the given info into the user info dictionary key, pre-pending it to an existing message if it already exists.
    /// Note that this will lose the existing error type and wrap it in an `NSError`.
    func withInfo(for key: String, _ info: @autoclosure () -> String, prefix: Bool? = true) -> Error {
        let nserr = (self as NSError)
        var errorDic = nserr.userInfo

        errorDic[key] = [
            prefix == true ? info() : nil,
            prefix == nil ? nil : errorDic[key] as? String,
            prefix != true ? info() : nil,
        ].compactMap({ $0 }).joined(separator: ". ")

        let nserr2 = NSError(domain: nserr.domain, code: nserr.code, userInfo: errorDic)
        return nserr2
    }

    func dumpError<O: TextOutputStream>(out: inout O) {
        print("Error:", self.localizedDescription, to: &out)
        let localizedError = self as NSError // handles LocalizedError

        if let failureReason = localizedError.localizedFailureReason {
            print("   Reason:", failureReason, to: &out)
        }
        if let recoverySuggestion = localizedError.localizedRecoverySuggestion {
            print("   Suggestion:", recoverySuggestion, to: &out)
        }
        if let helpAnchor = localizedError.helpAnchor {
            print("   Help:", helpAnchor, to: &out)
        }
        print("Raw:", localizedError.debugDescription, to: &out)
    }
}


/// Wrapper around `NSCache` that allows keys/values to be value types and has an atomic `fetch` option.
public final class Cache<Key : Hashable, Value> {
    @usableFromInline typealias CacheType = NSCache<KeyRef, ValRef>

    /// We work with an internal cache because “Extension of a generic Objective-C class cannot access the class's generic parameters at runtime”
    @usableFromInline let cache = CacheType()

    // private let logger = LoggingDelegate()
    @usableFromInline let lock = NSRecursiveLock()

    public init(name: String = "\(#file):\(#line)", countLimit: Int? = 0) {
        self.cache.name = name
        // self.cache.delegate = logger
        if let countLimit = countLimit {
            self.cache.countLimit = countLimit
        }
    }

    /// Performs an operation on the reference, optionally locking it first
    @usableFromInline func withLock<T>(exclusive: Bool = true, action: () throws -> T) rethrows -> T {
        if exclusive { lock.lock() }
        defer { if exclusive { lock.unlock() } }
        return try action()
    }

    private class LoggingDelegate : NSObject, NSCacheDelegate {
        func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
//            if let obj = obj as? ValRef {
//                print("evicting", obj.val, "from", Cache<Key, Value>.self)
//            } else {
//                print("evicting", obj, "from", Cache<Key, Value>.self)
//            }
        }
    }

    public subscript(key: Key) -> Value? {
        get {
            cache.object(forKey: KeyRef(key))?.val
        }

        set {
            if let newValue = newValue {
                cache.setObject(ValRef(.init(newValue)), forKey: KeyRef(key))
            } else {
                cache.removeObject(forKey: KeyRef(key))
            }
        }
    }

    /// Gets the instance from the cache, or `create`s it if is not present
    @inlinable public func fetch(key: Key, exclusive: Bool = false, create: (Key) throws -> (Value)) rethrows -> Value {
        // cache is thread safe, so we don't need to sync; but one possible advantage of syncing is that two threads won't try to generate the value for the same key at the same time, but in an environment where we are pre-populating the cache from multiple threads, it is probably better to accept the multiple work items rather than cause the process to be serialized
        let keyRef = KeyRef(key) // NSCache requires that the key be an NSObject subclass
        // quick lockless check for the object; we will check again inside any exclusive block
        if let object = cache.object(forKey: keyRef)?.val {
            return object
        }

        var lockOrValue = ValRef(nil) // empty value: create a new empty ValRef (i.e., the lock)

        do {
            if let lockValue = cache.object(forKey: keyRef) {
                if let value: Value = lockValue.withLock(exclusive: exclusive, action: {
                    if let value = lockValue.val {
                        return value
                    } else {
                        lockOrValue = lockValue // empty value means use the ref as a lock
                        return Value?.none
                    }
                }) {
                    return value
                }
            } else {
                cache.setObject(lockOrValue, forKey: keyRef)
            }
        }

        do {
            let value = try lockOrValue.withLock(exclusive: exclusive) {
                try create(key)
            }

            if exclusive {
                // when exclusive, we update the existing value's pointer…
                lockOrValue.val = value
            } else {
                // …otherwise we overwrite with a new (unsynchronized) value
                cache.setObject(ValRef(value), forKey: keyRef)
            }

            return value
        }
    }

    /// Empties the cache.
    public func clear() {
        cache.removeAllObjects()
    }

    /// The maximum total cost that the cache can hold before it starts evicting objects.
    /// If 0, there is no total cost limit. The default value is 0.
    /// When you add an object to the cache, you may pass in a specified cost for the object, such as the size in bytes of the object. If adding this object to the cache causes the cache’s total cost to rise above totalCostLimit, the cache may automatically evict objects until its total cost falls below totalCostLimit. The order in which the cache evicts objects is not guaranteed.
    /// - Note: This is not a strict limit, and if the cache goes over the limit, an object in the cache could be evicted instantly, at a later point in time, or possibly never, all depending on the implementation details of the cache.
    public var totalCostLimit: Int {
        get { cache.totalCostLimit }
        set { cache.totalCostLimit = newValue }
    }

    /// The maximum number of objects the cache should hold.
    /// If 0, there is no count limit. The default value is 0.
    /// - Note: This is not a strict limit—if the cache goes over the limit, an object in the cache could be evicted instantly, later, or possibly never, depending on the implementation details of the cache.
    public var countLimit: Int {
        get { cache.countLimit }
        set { cache.countLimit = newValue }
    }

    /// A reference wrapper around another type that enables locking operations.
    @usableFromInline final class ValRef {
        @usableFromInline var val: Value?
        @usableFromInline let lock = NSRecursiveLock()

        @inlinable init(_ val: Value?) { self.val = val }

        /// Performs an operation on the reference, optionally locking it first
        @usableFromInline func withLock<T>(exclusive: Bool = true, action: () throws -> T) rethrows -> T {
            if exclusive { lock.lock() }
            defer { if exclusive { lock.unlock() } }
            return try action()
        }
    }

    /// A reference that can be used as a cache key for `NSCache` that wraps a value type. Unlike `ValRef`, the key must be an `NSObject`
    @usableFromInline final class KeyRef: NSObject {
        @usableFromInline let val: Key

        @usableFromInline init(_ val: Key) {
            self.val = val
        }

        @inlinable override func isEqual(_ object: Any?) -> Bool {
            return (object as? Self)?.val == self.val
        }

        @inlinable static func ==(lhs: KeyRef, rhs: KeyRef) -> Bool {
            return lhs.val == rhs.val
        }

        @inlinable override var hash: Int {
            return self.val.hashValue
        }
    }
}

/// A property list, which is simply a wrapper around an `NSDictionary` with some conveniences.
public final class Plist : RawRepresentable, Hashable {
    public let rawValue: NSDictionary

    public init() {
        self.rawValue = NSDictionary()
    }

    public init(rawValue: NSDictionary) {
        self.rawValue = rawValue
    }

    /// Attempts to parse the given data as a property list
    /// - Parameters:
    ///   - data: the property list data to parse
    ///   - format: the format the data is expected to be in, or nil if empty
    public convenience init(data: Data) throws {
        guard let props = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? NSDictionary else {
            throw CocoaError(.coderInvalidValue)
        }
        self.init(rawValue: props)
    }

    public convenience init(url: URL) throws {
        do {
            let data = try Data(contentsOf: url)
            try self.init(data: data)
        } catch {
            throw error.withInfo(for: NSLocalizedFailureReasonErrorKey, "Error loading from: \(url.absoluteString)")
        }
    }

    /// Serialize this property list to data
    public func serialize(as format: PropertyListSerialization.PropertyListFormat) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: rawValue, format: format, options: 0)
    }

    public func json() throws -> JSON {
        try rawValue.json()
    }
}

extension NSDictionary {
    public func json(failure: (Any) throws -> () = { _ in }) rethrows -> JSON {
        try Self.json(dictionary: self, failure: failure)
    }

    private static func json(dictionary: NSDictionary, failure: (Any) throws -> ()) rethrows -> JSON {
        var obj = JSON.Object()

        for (key, value) in dictionary {
            guard let key = key as? String else {
                try failure(key)
                continue
            }

            try obj[key] = json(element: value, failure: failure)
        }

        return .object(obj)
    }

    private static func json(array: NSArray, failure: (Any) throws -> ()) rethrows -> JSON {
        var arr: [JSON] = []

        for value in array {
            try arr.append(json(element: value, failure: failure))
        }

        return .array(arr)
    }

    /// Converts this `NSDictionary` into a `JSON` type, optionally failing on un-translatable elements.
    private static func json(element: Any, failure: (Any) throws -> ()) rethrows -> JSON {
        if let obj = element as? NSDictionary {
            return try json(dictionary: obj, failure: failure)
        } else if let arr = element as? NSArray {
            return try json(array: arr, failure: failure)
        } else if let data = element as? Data {
            return .string(data.base64EncodedString())
        } else if let date = element as? Date {
            return .string(iso8601.string(from: date))
        } else if let _ = element as? NSNull {
            return .null
        } else if let str = element as? String {
            return .string(str)
        } else if let bol = element as? Bool {
            return .boolean(bol)
        } else if let num = element as? NSNumber {
            #if canImport(ObjectiveC)
            if CFNumberGetType(num) == .charType {
                return .boolean(num.boolValue)
            } else {
                return .number(num.doubleValue)
            }
            #else
            return .number(num.doubleValue)
            #endif
        } else {
            try failure(element)
            return .null
        }
    }
}

/// A shared date formatter for JSON serialization
private let iso8601: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

extension JSON {
    /// Parses the given plist data into a JSON structure.
    public static func parse(plist data: Data) throws -> JSON {
        try Plist(data: data).json()
    }
}

/// A type that permits items to be initialized non-optionally
public protocol RawInitializable : RawRepresentable {
    init(rawValue: RawValue)
}

public extension RawInitializable {
    /// Delegate optional initializer to the guaranteed initializer.
    /// - Parameter rawValue: the value to store in the representable
    init?(rawValue: RawValue) {
        self.init(rawValue: rawValue)
    }
}

public extension Equatable {
    /// Wraps this instance in the `RawInitializable` specified by the type (often expected to be inferred)
    /// - Returns: a `RawInitializable` wrapper around the type
    func represent<T: RawInitializable>() -> T where T.RawValue == Self {
        T(rawValue: self)
    }
}

public extension Equatable {
    /// Wraps this instance in the `RawRepresentable` specified by the type (often expected to be inferred)
    /// - Returns: a `RawRepresentable` wrapper around the type
    func represent<T: RawRepresentable>() -> T? where T.RawValue == Self {
        T(rawValue: self)
    }
}


/// A `RawDecodable` is a `RawInitializable` with a `Decodable` `RawValue`.
/// Implementations of this type will decode their `rawValue` payload directly, rather than from an objec with a "rawValue" property.
public protocol RawDecodable : RawInitializable, Decodable where RawValue : Decodable {
}

/// A `RawDecodable` is a `RawRepresentable` with an `Encodable` `RawValue`.
/// Implementations of this type will encode their `rawValue` payload directly, rather than to an objec with a "rawValue" property.
public protocol RawEncodable : RawRepresentable, Encodable where RawValue : Encodable {
}

/// A RawCodable is a simple `RawRepresentable` wrapper except its coding
/// will store the underlying value directly rather than keyed as "rawValue",
/// thus requiring that the `init(rawValue:)` be non-failable; it is useful
/// as a codable typesafe wrapper for some general type like UUID where the
/// Codable implementation does not automatically use the underlying type (like
/// it does with primitives and Strings)
public typealias RawCodable = RawDecodable & RawEncodable

public extension RawDecodable {
    /// A `RawCodable` deserializes from the underlying type's decoding with any intermediate wrapper
    init(from decoder: Decoder) throws {
        try self.init(rawValue: RawValue(from: decoder))
    }
}

public extension RawEncodable {
    /// A `RawCodable` serializes to the underlying type's encoding with any intermediate wrapper
    func encode(to encoder: Encoder) throws {
        try rawValue.encode(to: encoder)
    }
}

public extension Task where Success == Never, Failure == Never {
    /// Suspends the current task for at least the given ``TimeInterval`` duration.
    ///
    /// If the task is canceled before the time ends, this function throws CancellationError.
    /// This function doesn’t block the underlying thread.
    static func sleep(interval: TimeInterval) async throws {
        try await sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
}

/// `true` if assertions are enabled for the current build
public let assertionsEnabled: Bool = {
    var enabled = false
    assert({
        enabled = true
        return enabled
    }())
    return enabled
}()


// MARK: Package-Specific Utilities


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
private let moduleBundle = Bundle(url: Bundle.main.bundleURL.appendingPathComponent("Fair_FairCore.bundle"))


/// Work-in-Progress marker
@available(*, deprecated, message: "work in progress")
@usableFromInline internal func wip<T>(_ value: T) -> T { value }
