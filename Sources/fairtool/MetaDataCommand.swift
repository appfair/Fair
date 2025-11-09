import Foundation
import FairCore
import FairExpo
import ArgumentParser

extension FairCommand {

    public struct MetadataCommand: FairStructuredCommand {
        public typealias Output = AppMetadata
        public static let experimental = false
        public static var configuration = CommandConfiguration(commandName: "metadata",
                                                               abstract: "Output metadata for the given app.",
                                                               shouldDisplay: !experimental)
        @OptionGroup public var msgOptions: MsgOptions

        @Option(name: [.long, .customShort("x")], help: ArgumentHelp("Export deliver metadata folder.", valueName: "dir"))
        public var export: String?

        @Option(name: [.long, .customShort("k")], help: ArgumentHelp("The root key containg the app metadata.", valueName: "key"))
        public var key: String = "app"

        @Option(name: [.customLong("default")], help: ArgumentHelp("Property default value for the key.", valueName: "key=value"))
        public var valueDefault: [String] = []

        /// e.g.: `fairtool fair metadata --override "subtitle=A simple app" --override "fr-FR/subtitle=Une app simple"`
        @Option(name: [.customLong("override")], help: ArgumentHelp("Property override value for the key.", valueName: "key=value"))
        public var valueOverride: [String] = []

        /// Appends the given property value to the specified metadata key (or, if the key does not exist, replaces it).
        ///
        /// e.g.: `fairtool fair metadata --append "description=\n\nSome more info about this app."`
        @Option(name: [.customLong("append")], help: ArgumentHelp("Property append value for the key.", valueName: "key=value"))
        public var valueAppend: [String] = []

        @Argument(help: ArgumentHelp("Path to the metadata file", valueName: "App.yml", visibility: .default))
        public var yaml: [String] = ["App.yml"]

        public init() { }

