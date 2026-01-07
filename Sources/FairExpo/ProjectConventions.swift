// Copyright (c) 2022 - 2026 The App Fair Project <info@appfair.org>
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import FairCore

/// The layout of a project
public protocol ProjectConvention {
    /// Examines the app at the given folder and creates an `Appcat.App` from the metadata therein
    func buildAppcatApp(in folder: URL) throws -> Appcat.App
}

/// The layout of a Skip project
public struct SkipProjectConvention: ProjectConvention {
    public let darwinFolder = "Darwin"
    public let androidFolder = "Android"

    public init() {
    }

    public func buildAppcatApp(in folder: URL) throws -> Appcat.App {
        let fm = FileManager.default
        let darwinPath = URL(fileURLWithPath: darwinFolder, relativeTo: folder)
        let androidPath = URL(fileURLWithPath: androidFolder, relativeTo: folder)

        let envFileData = try Data(contentsOf: folder.appendingPathComponent("Skip.env", isDirectory: false))
        let envFile = try EnvFile(data: envFileData)

        var app = Appcat.App(id: "", icon: [:], platforms: [:])

        func env(key: String) throws -> String {
            guard let value = envFile[key] else {
                throw AppError("Could not load \(key) from Skip.env")
            }
            return value
        }

        //msg(.info, "env file contents: \(envFile.contents)")
        let productName = try env(key: "PRODUCT_NAME")
        let marketingVersion = try env(key: "MARKETING_VERSION")
        let projectVersion = try env(key: "CURRENT_PROJECT_VERSION")
        let bundleIdentifier = try env(key: "PRODUCT_BUNDLE_IDENTIFIER")
        //let packageName = try env(key: "ANDROID_PACKAGE_NAME")

        // The last part of the bundle ID usually, but not always, is the app token (e.g., org.appfair.app.SkipNotes vs. Skip-Notes)

        let releaseDate = Calendar.current.startOfDay(for: Date()).ISO8601Format() // FIXME: use the date of the release

        let darwinFastlaneBase = darwinPath.appendingPathComponent("fastlane", isDirectory: true)
        let darwinFastlaneMetadataRoot = darwinFastlaneBase.appendingPathComponent("metadata", isDirectory: true)
        let androidFastlaneRoot = androidPath.appendingPathComponent("fastlane/metadata/android", isDirectory: true)

        func components(in path: URL, dir: Bool) throws -> [URL] {
            // we map the URL to appendingPathComponent so we can preserve the relativePath of the root
            try fm.contentsOfDirectory(at: path, includingPropertiesForKeys: [.isDirectoryKey])
                .filter({ $0.pathIsDirectory == dir })
                .map({ path.appendingPathComponent($0.lastPathComponent, isDirectory: dir) })
        }

        func dirs(in path: URL) throws -> [URL] {
            try components(in: path, dir: true)
        }

        func files(in path: URL) throws -> [URL] {
            try components(in: path, dir: false)
        }

        let darwinLocaleFolders = try dirs(in: darwinFastlaneMetadataRoot)
        let androidLocaleFolders = try dirs(in: androidFastlaneRoot)

        let allLocales = Set((darwinLocaleFolders + androidLocaleFolders).map(\.lastPathComponent)).sorted()

        func loadFastlaneMeta(_ path: URL) -> String? {
            (try? String(contentsOf: path, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func loadMetadatas(androidPath: String, darwinPath: String) -> (Appcat.LocalizedText, Appcat.LocalizedText) {
            var androidTexts: Appcat.LocalizedText = [:]
            var darwinTexts: Appcat.LocalizedText = [:]

            for locale in allLocales {
                let androidMetadataRoot = androidFastlaneRoot.appendingPathComponent(locale, isDirectory: true)
                androidTexts[locale] = loadFastlaneMeta(androidMetadataRoot.appendingPathComponent(androidPath))

                let darwinMetadataRoot = darwinFastlaneMetadataRoot.appendingPathComponent(locale, isDirectory: true)
                darwinTexts[locale] = loadFastlaneMeta(darwinMetadataRoot.appendingPathComponent(darwinPath))
            }

            return (androidTexts, darwinTexts)
        }

        let androidAppId = bundleIdentifier.replacing("-", with: "_")
        var androidPlatform = Appcat.App.Platform(id: androidAppId, channels: [:], profiles: [:])
        var darwinPlatform = Appcat.App.Platform(id: bundleIdentifier, channels: [:], profiles: [:])

        let (androidTitles, darwinTitles) = loadMetadatas(androidPath: "title.txt", darwinPath: "title.txt")
        if androidTitles == darwinTitles { // promote
            app.title = androidTitles
        } else {
            (androidPlatform.title, darwinPlatform.title) = (androidTitles, darwinTitles)
        }

        let (androidSummaries, darwinSummaries) = loadMetadatas(androidPath: "short_description.txt", darwinPath: "subtitle.txt")
        if androidSummaries == darwinSummaries { // promote
            app.summary = androidSummaries
        } else {
            (androidPlatform.summary, darwinPlatform.summary) = (androidSummaries, darwinSummaries)
        }

        let (androidDescription, darwinDescription) = loadMetadatas(androidPath: "full_description.txt", darwinPath: "description.txt")
        if androidDescription == darwinDescription { // promote
            app.description = androidDescription
        } else {
            (androidPlatform.description, darwinPlatform.description) = (androidDescription, darwinDescription)
        }

        var (androidKeywords, darwinKeywords) = loadMetadatas(androidPath: "keywords.txt", darwinPath: "keywords.txt")
        func splitTrim(_ value: String) -> [String] {
            value.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        }
        let androidKeywordList = androidKeywords.mapValues(splitTrim)
        let darwinKeywordList = darwinKeywords.mapValues(splitTrim)
        if androidKeywordList == darwinKeywordList { // promote
            app.keywords = androidKeywordList
        } else {
            (androidPlatform.keywords, darwinPlatform.keywords) = (androidKeywordList, darwinKeywordList)
        }

        // Android icon and screenshots
        for locale in allLocales {
            let androidMetadataRoot = androidFastlaneRoot.appendingPathComponent(locale, isDirectory: true)
            let androidImagesFolder = androidMetadataRoot.appendingPathComponent("images", isDirectory: true)

            let iconFile = androidImagesFolder.appendingPathComponent("icon.png", isDirectory: false)
            if iconFile.pathIsRegularFile {
                let iconRef = try readImageRef(Data(contentsOf: iconFile), location: iconFile.relativePath)
                var appIcon = app.icon
                appIcon[locale] = iconRef
                app.icon = appIcon
            }

            for screenshotDir in try dirs(in: androidImagesFolder) {
                let suffix = "Screenshots"
                if !screenshotDir.lastPathComponent.hasSuffix(suffix) { continue }
                // e.g., "phoneScreenshots"
                let profileName = screenshotDir.lastPathComponent.dropLast(suffix.count).description
                var screenshots: Appcat.LocalizedImageList = androidPlatform.profiles[profileName]?.screenshots ?? [:]
                for screenshotFile in try files(in: screenshotDir).filter({ $0.pathExtension == "png" }) {
                    let screenshotData = try Data(contentsOf: screenshotFile)
                    let screenshot = try readImageRef(screenshotData, location: screenshotFile.relativePath)
                    screenshots[locale] = screenshots[locale] ?? .init()
                    screenshots[locale]?.append(screenshot)
                }

                if !screenshots.isEmpty {
                    androidPlatform.profiles[profileName] = Appcat.App.Platform.Profile(screenshots: screenshots)
                }
            }
        }

        // Darwin icon and screenshots
        for locale in allLocales {
            let darwinScreenshotsFolder = darwinFastlaneBase
                .appendingPathComponent("screenshots", isDirectory: true)
                .appendingPathComponent(locale, isDirectory: true)
            if !darwinScreenshotsFolder.pathIsDirectory { continue }

            for screenshotFile in try files(in: darwinScreenshotsFolder).filter({ $0.pathExtension == "png" }) {
                let screenshotData = try Data(contentsOf: screenshotFile)
                let screenshot = try readImageRef(screenshotData, location: screenshotFile.relativePath)
                // guess whether the screenshot is for an iPhone or iPad based on the length of the shortest dimension
                let profileName = min(screenshot.width, screenshot.height) >= 2048 ? "ipad" : "iphone"
                var screenshots: Appcat.LocalizedImageList = darwinPlatform.profiles[profileName]?.screenshots ?? [:]
                screenshots[locale] = screenshots[locale] ?? .init()
                screenshots[locale]?.append(screenshot)
                if !screenshots.isEmpty {
                    darwinPlatform.profiles[profileName] = Appcat.App.Platform.Profile(screenshots: screenshots)
                }
            }
        }

        var playstoreChannel = Appcat.App.Platform.Channel(version: marketingVersion, build: Int64(projectVersion), date: Date.now)
        androidPlatform.channels["playstore"] = playstoreChannel

        var appstoreChannel = Appcat.App.Platform.Channel(version: marketingVersion, build: Int64(projectVersion), date: Date.now)

        let categories = [
            loadFastlaneMeta(darwinFastlaneMetadataRoot.appendingPathComponent("primary_category.txt", isDirectory: false)),
            loadFastlaneMeta(darwinFastlaneMetadataRoot.appendingPathComponent("secondary_category.txt", isDirectory: false)),
        ].compacted()
        if !categories.isEmpty {
            appstoreChannel.categories = categories
        }
        darwinPlatform.channels["appstore"] = appstoreChannel

        app.platforms["android"] = androidPlatform
        app.platforms["darwin"] = darwinPlatform

        return app
    }

    func readImageRef(_ data: Data, location: String) throws -> Appcat.ImageResourceRef {
        let size = data.count
        let sha256 = data.sha256().hex()

        enum PNGParseError: Error {
            case invalidSignature
            case dataTooShort
            case invalidIHDR
        }

        // A PNG must be at least 33 bytes to contain the signature (8) and a full IHDR chunk (25)
        guard data.count >= 33 else {
            throw PNGParseError.dataTooShort
        }

        // Validate PNG Signature
        let signature = data.prefix(8)
        let expectedSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard signature == Data(expectedSignature) else {
            throw PNGParseError.invalidSignature
        }

        // Verify the IHDR chunk type
        // The chunk type starts at offset 12 (after 8-byte signature + 4-byte length)
        let ihdrTypeRange = 12..<16
        let ihdrType = String(data: data.subdata(in: ihdrTypeRange), encoding: .ascii)
        guard ihdrType == "IHDR" else {
            throw PNGParseError.invalidIHDR
        }

        // Extract Width and Height
        // Width starts at offset 16, Height at offset 20
        let widthData = data.subdata(in: 16..<20)
        let heightData = data.subdata(in: 20..<24)

        // PNG uses Big-Endian. UInt32.init(bigEndian:) handles the conversion.
        let width = widthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let height = heightData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

        return Appcat.ImageResourceRef(mimeType: "image/png", location: location, size: Int64(size), hash: sha256, width: Int(width), height: Int(height), caption: nil)
    }
}
