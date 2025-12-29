// Copyright (c) 2022 - 2026 The App Fair Project <info@appfair.org>
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FairCore

/// A cursor that represents a pointer to a page in a set of GraphQL results.
/// It is an opaque (base-64 encoded) string.
public struct GraphQLCursor : RawRepresentable, Decodable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// The payload of a successful `GraphQL` query.
public struct GraphQLPayload<T : Decodable> : Decodable {
    public var data: T
}

/// Pass-through cursor support.
extension GraphQLPayload : CursoredAPIResponse where T : CursoredAPIResponse {
    public var hasNextPage: Bool {
        data.hasNextPage
    }

    public var endCursor: GraphQLCursor? {
        data.endCursor
    }

    public var elementCount: Int {
        data.elementCount
    }
}

// MARK: GraphQL Request & Response


public struct GraphQLError : Decodable, LocalizedError {
    public var message: String // e.g., "Could not resolve to a Repository with the name '/App'."
    public var type: String? // e.g., "NOT_FOUND", "INSUFFICIENT_SCOPES"
    public var path: [String]? // e.g., ["repository"] or ["query FindPullRequests","repository","pullRequests","states"]
    public var documentation_url: URL?

    public var errorDescription: String? { message }
}

/// A set of one or more errors returned by the GraphQL API.
public struct GraphQLErrorList : Decodable, Error {
    public var errors: [GraphQLError]
}

/// Either a single error or a list of errors

public struct GraphQLRequestFailure : Error, RawDecodable {
    public typealias ErrorTypes = Either<GraphQLError>.Or<GraphQLErrorList>
    public let rawValue: ErrorTypes
    public init(rawValue: ErrorTypes) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        try self.init(rawValue: RawValue(from: decoder))
    }
}

extension GraphQLRequestFailure : LocalizedError {
    public var errorDescription: String? {
        firstFailureReason
    }

    /// The first error message for the failure
    public var firstFailureReason: String? {
        rawValue.infer()?.failureReason ?? rawValue.infer()?.errors.first?.message
    }

    /// Returns `true` if the error is due to a rate limitation
    public var isRateLimitError: Bool {
        // TODO: check for error code rather than message
        self.firstFailureReason == "You have exceeded a secondary rate limit. Please wait a few minutes before you try again."
    }
}

public extension GraphQLEndpointService {
    /// A failure can be either a single error (typically for syntax errors), or a list of errors (typically for structural issues)

    /// A response can contain either a successful value or an error instance
    typealias GraphQLResponse<T: Decodable> = Either<GraphQLRequestFailure>.Or<GraphQLPayload<T>>
}


