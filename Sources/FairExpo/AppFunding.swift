import Foundation
import FairCore

/// A link to a particular funding platform.
public struct AppFundingLink : Codable, Equatable {
    /// E.g., "GITHUB" or "PATREON"
    ///
    /// This list should be harmonized with the funding platforms defined in [FundingPlatform](https://docs.github.com/en/graphql/reference/enums#fundingplatform)
    public var platform: AppFundingPlatform
    /// E.g., https://patreon.com/SomeCreator or https://github.com/Some-App-Org
    public var url: URL
    /// The title of this funding, such as "Support this Creator on Patreon" or "Sponsor the Developer on GitHub".
    public var localizedTitle: String?
    /// The description
    public var localizedDescription: String?

    public init(platform: AppFundingPlatform, url: URL, localizedTitle: String? = nil, localizedDescription: String? = nil) {
        self.platform = platform
        self.url = url
        self.localizedTitle = localizedTitle
        self.localizedDescription = localizedDescription
    }
}

/// A link to a particular funding platform.
public struct AppFundingSource : Codable, Equatable {
    /// E.g., "GITHUB" or "PATREON"
    ///
    /// This list should be harmonized with the funding platforms defined in [FundingPlatform](https://docs.github.com/en/graphql/reference/enums#fundingplatform)
    public var platform: AppFundingPlatform
    /// E.g., https://patreon.com/SomeCreator or https://github.com/Some-App-Org
    public var url: URL
    /// The currently active goals that can be funded
    public let goals: [FundingGoal]

    public init(platform: AppFundingPlatform, url: URL, goals: [AppFundingSource.FundingGoal]) {
        self.platform = platform
        self.url = url
        self.goals = goals
    }

    /// A funding goal, such as reaching a certain monthly donation amount or sponsorship count.
    public struct FundingGoal : Codable, Equatable {
        public var kind: String // e.g. TOTAL_SPONSORS_COUNT or MONTHLY_SPONSORSHIP_AMOUNT
        public var title: String?
        public var description: String?
        public var percentComplete: Double?
        public var targetValue: Double?

        public init(kind: String, title: String? = nil, description: String? = nil, percentComplete: Double? = nil, targetValue: Double? = nil) {
            self.kind = kind
            self.title = title
            self.description = description
            self.percentComplete = percentComplete
            self.targetValue = targetValue
        }
    }
}

/// The platform for an ``AppCatalog``.
public struct AppPlatform : RawCodable, Hashable {
    public var rawValue: String

    public static let macOS = AppPlatform(rawValue: "macos")
    public static let iOS = AppPlatform(rawValue: "ios")
    //public static let tvos = AppPlatform(rawValue: "tvos")
    //public static let watchos = AppPlatform(rawValue: "watchos")
    public static let android = AppPlatform(rawValue: "android")
    //public static let linux = AppPlatform(rawValue: "linux")
    //public static let windows = AppPlatform(rawValue: "windows")

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}


@available(*, deprecated, renamed: "AppCategoryType")
public typealias AppCategory = AppCategoryType

/// The `LSApplicationCategoryType` for an app
public struct AppCategoryType : RawCodable, CaseIterable, Hashable {
    public var rawValue: String

    private static let basePrefix = "public.app-category."

    public static let business = Self(rawValue: "public.app-category.business")
    public static let developertools = Self(rawValue: "public.app-category.developer-tools")
    public static let education = Self(rawValue: "public.app-category.education")
    public static let entertainment = Self(rawValue: "public.app-category.entertainment")
    public static let finance = Self(rawValue: "public.app-category.finance")
    public static let games = Self(rawValue: "public.app-category.games")
    public static let graphicsdesign = Self(rawValue: "public.app-category.graphics-design")
    public static let healthcarefitness = Self(rawValue: "public.app-category.healthcare-fitness")
    public static let lifestyle = Self(rawValue: "public.app-category.lifestyle")
    public static let medical = Self(rawValue: "public.app-category.medical")
    public static let music = Self(rawValue: "public.app-category.music")
    public static let news = Self(rawValue: "public.app-category.news")
    public static let photography = Self(rawValue: "public.app-category.photography")
    public static let productivity = Self(rawValue: "public.app-category.productivity")
    public static let reference = Self(rawValue: "public.app-category.reference")
    public static let socialnetworking = Self(rawValue: "public.app-category.social-networking")
    public static let sports = Self(rawValue: "public.app-category.sports")
    public static let travel = Self(rawValue: "public.app-category.travel")
    public static let utilities = Self(rawValue: "public.app-category.utilities")
    public static let video = Self(rawValue: "public.app-category.video")
    public static let weather = Self(rawValue: "public.app-category.weather")
    public static let actiongames = Self(rawValue: "public.app-category.action-games")
    public static let adventuregames = Self(rawValue: "public.app-category.adventure-games")
    public static let arcadegames = Self(rawValue: "public.app-category.arcade-games")
    public static let boardgames = Self(rawValue: "public.app-category.board-games")
    public static let cardgames = Self(rawValue: "public.app-category.card-games")
    public static let casinogames = Self(rawValue: "public.app-category.casino-games")
    public static let dicegames = Self(rawValue: "public.app-category.dice-games")
    public static let educationalgames = Self(rawValue: "public.app-category.educational-games")
    public static let familygames = Self(rawValue: "public.app-category.family-games")
    public static let kidsgames = Self(rawValue: "public.app-category.kids-games")
    public static let musicgames = Self(rawValue: "public.app-category.music-games")
    public static let puzzlegames = Self(rawValue: "public.app-category.puzzle-games")
    public static let racinggames = Self(rawValue: "public.app-category.racing-games")
    public static let roleplayinggames = Self(rawValue: "public.app-category.role-playing-games")
    public static let simulationgames = Self(rawValue: "public.app-category.simulation-games")
    public static let sportsgames = Self(rawValue: "public.app-category.sports-games")
    public static let strategygames = Self(rawValue: "public.app-category.strategy-games")
    public static let triviagames = Self(rawValue: "public.app-category.trivia-games")
    public static let wordgames = Self(rawValue: "public.app-category.word-games")

