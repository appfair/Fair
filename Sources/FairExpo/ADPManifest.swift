// Copyright (c) 2022 - 2026 The App Fair Project <info@appfair.org>
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// https://developer.apple.com/documentation/marketplacekit/ingesting-an-alternative-distribution-package#Process-the-manifest-file
public struct ADPManifest: Codable, Equatable {
    public var manifestSchemaVersion: String? // "1.0"
    public var distributionPackageRevision: Int // 1, 2 for subsequent manifest delivery with deltas…
    public var appleItemId: String // "6740916318"
    public var bundleId: String // "org.appfair.app.SkipNotes"
    public var shortVersionString: String // "0.8.7"
    public var bundleVersion: String // "44"
    public var appleVersionId: String // "879184094"
    public var platforms: [String] // [ "ios" ]
    public var minimumSystemVersions: [String: String] // { "ios": "17.2" }
    public var requiredDeviceCapabilities: [String] // ["arm64"]
    //public var appInstallDeterminants: [Any] // unsure what this data type should be
    public var hasMessagesExtension: Bool?
    public var isLaunchProhibited: Bool?
    public var variants: [Variant]
    public var deltas: [Delta]

    public struct Variant: Codable, Equatable {
        public var publicId: UUID // "219750db-80c2-4c75-aecc-fa67835f384d"
        public var assetPath: String // "variant/219750db-80c2-4c75-aecc-fa67835f384d.ipa"
        public var installTargets: [[String: String]] // { "device": "iPhone13,4", "os": "17.4" }
        public var variantDetails: AssetDetails
    }

    public struct Delta: Codable, Equatable {
        public var publicId: UUID // "ffbc52b6-f76b-4d51-9eff-5388bc6b7572"
        public var assetPath: String // "delta/ffbc52b6-f76b-4d51-9eff-5388bc6b7572.ipa"
        public var sourceVariant: SourceVariant
        public var targetVariantAssetPath: String // "variant/219750db-80c2-4c75-aecc-fa67835f384d.ipa"
        public var deltaDetails: AssetDetails

        public struct SourceVariant: Codable, Equatable {
            public var installTargets: [[String: String]] // [ { "device": "iPhone14,5", "os": "17.4" }, … ]
            public var appleVersionId: String // "878080263"
            public var version: String // "0.8.5"
        }
    }

    public struct AssetDetails: Codable, Equatable {
        public var compressedSize: Int64 // 183335
        public var uncompressedSize: Int64 // 375808
        public var hashes: [Hash]

        public struct Hash: Codable, Equatable {
            public var algorithm: String // "sha256"
            public var chunkSize: Int64 // 183335
            public var encryptedChunkDigests: [String] // ["ecc9df4860bd98b17dd8eae7f6b7aa6371fb51911ad13578da2293409366e53c"]
            public var unencryptedChunkDigests: [String]? // undocumented
        }
    }
}
