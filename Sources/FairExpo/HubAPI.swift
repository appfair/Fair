import Foundation
import FairCore

/// The repository name for the base fairground. It is "App".
public let baseFairgroundRepoName = "App"

/// The organization name of the fair-ground: `"appfair"`
/// @available(*, deprecated, message: "move to hub configuration")
public let appfairName = "appfair"

public let appfairRoot = URL(string: "https://appfair.net")!

/// A Fair Ground based on an online git service such as GitHub or GitLab.
public struct FairHub : GraphQLEndpointService {
    /// The root of the FairGround-compatible service
    public var baseURL: URL

    /// The organization in the hub
    public var org: String

    /// The authorization token for this request, if any
    public var authToken: String?

    /// The username of the issuer of the fairseal, user for querying purposes
    public var fairsealIssuer: String?

    /// The signing key for the seal data, used to authenticate payloads
    public var fairsealKey: Data?

    public typealias BaseFork = FairHub.CatalogForksQuery.QueryResponse.BaseRepository.Repository

    /// The FairHub is initialized with a host identifier (e.g., "github.com/appfair") that corresponds to the hub being used.
    public init(hostOrg: String, authToken: String? = nil, fairsealIssuer: String?, fairsealKey: Data?) throws {
        guard let url = URL(string: "https://api." + hostOrg) else {
            throw Errors.badHostOrg(hostOrg)
        }

        self.org = url.lastPathComponent
        self.baseURL = url.deletingLastPathComponent()
        self.authToken = authToken
        self.fairsealIssuer = fairsealIssuer
        self.fairsealKey = fairsealKey

        if org.isEmpty {
            throw Errors.emptyOrganization(url)
        }
        if self.baseURL.path != "/" {
            throw Errors.notTopLevelURL(url)
        }
        if self.baseURL.scheme != "https" {
            throw Errors.badURLScheme(url)
        }
        if let authToken = authToken {
            if authToken.isEmpty {
                throw Errors.emptyAuthToken
            }
        }
    }

    /// The hardwired code that returns an HTTP error but contains information about backing off
    /// 403 is just retry
    /// 502 sometimes happens with large responses
    public static var backoffCodes: IndexSet { IndexSet([403, 502]) }
}

public struct ArtifactTarget : Codable, Hashable {
    public let artifactType: String
    public let devices: Array<String>

    public init(artifactType: String, devices: Array<String>) {
        self.artifactType = artifactType
        self.devices = devices
    }
}

extension FairHub {
    public struct ProjectConfiguration {
        /// The regular expression patterns of allowed app names
        public var allowName: [NSRegularExpression]

        /// The regular expression patterns of disallowed app names
        public var denyName: [NSRegularExpression]

        /// The regular expression patterns of allowed e-mail addresses
        public var allowFrom: [NSRegularExpression]

        /// The regular expression patterns of disallowed e-mail addresses
        public var denyFrom: [NSRegularExpression]

        /// The license (SPDX IDs) of permitted licenses, such as: "AGPL-3.0"
        public var allowLicense: [String]

        public init(allowName: [String] = [], denyName: [String] = [], allowFrom: [String] = [], denyFrom: [String] = [], allowLicense: [String] = []) throws {
            let regexs = { try NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
            self.allowFrom = try allowFrom.map(regexs)
            self.denyFrom = try denyFrom.map(regexs)
            self.allowName = try allowName.map(regexs)
            self.denyName = try denyName.map(regexs)

            self.allowLicense = allowLicense
        }

        /// Validates that the app name is included in the `allow-name` patterns and not included in the `deny-name` list of expressions.
        public func validateAppName(_ name: String?) throws {
            guard let name = name, try permitted(value: name, allow: allowName, deny: denyName) == true else {
                throw FairHub.Errors.invalidName(name)
            }
        }

        private func permitted(value: String, allow: [NSRegularExpression], deny: [NSRegularExpression]) throws -> Bool {
            func matches(pattern: NSRegularExpression) -> Bool {
                pattern.firstMatch(in: value, options: [], range: value.span) != nil
            }

            // if we specified an allow list, then at least one of the patterns must match the email
            if !allow.isEmpty {
                guard let _ = allow.first(where: matches) else {
                    throw FairHub.Errors.valueNotAllowed(value)
                }
            }

            // conversely, if we specified a deny list, then all the addresses must not match
            if !deny.isEmpty {
                if let _ = deny.first(where: matches) {
                    throw FairHub.Errors.valueDenied(value)
                }
            }

            return true
        }

        /// Validates that the e-mail address is included in the `allow-from` patterns and not included in the `deny-from` list of expressions.
        func validateEmailAddress(_ email: String?) throws {
    //        guard let email = email, try permitted(value: email, allow: allowFrom, deny: denyFrom) == true else {
    //            throw Errors.invalidEmail(email)
    //        }
        }

    }

