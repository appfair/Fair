import Foundation
import FairCore

/// The repository name for the base fairground. It is "App".
public let baseFairgroundRepoName = "App"

/// The organization name of the fair-ground: `"appfair"`
/// @available(*, deprecated, message: "move to hub configuration")
public let appfairName = "appfair"

public let appfairRoot = URL(string: "https://appfair.net")!

/// The canonical location of the catalog for the Fair Ground
public let appfairCatalogURLMacOS = URL(string: "fairapps-macos.json", relativeTo: appfairRoot)!

/// The canonical location of the iOS catalog for the Fair Ground
public let appfairCatalogURLIOS = URL(string: "fairapps-ios.json", relativeTo: appfairRoot)!

/// The canonical location of the enhanced cask app metadata
public let appfairCaskAppsURL = URL(string: "appcasks.json", relativeTo: appfairRoot)!

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

//    /// Generates the catalog by fetching all the valid forks of the base fair-ground and associating them with the fairseals published by the fairsealIssuer.
//    public func buildAppCatalog(title: String, identifier: String, owner: String, sourceURL: URL? = nil, baseRepository: String, fairsealCheck: Bool, artifactTarget: ArtifactTarget?, configuration: ProjectConfiguration, requestLimit: Int?) async throws -> AppCatalog {
//        // all the seal hashes we will look up to validate releases
//        dbg("fetching fairseals")
//
//        var apps: [AltCatalogItem] = []
//        var forkBaseRepos = [(owner, baseRepository)]
//        while let (owner, repo) = forkBaseRepos.first {
//            forkBaseRepos.removeFirst()
//
//            for try await catalogApps in createAltCatalogItemsFromForks(title: title, owner: owner, baseRepository: repo, fairsealCheck: fairsealCheck, artifactTarget: artifactTarget, configuration: configuration, requestLimit: requestLimit) {
//                for app in catalogApps {
//                    apps.append(app)
//                    // TODO: how best to recurse into forks?
////                    if let stats = app.stats, let forkCount = stats.forkCount, forkCount > 0 {
////                        forkBaseRepos.append((app.appNameHyphenated, baseRepository))
////                    }
//                }
//            }
//        }
//        let news: [AppNewsPost]? = nil
//
//        // try sorting by download count, and then bundle identifier (for consistency)
//        // in the future, more sophisticated rankings may be used here
//        apps.sort { lhs, rhs in
//            if let dl1 = lhs.stats?.downloadCount,
//                let dl2 = rhs.stats?.downloadCount {
//                return dl1 > dl2
//            }
//            return lhs.bundleIdentifier ?? lhs.name < rhs.bundleIdentifier ?? rhs.name
//        }
//
//        let macOS = artifactTarget?.devices.contains("mac") == true
//        let iOS = macOS == false && artifactTarget != nil // artifactTarget?.devices.contains("ios") == true
//        let catalogURL = sourceURL
//        let catalog = AppCatalog(name: title, identifier: identifier, platform: macOS ? .macOS : iOS ? .iOS : nil, sourceURL: catalogURL, apps: apps, news: news)
//        return catalog
//    }
//
//    func createAltCatalogItemsFromForks(title: String, owner: String, baseRepository: String, fairsealCheck: Bool, artifactTarget: ArtifactTarget?, configuration: ProjectConfiguration, requestLimit: Int?) -> AsyncThrowingMapSequence<AsyncThrowingStream<CatalogForksQuery.Response, Error>, [AltCatalogItem]> {
//        requestBatchedStream(CatalogForksQuery(owner: owner, name: baseRepository))
//            .map { forks in try assembleCatalog(fromForks: forks, artifactTarget: artifactTarget, fairsealCheck: fairsealCheck, configuration: configuration) }
//    }
//
//    private func assembleCatalog(fromForks forks: CatalogForksQuery.Response, artifactTarget: ArtifactTarget?, fairsealCheck: Bool, configuration: ProjectConfiguration) throws -> [AltCatalogItem] {
//        let forkNodes = try forks.result.get().data.repository.forks.nodes
//        //dbg(forkNodes.map(\.nameWithOwner))
//        var apps: [AltCatalogItem] = []
//
//        for fork in forkNodes {
//            dbg("checking app fork:", fork.owner.appNameWithSpace, fork.name)
//            // #warning("TODO validation")
//            // let invalid = validate(org: fork.owner)
//            // if !invalid.isEmpty {
//            //     throw Errors.repoInvalid(invalid, org, fork.name)
//            // }
//
//            let starCount = fork.stargazerCount
//            let watcherCount = fork.watchers.totalCount
//            let issueCount = fork.issues.totalCount
//            let forkCount = fork.forkCount
//
//            let fundingLinks = fork.fundingLinks
//
//            // get the "appfair-utilities" topic and convert it to the standard "public.app-category.utilities"
//            let categories = (fork.repositoryTopics.nodes ?? []).map(\.topic.name).compactMap({
//                AppCategoryType.valueFor(base: $0, validate: true)
//            })
//
//            let appName = fork.owner.login
//
//            do {
//                try configuration.validateAppName(appName)
//            } catch {
//                // skip packages whose names are not valid
//                dbg(fork.nameWithOwner, "invalid app name:", error)
//                continue
//            }
//
//            // with no fairseal issuer we simply index the bare forks themselves
//            guard let fairsealIssuer = fairsealIssuer else {
//                let appTitle = fork.name
//                var app = AltCatalogItem(name: appTitle)
//
//                // TODO: specify downloadBase as a parameter to the command
//                if let downloadBase = URL(string: "https://github.com/") {
//                    let forkURL = downloadBase.appendingPathComponent(fork.nameWithOwner)
//                    app.downloadURL = forkURL
//                }
//
//                app.subtitle = fork.description
//                // app.localizedDescription = localizedDescription
//                app.categories = (categories.isEmpty ? nil : categories)
//                app.fundingLinks = (fundingLinks.isEmpty ? nil : fundingLinks)?.map { link in
//                    AppFundingLink(platform: link.platform, url: link.url)
//                }
//                app.stats = AppStats(starCount: starCount == 0 ? nil : starCount, watcherCount: watcherCount == 0 ? nil : watcherCount, issueCount: issueCount == 0 ? nil : issueCount, forkCount: forkCount == 0 ? nil : forkCount)
//
//                apps.append(app)
//                continue
//            }
//
//            let appTitle = fork.owner.appNameWithSpace // un-hyphenated name
//            let appid = fork.owner.appNameWithHyphen
//            let bundleIdentifier = "app." + appid
//
//            var fairsealBetaFound = false
//            var fairsealFound = false
//
//            for release in (fork.releases.nodes ?? []) {
//                guard let appVersion = SemVer(string: release.tag.name) else {
//                    dbg("invalid release tag:", release.tag.name)
//                    continue
//                }
//                dbg("  checking release:", fork.nameWithOwner, appVersion.versionString)
//
//                // committer from the web will be "GitHub Web Flow" and either empty e-mail or "noreply@github.com"
//                //let developerEmail = release.tagCommit.signature?.signer.email
//                //let developerName = release.tagCommit.signature?.signer.name
//
//                let devName = release.tagCommit.author?.name
//
//                // if there is no homepage explicitly set, use the standard github page
//                let page = fork.homepageUrl ?? "https://\(appid).github.io/App"
//                let homepage = URL(string: page)
//
//                guard let devEmail = release.tagCommit.author?.email else {
//                    dbg(fork.nameWithOwner, "no email for commit")
//                    continue
//                }
//
//                let developerInfo: String
//
//                if let devName = devName, !devName.isEmpty {
//                    developerInfo = "\(devName) <\(devEmail)>"
//                } else {
//                    developerInfo = devEmail
//                }
//
//                do {
//                    try configuration.validateEmailAddress(devEmail)
//                } catch {
//                    // skip packages whose e-mail addresses are not valid
//                    dbg(fork.nameWithOwner, "invalid committer email:", error)
//                    continue
//                }
//
////                guard let orgEmail = fork.owner.email else {
////                    dbg(fork.nameWithOwner, "missing org email")
////                    continue
////                }
////                do {
////                    try validateEmailAddress(orgEmail)
////                } catch {
////                    // skip packages whose e-mail addresses are not valid
////                    dbg(fork.nameWithOwner, "invalid owner email:", error)
////                    continue
////                }
////
////                if orgEmail != devEmail {
////                    dbg(fork.nameWithOwner, "org email must match commit email")
////                    continue
////                }
//
//                let versionDate = release.createdAt
//                let versionDescription = release.description
//                let iconURL = release.releaseAssets.nodes.first { asset in
//                    asset.name == "\(appid).png" // e.g. "Fair-Skies.png"
//                }?.downloadUrl
//
//                let beta: Bool = release.isPrerelease
//
//                func releaseAsset(named name: String) -> ReleaseAsset? {
//                    release.releaseAssets.nodes.first(where: { node in
//                        node.name == name
//                    })
//                }
//
//                for artifactTarget in [artifactTarget] {
//                    guard let artifactType = artifactTarget?.artifactType else {
//                        continue
//                    }
//                    dbg("checking target:", appName, fork.name, appVersion.versionString, "type:", artifactType, "files:", release.releaseAssets.nodes.map(\.name))
//                    guard let appArtifact = release.releaseAssets.nodes.first(where: { node in
//                        node.name.hasSuffix(artifactType)
//                    }) else {
//                        dbg("missing app artifact from release")
//                        continue
//                    }
//
////                    guard let appMetadata = releaseAsset(named: "Info.plist") else {
////                        dbg("missing app artifact from release")
////                        continue
////                    }
//
////                    let appREADME = releaseAsset(named: "README.md")
////                    let appRELEASENOTES = releaseAsset(named: "RELEASE_NOTES.md")
//
//                    guard let appIcon = releaseAsset(named: appName + ".png") else {
//                        dbg("missing appIcon from release")
//                        continue
//                    }
//
//                    var seal: FairSeal? = nil
//
//                    // scan the comments for the base ref for the matching url seal
//                    var urlSeals: [URL: Set<String>] = [:]
//                    let prs = fork.defaultBranchRef.associatedPullRequests.nodes
//                    //dbg("scanning prs:", prs)
//                    let comments = (prs ?? []).compactMap(\.comments.nodes)
//
//                    let fairsealComments = comments.joined().filter({ $0.author.login == fairsealIssuer })
//                    for comment in fairsealComments {
//                        do {
//                            let body = comment.bodyText
//                                .trimmed(CharacterSet(charactersIn: "`").union(.whitespacesAndNewlines))
//                            seal = try FairSeal(fromJSON: body.utf8Data, dateDecodingStrategy: .iso8601)
//                            for asset in seal?.assets ?? [] {
//                                urlSeals[asset.url, default: []].insert(asset.sha256)
//                            }
//                        } catch {
//                            // comments can be anything, so tolerate JSON decoding failures
//                            // this will also catch serialization format changes: HubAPI:408 assembleCatalog: error parsing seal: typeMismatch(Swift.Array<Any>, Swift.DecodingError.Context(codingPath: [CodingKeys(stringValue: "permissions", intValue: nil)], debugDescription: "Expected to decode Array<Any> but found a number instead.", underlyingError: nil))
//                            dbg("error parsing seal:", error)
//                        }
//                    }
//
//                    let artifactURL = appArtifact.downloadUrl
//                    guard let artifactChecksum = urlSeals[artifactURL]?.first else {
//                        dbg("missing checksum for artifact url:", artifactURL.absoluteString)
//                        continue
//                    }
//                    dbg("checking artifact url:", artifactURL.absoluteString, "fairseal:", artifactChecksum)
//
////                    let metadataURL = appMetadata.downloadUrl
////                    guard let metadataChecksum = urlSeals[metadataURL]?.first else {
////                        dbg("missing checksum for metadata url:", metadataURL.absoluteString)
////                        continue
////                    }
////
////                    let readmeURL = appREADME.downloadUrl
////                    guard let readmeChecksum = urlSeals[readmeURL]?.first else {
////                        dbg("missing checksum for readme url:", readmeURL.absoluteString)
////                        continue
////                    }
////
////                    let releaseNotesURL = appRELEASENOTES?.downloadUrl
//
//                    let screenshotURLs = release.releaseAssets.nodes.filter { node in
//                        if !(node.name.hasSuffix(".png") || node.name.hasSuffix(".jpg")) {
//                            return false
//                        }
//                        return artifactTarget?.devices.contains { device in
//                            node.name.hasPrefix("screenshot") && node.name.contains("-" + device + "-")
//                        } == true
//                    }
//                    .compactMap { node in
//                        node.downloadUrl.appendingHash(urlSeals[node.downloadUrl]?.first)
//                    }
//
//                    let downloadCount = appArtifact.downloadCount
//                    let impressionCount = appIcon.downloadCount
////                    let viewCount = appREADME.downloadCount
//
//                    let size = appArtifact.size
//
//                    //let app = AltCatalogItem(name: appTitle, bundleIdentifier: bundleIdentifier, subtitle: subtitle, developerName: developerInfo, localizedDescription: localizedDescription, size: size, version: appVersion.versionString, versionDate: versionDate, downloadURL: artifactURL, iconURL: iconURL, screenshotURLs: screenshotURLs.isEmpty ? nil : screenshotURLs, versionDescription: versionDescription, tintColor: seal?.tint, beta: beta, categories: categories, downloadCount: downloadCount, impressionCount: impressionCount, viewCount: viewCount, starCount: starCount, watcherCount: watcherCount, issueCount: issueCount, coreSize: seal?.coreSize, sha256: artifactChecksum, permissions: seal?.permissions, metadataURL: metadataURL.appendingHash(metadataChecksum), readmeURL: readmeURL.appendingHash(readmeChecksum), releaseNotesURL: releaseNotesURL, homepage: homepage)
//
//                    // derive a source from the sealed info.plist, overriding properties as needed
//                    var app = seal?.appSource ?? AltCatalogItem(name: appTitle, bundleIdentifier: bundleIdentifier, downloadURL: artifactURL)
//
//                    app.name = appTitle
//                    app.bundleIdentifier = bundleIdentifier
//                    app.developerName = developerInfo
//                    app.size = size
//                    app.version = appVersion.versionString
//                    app.versionDate = versionDate
//                    app.downloadURL = artifactURL
//                    app.iconURL = iconURL
//                    app.screenshotURLs = screenshotURLs.isEmpty ? nil : screenshotURLs
//                    app.versionDescription = versionDescription
//                    app.tintColor = seal?.tint
//                    app.beta = beta
//                    app.categories = (categories.isEmpty ? nil : categories)
//                    app.sha256 = artifactChecksum
//                    app.homepage = homepage
//                    app.permissions = seal?.permissions
//
//                    // placeholders unless the fairseal contains additional information
//                    app.subtitle = fork.description
//                    app.localizedDescription = fork.description
//
//                    // app.links = wip(nil) // TODO: move metadata/readme/releaseNotes links into this section
//
////                    app.metadataURL = metadataURL.appendingHash(metadataChecksum)
////                    app.readmeURL = readmeURL.appendingHash(readmeChecksum)
////                    app.releaseNotesURL = releaseNotesURL
////                    app.fundingLinks = (fundingLinks.isEmpty ? nil : fundingLinks)?.map { link in
////                        AppFundingLink(platform: link.platform, url: link.url)
////                    }
//
//
//                    app.stats = AppStats(downloadCount: downloadCount, impressionCount: impressionCount, starCount: starCount, watcherCount: watcherCount, issueCount: issueCount, forkCount: forkCount, coreSize: seal?.coreSize)
//
//                    var locs: [String: AltCatalogItem] = [:]
//                    if let appMetaData = try seal?.parseAppMetaData() {
//                        if let subtitle = appMetaData.subtitle {
//                            app.subtitle = subtitle
//                        }
//
//                        if let description = appMetaData.description {
//                            app.localizedDescription = description
//                        }
//
//                        for (langCode, lmd) in appMetaData.localizations ?? [:] {
//                            var subItem = AltCatalogItem(name: lmd.name ?? app.name)
//                            subItem.subtitle = lmd.subtitle
//                            subItem.localizedDescription = lmd.description
//                            subItem.subtitle = lmd.subtitle
//                            subItem.versionDescription = lmd.release_notes
//                            subItem.homepage = lmd.marketing_url.flatMap(URL.init(string:))
//                            //subItem.keywords = lmd.keywords
//                            locs[langCode] = subItem
//                        }
//                    }
//
//                    app.localizations = locs.isEmpty ? nil : locs
//
//
//                    // walk through the recent releases until we find one that has a fairseal on it
//                    if beta == true {
//                        if !fairsealBetaFound {
//                            apps.append(app)
//                        }
//                        fairsealBetaFound = true
//                    } else {
//                        if !fairsealFound {
//                            apps.append(app)
//                        }
//                        fairsealFound = true
//                    }
//                }
//
//                if fairsealFound {
//                    // only add the single most recent valid release for any given fork
//                    // this will also ignore any betas earlier than the most recent non-prerelease
//                    break
//                }
//            }
//
//            if !fairsealFound {
//                dbg("WARNING: no fairseal found for:", fork.nameWithOwner)
//            }
//        }
//
//        return apps
//    }
//
//    /// Generates the appcasks enhanced catalog for Homebrew Casks
//    public func buildAppCasks(owner: String, catalogName: String, catalogIdentifier: String, baseRepository: String?, topicName: String?, starrerName: String?, excludeEmptyCasks: Bool = true, maxApps: Int? = nil, mergeCasksURL: URL? = nil, caskStatsURL: URL? = nil, boostMap: [String: Int]? = nil, boostFactor: Int64?, caskQueryCount: Int, releaseQueryCount: Int, assetQueryCount: Int, msg messageHandler: (Any?, Any?, Any?, Any?, Any?, Any?, Any?, Any?, Any?, Any?) -> () = { dbg($0, $1, $2, $3, $4, $5, $6, $7, $8, $9) }) async throws -> AppCatalog {
//
//        // all the seal hashes we will look up to validate releases
//        let boost = boostFactor ?? 10_000
//
//        // shim to enable debugging and CLI logging
//        func msg(_ a0: Any?, _ a1: Any? = nil, _ a2: Any? = nil, _ a3: Any? = nil, _ a4: Any? = nil, _ a5: Any? = nil, _ a6: Any? = nil, _ a7: Any? = nil, _ a8: Any? = nil, _ a9: Any? = nil) {
//            messageHandler(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9)
//        }
//
//        msg("building appcasks with maxApps:", maxApps, "boost:", boost)
//
//        struct CaskCatalog {
//            let casks: [String: CaskItem]
//            init(_ casks: [CaskItem]) {
//                self.casks = casks.dictionary(keyedBy: \.token)
//            }
//        }
//
//        let api = HomebrewAPI(caskAPIEndpoint: mergeCasksURL ?? HomebrewAPI.defaultEndpoint)
//
//        // if we specified catalog metadata to merge in, start fetching it now
//        async let casks = CaskCatalog(mergeCasksURL == nil ? [] : api.fetchCasks().casks)
//        async let stats = caskStatsURL == nil ? nil : api.fetchCaskStats(url: caskStatsURL!)
//
//        // the apps we have indexed
//        var apps: [AltCatalogItem] = []
//        // the app ids we have seen so far
//        var appids: Set<String> = []
//
//        var starredRepoMap: [String: CaskRepository] = [:]
//
//        // 1. Check repositories that have been starred by the fairbot
//        if let starrerName = starrerName, !starrerName.isEmpty {
//            for try await starredRepos in requestBatchedStream(AppCasksStarQuery(starrerName: starrerName, count: caskQueryCount, releaseCount: 5)) {
//
//                // we don't actually treat these as appcasks sources; instead, we just index some metadata that other casks may want to look up
//                for repo in try starredRepos.result.get().data.user.starredRepositories.nodes {
//                    msg("starred by:", starrerName, "repo:", repo.nameWithOwner)
//                    if repo.isArchived {
//                        continue
//                    }
//                    if repo.visibility != .PUBLIC {
//                        continue
//                    }
//                    if let url = repo.url {
//                        starredRepoMap[url.lowercased()] = repo
//                    }
//                }
////                if try await addAppCasks(repos.result.get().data.user.starredRepositories.nodes, caskCatalog: await casks, stats: await stats) == false {
////                    break
////                }
//            }
//
//            try await Task.sleep(interval: 1.0) // backoff before the next request
//        }
//
//
//        // 2. Check forks of the `appfair/appcasks` repository
//        if let baseRepository = baseRepository {
//            for try await forks in requestBatchedStream(AppCasksForkQuery(owner: owner, name: baseRepository, count: caskQueryCount, releaseCount: releaseQueryCount, assetCount: assetQueryCount)) {
//                if try await addAppCasks(forks.result.get().data.repository.forks.nodes, caskCatalog: await casks, stats: await stats) == false {
//                    break
//                }
//            }
//            try await Task.sleep(interval: 1.0) // backoff before the next request
//        }
//
//
//        // 3. Check repos with the "appfair-cask" topic
//        if let topicName = topicName, !topicName.isEmpty {
//            for try await topicRepos in requestBatchedStream(AppCasksTopicQuery(topicName: topicName, count: caskQueryCount, releaseCount: caskQueryCount)) {
//                if try await addAppCasks(topicRepos.result.get().data.topic.repositories.nodes, caskCatalog: await casks, stats: await stats) == false {
//                    break
//                }
//            }
//            try await Task.sleep(interval: 1.0) // backoff before the next request
//        }
//
//        func addAppCasks(_ repos: [FairHub.CaskRepository], caskCatalog casks: CaskCatalog?, stats: CaskStats?) async throws -> Bool {
//            msg("fetched appcasks repos:", repos.count)
//            for repo in repos {
//
//                if repo.isArchived {
//                    msg("skipping archived repository:", repo.nameWithOwner)
//                    continue
//                }
//
//                if repo.visibility != .PUBLIC {
//                    msg("skipping non-public repository:", repo.nameWithOwner)
//                    continue
//                }
//
//                try await addRepositoryReleases(repo, caskCatalog: casks, stats: stats)
//            }
//
//            if let maxApps = maxApps, apps.count >= maxApps {
//                msg("stopping due to maxapps:", maxApps)
//                return false
//            }
//
//            return true
//        }
//
//        func addRepositoryReleases(_ repo: CaskRepository, caskCatalog: CaskCatalog?, stats: CaskStats?) async throws {
//            if apps.count >= maxApps ?? .max {
//                return msg("not adding app beyond max:", maxApps)
//            }
//
//            msg("checking app repo:", repo.owner.appNameWithSpace, repo.name)
//
//            if repo.owner.isVerified != true {
//                return msg("skipping un-verified owner:", repo.nameWithOwner)
//            }
//
//            msg("received release names:", repo.releases.nodes.compactMap(\.name))
//            if addReleases(repo: repo, repo.releases.nodes, casks: caskCatalog, stats: stats) == true {
//                if repo.releases.pageInfo?.hasNextPage == true,
//                    let releaseCursor = repo.releases.pageInfo?.endCursor {
//                    msg("traversing release cursor:", releaseCursor)
//                    for try await moreReleasesNode in self.requestBatchedStream(AppCaskReleasesQuery(repositoryNodeID: repo.id, releaseCount: caskQueryCount, endCursor: releaseCursor)) {
//                        let moreReleaseNodes = try moreReleasesNode.get().data.node.releases.nodes
//                        msg("received more release names:", moreReleaseNodes.compactMap(\.name))
//                        if addReleases(repo: repo, moreReleaseNodes, casks: caskCatalog, stats: stats) == false {
//                            return
//                        }
//                    }
//                }
//            }
//        }
//
//        /// Adds the given cask result to the list of app catalog items
//        func addReleases(repo: CaskRepository, _ releaseNodes: [CaskRepository.Release], casks: CaskCatalog?, stats: CaskStats?) -> Bool {
//            for release in releaseNodes {
//                let caskPrefix = "cask-"
//                guard let tag = release.tag else {
//                    continue
//                }
//                if !tag.name.hasPrefix(caskPrefix) {
//                    msg("tag name", tag.name.enquote(), "does not begin with expected prefix", caskPrefix.enquote())
//                    continue
//                }
//
//                let token = tag.name.dropFirst(caskPrefix.count).description
//                let cask = casks?.casks[token]
//                if casks != nil && cask == nil {
//                    msg("  filtering app missing from casks:", token)
//                    continue
//                }
//
//                guard let website = repo.owner.websiteUrl else {
//                    msg("skipping un-set hostname for owner:", repo.nameWithOwner)
//                    continue
//                }
//
//                guard let homepage = cask?.homepage.flatMap(URL.init(string:)) else {
//                    msg("skipping un-set hostname for cask:", cask?.homepage)
//                    continue
//                }
//
//                msg("validating cask homepage: \(homepage.absoluteString) against fork websiteUrl: \(website.absoluteString)")
//
//                if !homepage.absoluteString.hasPrefix(website.absoluteString)
//                    && repo.nameWithOwner != "App-Fair/appcasks" { // TODO: specify privileged base repository in args
//                    msg("skipping un-matched cask homepage and verified url:", homepage, website)
//                    continue
//                }
//
//                if var app = createApp(token: token, release: release, repo: repo, cask: cask, stats: stats) {
//                    // only add the cask if it has any supplemental information defined
//                    if excludeEmptyCasks == false
//                        || (app.stats?.downloadCount ?? 0) > 0
//                        || app.readmeURL != nil
//                        || app.releaseNotesURL != nil
//                        || app.iconURL != nil
//                        || app.tintColor != nil
//                        || app.categories?.isEmpty == false
//                        || app.screenshotURLs?.isEmpty == false
//                    {
//                        // Prune out apps with the same bundle identifier.
//                        // Since the forks are traversed in reverse-creation-date order,
//                        // this will have the effect that more recent forks defining
//                        // the same bundleIdentifier will have precedence over older forks,
//                        // which means that the oldest fork is the fallback for
//                        // all metadata lookups
//                        guard let id = app.bundleIdentifier, !appids.insert(id).inserted else {
//                            msg("skipping duplicate app id:", app.bundleIdentifier)
//                            continue
//                        }
//
//                        // the funding links will transfer from the associated starred repo
//                        if let homepage = cask?.homepage,
//                           let repo = starredRepoMap[homepage.lowercased()] {
//                            msg("checking app funding for:", homepage)
//                            if !repo.fundingLinks.isEmpty {
//                                app.fundingLinks = repo.fundingLinks.map { link in
//                                    AppFundingLink(platform: link.platform, url: link.url)
//                                }
//                                msg("added app funding links for \(homepage):", try? app.fundingLinks?.debugJSON)
//                            }
//                        }
//
//                        apps.append(app)
//                        if let maxApps = maxApps, apps.count >= maxApps {
//                            msg("stopping due to maxapps:", maxApps)
//                            return false
//                        }
//                    }
//                }
//            }
//
//            return true
//        }
//
//        // apps are ranked based on how much metadata is provided, and then their download count
//        func rank(for item: AltCatalogItem) -> Int64 {
//            var ranking: Int64 = 0
//
//            // the base ranking is the number of downloads
//            ranking += Int64(item.stats?.downloadCount ?? 0)
//
//            // each bit of metadata for a cask boosts its position in the rankings
////            if item.readmeURL != nil { ranking += boost }
//            if item.iconURL != nil { ranking += boost }
//            // if item.tintColor != nil { ranking += boost }
//            if item.categories?.isEmpty == false { ranking += boost }
//            if item.screenshotURLs?.isEmpty == false { ranking += boost }
//
//            // add in explicit boosts
//            if let boostMap = boostMap,
//               let id = item.bundleIdentifier,
//                let boostCount = boostMap[id] {
//                ranking += .init(boostCount) * boost
//            }
//
//            return ranking
//        }
//
//        // now check for any items that are in the casks list but do not have an appcasks fork
//        let forkedApps = apps.map(\.bundleIdentifier).set()
//        let caskMap = try await casks.casks
//        let caskStats = try await stats
//        if !caskMap.isEmpty {
//            for (token, cask) in caskMap.sorting(by: \.0).filter({ !forkedApps.contains($0.key) }) {
//                if let maxApps = maxApps, apps.count >= maxApps {
//                    continue
//                }
//                let app = createApp(token: token, release: nil, repo: nil, cask: cask, stats: caskStats)
//                msg("created app:", app)
//                if let app = app {
//                    apps.append(app)
//                }
//            }
//        }
//
//        apps.sort { rank(for: $0) > rank(for: $1) }
//
//        let catalog = AppCatalog(name: catalogName, identifier: catalogIdentifier, sourceURL: appfairCaskAppsURL, apps: apps, news: nil)
//        return catalog
//    }
//
//    private func createApp(token: String, release: CaskRepository.Release?, repo: CaskRepository?, cask: CaskItem?, stats: CaskStats?) -> AltCatalogItem? {
//        let caskName = cask?.name.first ?? release?.name ?? release?.tag?.name ?? token
//        let homepage = (cask?.homepage ?? repo?.homepageUrl).flatMap(URL.init(string:))
//        let dlurl = (cask?.url ?? cask?.homepage).flatMap(URL.init(string:))
//        let downloadURL = dlurl ?? appfairRoot
//        let checksum = cask?.checksum?.count == 64 ? cask?.checksum : nil
//        let version = cask?.version
//        let subtitle = cask?.desc
//        let versionDate: Date? = nil // release.createdAt // not the right thing
//        // let versionDescription = release?.description
//        let beta: Bool = release?.isPrerelease == true
//
//        func releaseAsset(named name: String) -> ReleaseAsset? {
//            release?.releaseAssets.nodes.first(where: { node in
//                node.name == name
//            })
//        }
//
//        dbg("checking target token:", token, "name:", caskName, "files:", release?.releaseAssets.nodes.map(\.name))
//
//        /// Returns all the asset names with the given prefix trimmed off
//        func prefixedAssetTag(_ prefix: String) -> [String]? {
//            release?.releaseAssets.nodes.filter {
//                $0.name.hasPrefix(prefix)
//            }
//            .map {
//                $0.name.dropFirst(prefix.count).description
//            }
//        }
//
//        // get the "appfair-utilities" topic and convert it to the standard "public.app-category.utilities"
//        let categories = prefixedAssetTag("category-")?
//            .compactMap({ AppCategoryType.valueFor(base: $0, validate: true) })
//
//        let tintColor = prefixedAssetTag("tint-")?
//            .filter({ $0.count == 6 }) // needs to be a 6-digit hex code
//            .first
//
////        let appREADME = releaseAsset(named: "README.md")
////        let readmeURL = appREADME?.downloadUrl
////        let viewCount = appREADME?.downloadCount
//
////        let appRELEASENOTES = releaseAsset(named: "RELEASE_NOTES.md")
////        let releaseNotesURL = appRELEASENOTES?.downloadUrl
//
//        let appIcon = releaseAsset(named: "AppIcon.png")
//        let impressionCount = appIcon?.downloadCount
//
//        let caskInstalls = releaseAsset(named: "cask-install")
//        var downloadCount = caskInstalls?.downloadCount ?? 0
//        if let stats = stats {
//            if let count = stats.formulae?[token]?.first?.count {
//                downloadCount += count
//            }
//        }
//
//        let screenshotURLs = release?.releaseAssets.nodes.filter { node in
//            if !(node.name.hasSuffix(".png") || node.name.hasSuffix(".jpg")) {
//                return false
//            }
//            return node.name.hasPrefix("screenshot") && node.name.contains("-mac-")
//        }
//
//        // the default app catalog item
//        var appItem = AltCatalogItem(name: caskName, bundleIdentifier: token, downloadURL: downloadURL)
//
//        // try to parse out the catalog item from the release's description;
//        // this will work if the embedded code block is fenced AppSource JSON
//        if let releaseDescription = release?.description {
//            do {
//                if try appItem.ingest(json: releaseDescription) {
//                    dbg("parsed item from release description:", appItem)
//                }
//            } catch {
//                dbg("error parsing release description into JSON:", error)
//            }
//        }
//
//        appItem.name = caskName
//        appItem.bundleIdentifier = token
//        appItem.subtitle = subtitle
//
//        appItem.downloadURL = downloadURL
//        appItem.sha256 = checksum
//        appItem.size = nil
//
////        appItem.readmeURL = readmeURL
////        appItem.releaseNotesURL = releaseNotesURL
//
//        appItem.homepage = homepage
//
//        // appItem.developerName = nil // may be set from config
//        appItem.localizedDescription = appItem.localizedDescription ?? cask?.desc
//        // appItem.versionDescription = versionDescription
//
//        appItem.version = version
//        appItem.versionDate = versionDate
//
//        appItem.iconURL = appIcon?.downloadUrl
//
//        appItem.tintColor = appItem.tintColor ?? tintColor
//        appItem.beta = appItem.beta ?? beta
//        appItem.categories = appItem.categories ?? categories
//
//        // we don't currently allow overriding of screenshot URLs;
//        // release resources must be used
//        appItem.screenshotURLs = screenshotURLs?.isEmpty != false ? nil : screenshotURLs?.map(\.downloadUrl)
//
//        // stats cannot be overridden
//
//
//        appItem.stats = AppStats(downloadCount: downloadCount, impressionCount: impressionCount)
//
//        appItem.permissions = nil
//        appItem.metadataURL = nil
//
//        return appItem
//    }
//
//    public func buildFundingSources(owner: String, baseRepository: String) async throws -> [AppFundingSource] {
//        var sources: [AppFundingSource] = []
//
//        func createSponsor(from sponsor: FairHub.GetSponsorsQuery.QueryResponse.Repository.SponsorsListing, url: URL) -> AppFundingSource {
//            var goals: [AppFundingSource.FundingGoal] = []
//            if let activeGoal = sponsor.activeGoal,
//                let goalKind = activeGoal.kind?.rawValue {
//                let goal = AppFundingSource.FundingGoal(kind: goalKind, title: activeGoal.title, description: activeGoal.description, percentComplete: activeGoal.percentComplete, targetValue: activeGoal.targetValue)
//                goals.append(goal)
//            }
//
//            return AppFundingSource(platform: .GITHUB, url: url, goals: goals)
//        }
//
//
//        for try await forks in requestBatchedStream(GetSponsorsQuery(owner: owner, name: baseRepository)) {
//            let rootOwner = try forks.get().data.repository.owner
//            if sources.isEmpty,
//                let rootSponsor = rootOwner.sponsorsListing,
//                let url = rootOwner.url.flatMap(URL.init(string:)) {
//                // always add the root repo's funding first
//                sources.append(createSponsor(from: rootSponsor, url: url))
//            }
//            for node in try forks.get().data.repository.forks.nodes {
//                if let sponsorListing = node.sponsorsListing,
//                   let url = node.owner.url.flatMap(URL.init(string:)) {
//                    sources.append(createSponsor(from: sponsorListing, url: url))
//                }
//            }
//        }
//
//        return sources
//    }
//
//    public func validate(org: RepositoryQuery.QueryResponse.Organization, configuration: ProjectConfiguration) -> AppOrgValidationFailure {
//        let repo = org.repository
//        let isOrigin = org.login == appfairName
//        var invalid: AppOrgValidationFailure = []
//
//        if !isOrigin {
//            do {
//                try AppNameValidation.standard.validate(name: org.login) 
//                try configuration.validateAppName(org.login)
//            } catch {
//                invalid.insert(.invalidName)
//            }
//        }
//
//        if org.isVerified != true {
//            // invalid.insert(.notVerified)
//            // we do not currently require that organizations be verified
//        }
//
//        if !org.isOrganization {
//            invalid.insert(.ownerNotOrganization)
//        }
//
//        if !repo.isInOrganization {
//            invalid.insert(.ownerNotOrganization)
//        }
//
//        if !isOrigin {
//            do {
//                try configuration.validateEmailAddress(org.email)
//            } catch {
//                invalid.insert(.invalidEmail)
//            }
//        }
//
//        if repo.isArchived {
//            invalid.insert(.isArchived)
//        }
//
//        if repo.isDisabled {
//            invalid.insert(.isDisabled)
//        }
//
//        if repo.isPrivate {
//            invalid.insert(.isPrivate)
//        }
//
//        if !isOrigin && !repo.hasIssuesEnabled {
//            invalid.insert(.noIssues)
//        }
//
//        // there's no "hasDiscussionsEnabled" key, but the count of categories will be zero if discussions are not enabled
//        if !isOrigin && repo.discussionCategories.totalCount <= 0 {
//           invalid.insert(.noDiscussions)
//        }
//
//        if !configuration.allowLicense.isEmpty && !configuration.allowLicense.contains(repo.licenseInfo.spdxId ?? "none") {
//            //dbg(allowLicense)
//            invalid.insert(.invalidLicense)
//        }
//
//        return invalid
//    }
//
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

