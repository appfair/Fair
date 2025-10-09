import Foundation
import FairCore

/// The collection of URLs associated with a Homebrew API
public struct HomebrewAPI {
    /// The default base for the cask API
    public static let defaultEndpoint = URL(string: "https://formulae.brew.sh/api/cask.json")!

    /// The base endpoint for casks
    public let caskAPIEndpoint: URL

    public init(caskAPIEndpoint: URL) {
        self.caskAPIEndpoint = caskAPIEndpoint
    }
}

public extension HomebrewAPI {
    /// The list of casks
    var caskList: URL { URL(string: "cask.json", relativeTo: caskAPIEndpoint)! }
    var formulaList: URL { URL(string: "formula.json", relativeTo: caskAPIEndpoint)! }

    var caskSourceBase: URL { URL(string: "cask-source/", relativeTo: caskAPIEndpoint)! }
    var caskMetadataBase: URL { URL(string: "cask/", relativeTo: caskAPIEndpoint)! }

    var caskStatsBase: URL { URL(string: "analytics/cask-install/homebrew-cask/", relativeTo: caskAPIEndpoint)! }

    var caskStats30: URL { URL(string: "30d.json", relativeTo: caskStatsBase)! }
    var caskStats90: URL { URL(string: "90d.json", relativeTo: caskStatsBase)! }
    var caskStats365: URL { URL(string: "365d.json", relativeTo: caskStatsBase)! }


    /// Fetches the cask list and returns it in the `casks` array
    func fetchCasks() async throws -> (casks: Array<CaskItem>, response: URLResponse?) {
        dbg("loading cask list")
        let url = self.caskList
        let request = URLRequest(url: url)
        let (data, response) = try await URLSession.shared.fetch(request: request)

        dbg("loaded cask JSON", data.count.localizedByteCount(), "from url:", url)
        let casks = try Array<CaskItem>(fromJSON: data)
        dbg("loaded", casks.count, "casks")

        return (casks, response)
    }

    /// Fetches the cask stats and populates it in the `stats` property
    func fetchAppStats() async throws -> CaskStats {
        try await fetchCaskStats(url: caskStats30)
    }

    func fetchCaskStats(url: URL) async throws -> CaskStats {
        dbg("loading cask stats:", url.absoluteString)
        let data = try await URLRequest(url: url).fetch()

        dbg("loaded cask stats", data.count.localizedByteCount(), "from url:", url)
        return try CaskStats(fromJSON: data, dateDecodingStrategy: .iso8601)
    }
}


/// A Homebrew Cask, as defined by the API specification at [https://formulae.brew.sh/docs/api/#get-formula-metadata-for-a-cask-formula](https://formulae.brew.sh/docs/api/#get-formula-metadata-for-a-cask-formula)
public struct CaskItem : Equatable, Decodable {

    /// The token of the cask. E.g., `alfred`
    public var token: String

    /// E.g., `4.6.1,1274`
    public var version: String

    /// E.g., `["Alfred"]`
    public var name: [String]

    /// E.g., `"Application launcher and productivity software"`
    public var desc: String?

    /// E.g., `https://www.alfredapp.com/`
    public var homepage: String?

    /// E.g., `https://cachefly.alfredapp.com/Alfred_4.6.1_1274.dmg`
    public var url: String?

    /// E.g., `alfred` or `appfair/app/bon-mot`
    public var full_token: String

    /// E.g., `homebrew/cask` or `appfair/app`
    public var tap: String?

    /// E.g., `https://nucleobytes.com/4peaks/index.html`
    public var appcast: String?

    /// E.g., `5.8.3.2240`
    public var installed: String? // always nil when taken from API

    // TODO
    // let versions": {},

    // let outdated: false // not relevent for API

    /// The SHA-256 hash of the artifact.
    private var sha256: String

    /// Returns the checksum unless it is the "no_check" constant or does not otherwise appear to be a checksum
    public var checksum: String? {
        //let validCharacters = CharacterSet(charactersIn: "")
        sha256 == "no_check" || sha256.count != 64 ? nil : sha256
    }