    public func buildFundingSources(owner: String, baseRepository: String) async throws -> [AppFundingSource] {
        var sources: [AppFundingSource] = []

        func createSponsor(from sponsor: FairHub.GetSponsorsQuery.QueryResponse.Repository.SponsorsListing, url: URL) -> AppFundingSource {
            var goals: [AppFundingSource.FundingGoal] = []
            if let activeGoal = sponsor.activeGoal,
                let goalKind = activeGoal.kind?.rawValue {
                let goal = AppFundingSource.FundingGoal(kind: goalKind, title: activeGoal.title, description: activeGoal.description, percentComplete: activeGoal.percentComplete, targetValue: activeGoal.targetValue)
                goals.append(goal)
            }

            return AppFundingSource(platform: .GITHUB, url: url, goals: goals)
        }


        for try await forks in requestBatchedStream(GetSponsorsQuery(owner: owner, name: baseRepository)) {
            let rootOwner = try forks.get().data.repository.owner
            if sources.isEmpty,
                let rootSponsor = rootOwner.sponsorsListing,
                let url = rootOwner.url.flatMap(URL.init(string:)) {
                // always add the root repo's funding first
                sources.append(createSponsor(from: rootSponsor, url: url))
            }
            for node in try forks.get().data.repository.forks.nodes {
                if let sponsorListing = node.sponsorsListing,
                   let url = node.owner.url.flatMap(URL.init(string:)) {
                    sources.append(createSponsor(from: sponsorListing, url: url))
                }
            }
        }

        return sources
    }

    public func validate(org: RepositoryQuery.QueryResponse.Organization, configuration: ProjectConfiguration) -> AppOrgValidationFailure {
        let repo = org.repository
        let isOrigin = org.login == appfairName
        var invalid: AppOrgValidationFailure = []

        if !isOrigin {
            do {
                try AppNameValidation.standard.validate(name: org.login) 
                try configuration.validateAppName(org.login)
            } catch {
                invalid.insert(.invalidName)
            }
        }

        if org.isVerified != true {
            // invalid.insert(.notVerified)
            // we do not currently require that organizations be verified
        }

        if !org.isOrganization {
            invalid.insert(.ownerNotOrganization)
        }

        if !repo.isInOrganization {
            invalid.insert(.ownerNotOrganization)
        }

        if !isOrigin {
            do {
                try configuration.validateEmailAddress(org.email)
            } catch {
                invalid.insert(.invalidEmail)
            }
        }

        if repo.isArchived {
            invalid.insert(.isArchived)
        }

        if repo.isDisabled {
            invalid.insert(.isDisabled)
        }

        if repo.isPrivate {
            invalid.insert(.isPrivate)
        }

        if !isOrigin && !repo.hasIssuesEnabled {
            invalid.insert(.noIssues)
        }

        // there's no "hasDiscussionsEnabled" key, but the count of categories will be zero if discussions are not enabled
        if !isOrigin && repo.discussionCategories.totalCount <= 0 {
           invalid.insert(.noDiscussions)
        }

        if !configuration.allowLicense.isEmpty && !configuration.allowLicense.contains(repo.licenseInfo.spdxId ?? "none") {
            //dbg(allowLicense)
            invalid.insert(.invalidLicense)
        }

        return invalid
    }