extension AltCatalogItem {
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

extension AltCatalogItem {
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

        // FIXME: this is slow because we are converting the Plist to JSON and then parsing it back into an AltCatalogItem
        let appItem = try AltCatalogItem(json: jobj.json())
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

extension AltCatalogItem {
    public struct Diff {
        public let new: AltCatalogItem
        public let old: AltCatalogItem?
    }
}

//extension AppCatalog {
//
//    /// Transfers version date information from the source catalog to this catalog for each bundle identifier
//    public mutating func importVersionDates(from sourceCatalog: AppCatalog) {
//        let srcMap = sourceCatalog.apps.dictionary(keyedBy: \.bundleIdentifier)
//
//        for (index, item) in self.apps.enumerated() {
//            if let oldApp = srcMap[item.bundleIdentifier] {
//                self.apps[index].versionDate = oldApp.versionDate
//            }
//        }
//
//    }
//
//    /// Update the version date to the current date for each item that has changed
//    public mutating func updateVersionDates(for diffs: [AltCatalogItem.Diff], with date: Date) {
//        let diffMap = diffs.dictionary(keyedBy: \.new.bundleIdentifier)
//        for (index, item) in self.apps.enumerated() {
//            if let diff = diffMap[item.bundleIdentifier] {
//                if diff.new.version != diff.old?.version {
//                    dbg("updating version date for diff of:", diff.new.bundleIdentifier)
//                    self.apps[index].versionDate = date
//                }
//            }
//        }
//    }
//
//    /// Compare two catalogs and report the changes that indicate version changes between catalog entries with the same bundle identifier
//    public static func newReleases(from oldcat: AppCatalog, to newcat: AppCatalog, comparator: (_ new: AltCatalogItem, _ old: AltCatalogItem?) -> Bool = { $0.version != $1?.version }) -> [AltCatalogItem.Diff] {
//        let oldapps = oldcat.apps.filter { $0.beta != true }
//        let newapps = newcat.apps.filter { $0.beta != true }
//
//        let oldids = oldapps.map(\.bundleIdentifier)
//        let newids = newapps.map(\.bundleIdentifier)
//
//        let oldmap = oldapps.dictionary(keyedBy: \.bundleIdentifier)
//        let newmap = newapps.dictionary(keyedBy: \.bundleIdentifier)
//
//        var diffs: [AltCatalogItem.Diff] = []
//        for appid in (oldids + newids).distinct() {
//            guard let newapp = newmap[appid] else {
//                // the app has been removed; not newsworthy
//                continue
//            }
//
//            let oldapp: AltCatalogItem? = oldmap[appid]
//            if comparator(newapp, oldapp) {
//                diffs.append(AltCatalogItem.Diff(new: newapp, old: oldapp))
//            }
//        }
//
//        return diffs
//    }
//
//    /// Returns true if this catalog is for the given ``AppPlatform``.
//    public func isPlatform(_ platform: AppPlatform) -> Bool? {
//        if let p = self.platform {
//            return p == platform
//        }
//
//        // otherwise, guess based on the platform
//        let exts = self.apps.compactMap(\.downloadURL).map(\.pathExtension).set()
//        switch platform {
//        case .iOS: return exts.isSubset(of: ["ipa", ""])
//        case .macOS: return exts.isSubset(of: ["zip", "dmg", "pkg", "gz", "tgz", "bz2", "tbz", "jar", "tar", ""])
//        default: return nil // unknown
//        }
//    }
//}



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