    public static var allCases: [Self] {
        return [
            .business,
            .developertools,
            .education,
            .entertainment,
            .finance,
            .games,
            .graphicsdesign,
            .healthcarefitness,
            .lifestyle,
            .medical,
            .music,
            .news,
            .photography,
            .productivity,
            .reference,
            .socialnetworking,
            .sports,
            .travel,
            .utilities,
            .video,
            .weather,
            .actiongames,
            .adventuregames,
            .arcadegames,
            .boardgames,
            .cardgames,
            .casinogames,
            .dicegames,
            .educationalgames,
            .familygames,
            .kidsgames,
            .musicgames,
            .puzzlegames,
            .racinggames,
            .roleplayinggames,
            .simulationgames,
            .sportsgames,
            .strategygames,
            .triviagames,
            .wordgames,
        ]
    }

    public var id: Self { self }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Takes the given base string and create a known category for it.
    public static func valueFor(base: String, validate: Bool) -> Self? {
        let value = Self(rawValue: basePrefix + base)
        if validate && !allCases.contains(value) {
            return nil
        }
        return value
    }

    /// The base underlying value.
    ///
    /// E.g., `public.app-category.productivity` becomes `productivity`
    public var baseValue: String {
        String(rawValue.dropFirst(Self.basePrefix.count))
    }

}


/// A funding platform, which is represented by a raw string.
///
/// Known platforms can be accessed with ``allCases``.
public struct AppFundingPlatform : RawCodable, Hashable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}


// MARK: Extensions


extension AppFundingPlatform : CaseIterable {
    /// All the known funding platforms, both supported and unsupported.
    ///
    /// - See: ``isSupported``
    public static let allCases: [AppFundingPlatform] = [
        .COMMUNITY_BRIDGE,
        .GITHUB,
        .ISSUEHUNT,
        .KO_FI,
        .LIBERAPAY,
        .OPEN_COLLECTIVE,
        .OTECHIE,
        .PATREON,
        .TIDELIFT,
        //.CUSTOM
    ]

    /// GitHub funding platform. [https://github.com/](https://github.com/)
    public static let GITHUB = AppFundingPlatform(rawValue: "GITHUB")

    /// Patreon funding platform. [https://patreon.com](https://patreon.com)
    public static let PATREON = AppFundingPlatform(rawValue: "PATREON")

    /// Community Bridge funding platform: [https://funding.communitybridge.org](https://funding.communitybridge.org)
    public static let COMMUNITY_BRIDGE = AppFundingPlatform(rawValue: "COMMUNITY_BRIDGE")

    /// IssueHunt funding platform. [https://issuehunt.io](https://issuehunt.io)
    public static let ISSUEHUNT = AppFundingPlatform(rawValue: "ISSUEHUNT")

    /// Ko-fi funding platform. [https://ko-fi.com](https://ko-fi.com)
    public static let KO_FI = AppFundingPlatform(rawValue: "KO_FI")

    /// Liberapay funding platform. [https://liberapay.com](https://liberapay.com)
    public static let LIBERAPAY = AppFundingPlatform(rawValue: "LIBERAPAY")

    /// Open Collective funding platform. [https://opencollective.com](https://opencollective.com)
    public static let OPEN_COLLECTIVE = AppFundingPlatform(rawValue: "OPEN_COLLECTIVE")

    /// Otechie funding platform. [https://otechie.com](https://otechie.com)
    public static let OTECHIE = AppFundingPlatform(rawValue: "OTECHIE")

    /// Tidelift funding platform. [https://tidelift.com](https://tidelift.com)
    public static let TIDELIFT = AppFundingPlatform(rawValue: "TIDELIFT")

    /// Custom funding platform. Not supported
    @available(*, unavailable, message: "custom funding sources are not supported")
    static let CUSTOM = AppFundingPlatform(rawValue: "CUSTOM")

