// Copyright (c) 2022 - 2026 The App Fair Project <info@appfair.org>
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import FairCore
import FairExpo
import ArgumentParser

public struct AppcatCommand: AsyncParsableCommand {
    public static let experimental = true
    public static var configuration = CommandConfiguration(commandName: "appcat",
                                                           abstract: "Commands for creating and validating appcat metadata.",
                                                           shouldDisplay: !experimental, subcommands: Self.subcommands)
    static let subcommands: [ParsableCommand.Type] = [
        CreateCommand.self,
    ]

    public init() {
    }


    public struct CreateCommand: AsyncParsableCommand, FairMsgCommand {
        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var projectOptions: ProjectOptions

        public static let experimental = false
        public static var configuration = CommandConfiguration(commandName: "create", abstract: "Build and validate an appcat project.", shouldDisplay: !experimental)

        public typealias Output = Appcat.App

        public init() {
        }

        public func run() async throws {
            msg(.debug, "creating appcat metadata for project:", projectOptions.projectPathFlag)
            warnExperimental(Self.experimental)
            let dir = URL(fileURLWithPath: projectOptions.projectPathFlag)
            let convention = SkipProjectConvention()
            var app = try convention.buildAppcatApp(in: dir)

            let yaml = try app.toYAML()
            try msgOptions.writeOutput(yaml.utf8Data)
        }
    }
}
