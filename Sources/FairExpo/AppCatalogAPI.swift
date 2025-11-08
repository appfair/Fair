import Foundation
import FairCore

extension AppCatalogIndex {
    public static let appfairCatalogURL: URL! = URL(string: "https://appfair.net/appfair-apps.json")
}


/// The master list of apps and configuration for an app catalog.
///
/// This merely includes fundamental pointers to the app's location, like the app name and token and bundleID/appid.
/// The remainder of the metadata will be fetched from the specific catalog (e.g., `altstore.json`, `fdroid.json`)
/// attached to individual releases.
///
/// See: https://appfair.net/appfair-apps.json
public struct AppCatalogIndex : Decodable {
    public var catalogs: Catalogs
    public var apps: [App]

    public struct Catalogs : Decodable {
        public var altstore: AltCatalog?
        public var fdroid: FDroidIndex.Repo?
    }

    public struct App : Decodable {
        public var token: String // e.g., "Skip-Notes"
        public var ios: DarwinApp?
        public var android: AndroidApp?

        public struct DarwinApp : Decodable {
            public var bundleId: String
            public var appleItemId: String?
        }

        public struct AndroidApp : Decodable {
            public var appid: String
        }
    }
}


extension Plist {
    /// A map of all the "*UsageDescription*" properties that have string values
    var usageDescriptions: [String: String] {
        // gather the list of all "*UsageDescription" keys with string values
        // to ensure that they are all listed in the app's permissions
        self.rawValue
            .compactMap { key, value in
                (key as? String).flatMap { key in
                    (value as? String).flatMap { value in
                        (key, value)
                    }
                }
            }
            .filter { key, value in
                key.hasSuffix("UsageDescription")
            }
            .dictionary(keyedBy: \.0)
            .compactMapValues(\.1)
    }

    var backgroundModes: [String]? {
        (self.rawValue["UIBackgroundModes"] as? NSArray)?.compactMap({ $0 as? String })
    }
}

public extension Plist {
    /// The usage description dictionary for the `"FairUsage"` key.
    /// - TODO: @available(*, deprecated, message: "moved to AppSource.permissions key")
    var FairUsage: NSDictionary? {
        plistValue(for: .FairUsage) as? NSDictionary
    }

}


extension PropertyListKey {
    /// - TODO: @available(*, deprecated, message: "moved to AppSource.permissions key")
    public static let FairUsage = Self("FairUsage")
}

public typealias MessagePayload = (MessageKind, [Any?])

/// The type of message output
public enum MessageKind {
    case debug, info, warn, error

    public var name: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        }
    }
}

/// A representation of a `Localized.strings` file that retains its formatting and comments.
///
/// This structure is meant to be used to parse the output from `genstrings`, which saves
/// to a UTF-16 OpenStep simplified `.plist` with comments for the translation context.
///
/// Since all the native plist parsers do not preserve comments, we save the raw string from the
/// strings file, and any updates to the dictionary will preserve the existing comment for that key
/// (assuming it exists).
public struct LocalizedStringsFile {
    public private(set) var fileContents: String
    public private(set) var plist: Plist
    /// An index of the plist keys to the lines in the property list file.
    private(set) var keyLines: [String?: Int] = [:]

    /// Returns all the keys in this property list
    public var keys: Set<String> {
        plist.rawValue.allKeys.compactMap({ $0 as? String }).set()
    }

    var fileLines: [Substring] {
        fileContents.split(separator: "\n", omittingEmptySubsequences: false)
    }

    public init(fileContents: String) throws {
        self.fileContents = fileContents
        self.plist = try Plist(data: fileContents.utf8Data)
        self.keyLines = Dictionary(fileLines.enumerated().map({ (Self.parseKeyFromLine($1), $0) })) { $1 }
    }

    static func parseKeyFromLine<S: StringProtocol>(_ line: S) -> String? {
        guard line.first == #"""# else {
            return nil
        }

        let parts = (line.dropFirst(1)).components(separatedBy: #"" = ""#)
        guard parts.count == 2 else {
            dbg("invalid parts count")
            return nil
        }

        return parts.first
    }