    /// Returns `true` if the funding platform is known and supported.
    public var isSupported: Bool {
        switch self {
        case .GITHUB: return true
        case .PATREON: return true

        case .KO_FI: return false
        case .OTECHIE: return false
        case .TIDELIFT: return false
        case .ISSUEHUNT: return false
        case .LIBERAPAY: return false
        case .OPEN_COLLECTIVE: return false
        case .COMMUNITY_BRIDGE: return false

        case _: return false
        }
    }

    /// The localized name of the funding platform
    public var platformName: String? {
        switch self {
        case .GITHUB: return NSLocalizedString("GitHub", bundle: .module, comment: "funding platform name for GitHub")
        case .COMMUNITY_BRIDGE: return NSLocalizedString("Community Bridge", bundle: .module, comment: "funding platform name for Community Bridge")
        case .ISSUEHUNT: return NSLocalizedString("IssueHunt", bundle: .module, comment: "funding platform name for IssueHunt")
        case .KO_FI: return NSLocalizedString("Ko-fi", bundle: .module, comment: "funding platform name for Ko-fi")
        case .LIBERAPAY: return NSLocalizedString("Liberapay", bundle: .module, comment: "funding platform name for Liberapay")
        case .OPEN_COLLECTIVE: return NSLocalizedString("Open Collective", bundle: .module, comment: "funding platform name for Open Collective")
        case .OTECHIE: return NSLocalizedString("Otechie", bundle: .module, comment: "funding platform name for Otechie")
        case .PATREON: return NSLocalizedString("Patreon", bundle: .module, comment: "funding platform name for Patreon")
        case .TIDELIFT: return NSLocalizedString("Tidelift", bundle: .module, comment: "funding platform name for Tidelift")
        case _: return nil
        }
    }

    /// Checks that the given link is valid for the known funding platform
    public func serviceIdentifier(from url: URL) -> String? {
        func trimming(_ source: String) -> String? {
            let urlString = url.absoluteString
            if !urlString.hasPrefix(source) { return nil }
            return urlString.dropFirst(source.count).description
        }

        switch self {
        case .GITHUB: return trimming("https://github.com/") // USERNAME
        case .COMMUNITY_BRIDGE: return trimming("https://funding.communitybridge.org/projects/") // PROJECT-NAME
        case .ISSUEHUNT: return trimming("https://issuehunt.io/r/") // USERNAME
        case .KO_FI: return trimming("https://ko-fi.com/") // USERNAME
        case .LIBERAPAY: return trimming("https://liberapay.com/") // USERNAME
        case .OPEN_COLLECTIVE: return trimming("https://opencollective.com/") // USERNAME
        case .OTECHIE: return trimming("https://otechie.com/") // USERNAME
        case .PATREON: return trimming("https://patreon.com/") // USERNAME
        case .TIDELIFT: return trimming("https://tidelift.com/funding/") // github/PLATFORM-NAME/PACKAGE-NAME
        case _: return nil // unknown platform is never valid
        }
    }

    /// A URL is valid for a specific funding source if it matches a known pattern and the platform is supported
    public func isValidURL(_ url: URL) -> Bool {
        isSupported && (serviceIdentifier(from: url) != nil)
    }
}

extension AppFundingLink {
    /// Checks that the given link is valid for the known funding platform
    public func isValidFundingURL() -> Bool {
        self.platform.isValidURL(self.url)
    }

    public var fundingURL: URL? {
        guard let id = self.platform.serviceIdentifier(from: self.url) else {
            return nil // not a supported platform
        }

        switch self.platform {
        case .GITHUB: return URL(string: "http://github.com/sponsors/\(id)")
        default: return self.url // default platform just uses the identifier link directly
        }
    }
}

public extension AltCatalogAppItem {

    /// The hyphenated form of this app's name
    var appNameHyphenated: String {
        self.name.rehyphenated()
    }

    /// The official landing page for the app
    var landingPage: URL? {
        URL(string: "https://\(appNameHyphenated).github.io/App/")
    }

    /// Returns the URL to this app's home page
    var projectURL: URL? {
        URL(string: "https://github.com/\(appNameHyphenated)/App/")
    }

    /// The e-mail address for contacting the developer
    var developerEmail: String? {
        developerName // TODO: parse out
    }

    /// Returns the URL to this app's home page
    var sourceURL: URL? {
        projectURL?.appendingPathExtension("git")
    }

    var issuesURL: URL? {
        URL(string: "issues", relativeTo: projectURL)
    }

    var discussionsURL: URL? {
        URL(string: "discussions", relativeTo: projectURL)
    }

    var stargazersURL: URL? {
        URL(string: "stargazers", relativeTo: projectURL)
    }

    var releasesURL: URL? {
        URL(string: "releases/", relativeTo: projectURL)
    }

    var developerURL: URL? {
        queryURL(type: "users", term: developerEmail ?? "")
    }

    /// Builds a general query
    private func queryURL(type: String, term: String) -> URL? {
        URL(string: "https://github.com/search?type=" + type.escapedURLTerm + "&q=" + term.escapedURLTerm)
    }
}

