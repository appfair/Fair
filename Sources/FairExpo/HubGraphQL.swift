import Foundation
import FairCore

/// A `GraphQL` endpoint
public protocol GraphQLEndpointService : EndpointService {
}

/// An API request that is expected to use GraphQL `POST` requests.
public protocol GraphQLAPIRequest : APIRequest where Service == FairHub {
}

public extension GraphQLAPIRequest {
    /// GraphQL requests all use the same query endpoint
    func queryURL(for service: Service) -> URL {
        let url = service.serviceURL
        return url
    }

    /// Creates a GraphQL query with a variable mapping.
    fileprivate func executeGraphQL(_ body: String, includeNulls: Bool = true, variables: [String: GraphQLAPIParameter?] = [:]) throws -> Data {
        var req = JSON.Object()
        req["query"] = .string(body)
        if includeNulls {
            req["variables"] = .object(variables.mapValues({ $0?.parameterValue ?? JSON.null }))
        } else {
            req["variables"] = .object(variables.compactMapValues({ $0?.parameterValue }))
        }
        return try req.toJSON()
    }
}

private protocol GraphQLAPIParameter {
    /// The encoded parameter in a GraphQL parameter map
    var parameterValue: JSON { get }
}

extension FairHub.GHID : GraphQLAPIParameter { var parameterValue: JSON { .string(self.rawValue) } }
extension String : GraphQLAPIParameter { var parameterValue: JSON { .string(self) } }
extension Double : GraphQLAPIParameter { var parameterValue: JSON { .number(self) } }
extension Int : GraphQLAPIParameter { var parameterValue: JSON { .number(Double(self)) } }
extension Bool : GraphQLAPIParameter { var parameterValue: JSON { .boolean(self) } }
extension GraphQLCursor : GraphQLAPIParameter { var parameterValue: JSON { .string(self.rawValue) } }
//extension Data : GraphQLAPIParameter { var parameterValue: JSON { .str(self.base64EncodedString()) } }
//extension Date : GraphQLAPIParameter { var parameterValue: JSON { .str(self.iso8601String) } }


private extension String {
    /// http://spec.graphql.org/draft/#sec-String-Value
    var escapedGraphQLString: String {
        let scalars = self.unicodeScalars

        var output = ""
        output.reserveCapacity(scalars.count)
        for scalar in scalars {
            switch scalar {
            case "\u{8}": output.append("\\b")
            case "\u{c}": output.append("\\f")
            case "\"": output.append("\\\"")
            case "\\": output.append("\\\\")
            case "\n": output.append("\\n")
            case "\r": output.append("\\r")
            case "\t": output.append("\\t")
            case UnicodeScalar(0x0)...UnicodeScalar(0xf), UnicodeScalar(0x10)...UnicodeScalar(0x1f): output.append(String(format: "\\u%04x", scalar.value))
            default: output.append(Character(scalar))
            }
        }

        return output
    }
}


private let gitHubServiceURL = URL(string: "https://api.github.com/graphql")!

extension FairHub {
    /// The base URL for servicing GraphQL requests
    public var serviceURL: URL { gitHubServiceURL }

    /// The HTTP headers that should be attached to all API requests
    public var requestHeaders: [String: String] {
        var headers: [String: String] = [:]
        headers["Accept"] = "application/vnd.github.v3+json"
        // apply auth headers if we have one set
        if let authToken = authToken {
            headers["Authorization"] = "token " + authToken
        }

        return headers
    }

    public func endpoint(action: [String], _ params: [String: String?]) -> URL {
        var comps = URLComponents()
        comps.path = action.joined(separator: "/")
        comps.queryItems = params.map(URLQueryItem.init(name:value:))
        return comps.url(relativeTo: baseURL) ?? baseURL
    }


    /// A wrapper for an `id` type.
    ///
    /// The ID scalar type represents a unique identifier, often used to refetch an object or as key for a cache. The ID type appears in a JSON response as a String; however, it is not intended to be human-readable. When expected as an input type, any string (such as "4") or integer (such as 4) input value will be accepted as an ID.
    public struct GHID: RawDecodable, Hashable {
        public var rawValue: String
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// An object ID
    public struct OID : RawDecodable, Hashable {
        public let rawValue: String
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// Generic placeholder for a related collection that only has a `totalCount` property requested
    public struct NodeCount : Decodable {
        public let totalCount: Int
    }

    public struct NodeList<T: Decodable>: Decodable {
        let nodes: [T]?
    }

    public struct EdgeList<T: Decodable>: Decodable {
        let totalCount: Int?
        let pageInfo: PageInfo?
        let edges: [EdgeNode<T>]

        /// Maps through to the edge's node
        var nodes: [T] {
            edges.map(\.node)
        }

        struct EdgeNode<N: Decodable>: Decodable {
            let cursor: String?
            let node: N
        }

        /// The info for a page of results, which includes a cursor to traverse
        struct PageInfo : Decodable {
            let endCursor: GraphQLCursor?
            let hasNextPage: Bool?
            let hasPreviousPage: Bool?
            let startCursor: GraphQLCursor?
        }
    }
}

// MARK: CurrentViewerLoginQuery

extension FairHub {
    /// One of the simplest possible queries, it simply returns the current viewer's login
    ///
    /// Example usage:
    ///
    /// ```
    /// let hub: FairHub = …
    /// let response = try await hub.request(FairHub.CurrentViewerLoginQuery()).get()
    /// let login = response.data.viewer.login
    /// ```
    public struct CurrentViewerLoginQuery : GraphQLAPIRequest {
        public func postData() throws -> Data? {
            try executeGraphQL("query { viewer { login } }")
        }

        public typealias Response = GraphQLResponse<CurrentViewerLoginResponse>

        public struct CurrentViewerLoginResponse : Decodable {
            public let viewer: Viewer
            public struct Viewer : Decodable {
                public let login: String
            }
        }
    }
}

// MARK: GetCommitQuery

extension FairHub {
    public struct GetCommitQuery : GraphQLAPIRequest {
        public var owner: String
        public var name: String
        public var ref: String

