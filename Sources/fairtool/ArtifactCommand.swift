// Copyright (c) 2022 - 2026 The App Fair Project <info@appfair.org>
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import FairCore
import FairExpo
import ArgumentParser

public struct ArtifactCommand : AsyncParsableCommand {
    public static let experimental = false
    public static var configuration = CommandConfiguration(commandName: "artifact",
                                                           abstract: "Commands for examining a compiled app artifact.",
                                                           shouldDisplay: !experimental, subcommands: Self.subcommands)

    static let subcommands: [ParsableCommand.Type] = [
        InfoCommand.self,
    ]

    public init() {
    }

    public struct InfoCommand: FairStructuredCommand {
        public static let experimental = false
        public static var configuration = CommandConfiguration(commandName: "info",
                                                               abstract: "Output information about the specified app(s).",
                                                               shouldDisplay: !experimental)

        public typealias Output = InfoItem

        public struct InfoItem : FairCommandOutput, Decodable {
            public var url: URL
            public var info: JSON
            public var entitlements: [JSON]?
        }

        @OptionGroup public var msgOptions: MsgOptions
        @OptionGroup public var downloadOptions: DownloadOptions

        @Argument(help: ArgumentHelp("Path(s) or url(s) for app folders or ipa archives", valueName: "apps", visibility: .default))
        public var apps: [String]

        public init() {
        }

        public func executeCommand() -> AsyncThrowingStream<InfoItem, Error> {
            msg(.debug, "getting info from apps:", apps)
            return executeStream(apps) { app in
                return try extractInfo(from: await downloadOptions.acquire(path: app, onDownload: { url in
                    msg(.info, "downloading from URL:", url.absoluteString)
                    return url
                }))
            }
        }

        private func extractInfo(from: (from: URL, local: URL)) throws -> InfoItem {
            msg(.info, "extracting info: \(from.from)")
            let (info, entitlements) = try AppBundleLoader.loadInfo(fromAppBundle: from.local)

            return try InfoItem(url: from.from, info: info.json(), entitlements: entitlements?.map({ try $0.json() }))
        }
    }
}
