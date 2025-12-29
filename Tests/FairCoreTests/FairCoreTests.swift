// Copyright (c) 2022 - 2026 The App Fair Project <info@appfair.org>
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-or-later
import Swift
import XCTest
import FairCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class FairCoreTests: XCTestCase {
    func testXOrOr() throws {
        typealias StringOrInt = Either<String>.Or<Int>
        let str = StringOrInt.a("ABC")
        let int = StringOrInt.b(12)
        XCTAssertNotEqual(str, int)
        XCTAssertEqual("[\"ABC\"]", try String(data: JSONEncoder().encode([str]), encoding: .utf8))
        XCTAssertEqual("[12]", try String(data: JSONEncoder().encode([int]), encoding: .utf8))

        func rt<T: Codable & Equatable>(_ value: T, equal: Bool = true, line: UInt = #line) throws {
            let roundTripped = try T(fromJSON: value.debugJSON.utf8Data)
            if equal {
                XCTAssertEqual(value, roundTripped, line: line)
            } else {
                XCTAssertNotEqual(value, roundTripped, line: line)
            }
        }

        let _: Either<String>.Or<Either<Int>.Or<Double>> = Either<String>.Or<Int>.Or<Double>.a("")

        // check that `infer()` works on nested XOrs
        let nested: Either<String>.Or<Either<Either<Int>.Or<Double>>.Or<Bool>> = Either<String>.Or<Int>.Or<Double>.Or<Bool>.a("")
        let _: String? = nested.infer()
        let _: Int? = nested.infer()
        let _: Double? = nested.infer()
        let _: Bool? = nested.infer()
        XCTAssertEqual("", nested.infer())

        let _: Either<String>.Or<Either<Either<Either<Int>.Or<Double>>.Or<Bool>>.Or<Float>> = Either<String>.Or<Int>.Or<Double>.Or<Bool>.Or<Float>.a("")

        //        let _: Either<String>.Or<Either<Int>.Or<Either<Double>.Or<Float>>> = Either<String>.Or<Int>.Or<Double>.Or<Float>("")

        XCTAssertEqual("[123]", try [Either<Int>(123)].debugJSON)
        XCTAssertEqual("[false]", try [Either<String>.Or<Bool>(false)].debugJSON)
        XCTAssertEqual("[[]]", try [Either<String>.Or<[String]>([])].debugJSON)
        XCTAssertEqual("[{}]", try [Either<String>.Or<[String: String]>([:])].debugJSON)
        XCTAssertEqual("[{\"X\":1}]", try [Either<String>.Or<[String: Int]>(["X":1])].debugJSON)
        XCTAssertEqual("[\"ABC\"]", try [Either<String>.Or<Bool>.a("ABC")].debugJSON)

        try rt(Either<Int>(123))
        try rt(Either<String>("ABC"))

        try rt(Either<Int>.Or<String>.b("ABC"))
        try rt(Either<Int>.Or<String>(12))

        try rt(Either<Int>.Or<String>.Or<Bool>(12))
        try rt(Either<Int>.Or<String>.Or<Bool>(.init("ABC")))
        try rt(Either<Int>.Or<String>.Or<Bool>(.init(true)))
        try rt(Either<Int>.Or<String>.Or<Bool>(.init(false)))

        try rt(Either<UInt8>.Or<UInt16>(UInt8.max))
        try rt(Either<UInt8>.Or<UInt16>(UInt16.max))
        try rt(Either<UInt16>.Or<UInt8>(UInt16.max))
        // since UInt8.max can be decoded into UInt16, this test will fail because the UInt8 side is encoded, but the UInt16 side is decoded
        try rt(Either<UInt16>.Or<UInt8>(UInt8.max), equal: false)

        try rt(Either<Int>.Or<Double>(123.4))

        // should fail because round numbers are indistinguishable beteen Int and Double in JSON, so the Double side will be encoded, but the Int side will be the one that will be decoded (simply because it is first in the list)
        try rt(Either<Int>.Or<Double>(123.0), equal: false)
    }

    /// Tests modeling JSON types using `XOr.Or`
    func testJSON() throws {
        typealias JSONPrimitive = Either<String>.Or<Double>.Or<Bool>?
        typealias JSON1<T> = Either<JSONPrimitive>.Or<T>
        typealias JSON2<T> = JSON1<JSON1<T>>
        typealias JSON3<T> = JSON2<JSON1<T>>
        typealias JSON = JSON3<JSONPrimitive>
        typealias JSONArray = Array<JSON>
        typealias JSONObject = Dictionary<String, JSON>
        typealias JSONComplex = Either<JSONObject>.Or<JSONArray>

        // let json1 = try JSON(fromJSON: "abc".utf8Data)
    }

    func testProjectFormat() throws {
        let valid = { PropertyListSerialization.propertyList($0, isValidFor: PropertyListSerialization.PropertyListFormat.openStep) }

        let _ = valid

        var fmt: PropertyListSerialization.PropertyListFormat = .binary
        let parse = { (x: Data) in try PropertyListSerialization.propertyList(from: x, options: [], format: &fmt) }

        let _ = parse
    }

    func testAppVersionParsing() {
        let versionString = { SemVer(string: $0)?.versionString }

        XCTAssertEqual(nil, versionString(""))
        XCTAssertEqual(nil, versionString(" "))
        XCTAssertEqual(nil, versionString("1.2. 3"))
        XCTAssertEqual(nil, versionString("1.2..3"))
        XCTAssertEqual(nil, versionString(".1.2.3"))
        XCTAssertEqual(nil, versionString("1.2.3."))
        XCTAssertEqual(nil, versionString("1_1.2.3."))
        XCTAssertEqual(nil, versionString("-1.2.3"))
        XCTAssertEqual(nil, versionString("1.-2.3"))
        XCTAssertEqual(nil, versionString("1.2.-3"))

        XCTAssertEqual("1.2.3", versionString("1.2.3"))
        XCTAssertEqual("0.2.3", versionString("0.2.3"))
        XCTAssertEqual("999.9999.99999", versionString("999.9999.99999"))

        // test semantic version sorting
        // https://semver.org/#spec-item-11
        let parse = { try XCTUnwrap(SemVer(string: $0)) }
        let roundtrip = { XCTAssertEqual($0, SemVer(string: $0)?.versionString) }

        // 1.0.0-alpha, 1.0.0-alpha.1, 1.0.0-0.3.7, 1.0.0-x.7.z.92, 1.0.0-x-y-z
        roundtrip("1.0.0-alpha")
        roundtrip("1.0.0-alpha.1")
        roundtrip("1.0.0-0.3.7")
        roundtrip("1.0.0-x.7.z.92")
        roundtrip("1.0.0-x-y-z")

        // 1.0.0-alpha+001, 1.0.0+20130313144700, 1.0.0-beta+exp.sha.5114f85, 1.0.0+21AF26D3----117B344092BD
        roundtrip("1.0.0-alpha+001")
        roundtrip("1.0.0+20130313144700")
        roundtrip("1.0.0-beta+exp.sha.5114f85")
        roundtrip("1.0.0+21AF26D3----117B344092BD")

        // 1.0.0 < 2.0.0 < 2.1.0 < 2.1.1
        try XCTAssertLessThan(parse("1.0.0"), parse("2.0.0"))
        try XCTAssertLessThan(parse("2.0.0"), parse("2.1.0"))
        try XCTAssertLessThan(parse("2.1.0"), parse("2.1.1"))

        // 1.0.0-alpha < 1.0.0
        try XCTAssertLessThan(parse("1.0.0-alpha"), parse("1.0.0"))

        // 1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta < 1.0.0-beta.2 < 1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0
        try XCTAssertLessThan(parse("1.0.0-alpha"), parse("1.0.0-alpha.1"))
        try XCTAssertLessThan(parse("1.0.0-alpha.1"), parse("1.0.0-alpha.beta"))
        try XCTAssertLessThan(parse("1.0.0-alpha.beta"), parse("1.0.0-beta"))
        try XCTAssertLessThan(parse("1.0.0-beta"), parse("1.0.0-beta.2"))
        try XCTAssertLessThan(parse("1.0.0-beta.2"), parse("1.0.0-beta.11"))
        try XCTAssertLessThan(parse("1.0.0-beta.11"), parse("1.0.0-rc.1"))
        try XCTAssertLessThan(parse("1.0.0-rc.1"), parse("1.0.0"))
    }

    func testSorting() {
        do {
            let ints = [0, 1, 2, 3]
            XCTAssertEqual(ints, ints.sorting(by: \.self, ascending: true))
            XCTAssertEqual(ints.reversed(), ints.sorting(by: \.self, ascending: false))
        }

        do {
            let ints = [0, 1, 2, 2, 3]
            XCTAssertEqual(ints, ints.sorting(by: \.self, ascending: true))
            XCTAssertEqual(ints.reversed(), ints.sorting(by: \.self, ascending: false))
        }

        do {
            let intsNoneFirst = [Optional.none, 0, 1, 2, 2, 2, 3]
            let intsNoneLast = [0, 1, 2, 2, 2, 3, Optional.none]

            XCTAssertEqual(intsNoneFirst, intsNoneFirst.sorting(by: \.self))
            XCTAssertEqual(intsNoneFirst, intsNoneFirst.sorting(by: \.self, ascending: true))
            XCTAssertEqual(intsNoneFirst, intsNoneFirst.sorting(by: \.self, ascending: true, noneFirst: true))

            XCTAssertEqual(intsNoneLast, intsNoneFirst.sorting(by: \.self, noneFirst: false))
            XCTAssertEqual(intsNoneLast, intsNoneFirst.sorting(by: \.self, ascending: true, noneFirst: false))
            XCTAssertEqual(intsNoneLast.reversed(), intsNoneFirst.sorting(by: \.self, ascending: false, noneFirst: false))

            XCTAssertEqual(intsNoneFirst, intsNoneFirst.sorting(by: \.self, noneFirst: true))
            XCTAssertEqual(intsNoneFirst, intsNoneFirst.sorting(by: \.self, ascending: true, noneFirst: true))
            XCTAssertEqual(intsNoneFirst.reversed(), intsNoneFirst.sorting(by: \.self, ascending: false, noneFirst: true))
        }
    }

    func testFairCoreVersion() throws {
        let version = try XCTUnwrap(Bundle.fairCoreVersion)
        dbg("loaded fairCoreVersion:", version.versionString)
        XCTAssertGreaterThan(version, SemVer(major: 0, minor: 1, patch: 0))

        // shows the difference between the auto-generated bundle's infoDictionary and the FairCore.plist
        // XCTAssertEqual("Fair-FairCore-resources", Bundle.fairCore.infoDictionary?["CFBundleIdentifier"] as? String) // this doesn't seem to happen on CI
        XCTAssertEqual("org.appfair.Fair", Bundle.fairCoreInfo.CFBundleIdentifier)

    }

    func testBinaryReadable() async throws {
        let bytes: [UInt8] = [ 32, 232, 52, 41, 4, 0, 0, 0, 0, 1, 0, 0, 0, 33]

        /// Wrapper around XCTAssertEqual to bypass lack of support for async
        func xeq<T: Equatable>(_ expect: T, _ actual: T) {
            XCTAssertEqual(expect, actual)
        }

        do { // SeekableDataHandle
            let data = SeekableDataHandle(Data(bytes))
            xeq(32, try data.readUInt8())
            xeq(3895732484, try data.readUInt32())
            xeq(16777216, try data.readInt64())
            xeq(33, try data.readUInt8())
//            XCTAssertThrowsError(try data.readData(ofLength: 1))
        }

        do { // SeekableDataHandle & ReverseEndianSeekableData
            let data = SeekableDataHandle(Data(bytes)).reversedEndian()
            xeq(32, try data.readUInt8())
            xeq(69809384, try data.readUInt32())
            xeq(4294967296, try data.readInt64())
            xeq(33, try data.readUInt8())
//            XCTAssertThrowsError(try data.readData(ofLength: 1))
        }

        do { // SeekableDataHandle & ReverseEndianSeekableData & ReverseEndianSeekableData
            let data = SeekableDataHandle(Data(bytes)).reversedEndian().reversedEndian()
            xeq(32, try data.readUInt8())
            xeq(3895732484, try data.readUInt32())
            xeq(16777216, try data.readInt64())
            xeq(33, try data.readUInt8())
//            XCTAssertThrowsError(try data.readData(ofLength: 1))
        }

        do { // SeekableFileHandle
            let file = URL(fileURLWithPath: UUID().uuidString, isDirectory: false, relativeTo: .tmpdir)
            try Data(bytes).write(to: file)
            let data = try SeekableFileHandle(FileHandle(forReadingFrom: file))
            xeq(32, try data.readUInt8())
            xeq(3895732484, try data.readUInt32())
            xeq(16777216, try data.readInt64())
            xeq(33, try data.readUInt8())
//            XCTAssertThrowsError(try data.readData(ofLength: 1))
        }
    }

    func testFileHandleBytesAsync() async throws {
        let fh = try FileHandle(forReadingFrom: URL(fileURLWithPath: "/dev/urandom"))
        let xpc = expectation(description: "asyncRead")

        let _ = Task.detached {
            var reads = 0
            do {
                for try await b in fh.bytesAsync {
                    //dbg("read /dev/random chunk:", b)
                    let _ = b
                    reads += 1
                    if reads == 999 {
                        xpc.fulfill()
                        break
                    }
                }
            } catch {
                XCTFail("\(error)")
                xpc.fulfill()
            }
        }

        try await Task.sleep(interval: 0.0) // seems to be needed on iOS to start the bytes
        //wait(for: [xpc], timeout: 2)
        await fulfillment(of: [xpc], timeout: 2, enforceOrder: true)
    }

    func testURLSessionDataAsync() async throws {
        // try await readURLAsync(url: URL(fileURLWithPath: "/dev/urandom")) // works on Darwin but not on Linux

        try await readURLAsync(url: URL(string: "https://www.example.org")!, expectRedirect: 0)

        try await readURLAsync(url: URL(string: "https://github.com/appfair/Fair")!, expectRedirect: 0)
        try await readURLAsync(url: URL(string: "https://github.com/appfair/Fair.git")!, expectRedirect: 1)

        // two separate redirects: www.github.com -> github.com and Fair.git to Fair/
        try await readURLAsync(url: URL(string: "https://www.github.com/appfair/Fair.git")!, expectRedirect: 2, expectChallenge: 2)

        try await readURLAsync(url: URL(string: "https://github.com/appfair/UNKNOWN_REPO")!, expectRedirect: 0, expectChallenge: 1) // unknown repositories response with a challenge
    }
    
    func readURLAsync(url: URL, expectRedirect: Int? = nil, expectChallenge: Int? = nil) async throws {
        var redirectReceived: Int = 0
        var challengeReceived: Int = 0
    out:
        for try await event in try URLRequest(url: url).openStream() {
            switch event {
            case .response(let response):
                dbg("response:", response.expectedContentLength, response.mimeType, response.suggestedFilename)
            case .data(let data):
                dbg("data:", data)
                break out
            case .redirect(let redirectResponse, let newRequest, _):
                dbg("redirect:", redirectResponse, newRequest)
                redirectReceived += 1
            case .challenge(let challenge):
                dbg("challenge:", challenge)
                challengeReceived += 1
            default:
                dbg("unhandled event:", event)
            }
        }

        if let expectRedirect = expectRedirect {
            XCTAssertEqual(expectRedirect, redirectReceived, "expected to receive a redirect for: \(url.absoluteString)")
        }

//        if let expectChallenge = expectChallenge {
            //XCTAssertEqual(expectChallenge, challengeReceived, "expected to receive a challenge: \(url.absoluteString)")
//        }
    }

    func testTemplating() throws {
        XCTAssertEqual("XXX", "XXX".replacing(variables: [:]))
        XCTAssertEqual("Abc XXX 123", "Abc #(var) 123".replacing(variables: ["var": "XXX"]))
        XCTAssertEqual("result", "#(v3#(v2#(v1)))".replacing(variables: ["v1": "P", "v2P": "Q", "v3Q": "result"]))
    }

    func XXXtestReplaceRegex() throws {
        do {
            let exp = try NSRegularExpression(pattern: #"^#+ (?<text>.*)$"#, options: [.anchorsMatchLines])
            XCTAssertEqual("123", "# ABC".replacing(expression: exp, captureGroups: ["text"], replacing: { paramName, paramValue in
                paramName == "text" && paramValue == "ABC" ? "123" : nil
            }))
        }

        do {
            let exp = try NSRegularExpression(pattern: #"\[(?<title>.*)\]\((?<url>.*)\)"#)
            let demo = "[TITLE](URL)"
            // not working; need to re-think multiple capture group handling
            XCTAssertEqual("", demo.replacing(expression: exp, captureGroups: ["title", "url"], replacing: { paramName, paramValue in
                paramName == "url" ? "https://whatever.com" : paramName == "title" ? "some title" : nil
            }))
        }
    }

    func testIndexedCollection() {
        struct Value {
            let name: String
            let value: Int
        }

        var array = IndexedCollection(indexKeyPath: \Value.name)
        array.append(Value(name: "a", value: 0))
        array.append(Value(name: "b", value: 1))
        XCTAssertEqual(array.map(\.name), ["a", "b"])

        array.append(Value(name: "a", value: 2))
        XCTAssertEqual(array.map(\.name), ["b", "a"])
        XCTAssertEqual(array.map(\.value), [1, 2])

        array.append(Value(name: "c", value: 3))
        array.append(Value(name: "b", value: 4))
        array.append(Value(name: "d", value: 5))

        XCTAssertEqual(array.map(\.name), ["a", "c", "b", "d"])
        XCTAssertEqual(array.map(\.value), [2, 3, 4, 5])

        array.removeLast()
        XCTAssertEqual(array.map(\.name), ["a", "c", "b"])

        array.remove(at: 1)
        XCTAssertEqual(array.map(\.name), ["a", "b"])
        XCTAssertEqual(array.map(\.value), [2, 4])

        array.swapAt(0, 1)
        XCTAssertEqual(array.map(\.name), ["b", "a"])
        XCTAssertEqual(array.map(\.value), [4, 2])

        XCTAssertEqual(2, array.count)
        XCTAssertFalse(array.isEmpty)

        array.removeAll()

        XCTAssertTrue(array.isEmpty)
        XCTAssertEqual(0, array.count)
    }

    /// Tests the formatting of `ISO8601Format`, which is absent on Linux and so it implemented via a formatter.
    func testISO8601Format() {
        XCTAssertEqual("1970-01-01T00:00:00Z", Date(timeIntervalSince1970: 0).ISO8601Format())
        XCTAssertEqual("2001-01-01T00:00:00Z", Date(timeIntervalSinceReferenceDate: 0).ISO8601Format())
        XCTAssertEqual("4001-01-01T00:00:00Z", Date.distantFuture.ISO8601Format())

        XCTAssertEqual(-62135769600.0, Date.distantPast.timeIntervalSince1970)
        XCTAssertEqual("0001-01-01T00:00:00Z", Date.distantPast.ISO8601Format())
    }

    #if !os(Linux) && !os(Android) && !os(Windows)
    func testDispatchSource() async throws {
//        let url = URL(fileOrScheme: "~/Library/Mobile Documents/com~apple~CloudDocs/testDispatchSource.txt")
        //        let url = URL(fileOrScheme: "~/Desktop/testDispatchSource.txt")
        let url = URL(fileURLWithPath: UUID().uuidString, isDirectory: false, relativeTo: .tmpdir)
        try "ABC".write(to: url, atomically: true, encoding: .utf8)
        guard FileManager.default.fileExists(atPath: url.path) == true else {
            return XCTFail("no local file for \(url.path)")
        }

        var changes = 0
        let obs = FileSystemObserver(URL: url) {
            dbg("file change: \(url.path)")
            changes += 1
        }
        XCTAssertEqual(changes, 0)
        try await Task.sleep(interval: 0.1)
        dbg("writing to URL")
        try "XYZ".write(to: url, atomically: true, encoding: .utf8)
        try await Task.sleep(interval: 0.1)
        XCTAssertEqual(changes, 1)
        let _ = obs // need to retain
    }
    #endif
}

extension String {
    public func replacing(expression: NSRegularExpression, options: NSRegularExpression.MatchingOptions = [], captureGroups: [String], replacing: (_ captureGroupName: String, _ captureGroupValue: String) throws -> String?) rethrows -> String {
        var str = self
        for match in expression.matches(in: self, options: options, range: self.span).reversed() {
            for valueName in captureGroups {
                let textRange = match.range(withName: valueName)
                if textRange.location == NSNotFound {
                    continue
                }
                let existingValue = (self as NSString).substring(with: textRange)

                //dbg("replacing header range:", match.range, " with bold text:", text)
                if let newValue = try replacing(valueName, existingValue) {
                    str = (str as NSString).replacingCharacters(in: match.range, with: newValue)
                }
            }
        }
        return str
    }
}