        public init(owner: String, name: String, ref: String) {
            self.owner = owner
            self.name = name
            self.ref = ref
        }

        public func postData() throws -> Data? {
            try executeGraphQL(Self.query, variables: [
                "owner": owner,
                "name": name,
                "ref": ref,
            ])
        }

        private static let query = """
            query GetCommitQuery($owner:String!, $name:String!, $ref:GitObjectID!) {
               __typename
               repository(owner: $owner, name: $name) {
                object(oid: $ref) {
                  ... on Commit {
                    oid
                    abbreviatedOid
                    author {
                      name
                      email
                      date
                    }
                    signature {
                      email
                      isValid
                      state
                      wasSignedByGitHub
                      signer {
                        email
                        name
                        createdAt
                      }
                    }
                  }
                }
              }
            }
            """

        public typealias Response = GraphQLResponse<QueryResponse>

        public struct QueryResponse : Decodable {
            public enum TypeName : String, Decodable { case Query }
            public let __typename: TypeName
            public let repository: Repository
            public struct Repository : Decodable {
                public let object: Object
                public struct Object : Decodable {
                    public let oid: OID
                    public let abbreviatedOid: String
                    public let author: Author?
                    public let signature: Signature?

                    public struct Author : Decodable {
                        let name: String?
                        let email: String?
                        let date: Date
                    }

                    public struct Signature : Decodable {
                        let email: String?
                        let isValid: Bool
                        let state: GitSignatureState
                        let wasSignedByGitHub: Bool
                        let signer: Signer
                        public struct Signer : Decodable {
                            let name: String?
                            let email: String
                            let createdAt: Date
                        }
                    }
                }
            }
        }
    }
}

// MARK: RepositoryQuery

extension FairHub {
    public struct RepositoryQuery : GraphQLAPIRequest {
        public var owner: String
        public var name: String

        public init(owner: String, name: String) {
            self.owner = owner
            self.name = name
        }

        public func postData() throws -> Data? {
            try executeGraphQL(Self.query, variables: [
                "owner": owner,
                "name": name,
            ])
        }

        private static let query = """
            query RepositoryQuery($owner:String!, $name:String!) {
               __typename
               organization(login: $owner) {
                __typename
                id
                name
                login
                email
                isVerified
                websiteUrl
                url
                createdAt
                repository(name: $name) {
                  __typename
                  visibility
                  createdAt
                  updatedAt
                  homepageUrl
                  isFork
                  isEmpty
                  isLocked
                  isMirror
                  isPrivate
                  isArchived
                  isDisabled
                  forkCount
                  stargazerCount
                  watchers { totalCount }
                  isInOrganization
                  hasIssuesEnabled
                  discussionCategories { totalCount }
                  issues { totalCount }
                  licenseInfo {
                    __typename
                    spdxId
                  }
                }
              }
            }
            """

        public typealias Response = GraphQLResponse<QueryResponse>

        public struct QueryResponse : Decodable {
            public enum TypeName : String, Decodable { case Query }
            public let __typename: TypeName
            public let organization: Organization
            public struct Organization : Decodable {
                public enum TypeName : String, Decodable { case User, Organization }
                public let __typename: TypeName
                public let name: String? // the string title, falling back to the login name
                public let login: String
                public let email: String?
                public let isVerified: Bool?
                public let websiteUrl: URL?
                public let url: URL?
                public let createdAt: Date?

                public var isOrganization: Bool { __typename == .Organization }

                public let repository: Repository
                public struct Repository : Decodable {
                    public enum TypeName : String, Decodable { case Repository }
                    public let __typename: TypeName
                    public let visibility: RepositoryVisibility // e.g., "PUBLIC",
                    public let createdAt: Date
                    public let updatedAt: Date
                    public let homepageUrl: String?
                    public let isFork: Bool
                    public let isEmpty: Bool
                    public let isLocked: Bool
                    public let isMirror: Bool
                    public let isPrivate: Bool
                    public let isArchived: Bool
                    public let isDisabled: Bool
                    public let isInOrganization: Bool
                    public let hasIssuesEnabled: Bool
                    public let discussionCategories: NodeCount
                    public let forkCount: Int
                    public let stargazerCount: Int
                    public let issues: NodeCount
                    public let licenseInfo: License
                    public struct License : Decodable {
                        public enum TypeName : String, Decodable { case License }
                        public let __typename: TypeName
                        public let spdxId: String?
                    }
                }
            }
        }
    }
}

// MARK: AppCasksTopicQuery / AppCasksStarQuery / AppCasksForkQuery

extension FairHub {
    public struct AppCasksTopicQuery : GraphQLAPIRequest & CursoredAPIRequest {
        public typealias Service = FairHub

        public var topicName: String

        /// the number of forks to return per batch
        public var count: Int

        /// the number of releases to scan
        public var releaseCount: Int

        /// the number of release assets to process
        public var assetCount: Int = 25

        public var endCursor: GraphQLCursor? = nil

        public func postData() throws -> Data? {
            try executeGraphQL(Self.query, variables: [
                "topicName": topicName,
                "count": count,
                "releaseCount": releaseCount,
                "assetCount": assetCount,
                "endCursor": endCursor
            ])
        }

        private static let query = """
            query AppCasksTopicQuery($topicName:String!, $count:Int!, $releaseCount:Int!, $assetCount:Int!, $endCursor:String) {
               __typename
               topic(name: $topicName) {
                __typename
                name
                repositories(after: $endCursor, first: $count, isLocked: false, privacy: PUBLIC, orderBy: { field: CREATED_AT, direction: DESC }) {
                    \(CaskRepositoryFragment)
                }
              }
            }
            """

        public typealias Response = GraphQLResponse<QueryResponse>

        public struct QueryResponse : Decodable, CursoredAPIResponse {
            public var hasNextPage: Bool {
                topic.repositories.pageInfo?.hasNextPage == true
            }

            public var endCursor: GraphQLCursor? {
                topic.repositories.pageInfo?.endCursor
            }

            public var elementCount: Int {
                topic.repositories.nodes.count
            }

