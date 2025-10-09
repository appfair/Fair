import Foundation
import FairCore
import FairExpo
import ArgumentParser

public struct TranslateCommand : AsyncParsableCommand {
    public static let experimental = false
    public static var configuration = CommandConfiguration(commandName: "translate",
                                                           abstract: "Commands for handling localizations",
                                                           shouldDisplay: !experimental, subcommands: Self.subcommands)
    static let subcommands: [ParsableCommand.Type] = [
        ScanCommand.self,
    ]

    public init() {
    }


    /// An aggregate command that performs the following tasks:
    ///
    ///  - create or update the docs/CNAME file
    ///  - create and update the localized strings file
    public struct ScanCommand: FairMsgCommand {
        public static let experimental = true
        public static var configuration = CommandConfiguration(commandName: "scan", abstract: "Scans translations for the given key(s)", shouldDisplay: !experimental)

        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var projectOptions: ProjectOptions

        @Option(name: [.long], help: ArgumentHelp("The translation keys to search for"))
        public var key: [String] = [".*"]

        @Argument(help: ArgumentHelp("Resources folder to scan", valueName: "dir", visibility: .default))
        public var dir: [String]

        public init() {
        }

        public func run() async throws {
//            for dir in dir {
//                msg(.info, "scanning", dir)
//                do {
//                    let locales: [String : [(URL, Plist)]] = try loadLocalizations(resourcesFolder: URL(fileOrScheme: dir), localeFileName: ".*.strings")
//                    msg(.info, "loaded", locales.count, "languages", locales.keys.sorted())
//                    for (_, localeFiles) in locales {
//                        //msg(.info, "locale", localeName)
//                        for (localeFile, plist) in localeFiles {
//                            for keyArg in self.key {
//                                for (pkey, pvalue) in plist.rawValue {
//                                    guard let skey = pkey as? String else { continue }
//                                    if try skey.matches(regex: keyArg) {
//                                        msg(.info, dir, "locale:", localeFile.path, "key:", skey, "value:", pvalue)
//                                        // TODO: store the localized translations
//                                    }
//                                }
//                            }
//                        }
//                    }
//                } catch {
//                    msg(.info, "error loading:", dir, error)
//                }
//            }
        }
    }
}