    /// The varios reasons why an organization or repository might be invalid
    public struct AppOrgValidationFailure : OptionSet, CustomStringConvertible {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let isPrivate = AppOrgValidationFailure(rawValue: 1 << 0)
        public static let isArchived = AppOrgValidationFailure(rawValue: 1 << 1)
        public static let noIssues = AppOrgValidationFailure(rawValue: 1 << 2)
        public static let noDiscussions = AppOrgValidationFailure(rawValue: 1 << 3)
        public static let invalidLicense = AppOrgValidationFailure(rawValue: 1 << 4)
        public static let isDisabled = AppOrgValidationFailure(rawValue: 1 << 5)
        public static let notVerified = AppOrgValidationFailure(rawValue: 1 << 6)
        public static let invalidEmail = AppOrgValidationFailure(rawValue: 1 << 7)
        public static let invalidName = AppOrgValidationFailure(rawValue: 1 << 8)
        public static let ownerNotOrganization = AppOrgValidationFailure(rawValue: 1 << 9)
        public static let mismatchedEmail = AppOrgValidationFailure(rawValue: 1 << 10)

        public var description: String {
            [
                contains(.isPrivate) ? "Repository must be public" : nil,
                contains(.isArchived) ? "Repository must not be archived" : nil,
                contains(.noIssues) ? "Repository must have issues enabled" : nil,
                contains(.noDiscussions) ? "Repository must have discussions enabled" : nil,
                contains(.invalidLicense) ? "Repository must use an approved license" : nil,
                contains(.isDisabled) ? "Repository must not be disabled" : nil,
                contains(.notVerified) ? "Organization must be verified" : nil,
                contains(.invalidEmail) ? "The e-mail for the organization must be public and match the approved list" : nil,
                contains(.invalidName) ? "The name of the organization is not valid" : nil,
                contains(.ownerNotOrganization) ? "The owner of the repository must be an organization and not an individual user" : nil,
                contains(.mismatchedEmail) ? "The e-mail for the commit must match the public e-mail of the organization" : nil,
            ].compactMap({ $0 }).joined(separator: ", ")
        }
    }