            public enum TypeName : String, Decodable { case Query }
            public let __typename: TypeName
            public let topic: Topic
            public struct Topic : Decodable {
                public enum TypeName : String, Decodable { case Topic }
                public let name: String
                public let repositories: EdgeList<CaskRepository>
            }
        }
    }

    public struct AppCasksStarQuery : GraphQLAPIRequest & CursoredAPIRequest {
        public typealias Service = FairHub

        public var starrerName: String

        /// the number of forks to return per batch
        public var count: Int

        /// the number of releases to scan
        public var releaseCount: Int

        /// the number of release assets to process
        public var assetCount: Int = 25

        public var endCursor: GraphQLCursor? = nil

        public func postData() throws -> Data? {
            try executeGraphQL(Self.query, variables: [
                "starrerName": starrerName,
                "count": count,
                "releaseCount": releaseCount,
                "assetCount": assetCount,
                "endCursor": endCursor
            ])
        }

        private static let query = """
            query AppCasksTopicQuery($starrerName:String!, $count:Int!, $releaseCount:Int!, $assetCount:Int!, $endCursor:String) {
               __typename
               user(login: $starrerName) {
                __typename
                starredRepositories(after: $endCursor, first: $count, orderBy: { field: STARRED_AT, direction: DESC }) {
                    \(CaskRepositoryFragment)
                }
              }
            }
            """

        public typealias Response = GraphQLResponse<QueryResponse>

        public struct QueryResponse : Decodable, CursoredAPIResponse {
            public var hasNextPage: Bool {
                user.starredRepositories.pageInfo?.hasNextPage == true
            }

            public var endCursor: GraphQLCursor? {
                user.starredRepositories.pageInfo?.endCursor
            }

            public var elementCount: Int {
                user.starredRepositories.nodes.count
            }

            public enum TypeName : String, Decodable { case Query }
            public let __typename: TypeName
            public let user: User
            public struct User : Decodable {
                public enum TypeName : String, Decodable { case User }
                public let starredRepositories: EdgeList<CaskRepository>
            }
        }
    }

    /// The query to generate a catalog of enhanced cask metadata
    public struct AppCasksForkQuery : GraphQLAPIRequest & CursoredAPIRequest {
        public typealias Service = FairHub

        public var owner: String
        public var name: String

        /// the number of forks to return per batch
        public var count: Int

        /// the number of releases to scan
        public var releaseCount: Int

        /// the number of release assets to process
        public var assetCount: Int

        public var endCursor: GraphQLCursor? = nil

        public func postData() throws -> Data? {
            try executeGraphQL(Self.query, variables: [
                "owner": owner,
                "name": name,
                "count": count,
                "releaseCount": releaseCount,
                "assetCount": assetCount,
                "endCursor": endCursor
            ])
        }

        private static let query = """
            query AppCasksForkQuery($owner:String!, $name:String!, $count:Int!, $releaseCount:Int!, $assetCount:Int!, $endCursor:String) {
               __typename
               repository(owner: $owner, name: $name) {
                __typename
                forks(after: $endCursor, first: $count, isLocked: false, privacy: PUBLIC, orderBy: { field: CREATED_AT, direction: DESC }) {
                    \(CaskRepositoryFragment)
                }
              }
            }
            """

        public typealias Response = GraphQLResponse<QueryResponse>

        public struct QueryResponse : Decodable, CursoredAPIResponse {
            public var hasNextPage: Bool {
                repository.forks.pageInfo?.hasNextPage == true
            }

            public var endCursor: GraphQLCursor? {
                repository.forks.pageInfo?.endCursor
            }

            public var elementCount: Int {
                repository.forks.nodes.count
            }

            public enum TypeName : String, Decodable { case Query }
            public let __typename: TypeName
            public let repository: BaseRepository
            public struct BaseRepository : Decodable {
                public enum TypeName : String, Decodable { case Repository }
                public let __typename: TypeName
                public let forks: EdgeList<CaskRepository>
            }
        }
    }

    /// A fragment that will return a ``CaskRepository``
    private static let CaskRepositoryFragment: String = """
        __typename
        totalCount
        pageInfo { endCursor, hasNextPage, hasPreviousPage, startCursor }
        edges {
          node {
            __typename
            id
            name
            nameWithOwner
            owner {
              __typename
              login
              ... on Organization {
                isVerified
                email
                websiteUrl
                createdAt
              }
              ... on User {
                email
                websiteUrl
                createdAt
              }
            }
            description
            visibility
            isArchived
            url
            homepageUrl
            fundingLinks { __typename, platform, url }
            releases(first: $releaseCount, orderBy: {field: CREATED_AT, direction: DESC}) {
              pageInfo { endCursor, hasNextPage, hasPreviousPage, startCursor }
              edges {
                node {
                  __typename
                  name
                  createdAt
                  updatedAt
                  isPrerelease
                  isDraft
                  description
                  releaseAssets(first: $assetCount) {
                    __typename
                    edges {
                      node {
                        __typename
                        id
                        name
                        size
                        contentType
                        downloadUrl
                        downloadCount
                        updatedAt
                        createdAt
                      }
                    }
                  }
                  tag {
                    name
                  }
                }
              }
            }
          }
        }
        """

    /// A repository returned as part of a ``AppCasksForkQuery``.
    public struct CaskRepository : Decodable {
        public enum TypeName : String, Decodable { case Repository }
        public let __typename: TypeName
        public let id: GHID // used as a base for paginaton
        public let name: String
        public let nameWithOwner: String
        public let owner: RepositoryOwner
        public let description: String?
        public let visibility: RepositoryVisibility // e.g. "PUBLIC"
        public let isArchived: Bool
        public let url: String?
        public let homepageUrl: String?
        public let fundingLinks: [FundingLink]
        public let releases: EdgeList<Release>

        public struct Release : Decodable {
            public enum TypeName : String, Decodable { case Release }
            public let __typename: TypeName
            public let tag: Tag?
            public let createdAt: Date
            public let updatedAt: Date
            public let isPrerelease: Bool
            public let isDraft: Bool
            public let name: String?
            public let description: String?
            public let releaseAssets: EdgeList<ReleaseAsset>

