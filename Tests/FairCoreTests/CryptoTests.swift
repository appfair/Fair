import Swift
import XCTest
import FairCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class CryptoTests: XCTestCase {
    func testSeededRandom() throws {
        do {
            var rng = SeededRandomNumberGenerator(seed: [0])
            XCTAssertEqual(87, Int.random(in: 0...100, using: &rng))
        }

        do {
            var rng = SeededRandomNumberGenerator(seed: [1])
            XCTAssertEqual(2, Int.random(in: 0...100, using: &rng))
        }

        do {
            var rng = SeededRandomNumberGenerator(seed: [2])
            XCTAssertEqual(64, Int.random(in: 0...100, using: &rng))
        }

        do {
            let uuid = try XCTUnwrap(UUID(uuidString: "A2735FD6-9AA2-4D4C-A38C-204032777FB0"))
            var rng = SeededRandomNumberGenerator(uuids: uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid)
            XCTAssertEqual(59, Int.random(in: 0...100, using: &rng))
            XCTAssertEqual(3, Int.random(in: 0...100, using: &rng))
            XCTAssertEqual(53, Int.random(in: 0...100, using: &rng))
            XCTAssertEqual(44, Int.random(in: 0...100, using: &rng))
            XCTAssertEqual(7, Int.random(in: 0...100, using: &rng))
        }

        do {
            // ensure that two randomly-seeded generators generate distinct elements
            var rngA = SeededRandomNumberGenerator()
            var rngB = SeededRandomNumberGenerator()
            for _ in 0...999 {
                XCTAssertNotEqual(Int64.random(in: .min...(.max), using: &rngA), Int64.random(in: .min...(.max), using: &rngB))
            }
        }

        XCTAssertEqual([58, 109, 151], UInt8.randomSequence(seed: [0]).prefix(3).array())
        XCTAssertEqual([58, 109, 151], UInt8.randomSequence(seed: [0, 0]).prefix(3).array())
        XCTAssertEqual([58, 109, 151], UInt8.randomSequence(seed: Array(repeating: 0, count: 256)).prefix(3).array())

        XCTAssertEqual([41, 131, 124], UInt8.randomSequence(seed: [1]).prefix(3).array())
        XCTAssertEqual([86, 193, 50], UInt8.randomSequence(seed: [1, 2]).prefix(3).array())
        XCTAssertEqual([180, 176, 90], UInt8.randomSequence(seed: [1, 2, 3]).prefix(3).array())
        XCTAssertEqual([223, 104, 112], UInt8.randomSequence(seed: [1, 2, 3, 0]).prefix(3).array())
        XCTAssertEqual([77, 149, 52], UInt8.randomSequence(seed: [1, 2, 3, 4]).prefix(3).array())

        XCTAssertEqual([251, 161, 11], UInt8.randomSequence(seed: [1, 2, 3, 9, 99]).prefix(3).array())
        XCTAssertEqual([14, 113, 168], UInt8.randomSequence(seed: [1, 2, 3, 9, 99, 0]).prefix(3).array())
    }

    private static func randomData(count: Int) -> Data {
        Data((1...count).map({ _ in UInt8.random(in: (.min)...(.max)) }))
    }

    func testSHAHash() throws {
        // echo -n abc | shasum -a 256 hash.txt
        XCTAssertEqual("edeaaff3f1774ad2888673770c6d64097e391bc362d7d6fb34982ddf0efd18cb", "abc\n".utf8Data.sha256().hex())
    }

    /// Checks that the SHA1 hex from random data matches between the internal implementation and the CommonCrypto one
    func testSHA1Implementation() {
        DispatchQueue.concurrentPerform(iterations: 10) { _ in
            let data = Self.randomData(count: Int.random(in: 1...10000))
            let sha1a = data.sha1()
            let sha1b = data.sha1Uncommon()
            XCTAssertEqual(sha1a.hex(), sha1b.hex())
        }
    }

    /// Checks that the SHA256 hex from random data matches between the internal implementation and the CommonCrypto one
    func testSHA256Implementation() {
        DispatchQueue.concurrentPerform(iterations: 10) { _ in
            let data = Self.randomData(count: Int.random(in: 1...10000))
            let sha256a = data.sha256()
            let sha256b = data.sha256Uncommon()
            XCTAssertEqual(sha256a.hex(), sha256b.hex())
        }
    }

    /// Checks that the HMAC hex from random data matches between the internal implementation and the CommonCrypto one
    func testHMACSHA1Implementation() {
        DispatchQueue.concurrentPerform(iterations: 10) { _ in
            let data = Self.randomData(count: Int.random(in: 1...100_000))
            let kdata = Self.randomData(count: Int.random(in: 1...1_000))
            let hmac1 = data.hmacSHA(key: kdata, hash: .sha1)
            let hmac2 = data.hmacSHAUncommon(key: kdata, hash: .sha1)
            XCTAssertEqual(hmac1.hex(), hmac2.hex())
        }
    }

    /// Checks that the HMAC hex from random data matches between the internal implementation and the CommonCrypto one
    func testHMACSHA256Implementation() async {
        DispatchQueue.concurrentPerform(iterations: 10) { _ in
            let data = Self.randomData(count: Int.random(in: 1...100_000))
            let kdata = Self.randomData(count: Int.random(in: 1...1_000))
            let hmac1 = data.hmacSHA(key: kdata, hash: .sha256)
            let hmac2 = data.hmacSHAUncommon(key: kdata, hash: .sha256)
            XCTAssertEqual(hmac1.hex(), hmac2.hex())
        }
    }

    /// https://en.wikipedia.org/wiki/HMAC#Examples
    func testHMACSSHA1() {
        let msg = "The quick brown fox jumps over the lazy dog"
        let key = "key"
        let sha1 = msg.utf8Data.hmacSHA(key: key.utf8Data, hash: .sha1)
        XCTAssertEqual("3nybhbi3iqa8ino29wqQcBydtNk=", sha1.base64EncodedString())
    }

    func testHMACCompat() throws {
        // echo -n "value-to-digest" | openssl dgst -sha256 -hmac "secret-key-here" -binary | openssl enc -base64 -A
        // G73zFnFYggHRpmwuRFPgch6ctqEfyhZu33j5PQWYm+4=

        let msg = "value-to-digest"
        let key = "secret-key-here"
        let sha1 = msg.utf8Data.hmacSHA(key: key.utf8Data, hash: .sha256)
        XCTAssertEqual("G73zFnFYggHRpmwuRFPgch6ctqEfyhZu33j5PQWYm+4=", sha1.base64EncodedString())

    }

    /// https://jwt.io/introduction/
    /// https://en.wikipedia.org/wiki/JSON_Web_Token#Structure
    func testHMACSSHA256JWT() throws {
        struct JWTHeader : Encodable {
            var alg: String
            var typ: String
        }

        struct JWTPayload : Encodable {
            var sub: String
            var name: String
            var iat: Int
        }

        // note that field ordering matters, since the serialized JSON is signed
        let header = try JWTHeader(alg: "HS256", typ: "JWT").toJSON(outputFormatting: [.sortedKeys, .withoutEscapingSlashes])
        let payload = try JWTPayload(sub: "1234567890", name: "John Doe", iat: 1516239022).toJSON(outputFormatting: [.sortedKeys, .withoutEscapingSlashes])

        func encode(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "+", with: "-")
                .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        }

        let message = encode(header) + "." + encode(payload)

        let key = "secretkey" // verify at https://jwt.io/#debugger-io

        let signature = message.utf8Data.hmacSHA(key: key.utf8Data, hash: .sha256)

        let jwt = message + "." + encode(signature)

        XCTAssertEqual(jwt, "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE1MTYyMzkwMjIsIm5hbWUiOiJKb2huIERvZSIsInN1YiI6IjEyMzQ1Njc4OTAifQ.bKB04O-OWqZhSxdzOhf2RdM_5nb-fWZgpkKpzoa35ks")
    }

    func testJSONSignable() throws {
        struct SigDemo : Codable, JSONSignable {
            var name: String
            var date: Date
            var valid: Bool
            var signatureData: Data?
        }

        let key = "This is my key of arbitrary length."

        let referenceDate = Date(timeIntervalSinceReferenceDate: 1234)
        var ob = SigDemo(name: "Marc", date: referenceDate, valid: true)
        try ob.embedSignature(key: key.utf8Data)
        XCTAssertEqual("rLHGHKe3VGoI3iP5vEg0ytPwaouSFdMq+xl1MYMKsoc=", ob.signatureData?.base64EncodedString())

        try ob.authenticateSignature(key: key.utf8Data)

        ob.date = Date()
        XCTAssertThrowsError(try ob.authenticateSignature(key: key.utf8Data), "altered payload should invalidate signature")

        ob.date = referenceDate
        try ob.authenticateSignature(key: key.utf8Data)


        let key2 = "But now my key is wrong!"
        XCTAssertThrowsError(try ob.authenticateSignature(key: key2.utf8Data), "bad key should not have authenticated the signature")

        // make a new key and re-embed the signature
        try ob.embedSignature(key: key2.utf8Data)
        XCTAssertEqual("90e00sczi/6eraYMF4NXZEOq9QGyFzni5q8O4SGH3b0=", ob.signatureData?.base64EncodedString())

    }

    /// Tests [3.2.3. Sorting of Object Properties](https://tools.ietf.org/id/draft-rundgren-json-canonicalization-scheme-05.html#json.sorting.properties)
    ///
    /// TODO: cross-reference with spec: https://wiki.laptop.org/go/Canonical_JSON
    func testJSONCanonicalForm() throws {
        // check the JSON canonical form
        let source = """
        {
          "numbers": [333333333.33333329, 1E30, 4.50,
                      2e-3, 0.000000000000000000000000001],
          "string": "\\u20ac$\\u000F\\u000aA'\\u0042\\u0022\\u005c\\\\\\"\\/",
          "literals": [null, true, false]
        }
        """

        let expectedResult = #"{"literals":[null,true,false],"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27],"string":"€$\u000f\nA'B\"\\\\\"/"}"#

        struct ExampleObject : Codable {
            let numbers: [Double]
            let string: String
            let literals: [Bool?]
        }

        let ob = try JSONDecoder().decode(ExampleObject.self, from: source.utf8Data)
        let json = try ob.canonicalJSON
        var correctedJSON = json.replacingOccurrences(of: "1.0000000000000002e-27", with: "1e-27") // rounding
        correctedJSON = correctedJSON.replacingOccurrences(of: "333333333.33333331,", with: "333333333.3333333,") // rounding

        XCTAssertEqual(expectedResult, correctedJSON)

        func checkCanonical(id: String, _ jsonString: String, line: UInt = #line) throws {
            let json = try JSON.parse(jsonString.utf8Data)
            let canon = try json.canonicalJSON
            XCTAssertEqual(jsonString, canon, line: line)
        }

        // from https://github.com/gibson042/canonicaljson-spec

        // try checkCanonical(id: "example", #"{"-0":0,"-1":-1,"0.1":1.0E-1,"1":1,"10.1":1.01E1,"emoji":"😃","escape":"\u001B","lone surrogate":"\uDEAD","whitespace":" \t\n\r"}"#)

        try checkCanonical(id: "example", #"{}"#)

//        try checkCanonical(id: "3.object-ordering", #"{"":"empty","\u0000":"U+0000 NULL","\u0001":"U+0001 START OF HEADING","\t":"U+0009 CHARACTER TABULATION","\u001F":"U+001F INFORMATION SEPARATOR ONE"," ":"U+0020 SPACE","\"":"U+0022 QUOTATION MARK","A":"U+0041 LATIN CAPITAL LETTER A","Å":"composition—U+0041 LATIN CAPITAL LETTER A + U+030A COMBINING RING ABOVE","\\":"U+005C REVERSE SOLIDUS","deep":["...","filler","...",{"":"empty","\u0000":"U+0000 NULL","\u0001":"U+0001 START OF HEADING","\t":"U+0009 CHARACTER TABULATION","\u001F":"U+001F INFORMATION SEPARATOR ONE"," ":"U+0020 SPACE","\"":"U+0022 QUOTATION MARK","A":"U+0041 LATIN CAPITAL LETTER A","Å":"composition—U+0041 LATIN CAPITAL LETTER A + U+030A COMBINING RING ABOVE","\\":"U+005C REVERSE SOLIDUS","deep":"…","é̂":"composition—U+0065 LATIN SMALL LETTER E + U+0301 COMBINING ACUTE ACCENT + U+0302 COMBINING CIRCUMFLEX ACCENT","ế":"composition—U+0065 LATIN SMALL LETTER E + U+0302 COMBINING CIRCUMFLEX ACCENT + U+0301 COMBINING ACUTE ACCENT","":"U+007F DELETE","":"U+0080 PADDING CHARACTER","Å":"U+00C5 LATIN CAPITAL LETTER A WITH RING ABOVE","ế":"composition—U+00EA LATIN SMALL LETTER E WITH CIRCUMFLEX + U+0301 COMBINING ACUTE ACCENT","́":"U+0301 COMBINING ACUTE ACCENT","̂":"U+0302 COMBINING CIRCUMFLEX ACCENT","̇":"U+0307 COMBINING DOT ABOVE","̊":"U+030A COMBINING RING ABOVE","ế":"U+1EBF LATIN SMALL LETTER E WITH CIRCUMFLEX AND ACUTE","Å":"U+212B ANGSTROM SIGN","←":"U+2190 LEFTWARDS ARROW","\uD800":"U+D800 lowest high surrogate","\uD800\uDBFF":"two high surrogates","\uDBFF":"U+DBFF highest high surrogate","\uDC00":"U+DC00 lowest low surrogate","\uDC00\uDBFF":"surrogates—low + high","\uDC00\uDFFF":"two low surrogates","\uDFFF":"U+DFFF highest high surrogate","ﬁ":"U+FB01 LATIN SMALL LIGATURE FI","�":"U+FFFD REPLACEMENT CHARACTER","𐀀":"U+10000 LINEAR B SYLLABLE B008 A","𝌆":"surrogate pair—U+1D306 TETRAGRAM FOR CENTRE"}],"é̂":"composition—U+0065 LATIN SMALL LETTER E + U+0301 COMBINING ACUTE ACCENT + U+0302 COMBINING CIRCUMFLEX ACCENT","ế":"composition—U+0065 LATIN SMALL LETTER E + U+0302 COMBINING CIRCUMFLEX ACCENT + U+0301 COMBINING ACUTE ACCENT","":"U+007F DELETE","":"U+0080 PADDING CHARACTER","Å":"U+00C5 LATIN CAPITAL LETTER A WITH RING ABOVE","ế":"composition—U+00EA LATIN SMALL LETTER E WITH CIRCUMFLEX + U+0301 COMBINING ACUTE ACCENT","́":"U+0301 COMBINING ACUTE ACCENT","̂":"U+0302 COMBINING CIRCUMFLEX ACCENT","̇":"U+0307 COMBINING DOT ABOVE","̊":"U+030A COMBINING RING ABOVE","ế":"U+1EBF LATIN SMALL LETTER E WITH CIRCUMFLEX AND ACUTE","Å":"U+212B ANGSTROM SIGN","←":"U+2190 LEFTWARDS ARROW","\uD800":"U+D800 lowest high surrogate","\uD800\uDBFF":"two high surrogates","\uDBFF":"U+DBFF highest high surrogate","\uDC00":"U+DC00 lowest low surrogate","\uDC00\uDBFF":"surrogates—low + high","\uDC00\uDFFF":"two low surrogates","\uDFFF":"U+DFFF highest high surrogate","ﬁ":"U+FB01 LATIN SMALL LIGATURE FI","�":"U+FFFD REPLACEMENT CHARACTER","𐀀":"U+10000 LINEAR B SYLLABLE B008 A","𝌆":"surrogate pair—U+1D306 TETRAGRAM FOR CENTRE"}"#)

        try checkCanonical(id: "1.no-negative-zero", #"["for sig in 0 0.0 0.00; do for e in '' e E; do [ x$e = x ] && echo $sig, && continue; for e_sign in '' '-' '+'; do for exp in 0 00 1 01; do echo $sig$e$e_sign$exp,; done; done; done; done",0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]"#)

//        try checkCanonical(id: "2.no-decimal-point", #"[0,0,4,4,42,42,42,42,8,8,179769313486231590772930519078902473361797697894230657273430081157732675805500963132708477322407536021120113879871393357658789768814416622492847430639474124377767893424865485276302219601246094119453082952085005768838150682342462881473913110540827237163350510684586298239947245938479716304835356329624224137217,0,0,-4,-4,-42,-42,-42,-42,-8,-8,-179769313486231590772930519078902473361797697894230657273430081157732675805500963132708477322407536021120113879871393357658789768814416622492847430639474124377767893424865485276302219601246094119453082952085005768838150682342462881473913110540827237163350510684586298239947245938479716304835356329624224137217]"#)

//        try checkCanonical(id: "3.no-exponent", #"["2^8 +/- 1",255,256,257,"2^16 +/- 1",65535,65536,65537,"2^32 +/- 1",4294967295,4294967296,4294967297,"2^53 +/- 1",9007199254740991,9007199254740992,9007199254740993,"2^64 +/- 1",18446744073709551615,18446744073709551616,18446744073709551617,"2^128 +/- 1",340282366920938463463374607431768211455,340282366920938463463374607431768211456,340282366920938463463374607431768211457,"2^256 +/- 1",115792089237316195423570985008687907853269984665640564039457584007913129639935,115792089237316195423570985008687907853269984665640564039457584007913129639936,115792089237316195423570985008687907853269984665640564039457584007913129639937,"10^100 +/- 1",9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999,10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001,"2^1024 +/- 1",179769313486231590772930519078902473361797697894230657273430081157732675805500963132708477322407536021120113879871393357658789768814416622492847430639474124377767893424865485276302219601246094119453082952085005768838150682342462881473913110540827237163350510684586298239947245938479716304835356329624224137215,179769313486231590772930519078902473361797697894230657273430081157732675805500963132708477322407536021120113879871393357658789768814416622492847430639474124377767893424865485276302219601246094119453082952085005768838150682342462881473913110540827237163350510684586298239947245938479716304835356329624224137216,179769313486231590772930519078902473361797697894230657273430081157732675805500963132708477322407536021120113879871393357658789768814416622492847430639474124377767893424865485276302219601246094119453082952085005768838150682342462881473913110540827237163350510684586298239947245938479716304835356329624224137217,"-2^8 +/- 1",-255,-256,-257,"-2^16 +/- 1",-65535,-65536,-65537,"-2^32 +/- 1",-4294967295,-4294967296,-4294967297,"-2^53 +/- 1",-9007199254740991,-9007199254740992,-9007199254740993,"-2^64 +/- 1",-18446744073709551615,-18446744073709551616,-18446744073709551617,"-2^128 +/- 1",-340282366920938463463374607431768211455,-340282366920938463463374607431768211456,-340282366920938463463374607431768211457,"-2^256 +/- 1",-115792089237316195423570985008687907853269984665640564039457584007913129639935,-115792089237316195423570985008687907853269984665640564039457584007913129639936,-115792089237316195423570985008687907853269984665640564039457584007913129639937,"-10^100 +/- 1",-9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999,-10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,-10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001,"-2^1024 +/- 1",-179769313486231590772930519078902473361797697894230657273430081157732675805500963132708477322407536021120113879871393357658789768814416622492847430639474124377767893424865485276302219601246094119453082952085005768838150682342462881473913110540827237163350510684586298239947245938479716304835356329624224137215,-179769313486231590772930519078902473361797697894230657273430081157732675805500963132708477322407536021120113879871393357658789768814416622492847430639474124377767893424865485276302219601246094119453082952085005768838150682342462881473913110540827237163350510684586298239947245938479716304835356329624224137216,-179769313486231590772930519078902473361797697894230657273430081157732675805500963132708477322407536021120113879871393357658789768814416622492847430639474124377767893424865485276302219601246094119453082952085005768838150682342462881473913110540827237163350510684586298239947245938479716304835356329624224137217]"#)

//        try checkCanonical(id: "1.single-digit-nonzero-significand-integer", #"[3.14E0,3.14E0,3.14E0,3.14E0,1.1E-2,1.79769313486231590772930519078902473361797697894230657273430081157732675805500963132708477322407536021120113879871393357658789768814416622492847430639474124377767893424865485276302219601246094119453082952085005768838150682342462881473913110540827237163350510684586298239947245938479716304835356329624224137217E307,1.79769313486231590772930519078902473361797697894230657273430081157732675805500963132708477322407536021120113879871393357658789768814416622492847430639474124377767893424865485276302219601246094119453082952085005768838150682342462881473913110540827237163350510684586298239947245938479716304835356329624224137217E307,-3.14E0,-3.14E0,-3.14E0,-3.14E0,-1.1E-2,-1.79769313486231590772930519078902473361797697894230657273430081157732675805500963132708477322407536021120113879871393357658789768814416622492847430639474124377767893424865485276302219601246094119453082952085005768838150682342462881473913110540827237163350510684586298239947245938479716304835356329624224137217E307,-1.79769313486231590772930519078902473361797697894230657273430081157732675805500963132708477322407536021120113879871393357658789768814416622492847430639474124377767893424865485276302219601246094119453082952085005768838150682342462881473913110540827237163350510684586298239947245938479716304835356329624224137217E307]"#)

//        try checkCanonical(id: "2.nonempty-significand-fraction", #"[1.0E-1000,9.900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000099E-100,-1.0E-1000,-9.900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000099E-100]"#)

//        try checkCanonical(id: "4.capital-E", #"[1.0E-2,1.0E-1,1.0E-100,1.0E-98,1.0E-100,-1.0E-2,-1.0E-1,-1.0E-100,-1.0E-98,-1.0E-100]"#)

//        try checkCanonical(id: "5.no-exponent-plus", #"[5.5E0,5.5000005E5,-5.5E0,-5.5000005E5]"#)

//        try checkCanonical(id: "6.no-exponent-leading-zeroes", #"[5.6E0,5.60000006E6,5.6E-1000,-5.6E0,-5.60000006E6,-5.6E-1000]"#)

        // try checkCanonical(id: "example", #"{}"#)
    }

    /// Verifies example case in ``JSONSignable`` header.
    func testJSONSignableCompat() throws {
        struct Inst : Encodable, SigningContainer {
            let b: String
            let d: Bool?
            let a: Int
            let e: [E]
            struct E: Encodable {
                let f: Double?
                let g: String?
            }
        }

        // echo '{ "b": "C", "d": false, "a":2, "e": [{ "f": 1.2 }] }' | jq -cjS | openssl dgst -sha256 -hmac "secret-key-here" -binary | openssl enc -base64 -A
        let inst = Inst(b: "C", d: false, a: 2, e: [Inst.E(f: 1.2, g: nil)])

        XCTAssertEqual(try inst.debugJSON, #"{"a":2,"b":"C","d":false,"e":[{"f":1.2}]}"#)

        /// the normalized data to be signed is: `{"a":2,"b":"C","d":false,"e":[{"f":1.2}]}`
        XCTAssertEqual("8JKugJUa41Uaf+lG1q6ndFpqGPxTPkLU9V17kkRBXB4=", try inst.sign(key: "secret-key-here".utf8Data).base64EncodedString())
    }
}