    /// Posts the fairseal to the most recent open PR that matches the download URL's appOrg
    public func postFairseal(_ fairseal: FairSeal, owner: String, baseRepository: String, issueNumber: Int?) async throws -> URL {
        guard let appOrg = fairseal.appOrg else {
            dbg("no app org for seal:", fairseal)
            throw Errors.noAppOrg(fairseal)
        }

        let nameWithOwner = appOrg + "/" + baseRepository

        let prid = try await fetchPRID()
        func fetchPRID() async throws -> FairHub.OID {
            if let issueNumber = issueNumber {
                // the issue number was explicitly specified; look up the PR issue by number
                return try await self.request(LookupPRNumberQuery(owner: owner, name: baseRepository, prid: issueNumber)).get().data.repository.pullRequest.id
            } else {
                // with no issue number specified, search through the open PR requests for the correct issue
                let lookupPRsRequest = FindPullRequests(owner: owner, name: baseRepository, state: .OPEN)
                let appPR = try await self.requestBatches(lookupPRsRequest) { resultIndex, urlResponse, batch in
                    try batch.result.get().data.repository.pullRequests.nodes.first { edge in
                        edge.state == .OPEN
                        //&& edge.mergeable != "CONFLICTING"
                        && edge.headRepository?.nameWithOwner == (nameWithOwner)
                    }
                }

                guard let appPR = appPR else {
                    dbg("no PRs found for \(appOrg)")
                    throw Errors.noPRFound(appOrg)
                }

                return appPR.id
            }
        }

        var signedSeal = fairseal
        if let key = self.fairsealKey {
            // sign the key if we have specified one
            try signedSeal.embedSignature(key: key)
        }

        let sealJSON = try signedSeal.toJSON(outputFormatting: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let sealComment = "```\n" + (sealJSON.utf8String ?? "") + "\n```"
        let postResponse = try await self.request(PostCommentQuery(id: prid, comment: sealComment)).get()
        let sealCommentURL = postResponse.data.addComment.commentEdge.node.url // e.g.: https://github.com/appfair/App/pull/72#issuecomment-924952591

        dbg("posted fairseal for:", fairseal.assets?.first?.url.absoluteString, "to:", sealCommentURL.absoluteString)

        return sealCommentURL
    }

    /// Checks the commit info to ensure that it is verified, and if so, returns the author information
    public func authorize(commit: CommitInfo) throws {
        let info = commit.repository.object
        //guard let verification = info.signature else {
            //throw Errors.noVerification(commit)
        //}

//        if verification.state != .VALID || verification.isValid == false {
//            throw Errors.invalidVerification(commit)
//        }

        guard let name = info.author?.name, !name.isEmpty else {
            throw Errors.noAuthor(commit)
        }

//        guard let email = info.author?.email, !email.isEmpty else {
//            throw Errors.invalidEmail(info.author?.email)
//        }

        // TODO: email isn't sent as part of owner; will need to match org-email and commit-email using a separate request
//        if email != info.owner.email {
//            throw Errors.mismatchedEmail(info.author?.email, info.owner.email)
//        }

//        try validateEmailAddress(email)
    }


    public enum Errors : LocalizedError {
        case emptyAuthToken
        case badHostOrg(String)
        case noPRFound(String)
        case emptyOrganization(URL)
        case notTopLevelURL(URL)
        case badURLScheme(URL)
        case noVerification(CommitInfo)
        case invalidVerification(CommitInfo)
        case noAuthor(CommitInfo)
        case invalidEmail(String?)
        case invalidName(String?)
        case valueNotAllowed(String?)
        case valueDenied(String?)
        case mismatchedEmail(String?, String?)
        case invalidSealHash(String?)
        case noAppOrg(FairSeal)
        case repoInvalid(_ reasons: AppOrgValidationFailure, _ org: String, _ repo: String)
        case missingFairsealIssuer

        public var errorDescription: String? {
            switch self {
            case .noAppOrg: return "No app organization"
            case .emptyAuthToken: return "No authorization token specified"
            case .badHostOrg(let string): return "Invalid fairground host/org: \(string)"
            case .emptyOrganization(let url): return "Missing organization name in URL: \"\(url.absoluteString)\""
            case .notTopLevelURL(let url): return "Not a top-level URL: \"\(url.absoluteString)\""
            case .badURLScheme(let url): return "Bad URL scheme: \"\(url.absoluteString)\""
            case .noVerification(let info): return "No verification information for commit ref: \"\(info.repository.object.oid.rawValue)\". Release tag commits must be marked 'verified', which means either performing the tag via the web interface, or else GPG signing the release tag."
            case .invalidVerification(let info): return "Commit ref must be verified as valid, but was: \"\(info.repository.object.signature?.state.rawValue ?? "empty")\". Release tag commits must be marked 'verified', which means either performing the tag via the web interface, or else GPG signing the release tag."
            case .noAuthor(let info): return "The author was empty for the commit: \"\(info.repository.object.oid.rawValue)\""
            case .invalidEmail(let email): return "The email address \"\(email ?? "")\" is not accepted"
            case .invalidName(let name): return "The app name \"\(name ?? "")\" is not accepted"
            case .valueNotAllowed(let value): return "The value \"\(value ?? "")\" is not allowed"
            case .valueDenied(let value): return "The value \"\(value ?? "")\" is not permitted"
            case .mismatchedEmail(let repoEmail, let orgEmail): return "The email address \"\(repoEmail ?? "")\" for the commit must match the public e-mail for the organization \"\(orgEmail ?? "")\""
            case .invalidSealHash(let hash): return "The fair seal hash has an invalid number of characters: \(hash?.count ?? 0)"
            case .repoInvalid(let reasons, let org, let repo): return "The repository \"\(org)/\(repo)\" is invalid because: \(reasons)"
            case .missingFairsealIssuer: return "Missing fairseal-issuer flag"
            case .noPRFound(_): return "No PR found"
            }
        }
    }

    public struct RepositoryOwner : Hashable, Decodable {
        public enum TypeName : String, Hashable, Decodable { case User, Organization }
        public let __typename: TypeName
        public var login: String

        // these can all be null for an app forked by a user due to the `... on Organization { }` clause

        ///  The organization's public email.
        public let email: String?
        /// Whether the organization has verified its profile email and website.
        public let isVerified: Bool?
        /// The organization's public profile URL.
        public let websiteUrl: URL?
        /// Identifies the date and time when the object was created.
        public let createdAt: Date?
        /// True if this user/organization has a GitHub Sponsors listing.
        public let hasSponsorsListing: Bool?
        /// The estimated monthly GitHub Sponsors income for this user/organization in cents (USD).
        public let monthlyEstimatedSponsorsIncomeInCents: Double?

        public var isOrganization: Bool { __typename == .Organization }

        /// The app name is simply the "Org-Name" without dashes: "Org Name"
        public var appNameWithSpace: String {
            login.dehyphenated()
        }

        /// The app name is simply the "Org-Name"
        public var appNameWithHyphen: String {
            login // .rehyphenated()
        }
    }
}

extension AltCatalogAppItem {
    /// The list of folders (with optional tilde) for deleting the app with the given bundle ID.
    ///
    /// The files and folders may not exist, but these are the potential locations that will be removed.
    public var installationDataLocations: [String] {
        bundleIdentifier.map({ bundleIdentifier in
            [
                "~/Library/Application Scripts/\(bundleIdentifier)",
                "~/Library/Application Support/\(bundleIdentifier)",
                "~/Library/Caches/\(bundleIdentifier)",
                "~/Library/Containers/\(bundleIdentifier)",
                "~/Library/HTTPStorages/\(bundleIdentifier)",
                "~/Library/HTTPStorages/\(bundleIdentifier).binarycookies",
                "~/Library/Preferences/\(bundleIdentifier).plist",
                "~/Library/Saved Application State/\(bundleIdentifier).savedState",
            ]
        }) ?? []
    }