            public struct Tag: Decodable, Hashable {
                public let name: String
            }
        }
    }

    /// A link to a funding platform
    public struct FundingLink : Decodable {
        public enum TypeName : String, Decodable { case FundingLink }
        public let __typename: TypeName
        public let platform: AppFundingPlatform
        public let url: URL
    }
}

// MARK: AppCaskReleasesQuery

extension FairHub {

    /// The query to get additional pages of releases for `AppCasksForkQuery` when a fork has many releases
    public struct AppCaskReleasesQuery : GraphQLAPIRequest & CursoredAPIRequest {
        public typealias Service = FairHub

        /// The opaque ID of the fork repository
        public let repositoryNodeID: GHID

        /// the number of releases to get per batch
        public var releaseCount: Int

        /// the number of release assets to process
        public var assetCount: Int = 25

        public var endCursor: GraphQLCursor?

        public func postData() throws -> Data? {
            try executeGraphQL(Self.query, variables: [
                "repositoryNodeID": repositoryNodeID,
                "releaseCount": releaseCount,
                "assetCount": assetCount,
                "endCursor": endCursor
            ])
        }

        private static let query = """
            query AppCaskReleasesQuery($repositoryNodeID:ID!, $releaseCount:Int!, $assetCount:Int!, $endCursor:String) {
              __typename
              node(id: $repositoryNodeID) {
                id
                __typename
                ... on Repository {
                  releases(after: $endCursor, first: $releaseCount) {
                    pageInfo { endCursor, hasNextPage, hasPreviousPage, startCursor }
                    edges {
                      node {
                        __typename
                        name
                        createdAt
                        updatedAt
                        isPrerelease
                        isDraft
                        description
                        releaseAssets(first: $assetCount) {
                          __typename
                          edges {
                            node {
                              __typename
                              id
                              name
                              size
                              contentType
                              downloadUrl
                              downloadCount
                              updatedAt
                              createdAt
                            }
                          }
                        }
                        tag {
                          name
                        }
                      }
                    }
                  }
                }
              }
            }
            """

        public typealias Response = GraphQLResponse<QueryResponse>

        public struct QueryResponse : Decodable, CursoredAPIResponse {
            public var hasNextPage: Bool {
                node.releases.pageInfo?.hasNextPage == true
            }

            public var endCursor: GraphQLCursor? {
                node.releases.pageInfo?.endCursor
            }

            public var elementCount: Int {
                node.releases.nodes.count
            }

            public let node: Repository
            public struct Repository : Decodable {
                public enum TypeName : String, Decodable { case Repository }
                public let __typename: TypeName
                public let id: GHID // used as a base for paginaton

                /// We re-use the same release structure between the parent query and the cursored release query
                public let releases: EdgeList<CaskRepository.Release>
            }
        }
    }
}

// MARK: CatalogForksQuery

extension FairHub {

    /// The query to generate a fair-ground catalog
    public struct CatalogForksQuery : GraphQLAPIRequest & CursoredAPIRequest {
        public typealias Service = FairHub

        public var owner: String
        public var name: String

        /// the number of forks to return per batch
        public var count: Int = 10 // any higher can trigger timeout errors like: “Something went wrong while executing your query. This may be the result of a timeout, or it could be a GitHub bug. Please include `AF94:6EB8:23D7BE:65794E:61DDA32D` when reporting this issue.”

        /// the number of releases to scan
        public var releaseCount: Int = 10
        /// the number of release assets to process
        public var assetCount: Int = 40
        /// the number of recent PRs to scan for a fairseal
        public var prCount: Int = 10
        /// the number of initial comments to scan for a fairseal
        public var commentCount: Int = 10

        public var endCursor: GraphQLCursor? = nil

        public func postData() throws -> Data? {
            try executeGraphQL(Self.query, variables: [
                "owner": owner,
                "name": name,
                "count": count,
                "releaseCount": releaseCount,
                "assetCount": assetCount,
                "prCount": prCount,
                "commentCount": count,
                "endCursor": endCursor
            ])
        }

        private static let query = """
            query CatalogForksQuery($owner:String!, $name:String!, $count:Int = 20, $releaseCount:Int = 10, $assetCount:Int = 40, $prCount:Int = 10, $commentCount:Int = 10, $endCursor:String) {
               __typename
               repository(owner: $owner, name: $name) {
                __typename
                forks(after: $endCursor, first: $count, isLocked: false, privacy: PUBLIC, orderBy: {field: PUSHED_AT, direction: DESC}) {
                  __typename
                  totalCount
                  pageInfo { endCursor, hasNextPage, hasPreviousPage, startCursor }
                  edges {
                    node {
                      __typename
                      id
                      name
                      nameWithOwner
                      owner {
                        __typename
                        login
                        ... on Organization {
                          email
                          isVerified
                          websiteUrl
                          createdAt
                        }
                      }
                      description
                      visibility
                      forkCount
                      stargazerCount
                      hasIssuesEnabled
                      discussionCategories { totalCount }
                      issues { totalCount }
                      stargazers { totalCount }
                      watchers { totalCount }
                      fundingLinks { __typename, platform, url }
                      isInOrganization
                      homepageUrl
                      repositoryTopics(first: 1) {
                        nodes {
                          __typename
                          topic {
                            __typename
                            name
                          }
                        }
                      }
                      releases(first: $releaseCount, orderBy: {field: CREATED_AT, direction: DESC}) {
                        nodes {
                          __typename
                          name
                          createdAt
                          updatedAt
                          isPrerelease
                          isDraft
                          description
                          releaseAssets(first: $assetCount) {
                            __typename
                            edges {
                              node {
                                __typename
                                id
                                name
                                size
                                contentType
                                downloadUrl
                                downloadCount
                                updatedAt
                                createdAt
                              }
                            }
                          }
                          tag {
                            name
                          }
                          tagCommit {
                            __typename
                            authoredByCommitter
                            author {
                              name
                              email
                              date
                            }
                            signature {
                              __typename
                              isValid
                              signer {
                                __typename
                                name
                                email
                              }
                            }
                          }
                        }
                      }

                      defaultBranchRef {
                        __typename
                        associatedPullRequests(states: [CLOSED], last: $prCount) {
                          nodes {
                            __typename
                            author {
                              __typename
                              login
                              ... on User {
                                name
                                email
                              }
                            }
                            baseRef {
                              __typename
                              name
                              repository {
                                nameWithOwner
                              }
                            }
                            # scan the first few PR comments for the fairseal issuer's signature
                            comments(first: $commentCount) {
                              totalCount
                              nodes {
                                __typename
                                author {
                                  login
                                }
                                bodyText # fairseal JSON
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
            """

