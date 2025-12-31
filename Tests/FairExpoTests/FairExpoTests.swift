// Copyright (c) 2022 - 2026 The App Fair Project <info@appfair.org>
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-or-later
import Swift
import XCTest
import FairCore
import FairExpo
import Yams

public class FairExpoTests : XCTestCase {

    func testAppCatalogIndex() async throws {
        /// https://appfair.net/appfair-apps.json
        let (data, _) = try await URLSession.shared.fetch(request: URLRequest(url: AppCatalogIndex.appfairCatalogURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData))
        let index = try JSONDecoder().decode(AppCatalogIndex.self, from: data)
        XCTAssertGreaterThan(index.apps.count, 0)

        XCTAssertEqual("The App Fair Project", index.catalogs.fdroid?.name["en-US"])
        XCTAssertEqual("The App Fair Project", index.catalogs.altstore?.name)

        XCTAssertEqual("https://api.appfair.net/fdroid/repo/", index.catalogs.fdroid?.address)
        XCTAssertEqual("https://appfair.org", index.catalogs.altstore?.website)

        XCTAssertEqual("/icons/appfair-icon.png", index.catalogs.fdroid?.icon["en-US"]?.name)
        XCTAssertEqual("https://appfair.net/appfair-icon.png", index.catalogs.altstore?.iconURL)
    }
    
    /// Parses the given type from YAML or JSON.
    ///
    /// - Parameters:
    ///   - verify: whether to verify the completeness of the type by checking the round-tripped fidelity
    ///   - yaml: a closure creating the YAML to check
    /// - Returns: the decoded type
    func deserialize<T: Codable>(_ type: ParseType, verify: Bool = true, file: StaticString = #file, line: UInt = #line, _ contents: () throws -> String) throws -> T {
        let stringContents = try contents()
        let data = stringContents.utf8Data
        switch type {
        case .yaml:
            let decoder = YAMLDecoder()
            //decoder.options = YAMLDecoder.Options(encoding: .utf8, aliasDereferencingStrategy: nil)
            let decoded = try decoder.decode(T.self, from: data)
            if verify {
                let encoder = YAMLEncoder()
                encoder.options.allowUnicode = true
                let decodedYAML = try encoder.encode(decoded)
                XCTAssertEqual(stringContents, decodedYAML, "round-trip of encoded YAML type \(T.self) failed", file: file, line: line)
            }
            return decoded
        case .json:
            let json = try JSON.parse(data)
            let decoded = try T(json: json, options: JSONDecodingOptions(dateDecodingStrategy: .iso8601))
            let decodedJSON = try decoded.json(options: JSONEncodingOptions(dateEncodingStrategy: .iso8601))
            if verify {
                if json != decodedJSON {
                    try XCTAssertEqual(json.prettyJSON, decodedJSON.prettyJSON, "round-trip of encoded type \(T.self) failed", file: file, line: line)
                }
            }
            return decoded
        }
    }

    enum ParseType {
        case yaml, json
    }

    func testAppcatMiniscule() async throws {
        let yaml = """
            appcat-version: 1
            title:
              en-US: App Fair
            description:
              en-US: A catalog of apps
            icon:
              en-US:
                location: icons/appfair_icon.png
                size: 123456
                hash: SHA256
                width: 512
                height: 512
            apps: []
            
            """
        let appcat: Appcat = try deserialize(.yaml) { yaml }
        XCTAssertEqual(1, appcat.appcatVersion)

        let json = #"{"appcat-version":1,"apps":[],"description":{"en-US":"A catalog of apps"},"icon":{"en-US":{"hash":"SHA256","height":512,"location":"icons/appfair_icon.png","size":123456,"width":512}},"title":{"en-US":"App Fair"}}"#

        let appcatJSON: Appcat = try deserialize(.json, { json })
        XCTAssertEqual(appcat, appcatJSON)
    }

