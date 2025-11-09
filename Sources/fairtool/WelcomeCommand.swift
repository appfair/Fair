import Foundation
import FairCore
import FairExpo
import ArgumentParser

public struct WelcomeCommand : AsyncParsableCommand {
    public static var configuration = CommandConfiguration(
        commandName: "welcome",
        abstract: "Show a welcome message for the tool.",
        shouldDisplay: false)

    @OptionGroup public var msgOptions: MsgOptions

    public init() {
    }

    public mutating func run() async throws {
        let v = Bundle.fairCoreVersion?.versionString ?? ""

        let term = msgOptions.term

        /// Colorize ASCI art banner by in fixed-width columns
        func col(_ value: String) -> String {
            term.cyan(value.slice(0, 2))         // f
            + term.red(value.slice(2, 4))        // a
            + term.green(value.slice(4, 5))      // i
            + term.blue(value.slice(5, 7))       // r
            + term.yellow(value.slice(7, 9))     // t
            + term.red(value.slice(9, 11))       // o
            + term.red(value.slice(11, 13))      // o
            + term.magenta(value.slice(13, 15))  // l
        }

        msgOptions.write("""
        \(col("▐▘  ▘  ▗     ▜ "))
        \(col("▜▘▀▌▌▛▘▜▘▛▌▛▌▐ "))
        \(col("▐ █▌▌▌ ▐▖▙▌▙▌▐▖")) \(v)

        Run fairtool --help for usage
        """)
    }
}