        public typealias Response = GraphQLResponse<QueryResponse>

        public struct QueryResponse : Decodable, CursoredAPIResponse {
            public var hasNextPage: Bool {
                repository.forks.pageInfo?.hasNextPage == true
            }

            public var endCursor: GraphQLCursor? {
                repository.forks.pageInfo?.endCursor
            }

            public var elementCount: Int {
                repository.forks.nodes.count
            }

            public enum TypeName : String, Decodable { case Query }
            public let __typename: TypeName
            public let repository: BaseRepository
            public struct BaseRepository : Decodable {
                public enum TypeName : String, Decodable { case Repository }
                public let __typename: TypeName
                public let forks: EdgeList<Repository>
                public struct Repository : Decodable {
                    public enum TypeName : String, Decodable { case Repository }
                    public let __typename: TypeName
                    public let id: GHID
                    public let name: String
                    public let nameWithOwner: String
                    public let owner: RepositoryOwner
                    public let description: String?
                    public let visibility: RepositoryVisibility // e.g. "PUBLIC"
                    public let forkCount: Int
                    public let stargazerCount: Int
                    public let hasIssuesEnabled: Bool
                    public let discussionCategories: NodeCount
                    public let issues: NodeCount
                    public let stargazers: NodeCount
                    public let watchers: NodeCount
                    public let fundingLinks: [FundingLink]
                    public let isInOrganization: Bool
                    public let homepageUrl: String?
                    public var repositoryTopics: NodeList<RepositoryTopic>
                    public let releases: NodeList<Release>
                    public let defaultBranchRef: Ref

                    public struct Ref : Decodable {
                        public enum TypeName : String, Decodable { case Ref }
                        public let __typename: TypeName
                        public let associatedPullRequests: NodeList<PullRequest>

                        public struct PullRequest : Decodable {
                            public enum TypeName : String, Decodable { case PullRequest }
                            public let __typename: TypeName
                            public let author: Author
                            public let baseRef: Ref
                            public let comments: NodeList<IssueComment>

                            public struct Author : Decodable {
                                public let login: String
                                public let name: String?
                                public let email: String?
                            }

                            public struct Ref : Decodable {
                                public enum TypeName : String, Decodable { case Ref }
                                public let name: String?
                                public let repository: Repository

                                public struct Repository : Decodable {
                                    public let nameWithOwner: String
                                }
                            }

                            public struct IssueComment : Decodable {
                                public enum TypeName : String, Decodable { case IssueComment }
                                public let __typename: TypeName
                                public let bodyText: String
                                public let author: Author
                                public struct Author : Decodable {
                                    public let login: String
                                }
                            }
                        }
                    }

                    public struct Release : Decodable {
                        public enum TypeName : String, Decodable { case Release }
                        public let __typename: TypeName
                        public let tag: Tag
                        public let tagCommit: Commit
                        public let createdAt: Date
                        public let updatedAt: Date
                        public let isPrerelease: Bool
                        public let isDraft: Bool
                        public let name: String?
                        public let description: String?
                        public let releaseAssets: EdgeList<ReleaseAsset>

                        public struct Tag: Decodable, Hashable {
                            public let name: String
                        }

                        public struct Commit: Decodable {
                            public enum TypeName : String, Decodable { case Commit }
                            public let __typename: TypeName
                            public let authoredByCommitter: Bool
                            public let author: Author?
                            public let signature: Signature?

                            public struct Author : Decodable {
                                let name: String?
                                let email: String?
                                let date: Date
                            }

                            public struct Signature : Decodable {
                                public enum TypeName : String, Decodable { case Signature, GpgSignature }
                                public let __typename: TypeName
                                public let isValid: Bool
                                public let signer: User

                                public struct User : Decodable {
                                    public enum TypeName : String, Decodable { case User }
                                    public let __typename: TypeName
                                    public let name: String?
                                    public let email: String?
                                }
                            }
                        }
                    }

                    public struct RepositoryTopic : Decodable {
                        public enum TypeName : String, Decodable { case RepositoryTopic }
                        public let __typename: TypeName
                        public let topic: Topic
                        public struct Topic : Decodable {
                            public enum TypeName : String, Decodable { case Topic }
                            public let __typename: TypeName
                            public let name: String // TODO: this will be the appfair- app category
                        }
                    }
                }
            }
        }
    }
}


// MARK: FairSealQuery

// NOTE: this is not yet used, but it could eventually be used as a more efficient way of generating the catalog than the CatalogForkQuery

extension FairHub {

    /// The query to gather all the fairseal comments for a specific login
    public struct FairSealQuery : GraphQLAPIRequest & CursoredAPIRequest {
        public typealias Service = FairHub

        public var login: String

        /// the number of comments to return per batch
        public var commentCount: Int = 100

        public var endCursor: GraphQLCursor? = nil

        public func postData() throws -> Data? {
            try executeGraphQL(Self.query, variables: [
                "login": login,
            ])
        }

        private static let query = """
            query FairSealQuery($login:String!, $commentCount:Int = 100, $endCursor:String) {
               __typename
              user(login: $login) {
                 __typename
                issueComments(first:$commentCount, orderBy: { field: UPDATED_AT, direction: DESC }) {
                  pageInfo { endCursor, hasNextPage, hasPreviousPage, startCursor }
                  edges {
                    node {
                      __typename
                      id
                      createdAt
                      pullRequest {
                        title
                        baseRepository {
                          nameWithOwner
                        }
                        headRepository {
                          nameWithOwner
                        }
                      }
                    }
                  }
                }
              }
            }
            """