        /// Takes a string in the format of `key=value` and returns a tuple with the key and value.
        func keyValueFormattedString(from keyValueString: String) -> (key: String, value: String?)? {
            let separator: Character = "="
            let parts = keyValueString.split(separator: separator, maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count < 2 {
                return nil
            }
            return (key: String(parts[0]), value: parts[1].isEmpty ? nil : String(parts[1]))
        }

        /// The maximum permitted value of the given metadata key.
        func maximumValueLength(for key: AppMetadata.CodingKeys) -> Int? {
            switch key {
            case .name: return 30
            case .subtitle: return 30
            case .keywords: return 100
            case .description: return 4000
            default: return nil
            }
        }

        public func executeCommand() -> AsyncThrowingStream<AppMetadata, Error> {
            warnExperimental(Self.experimental)

            let keyValues = { (vk: [String]) in
                vk.compactMap(keyValueFormattedString(from:))
                    .grouping(by: \.key)
                    .mapValues(\.first?.value)
                    .mapValues({
                        $0?.replacingOccurrences(of: "\\n", with: "\n") // allow literal "\n" in the text to indicate line breaks
                    })
            }

            let overrides = keyValues(valueOverride)
            let appends = keyValues(valueAppend)
            let defaults = keyValues(valueDefault)

            return executeSeries(yaml, initialValue: nil) { yaml, prev in
                msg(.info, "parsing metadata:", yaml)
                let json = try YAML.parse(Data(contentsOf: URL(fileOrScheme: yaml))).json()
                guard let appJSON = json[key]?.object else {
                    throw AppError(String(format: NSLocalizedString("Could not find key in YAML: %@", bundle: .module, comment: "error message"), arguments: [key]))
                }

                // attempt to re-parse the specified key's JSON-ized value as AppMetadata
                let appMeta = try AppMetadata(json: appJSON.json())

                if let export = export {
                    let exportURL = URL(fileURLWithPath: export, isDirectory: true)

                    func saveMetadata(locale: String?, meta: AppMetadata) throws {
                        func save(_ value: String?, review: Bool = false, _ key: AppMetadata.CodingKeys) throws {
                            if locale != nil && review == true {
                                // review properties are not localized
                                return
                            }

                            // CLI key is either '--default "key=the value"' or '--default "fr-FR/key=le value"'
                            let locKey = (locale.map({ $0 + "/" }) ?? "") + key.rawValue

                            // check for value-override, value-default, and vaue-append arguments
                            let valueDefault = defaults[locKey] ?? nil
                            let valueOverride = overrides[locKey] ?? nil
                            let valueAppend = appends[locKey] ?? nil

                            guard var value = valueOverride ?? value ?? valueDefault ?? valueAppend else {
                                return
                            }

                            // append the value with the given value
                            if let valueAppend = valueAppend, value != valueAppend {
                                value = value + valueAppend
                            }

                            if let maxLength = maximumValueLength(for: key), value.count > maxLength {
                                throw AppError(String(format: NSLocalizedString("The value for the property “%@” of length %d is beyond the maximum length of %d", bundle: .module, comment: "error message"), arguments: [locKey, value.count, maxLength]))
                            }

                            var outputURL = exportURL
                            if let locale = locale {
                                outputURL = URL(fileURLWithPath: locale, isDirectory: true, relativeTo: outputURL)
                            } else if review == false {
                                // localizable properties get put in the "default" folder
                                outputURL = URL(fileURLWithPath: "default", isDirectory: true, relativeTo: outputURL)
                            }

                            if review {
                                outputURL = URL(fileURLWithPath: "review_information", isDirectory: true, relativeTo: outputURL)
                            }

                            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

                            let path = URL(fileURLWithPath: key.rawValue, relativeTo: outputURL)
                            let file = path.appendingPathExtension("txt")
                            try value.write(to: file, atomically: false, encoding: .utf8)
                        }

                        for key in AppMetadata.CodingKeys.allCases {
                            switch key {
                            case .copyright: try save(meta.copyright, .copyright)
                            case .primary_category: try save(meta.primary_category, .primary_category)
                            case .secondary_category: try save(meta.secondary_category, .secondary_category)
                            case .primary_first_sub_category: try save(meta.primary_first_sub_category, .primary_first_sub_category)
                            case .primary_second_sub_category: try save(meta.primary_second_sub_category, .primary_second_sub_category)
                            case .secondary_first_sub_category: try save(meta.secondary_first_sub_category, .secondary_first_sub_category)
                            case .secondary_second_sub_category: try save(meta.secondary_second_sub_category, .secondary_second_sub_category)

                            case .name: try save(meta.name, .name)
                            case .subtitle: try save(meta.subtitle, .subtitle)
                            case .privacy_url: try save(meta.privacy_url, .privacy_url)
                            case .apple_tv_privacy_policy: try save(meta.apple_tv_privacy_policy, .apple_tv_privacy_policy)
                            case .description: try save(meta.description, .description)
                            case .keywords: try save(meta.keywords, .keywords)
                            case .release_notes: try save(meta.release_notes, .release_notes)
                            case .support_url: try save(meta.support_url, .support_url)
                            case .marketing_url: try save(meta.marketing_url, .marketing_url)
                            case .promotional_text: try save(meta.promotional_text, .promotional_text)

                            case .first_name: try save(meta.first_name, review: true, .first_name)
                            case .last_name: try save(meta.last_name, review: true, .last_name)
                            case .phone_number: try save(meta.phone_number, review: true, .phone_number)
                            case .email_address: try save(meta.email_address, review: true, .email_address)
                            case .demo_user: try save(meta.demo_user, review: true, .demo_user)
                            case .demo_password: try save(meta.demo_password, review: true, .demo_password)
                            case .notes: try save(meta.notes, review: true, .notes)

                            case .localizations: break
                            }
                        }
                    }

                    // the en-US folder needs to exist for the default metadata to be used in english
                    try FileManager.default.createDirectory(at: URL(fileURLWithPath: "en-US", isDirectory: true, relativeTo: exportURL), withIntermediateDirectories: true)

                    // save the root metadata; if there exists localizations, then save the root localizations to the "default" folder as expected by https://docs.fastlane.tools/actions/deliver/#default-values
                    try saveMetadata(locale: nil, meta: appMeta)

                    // save the localized app metadatas
                    for (localeName, localizedAppMeta) in appMeta.localizations ?? [:] {
                        try saveMetadata(locale: localeName, meta: localizedAppMeta)
                    }
                }
                return appMeta
            }
        }
    }
}