    func testAppcatMinimal() async throws {
        let appcat: Appcat = try deserialize(.yaml) { """
            appcat-version: 1
            title:
              en-US: App Fair
            description:
              en-US: A catalog of apps
            icon:
              en-US:
                location: icons/appfair_icon.png
                size: 123456
                hash: SHA256
                width: 512
                height: 512
            apps:
            - id: Tune-Out
              title:
                en-US: Tune Out
              summary:
                en-US: An internet radio player
              description:
                en-US: An internet radio player…
              icon:
                en-US:
                  location: icon.png
                  size: 123456
                  hash: SHA256
                  width: 512
                  height: 512
              platforms:
                ios:
                  id: org.appfair.app.Tune-Out
                  channels:
                    appstore:
                      version: 1.1.1
                      date: 2025-12-01T12:00:00Z
                      identifier: '987654321'
                      title:
                        en-US: Tune Out for iOS
                      keywords:
                        en-US:
                        - ios-key1
                        - ios-key2
                  profiles:
                    iphone:
                      screenshots:
                        en-US:
                        - location: screens/screenshot_iphone1.png
                          size: 123456
                          hash: SHA256
                          width: 800
                          height: 600
                          caption: A screenshot
            
            """ }
        XCTAssertEqual(1, appcat.appcatVersion)
    }

    func testAppcatMid() async throws {
        let appcat: Appcat = try deserialize(.yaml) { """
            appcat-version: 1
            title:
              en-US: App Fair
            description:
              en-US: A catalog of apps
            icon:
              en-US:
                location: icons/appfair_icon.png
                size: 123456
                hash: SHA256
                width: 512
                height: 512
            apps: []
            
            """ }
        XCTAssertEqual(1, appcat.appcatVersion)
    }