        public typealias Response = GraphQLResponse<QueryResponse>

        public struct QueryResponse : Decodable, CursoredAPIResponse {
            public var hasNextPage: Bool {
                user.issueComments.pageInfo?.hasNextPage == true
            }

            public var endCursor: GraphQLCursor? {
                user.issueComments.pageInfo?.endCursor
            }

            public var elementCount: Int {
                user.issueComments.nodes.count
            }

            public enum TypeName : String, Decodable { case Query }
            public let __typename: TypeName

            public let user: User
            public struct User : Decodable {
                public enum TypeName : String, Decodable { case User }
                public let __typename: TypeName
                public let issueComments: EdgeList<IssueComment>

                public struct IssueComment : Decodable {
                    public enum TypeName : String, Decodable { case IssueComment }
                    public let __typename: TypeName
                    public let bodyText: String
                }
            }
        }
    }
}


// MARK: LookupPRNumberQuery

extension FairHub {

    public struct LookupPRNumberQuery : GraphQLAPIRequest {
        let owner: String
        let name: String
        let prid: Int

        public func postData() throws -> Data? {
            try executeGraphQL(Self.query, variables: [
                "owner": owner,
                "name": name,
                "prid": prid,
            ])
        }

        private static let query = "query LookupPRNumberQuery($owner:String!, $name:String!, $prid:Int!) { __typename, repository(owner: $owner, name: $name) { pullRequest(number: $prid) { id, number } } }"

        public typealias Response = GraphQLResponse<QueryResponse>

        public struct QueryResponse : Decodable {
            public enum TypeName : String, Decodable { case Query }
            public let __typename: TypeName
            let repository: Repository
            struct Repository : Decodable {
                let pullRequest: PullRequest
                struct PullRequest : Decodable, Hashable {
                    let id: OID
                    let number: Int
                }
            }
        }
    }
}

// MARK: PostCommentQuery

extension FairHub {

    public struct PostCommentQuery : GraphQLAPIRequest {
        /// The issue or pull request ID
        let id: OID
        let comment: String?

        public func postData() throws -> Data? {
            try executeGraphQL(Self.mutation, variables: [
                "id": id.rawValue,
                "comment": comment,
            ])
        }

        private static let mutation = """
            mutation AddComment($id:ID!, $comment:String!) {
              __typename
              addComment(input: {subjectId: $id, body: $comment}) {
                commentEdge {
                  node {
                    body
                    url
                  }
                }
              }
            }
            """

        public typealias Response = GraphQLResponse<QueryResponse>

        public struct QueryResponse : Decodable {
            public enum TypeName : String, Decodable { case Mutation }
            public let __typename: TypeName
            let addComment: AddComment
            struct AddComment : Decodable {
                let commentEdge: CommentEdge
                struct CommentEdge : Decodable {
                    let node: Node
                    struct Node : Decodable {
                        let body: String
                        let url: URL
                    }
                }
            }
        }
    }
}

// MARK: FindPullRequests

extension FairHub {

    public struct FindPullRequests : GraphQLAPIRequest & CursoredAPIRequest {
        /// The owner organization for the PR
        public var owner: String
        /// The base repository name for the PR
        public var name: String
        /// The state of the PR
        public var state: PullRequestState
        public var count: Int = 100
        public var endCursor: GraphQLCursor? = nil

        public func postData() throws -> Data? {
            try executeGraphQL(Self.query, variables: [
                "owner": owner,
                "name": name,
                "state": state.rawValue,
                "count": count,
                "endCursor": endCursor
            ])
        }

        private static let query = """
            query FindPullRequests($owner:String!, $name:String!, $state:PullRequestState!, $count:Int!, $endCursor:String) {
               __typename
               repository(owner: $owner, name: $name) {
                 __typename
                 pullRequests(states: [$state], orderBy: { field: UPDATED_AT, direction: DESC }, first: $count, after: $endCursor) {
                    totalCount
                    pageInfo { endCursor, hasNextPage, hasPreviousPage, startCursor }
                    edges {
                      node {
                        id
                        number
                        url
                        state
                        mergeable
                        headRefName
                        headRepository {
                          nameWithOwner
                          visibility
                        }
                     }
                   }
                 }
               }
             }
            """

        public typealias Response = GraphQLResponse<QueryResponse>

        public struct QueryResponse : Decodable, CursoredAPIResponse {
            public var hasNextPage: Bool {
                repository.pullRequests.pageInfo?.hasNextPage == true
            }

            public var endCursor: GraphQLCursor? {
                repository.pullRequests.pageInfo?.endCursor
            }

            public var elementCount: Int {
                repository.pullRequests.nodes.count
            }

            public enum TypeName : String, Decodable { case Query }
            public let __typename: TypeName
            public var repository: Repository
            public struct Repository : Decodable {
                public enum Repository : String, Decodable, Hashable { case Repository }
                public let __typename: Repository
                public var pullRequests: EdgeList<PullRequest>
                public struct PullRequest : Decodable {
                    public var id: OID
                    public var number: Int
                    public var url: URL?
                    public var state: PullRequestState
                    public var mergeable: String // e.g., "CONFLICTING" or "UNKNOWN"
                    public var headRefName: String // e.g., "main"
                    public var headRepository: HeadRepository?
                    public struct HeadRepository : Decodable {
                        public var nameWithOwner: String
                        public var visibility: RepositoryVisibility // e.g., "PUBLIC"
                    }
                }
            }
        }
    }
}

// MARK: GetSponsorsQuery

extension FairHub {

    public struct GetSponsorsQuery : GraphQLAPIRequest & CursoredAPIRequest {
        /// The owner organization for the PR
        public var owner: String
        /// The base repository name for the PR
        public var name: String

        /// the number of forks to return per batch
        public var count: Int = 100

        public var endCursor: GraphQLCursor? = nil

        public func postData() throws -> Data? {
            try executeGraphQL(Self.query, variables: [
                "owner": owner,
                "name": name,
                "count": count,
                "endCursor": endCursor
            ])
        }