    /// Updates the strings file contents with the specified property list dictionary.
    public mutating func update(strings: Plist) throws {
        var lines = self.fileLines.map(String.init)
        var trimLines = IndexSet()

        for (key, value) in strings.rawValue {
            guard let key = key as? String else { continue }
            guard let value = value as? String else { continue }
            guard let lineIndex = keyLines[key] else {
                dbg("no key line for:", key)
                continue
            }

            // we need to manually construct the line ourselves, because `PropertyListSerialization.data(fromPropertyList: …, format: .openStep)` doesn't work for writing

            // for multi-line string values,
            // we can't just trim down the file here, because the keys are not necessarily stored in order.
            // so instead, save a list of lines to delete
            if let endStringLine = (lineIndex..<lines.count).first(where: { lines[$0].trimmingCharacters(in: .whitespaces).hasSuffix(#"";"#) }), endStringLine > lineIndex {
                trimLines.insert(integersIn: (lineIndex+1)...endStringLine)
            }

            // update the string in-place
            let newLine = "\"\(key)\" = \"\(value)\";"
            lines[lineIndex] = newLine
        }

        // now clear the extra parts of the trailing strings
        // lines.remove(atOffsets: trimLines) // not available on Linux
        for removeLine in trimLines.sorted().reversed() {
            lines.remove(at: removeLine)
        }

        self.plist = strings
        self.fileContents = lines.joined(separator: "\n")

        // now validate by trying to parse the plust before we write it out
        // TODO: throw a nicer error message when the generated localization file is invalid
        // Error: The data couldn’t be read because it isn’t in the correct format.
        dbg("attempting to re-parse Localized.strings size:", self.fileContents.utf8Data.count)
        _ = try Plist(data: self.fileContents.utf8Data)
    }
}

/// https://docs.fastlane.tools/actions/deliver/#available-metadata-folder-options
public struct AppMetadata : Codable {
    // Non-Localized Metadata
    public var copyright: String? // copyright.txt
    public var primary_category: String? // primary_category.txt
    public var secondary_category: String? // secondary_category.txt
    public var primary_first_sub_category: String? // primary_first_sub_category.txt
    public var primary_second_sub_category: String? // primary_second_sub_category.txt
    public var secondary_first_sub_category: String? // secondary_first_sub_category.txt
    public var secondary_second_sub_category: String? // secondary_second_sub_category.txt

    // Localized Metadata
    public var name: String? // <lang>/name.txt
    public var subtitle: String? // <lang>/subtitle.txt
    public var privacy_url: String? // <lang>/privacy_url.txt
    public var apple_tv_privacy_policy: String? // <lang>/apple_tv_privacy_policy.txt
    public var description: String? // <lang>/description.txt
    public var keywords: String? // <lang>/keywords.txt
    public var release_notes: String? // <lang>/release_notes.txt
    public var support_url: String? // <lang>/support_url.txt
    public var marketing_url: String? // <lang>/marketing_url.txt
    public var promotional_text: String? // <lang>/promotional_text.txt

    // Review Information
    public var first_name: String? // review_information/first_name.txt
    public var last_name: String? // review_information/last_name.txt
    public var phone_number: String? // review_information/phone_number.txt
    public var email_address: String? // review_information/email_address.txt
    public var demo_user: String? // review_information/demo_user.txt
    public var demo_password: String? // review_information/demo_password.txt
    public var notes: String? // review_information/notes.txt

    // Locale-specific metadata
    public var localizations: [String: AppMetadata]?

    public enum CodingKeys : String, CodingKey, CaseIterable {
        case copyright
        case primary_category
        case secondary_category
        case primary_first_sub_category
        case primary_second_sub_category
        case secondary_first_sub_category
        case secondary_second_sub_category

        case name
        case subtitle
        case privacy_url
        case apple_tv_privacy_policy
        case description
        case keywords
        case release_notes
        case support_url
        case marketing_url
        case promotional_text

        case first_name
        case last_name
        case phone_number
        case email_address
        case demo_user
        case demo_password
        case notes

        case localizations
    }
}


/// A generic configuration file.
///
/// The format is a line-based key/value pair separate with an equals. Key and values are always unquoted, and have no terminating character.
public struct EnvFile : RawRepresentable, Hashable {
    public var rawValue: [String?]

    public init(rawValue: [String?]) {
        self.rawValue = rawValue
    }

    public init(data: Data) throws {
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.coderInvalidValue)
        }
        self.rawValue = string.components(separatedBy: .newlines)
    }

    public init(url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    /// The underlying contents of this env file
    public var contents: String {
        rawValue.compacted().joined(separator: "\n")
    }

    /// Saves the contents of this `EnvFile`
    public func save(to url: URL, atomically atomic: Bool = true) throws {
        try contents.write(to: url, atomically: atomic, encoding: .utf8)
    }

    public subscript(path: String) -> String? {
        get {
            let token = path + " = "
            for line in rawValue.compacted() {
                if line.hasPrefix(token) {
                    return String(line.dropFirst(token.count))
                }
            }
            return nil
        }

        set {
            let token = path + " = "
            var updated = 0
            for (index, line) in rawValue.enumerated() {
                if let line = line {
                    if line.hasPrefix(token) {
                        if let newValue = newValue {
                            rawValue[index] = token + newValue
                        } else {
                            rawValue[index] = nil
                        }
                        updated += 1
                    }
                }
            }
            if let newValue = newValue, updated == 0 {
                // the value did not exist, so update it
                rawValue += [token + newValue]
            }
        }
    }
}