    /// Returns the list of file URLs for the app's potential installation data
    public func installationAuxiliaryURLs(checkExists: Bool) -> [URL] {
        installationDataLocations
            .map { ($0 as NSString).expandingTildeInPath }
            .filter { checkExists == false || FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }
}

extension AltCatalogAppItem {
    /// Ingest the given catalog JSON by parsing it and including all the non-optional properties into this catalog item.
    internal mutating func ingest(json: String, fence: String = "```", prefix: String? = "json") throws -> Bool {
        var json = json.trimmed()
        if !json.hasPrefix(fence) || !json.hasSuffix(fence) {
            return false
        }

        json = String(json.dropLast(fence.count).dropFirst(fence.count))
        if let prefix = prefix, json.hasPrefix(prefix) {
            json = String(json.dropFirst(prefix.count)) // permit code fence to start with "```json" for syntax highlighting in markdown editor. E.g.:
        }
        json = json.trimmed()
        var jobj = try JSON(fromJSON: json.utf8Data).object ?? JSON.Object()

        // inject the mandatory properties
        jobj["name"] = self.name.parameterValue
        jobj["bundleIdentifier"] = self.bundleIdentifier?.parameterValue
//        jobj["downloadURL"] = self.downloadURL?.absoluteString.parameterValue

        // FIXME: this is slow because we are converting the Plist to JSON and then parsing it back into an AltCatalogAppItem
        let appItem = try AltCatalogAppItem(json: jobj.json())
        self = appItem
        return true
    }
}


fileprivate extension Dictionary {
    func percentEncoded() -> Data? {
        return map { key, value in
            let escapedKey = "\(key)".escapedURLTerm
            let escapedValue = "\(value)".escapedURLTerm
            return escapedKey + "=" + escapedValue
        }
        .joined(separator: "&")
        .data(using: .utf8)
    }
}

extension AltCatalogAppItem {
    public struct Diff {
        public let new: AltCatalogAppItem
        public let old: AltCatalogAppItem?
    }
}


public extension URL {