        private static let query = """
            query GetSponsorsQuery($owner: String!, $name: String!, $count: Int!, $endCursor: String) {
              __typename
              repository(owner: $owner, name: $name) {
                __typename
                owner {
                  login
                  url
                  ... on Organization {
                    __typename
                    name
                    websiteUrl
                    sponsorsListing {
                      __typename
                      name
                      isPublic
                      activeGoal {
                        __typename
                        title
                        kind
                        percentComplete
                        targetValue
                        description
                      }
                    }
                  }
                }
                forks(first: $count, after: $endCursor) {
                  totalCount
                  pageInfo { endCursor, hasNextPage, hasPreviousPage, startCursor }
                  edges {
                    node {
                      __typename
                      id
                      nameWithOwner
                      owner {
                        login
                        url
                        ... on Organization {
                          __typename
                          name
                          websiteUrl
                          sponsorsListing {
                            __typename
                            name
                            isPublic
                            activeGoal {
                              __typename
                              title
                              kind
                              percentComplete
                              targetValue
                              description
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
            """

        public typealias Response = GraphQLResponse<QueryResponse>

        public struct QueryResponse : Decodable, CursoredAPIResponse {
            public var hasNextPage: Bool {
                repository.forks.pageInfo?.hasNextPage == true
            }

            public var endCursor: GraphQLCursor? {
                repository.forks.pageInfo?.endCursor
            }

            public var elementCount: Int {
                repository.forks.nodes.count
            }

            public enum TypeName : String, Decodable { case Query }
            public let __typename: TypeName
            public var repository: Repository
            public struct Repository : Decodable {
                public enum Repository : String, Decodable, Hashable { case Repository }
                public let __typename: Repository

                public var owner: Owner

                public struct Owner : Decodable {
                    var login: String?

                    // ... on Organization fields
                    var name: String?
                    var websiteUrl: String?
                    var url: String?
                    var sponsorsListing: SponsorsListing?
                }


                public struct SponsorsListing : Decodable {
                    public enum TypeName : String, Decodable { case SponsorsListing }
                    public let __typename: TypeName
                    var name: String
                    var isPublic: Bool
                    var activeGoal: SponsorsGoal?

                    public struct SponsorsGoal : Decodable {
                        public enum TypeName : String, Decodable { case SponsorsGoal }
                        public let __typename: TypeName
                        var kind: KindName? // e.g. TOTAL_SPONSORS_COUNT or MONTHLY_SPONSORSHIP_AMOUNT
                        var title: String?
                        var description: String?
                        var percentComplete: Double?
                        var targetValue: Double?

                        public struct KindName : RawDecodable, Hashable {
                            public static let TOTAL_SPONSORS_COUNT = KindName(rawValue: "TOTAL_SPONSORS_COUNT")
                            public static let MONTHLY_SPONSORSHIP_AMOUNT = KindName(rawValue: "MONTHLY_SPONSORSHIP_AMOUNT")
                            public let rawValue: String
                            public init(rawValue: String) {
                                self.rawValue = rawValue
                            }
                        }
                    }
                }

                public var forks: EdgeList<Fork>
                public struct Fork : Decodable {
                    public enum TypeName : String, Decodable { case Repository }
                    public let __typename: TypeName
                    public let id: GHID
                    public var nameWithOwner: String
                    public var owner: Owner
                    public var sponsorsListing: SponsorsListing?
                }
            }
        }
    }

    /// An asset returned from an API query
    public struct ReleaseAsset : Decodable {
        public let id: GHID
        public var name: String
        public var size: Int
        public var contentType: String
        public var downloadUrl: URL
        public var downloadCount: Int
        public var createdAt: Date
        public var updatedAt: Date
    }

    public struct User : Decodable {
        public var name: String
        public var email: String
        public var date: Date?
    }

}

// MARK: Semantic Forks


extension FairHub {

    public struct SemanticForksQuery : GraphQLAPIRequest & CursoredAPIRequest {
        /// The owner organization for the PR
        public var owner: String
        /// The base repository name for the PR
        public var name: String

        /// The number of forks to return per batch
        public var forkCount: Int = 10

        /// The number of most recent releases to index
        public var releaseCount: Int = 10

        /// The number of assets to include in each release
        public var assetCount: Int = 10

        public var endCursor: GraphQLCursor? = nil

        public func postData() throws -> Data? {
            try executeGraphQL(Self.query, variables: [
                "owner": owner,
                "name": name,
                "forkCount": forkCount,
                "releaseCount": releaseCount,
                "assetCount": assetCount,
                "endCursor": endCursor
            ])
        }

        private static let query = """
        query($name: String!, $owner: String!, $forkCount: Int = 10, $releaseCount: Int = 10, $assetCount: Int = 10, $endCursor: String) {
          __typename
          repository(owner: $owner, name: $name) {
            __typename
            id
            nameWithOwner

            forks(first: $forkCount, after: $endCursor, orderBy: { field: STARGAZERS, direction: DESC }) {
              totalCount
              pageInfo { hasNextPage, endCursor }
              edges {
                node {
                  __typename
                  id
                  nameWithOwner
                  viewerHasStarred
                  createdAt
                  description
                  hasDiscussionsEnabled
                  hasIssuesEnabled
                  forkCount
                  stargazerCount
                  isFork
                  isEmpty
                  isArchived
                  isDisabled
                  isInOrganization
                  isLocked
                  isMirror
                  isPrivate
                  isSecurityPolicyEnabled
                  openGraphImageUrl
                  viewerCanAdminister
                  visibility
                  discussionCategories(first: 10) {
                    edges {
                      node {
                        __typename
                        name
                        slug
                        description
                        emoji
                      }
                    }
                  }

                  releases(first: $releaseCount, orderBy: { field: CREATED_AT, direction: DESC }) {
                    edges {
                      node {
                        __typename
                        id
                        name
                        tagName
                        isDraft
                        isLatest
                        isPrerelease
                        description
                        resourcePath
                        createdAt
                        publishedAt
                        updatedAt
                        url
        
                        releaseAssets(first: $assetCount) {
                          edges {
                            node {
                              __typename
                              id
                              name
                              size
                              contentType
                              downloadUrl
                              downloadCount
                              createdAt
                              updatedAt
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        """

