import Foundation
import FairCore
import FairExpo
import ArgumentParser

public struct JSONCommand : AsyncParsableCommand {
    public static let experimental = true
    public static var configuration = CommandConfiguration(commandName: "json",
                                                           abstract: "JSON manipulation tools.",
                                                           shouldDisplay: !experimental,
                                                           subcommands: [
                                                            SignCommand.self,
                                                            VerifyCommand.self,
                                                           ])

    public init() {
    }

    enum Errors : Error {
        case invalidBase64Key
        case missingSignatureProperty
    }

    public struct SignCommand: FairStructuredCommand {
        public static let experimental = false

        public typealias Output = JSON

        public static var configuration = CommandConfiguration(commandName: "sign",
                                                               abstract: "Adds a message authentication code to the given JSON.",
                                                               shouldDisplay: !experimental)

        @OptionGroup public var msgOptions: MsgOptions

        @Option(name: [.long], help: ArgumentHelp("The property in which the signature will be stored", valueName: "prop"))
        public var property: String = "signature"

        @Option(name: [.long], help: ArgumentHelp("The base64 encoding of the key", valueName: "key"))
        public var keyBase64: String

        //@Argument(help: ArgumentHelp("A string version of the key", valueName: "keystr", visibility: .default))
        //public var keyString: String?

        /// The JSON files (or standard input) to encode
        @Argument(help: ArgumentHelp("The input JSON to sign", valueName: "body", visibility: .default))
        public var inputs: [String]

        public init() { }

        private func keyData() throws -> Data {
            if let data = Data(base64Encoded: keyBase64) {
                return data
            }

            throw Errors.invalidBase64Key
        }

        public func executeCommand() -> AsyncThrowingStream<JSON, Error> {
            warnExperimental(Self.experimental)

            return executeSeries(inputs, initialValue: nil) { input, prev in
                msg(.info, "signing input:", input)
                var json = try JSON(fromJSON: Data(contentsOf: URL(fileOrScheme: input)))
                json[property] = nil // clear the signature if it exists
                let sig = try json.sign(key: try keyData())
                json[property] = .string(sig.base64EncodedString()) // embed the signature into the JSON
                return json
            }
        }
    }

    public struct VerifyCommand: FairStructuredCommand {
        public static let experimental = false

        public typealias Output = [JSON]

        public static var configuration = CommandConfiguration(commandName: "verify",
                                                               abstract: "Verifies a message authentication code for the given JSON.",
                                                               shouldDisplay: !experimental)

        @OptionGroup public var msgOptions: MsgOptions

        @Option(name: [.long], help: ArgumentHelp("The property in which the signature will be stored", valueName: "prop"))
        public var property: String = "signature"

        @Option(name: [.long], help: ArgumentHelp("The base64 encoding of the key", valueName: "key"))
        public var keyBase64: String

        //@Argument(help: ArgumentHelp("A string version of the key", valueName: "keystr", visibility: .default))
        //public var keyString: String?

        /// The JSON files (or standard input) to encode
        @Argument(help: ArgumentHelp("The JSON file to verify", valueName: "file", visibility: .default))
        public var inputs: [String]

        public init() { }

        private func keyData() throws -> Data {
            if let data = Data(base64Encoded: keyBase64) {
                return data
            }

            throw Errors.invalidBase64Key
        }

        public func executeCommand() -> AsyncThrowingStream<[JSON], Error> {
            warnExperimental(Self.experimental)

            return executeSeries(inputs, initialValue: nil) { input, prev in
                msg(.info, "verifying input:", input)
                let contents = try JSON(fromJSON: Data(contentsOf: URL(fileOrScheme: input)))
                // the payload can either be an object or an array of objects
                let jsons = contents.array?.compactMap(\.object) ?? contents.object.map({ [$0 ]}) ?? []
                return try jsons.map {
                    var json = $0
                    guard let sig = json[property]?.string,
                          let sigData = Data(base64Encoded: sig) else {
                        throw Errors.missingSignatureProperty
                    }

                    json[property] = nil
                    let jobj = JSON.object(json)
                    let resigned = try jobj.sign(key: keyData())
                    if resigned != sigData {
                        throw SignableError.signatureMismatch//(resigned, sigData)
                    }
                    return jobj // returns the validated JSON without the signature
                }
            }
        }
    }

}