    /// Returns the URL for this app's hub page
    static func fairHubURL(_ path: String? = nil) -> URL? {
        guard let appOrgName = Bundle.main.appOrgName else {
            return nil
        }

        guard let baseURL = URL(string: "https://www.github.com/") else {
            return nil
        }

        return baseURL
            .appendingPathComponent(appOrgName)
            .appendingPathComponent(baseFairgroundRepoName)
            .appendingPathComponent(path ?? "")
    }
}

extension String {
    /// Checks whether the string contains the given regular expression.
    /// - Parameters:
    ///   - regex: the expression to parse
    ///   - expressionOptions: options like `.caseInsensitive` and `.anchorsMatchLines`
    ///   - matchingOptions: options like `.anchored`
    /// - Returns: whether the string matches or not
    @inlinable public func matches(regex: String, expressionOptions: NSRegularExpression.Options? = nil, matchingOptions: NSRegularExpression.MatchingOptions = []) throws -> Bool {
        let regex = try NSRegularExpression(pattern: regex, options: expressionOptions ?? [])
        return regex.matches(in: self, options: matchingOptions, range: self.span).isEmpty == false
    }
}

/// A generic error
public struct AppError : LocalizedError {
    /// A localized message describing what error occurred.
    public let errorDescription: String?

    /// A localized message describing the reason for the failure.
    public let failureReason: String?

    /// A localized message describing how one might recover from the failure.
    public let recoverySuggestion: String?

    /// A localized message providing "help" text if the user requests help.
    public let helpAnchor: String?

    /// An underlying error
    public let underlyingError: Error?

    @available(*, deprecated, message: "use error message constructor")
    public init(function: StaticString = #function, file: StaticString = #file, line: UInt = #line) {
        self.init("Error at \(function) in \(file):\(line)")
    }

    public init(_ errorDescription: String, failureReason: String? = nil, recoverySuggestion: String? = nil, helpAnchor: String? = nil, underlyingError: Error? = nil) {
        self.errorDescription = errorDescription
        self.failureReason = failureReason
        self.recoverySuggestion = recoverySuggestion
        self.helpAnchor = helpAnchor
        self.underlyingError = underlyingError
    }

    public init(_ error: Error) {
        if let error = error as? AppError {
            self.errorDescription = error.errorDescription
            self.failureReason = error.failureReason
            self.recoverySuggestion = error.recoverySuggestion
            self.helpAnchor = error.helpAnchor
            self.underlyingError = error.underlyingError
        } else {
            #if canImport(AppKit) || canImport(UIKit)
            let nsError = error as NSError
            self.errorDescription = nsError.localizedDescription
            self.failureReason = nsError.localizedFailureReason
            self.recoverySuggestion = nsError.localizedRecoverySuggestion
            self.helpAnchor = nsError.helpAnchor
            if #available(macOS 11.3, iOS 14.5, *) {
                self.underlyingError = nsError.underlyingErrors.first
            } else {
                self.underlyingError = nil
            }
            #else // NSError bridge on other platforms does not expose properties
            if let locError = error as? LocalizedError {
                self.errorDescription = locError.errorDescription
                self.failureReason = locError.failureReason
                self.recoverySuggestion = locError.recoverySuggestion
                self.helpAnchor = locError.helpAnchor
                self.underlyingError = nil
            } else {
                self.errorDescription = error.localizedDescription
                self.failureReason = nil
                self.recoverySuggestion = nil
                self.helpAnchor = nil
                self.underlyingError = nil
            }
            #endif
        }
    }
}