        public typealias Response = GraphQLResponse<QueryResponse>

        public struct QueryResponse : Decodable, CursoredAPIResponse {
            public var hasNextPage: Bool {
                repository.forks.pageInfo?.hasNextPage == true
            }

            public var endCursor: GraphQLCursor? {
                repository.forks.pageInfo?.endCursor
            }

            public var elementCount: Int {
                repository.forks.nodes.count
            }

            public enum TypeName : String, Decodable { case Query }
            public let __typename: TypeName
            public var repository: Repository
            public struct Repository : Decodable {
                public enum Repository : String, Decodable, Hashable { case Repository }
                public let __typename: Repository
                public let id: GHID
                public var nameWithOwner: String

                public var forks: EdgeList<Fork>
                public struct Fork : Decodable {
                    public enum TypeName : String, Decodable { case Repository }
                    public let __typename: TypeName
                    public let id: GHID
                    public var nameWithOwner: String
                    public var viewerHasStarred: Bool
                    public var createdAt: Date
                    public var description: String
                    public var hasDiscussionsEnabled: Bool
                    public var hasIssuesEnabled: Bool
                    public var forkCount: Int
                    public var stargazerCount: Int
                    public var isEmpty: Bool
                    public var isFork: Bool
                    public var isArchived: Bool
                    public var isDisabled: Bool
                    public var isInOrganization: Bool
                    public var isLocked: Bool
                    public var isMirror: Bool
                    public var isPrivate: Bool
                    public var isSecurityPolicyEnabled: Bool
                    public var openGraphImageUrl: URL?
                    public var viewerCanAdminister: Bool
                    public var visibility: RepositoryVisibility // e.g., "PUBLIC"

                    public let releases: EdgeList<Release>

                    public struct Release : Decodable {
                        public enum TypeName : String, Decodable { case Release }
                        public let __typename: TypeName
                        public let id: GHID
                        public var name: String?
                        public var tagName: String?
                        public var isDraft: Bool
                        public var isLatest: Bool
                        public var isPrerelease: Bool
                        public var description: String?
                        public var resourcePath: String?
                        public var createdAt: Date
                        public var publishedAt: Date
                        public var updatedAt: Date
                        public var url: URL
                        public let releaseAssets: EdgeList<ReleaseAsset>
                    }
                }
            }
        }
    }

}


extension FairHub {


    /// [PullRequestState](https://docs.github.com/en/graphql/reference/enums#pullrequeststate)
    public struct PullRequestState : RawDecodable, Hashable {
        /// A pull request that has been closed without being merged.
        public static let CLOSED = Self(rawValue: "CLOSED")
        /// A pull request that has been closed by being merged.
        public static let MERGED = Self(rawValue: "MERGED")
        /// A pull request that is still open.
        public static let OPEN = Self(rawValue: "OPEN")

        public let rawValue: String
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// [RepositoryVisibility](https://docs.github.com/en/graphql/reference/enums#repositoryvisibility)
    public struct RepositoryVisibility : RawDecodable, Hashable {
        /// The repository is visible only to users in the same business.
        public static let INTERNAL = Self(rawValue: "INTERNAL")
        /// The repository is visible only to those with explicit access.
        public static let PRIVATE = Self(rawValue: "PRIVATE")
        /// The repository is visible to everyone.
        public static let PUBLIC = Self(rawValue: "PUBLIC")

        public let rawValue: String
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }


    /// [GitSignatureState](https://docs.github.com/en/graphql/reference/enums#gitsignaturestate)
    public struct GitSignatureState : RawDecodable, Hashable {
        /// The signing certificate or its chain could not be verified.
        public static let BAD_CERT = Self(rawValue: "BAD_CERT")
        /// Invalid email used for signing.
        public static let BAD_EMAIL = Self(rawValue: "BAD_EMAIL")
        /// Signing key expired.
        public static let EXPIRED_KEY = Self(rawValue: "EXPIRED_KEY")
        /// Internal error - the GPG verification service misbehaved.
        public static let GPGVERIFY_ERROR = Self(rawValue: "GPGVERIFY_ERROR")
        /// Internal error - the GPG verification service is unavailable at the moment.
        public static let GPGVERIFY_UNAVAILABLE = Self(rawValue: "GPGVERIFY_UNAVAILABLE")
        /// Invalid signature.
        public static let INVALID = Self(rawValue: "INVALID")
        /// Malformed signature.
        public static let MALFORMED_SIG = Self(rawValue: "MALFORMED_SIG")
        /// The usage flags for the key that signed this don't allow signing.
        public static let NOT_SIGNING_KEY = Self(rawValue: "NOT_SIGNING_KEY")
        /// Email used for signing not known to GitHub.
        public static let NO_USER = Self(rawValue: "NO_USER")
        /// Valid signature, though certificate revocation check failed.
        public static let OCSP_ERROR = Self(rawValue: "OCSP_ERROR")
        /// Valid signature, pending certificate revocation checking.
        public static let OCSP_PENDING = Self(rawValue: "OCSP_PENDING")
        /// One or more certificates in chain has been revoked.
        public static let OCSP_REVOKED = Self(rawValue: "OCSP_REVOKED")
        /// Key used for signing not known to GitHub.
        public static let UNKNOWN_KEY = Self(rawValue: "UNKNOWN_KEY")
        /// Unknown signature type.
        public static let UNKNOWN_SIG_TYPE = Self(rawValue: "UNKNOWN_SIG_TYPE")
        /// Unsigned.
        public static let UNSIGNED = Self(rawValue: "UNSIGNED")
        /// Email used for signing unverified on GitHub.
        public static let UNVERIFIED_EMAIL = Self(rawValue: "UNVERIFIED_EMAIL")
        /// Valid signature and verified by GitHub.
        public static let VALID = Self(rawValue: "VALID")

        public let rawValue: String
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// The commit instance
    public typealias CommitInfo = GetCommitQuery.QueryResponse
}