    /// E.g.: `app has been officially discontinued upstream`
    public var caveats: String?

    public var auto_updates: Bool?

    // "artifacts":[["Signal.app"],{"trash":["~/Library/Application Support/Signal","~/Library/Preferences/org.whispersystems.signal-desktop.helper.plist","~/Library/Preferences/org.whispersystems.signal-desktop.plist","~/Library/Saved Application State/org.whispersystems.signal-desktop.savedState"],"signal":{}}]
    public typealias ArtifactItem = Either<Array<ArtifactNameTarget>>.Or<JSON>

    public var artifacts: Array<ArtifactItem>?

    /// Either the raw name of an app, or the target of the app
    public typealias ArtifactNameTarget = Either<ArtifactTarget>.Or<String>

    /// A target for the app, typically part of a hetergeneous array when the installed name of the app differs from the canonical name of the app
    /// E.g.: `["Eclipse.app", { "target": "Nodeclipse.app" } ]`
    public struct ArtifactTarget : Equatable, Decodable {
        public var target: String
    }

    /// `depends_on` is used to declare dependencies and requirements for a Cask. `depends_on` is not consulted until install is attempted.
    public var depends_on: DependsOn?

    public struct DependsOn : Equatable, Decodable {
        public var cask: [String]?

        /// E.g., `{"macos":{">=":["10.12"]}}`
        // let macOS: Either<Array<String>>.Or<String>?
    }

    /// E.g.: `"conflicts_with":{"cask":["homebrew/cask-versions/1password-beta"]}`
    // let conflicts_with: null

    /// E.g.: `"container":"{:type=>:zip}"`
    // let container": null,

    /// Possible model for https://github.com/Homebrew/brew/issues/12786
//    private let files: [FileItem]?
//    private struct FileItem : Equatable, Decodable {
//        /// E.g., "arm64" or "x86"
//        let arch: String?
//        let url: String?
//        let sha256: String?
//    }
}

/// ```{"category":"cask_install","total_items":6190,"start_date":"2021-12-05","end_date":"2022-01-04","total_count":894812,"items":[{"number":1,"cask":"google-chrome","count":"34,530","percent":"3.86"},{"number":2,"cask":"iterm2","count":"31,096","percent":"3.48"},{"number":6190,"cask":"zulufx11","count":"1","percent":"0"}]}```
/// https://formulae.brew.sh/docs/api/#list-analytics-events-for-all-cask-formulae
public struct CaskStats : Equatable, Decodable {
    /// E.g., `cask_install`
    public var category: String

    /// E.g., `6190`
    public var total_items: Int

    /// E.g., `2021-12-05`
    public var start_date: String

    /// E.g., `2022-01-04`
    public var end_date: String

    /// E.g., `894812`
    public var total_count: Int

    /// `cask-install` category has `formulae`, but regular `install` has `items`.
    /// (see [API Docs](https://formulae.brew.sh/docs/api/#response-5))
    public var formulae: [String: [Stat]]?

    public var items: [String: [Stat]]?

    /// `{"number":1,"cask":"google-chrome","count":"34,530","percent":"3.86"}`
    public struct Stat : Equatable, Decodable {
        public var cask: String
        public var count: Int

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.cask = try values.decode(String.self, forKey: .cask)
            /// The `count` field should be a number, but it appears to be a numeric string (US localized with commas), but since it ought to be a number and maybe someday will be, also permit a number
            do {
                self.count = try values.decode(Int.self, forKey: .count)
            } catch {
                let stringCount = try values.decode(String.self, forKey: .count)
                self.count = Self.formatter.number(from: stringCount)?.intValue ?? 0
            }
        }

        enum CodingKeys : String, CodingKey {
            case cask
            case count
        }

        private static let formatter: NumberFormatter = {
            let fmt = NumberFormatter()
            fmt.numberStyle = .decimal
            fmt.isLenient = true
            fmt.locale = Locale(identifier: "en_US")
            return fmt
        }()
    }
}