    func testAppcatConversion() async throws {
        let appcat: Appcat = try deserialize(.yaml) { """
            appcat-version: 1
            default-locales:
            - en-US
            - fr-FR
            title:
              en-US: App Fair
              fr-FR: Le App Fair
            description:
              en-US: A catalog of apps
              fr-FR: Une cataloge de les apps
            icon:
              en-US:
                location: icons/appfair_icon.png
                size: 123456
                hash: SHA256
                width: 512
                height: 512
            tint: AABBCC
            url: https://demo.appfair.net/appcat.json
            apps:
            - id: Tune-Out
              created: 2023-01-01T12:00:00Z
              location: apps/Tune-Out/
              title:
                en-US: Tune Out
              summary:
                en-US: An internet radio player
                fr-FR: Une player de radio internet
              description:
                en-US: An internet radio player…
                fr-FR: Une player de radio internet…
              keywords:
                en-US:
                - key1
                - key2
                fr-FR:
                - cle1
                - cle2
              icon:
                en-US:
                  location: icon.png
                  size: 123456
                  hash: SHA256
                  width: 512
                  height: 512
              homepage: https://tune-out.app
              email: support@tune-out.app
              issues: https://github.com/Tune-Out/Tune-Out/issues
              license: GPL-3.0-only
              platforms:
                ios:
                  id: org.appfair.app.Tune-Out
                  summary:
                    fr-FR: Une player de radio internet pour iOS
                  minVersion: '17.0'
                  channels:
                    direct:
                      version: 1.1.2
                      date: 2026-01-01T12:00:00Z
                      artifact:
                        location: releases/download/1.1.2/TuneOut-release.ipa
                        size: 123456
                        hash: SHA256
                    appstore:
                      version: 1.1.1
                      date: 2025-12-01T12:00:00Z
                      identifier: '987654321'
                      categories:
                      - Music
                      - Entertainment
                      title:
                        en-US: Tune Out for iOS
                        fr-FR: Le Tune Out for iOS
                      keywords:
                        en-US:
                        - ios-key1
                        - ios-key2
                        fr-FR:
                        - ios-cle1
                        - ios-cle2
                    altstore:
                      version: 1.1.2
                      date: 2026-01-01T12:00:00Z
                      artifact:
                        location: releases/download/1.1.2/manifest.json
                        size: 123456
                        hash: SHA256
                      categories:
                      - entertainment
                      summary:
                        en-US: An internet radio player for AltStore
                      notes:
                        en-US: Bug fixes and performance improvements
                  profiles:
                    iphone:
                      screenshots:
                        en-US:
                        - location: screens/screenshot_iphone1.png
                          size: 123456
                          hash: SHA256
                          width: 800
                          height: 600
                          caption: A screenshot
                    ipad:
                      screenshots:
                        fr-FR:
                        - location: screens/screenshot_ipad1.png
                          size: 123456
                          hash: SHA256
                          width: 800
                          height: 1024
                          caption: Une screenshot
                    watch:
                      screenshots:
                        fr-FR:
                        - location: screens/screenshot_watch1.png
                          size: 123456
                          hash: SHA256
                          width: 400
                          height: 400
                          caption: Une screenshot Watch
                  permissions:
                  - key: NSContactsUsageDescription
                    reason:
                      en-US: This app needs to access contents
                  - key: com.apple.developer.contacts.notes
                    reason:
                      en-US: This app needs to access contacts (entitlement)
                android:
                  id: org.appfair.app.Tune_Out
                  minVersion: '28'
                  targetVersion: '35'
                  channels:
                    direct:
                      version: 1.1.2
                      build: 112
                      date: 2026-01-01T12:00:00Z
                      artifact:
                        location: releases/download/1.1.2/TuneOut-release.apk
                        size: 123456
                        hash: SHA256
                    playstore:
                      version: 1.1.1
                      build: 111
                      date: 2025-12-01T12:00:00Z
                      identifier: '987654321'
                      description:
                        en-US: This special Play Store description for the app…
                    fdroid:
                      version: 1.1.2
                      build: 112
                      date: 2026-01-01T12:00:00Z
                      artifact:
                        location: releases/download/1.1.2/TuneOut-fdroid.apk
                        size: 123456
                        hash: SHA256
                      description:
                        en-US: This special F-Droid description for the app…
                        ja-JA: このアプリの特別なF-Droid説明文…
                        ar: هذا الوصف الخاص بتطبيق F-Droid
                      metadata:
                        authorWebSite: https://mysite.org
                  profiles:
                    phone:
                      screenshots:
                        en-US:
                        - location: screens/screenshot_android_phone1_en.png
                          size: 123456
                          hash: SHA256
                          width: 800
                          height: 600
                          caption: A screenshot
                        - location: screens/screenshot_android_phone2_en.png
                          size: 123456
                          hash: SHA256
                          width: 800
                          height: 600
                          caption: Another screenshot
                        fr-FR:
                        - location: screens/screenshot_android_phone1_fr.png
                          size: 123456
                          hash: SHA256
                          width: 800
                          height: 600
                          caption: Une screenshot
                    tv:
                      screenshots:
                        en-US:
                        - location: screens/screenshot_android_tv1.png
                          size: 123456
                          hash: SHA256
                          width: 800
                          height: 1024
                  permissions:
                  - key: android.permission.WRITE_EXTERNAL_STORAGE
                    reason:
                      en-US: This app needs to write to external storage

            """ }

        XCTAssertEqual("App Fair", appcat.title["en-US"])
        XCTAssertEqual("Le App Fair", appcat.title["fr-FR"])

        let app = try XCTUnwrap(appcat.apps.first)
        XCTAssertEqual("Tune Out", app.title?["en-US"])
        XCTAssertEqual(nil, app.title?["fr-FR"])

        XCTAssertEqual("An internet radio player", app.summary?["en-US"])
        XCTAssertEqual("Une player de radio internet", app.summary?["fr-FR"])

        XCTAssertEqual(["ios", "android"], app.platforms.keys)
        XCTAssertEqual(["direct", "appstore", "altstore"], app.platforms["ios"]?.channels.keys)
        XCTAssertEqual(["iphone", "ipad", "watch"], app.platforms["ios"]?.profiles.keys)
        XCTAssertEqual(["direct", "playstore", "fdroid"], app.platforms["android"]?.channels.keys)
        XCTAssertEqual(["phone", "tv"], app.platforms["android"]?.profiles.keys)

        // test conversion to AltStore source
        let altstoreConverted = appcat.toAltstoreSource()
        let altstore: AltCatalog = try deserialize(.json) { """
        {
          "name" : "App Fair",
          "description" : "A catalog of apps",
          "iconURL" : "https://demo.appfair.net/icons/appfair_icon.png",
          "tintColor" : "AABBCC",
          "apps" : [
            {
              "bundleIdentifier" : "org.appfair.app.Tune-Out",
              "name" : "Tune Out",
              "category" : "entertainment",
              "subtitle" : "An internet radio player for AltStore",
              "localizedSubtitles" : {
                "en-US" : "An internet radio player for AltStore",
                "fr-FR" : "Une player de radio internet pour iOS"
              },
              "localizedDescription" : "An internet radio player…",
              "localizedDescriptions" : {
                "en-US" : "An internet radio player…",
                "fr-FR" : "Une player de radio internet…"
              },
              "iconURL" : "https://demo.appfair.net/apps/Tune-Out/icon.png",
              "appPermissions" : {
                "entitlements" : [
                  {
                      "name" : "com.apple.developer.contacts.notes"
                  }
                ],
                "privacy" : [
                  {
                    "name" : "NSContactsUsageDescription",
                    "usageDescription" : "This app needs to access contents"
                  }
                ]
              },
              "screenshots" : {
                "iphone" : [
                  {
                    "imageURL" : "https://demo.appfair.net/apps/Tune-Out/screens/screenshot_iphone1.png",
                    "height" : 600,
                    "width" : 800
                  }
                ],
                "ipad" : [
                  {
                    "imageURL" : "https://demo.appfair.net/apps/Tune-Out/screens/screenshot_ipad1.png",
                    "height" : 1024,
                    "width" : 800
                  }
                ],
                "watch" : [
                  {
                    "imageURL" : "https://demo.appfair.net/apps/Tune-Out/screens/screenshot_watch1.png",
                    "height" : 400,
                    "width" : 400
                  }
                ]
              },
              "versions" : [
                {
                  "version" : "1.1.2",
                  "date" : "2026-01-01T12:00:00Z",
                  "downloadURL" : "https://demo.appfair.net/apps/Tune-Out/releases/download/1.1.2/manifest.json",
                  "size" : 123456,
                  "minOSVersion" : "17.0",
                  "localizedDescription" : "Bug fixes and performance improvements",
                  "localizedDescriptions" : {
                    "en-US" : "Bug fixes and performance improvements"
                  }
                }
              ]
            }
          ]
        }
        """ }

        try XCTAssertEqual(altstoreConverted.prettyJSON, altstore.prettyJSON)


        // test conversion to F-Droid index
        let fdroidConverted = appcat.toFDroidIndex(repoURL: "https://appfair.net/f-droid/repo")

        let fdroid: FDroidIndex = try deserialize(.json) { """
        {
          "packages" : {
            "org.appfair.app.Tune_Out" : {
              "metadata" : {
                "added" : 1672574400000,
                "authorEmail" : "support@tune-out.app",
                "authorWebSite" : "https://mysite.org",
                "description" : {
                  "ar" : "هذا الوصف الخاص بتطبيق F-Droid",
                  "en-US" : "This special F-Droid description for the app…",
                  "fr-FR" : "Une player de radio internet…",
                  "ja-JA" : "このアプリの特別なF-Droid説明文…"
                },
                "icon" : {
                  "en-US" : {
                    "name" : "icon.png",
                    "sha256" : "SHA256",
                    "size" : 123456
                  }
                },
                "issueTracker" : "https://github.com/Tune-Out/Tune-Out/issues",
                "lastUpdated" : 0,
                "license" : "GPL-3.0-only",
                "name" : {
                  "en-US" : "Tune Out"
                },
                "screenshots" : {
                  "phone" : {
                    "en-US" : [
                      {
                        "name" : "screens/screenshot_android_phone1_en.png",
                        "sha256" : "SHA256",
                        "size" : 123456
                      },
                      {
                        "name" : "screens/screenshot_android_phone2_en.png",
                        "sha256" : "SHA256",
                        "size" : 123456
                      }
                    ],
                    "fr-FR" : [
                      {
                        "name" : "screens/screenshot_android_phone1_fr.png",
                        "sha256" : "SHA256",
                        "size" : 123456
                      }
                    ]
                  },
                  "tv" : {
                    "en-US" : [
                      {
                        "name" : "screens/screenshot_android_tv1.png",
                        "sha256" : "SHA256",
                        "size" : 123456
                      }
                    ]
                  }
                },
                "summary" : {
                  "en-US" : "An internet radio player",
                  "fr-FR" : "Une player de radio internet"
                },
                "webSite" : "https://tune-out.app"
              },
              "versions" : {
                "SHA256" : {
                  "added" : 1767268800000,
                  "file" : {
                    "name" : "releases/download/1.1.2/TuneOut-fdroid.apk",
                    "sha256" : "SHA256",
                    "size" : 123456
                  },
                  "manifest" : {
                    "usesPermission" : [
                      {
                        "name" : "android.permission.WRITE_EXTERNAL_STORAGE"
                      }
                    ],
                    "usesSdk" : {
                      "minSdkVersion" : 28,
                      "targetSdkVersion" : 35
                    },
                    "versionCode" : 112,
                    "versionName" : "1.1.2"
                  }
                }
              }
            }
          },
          "repo" : {
            "address" : "https://appfair.net/f-droid/repo",
            "icon" : {
              "en-US" : {
                "name" : "icons/appfair_icon.png",
                "sha256" : "SHA256",
                "size" : 123456
              }
            },
            "name" : {
              "en-US" : "App Fair",
              "fr-FR" : "Le App Fair"
            },
            "timestamp" : 0
          }
        }
        """ }
        try XCTAssertEqual(fdroidConverted.prettyJSON, fdroid.prettyJSON)
    }

    func testParseFDroidCatalogs() throws {
        let dir = ProcessInfo.processInfo.environment["FAIR_EXPO_TESTS_FDROID_INDEX_DIRS"] ?? "/opt/src/github/appfair/misc/fdroid/catalogs"

        if !FileManager.default.fileExists(atPath: dir) {
            throw XCTSkip("No local fdroid .json files for testing")
        }

        let allFiles = try FileManager.default.enumeratedURLs(of: URL(fileURLWithPath: dir))

        let paths = allFiles
            .filter({ $0.pathExtension == "json" })

        if paths.isEmpty {
            throw XCTSkip("No local marketplace .json files for testing")
        }

        for path in paths {
            print("parsing source at path: \(path.path)")
            do {
                let catalog: FDroidIndex = try deserialize(.json, verify: true) { try String(contentsOf: path) }
                print("successfully parsed: \(path.path): \(catalog.repo.name.values.first ?? "Unnamed") with \(catalog.packages?.count ?? 0) apps")
            } catch {
                XCTFail("error parsing \(path.path): \(error)")
            }
        }
    }

    func testParseAltSources() throws {
        // list obtained from https://cdn.altstore.io/file/altstore/altstore/marketplace-sources.json
        let dir = ProcessInfo.processInfo.environment["FAIR_EXPO_TESTS_ALTSTORE_SOURCES_DIR"] ?? "/opt/src/github/altstore/sources/marketplace-sources"

        if !FileManager.default.fileExists(atPath: dir) {
            throw XCTSkip("No local altsource .json files for testing")
        }

        let allFiles = try FileManager.default.enumeratedURLs(of: URL(fileURLWithPath: dir))

        let paths = allFiles
            .filter({ $0.pathExtension == "json" })
            .filter({ $0.lastPathComponent != "marketplace-sources.json" }) // the marketplace index

        if paths.isEmpty {
            throw XCTSkip("No local marketplace .json files for testing")
        }

        for path in paths {
            print("parsing source at path: \(path.path)")
            do {
                let catalog = try AltCatalog(fromJSON: Data(contentsOf: path))
                print("successfully parsed: \(path.path): \(catalog.name ?? "Unnamed") with \(catalog.apps.count) apps")
            } catch {
                XCTFail("error parsing \(path.path): \(error)")
            }
        }
    }

    func testEnvFile() throws {
        do {
            let env = try EnvFile(data: """
            """.utf8Data)
            XCTAssertEqual(nil, env["x"])
        }

        do {
            let env = try EnvFile(data: """
            x = y
            """.utf8Data)
            XCTAssertEqual("y", env["x"])
        }

        do {
            var env = try EnvFile(data: """
            // comment
            ABC = 123
            """.utf8Data)
            XCTAssertEqual("123", env["ABC"])
            XCTAssertEqual("""
            // comment
            ABC = 123
            """, env.contents)

            env["ABC"] = "qrs"
            XCTAssertEqual("""
            // comment
            ABC = qrs
            """, env.contents)

            env["ABCD"] = "XYZ"
            XCTAssertEqual("""
            // comment
            ABC = qrs
            ABCD = XYZ
            """, env.contents)

            env["ABC"] = nil
            XCTAssertEqual("""
            // comment
            ABCD = XYZ
            """, env.contents)

            env["ABCD"] = nil
            XCTAssertEqual("""
            // comment
            """, env.contents)
        }
    }
}
