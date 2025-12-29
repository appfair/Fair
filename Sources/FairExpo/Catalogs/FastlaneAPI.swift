import Foundation

/// A collection of metadata described by a fastlane directory structure.
///
/// Implemented by `FastlaneAppStoreMetadata` and `FastlanePlayStoreMetadata`
public protocol FastlaneMetadata: Codable {
    var appTitle: String? { get }
    var appSubtitle: String? { get }
    var appDescription: String? { get }
    var localizations: [String: Self]? { get }

    associatedtype CodingKeys: CodingKey, CaseIterable
}

/// https://docs.fastlane.tools/actions/deliver/#available-metadata-folder-options
public struct FastlaneAppStoreMetadata: Codable {
    // Non-Localized Metadata
    public var copyright: String? // copyright.txt

    /// https://developer.apple.com/app-store/categories/
    public var primary_category: String? // primary_category.txt
    public var secondary_category: String? // secondary_category.txt
    public var primary_first_sub_category: String? // primary_first_sub_category.txt
    public var primary_second_sub_category: String? // primary_second_sub_category.txt
    public var secondary_first_sub_category: String? // secondary_first_sub_category.txt
    public var secondary_second_sub_category: String? // secondary_second_sub_category.txt

    // Localized Metadata
    public var name: String? // <lang>/name.txt
    public var subtitle: String? // <lang>/subtitle.txt
    public var privacy_url: String? // <lang>/privacy_url.txt
    public var apple_tv_privacy_policy: String? // <lang>/apple_tv_privacy_policy.txt
    public var description: String? // <lang>/description.txt
    public var keywords: String? // <lang>/keywords.txt
    public var release_notes: String? // <lang>/release_notes.txt
    public var support_url: String? // <lang>/support_url.txt
    public var marketing_url: String? // <lang>/marketing_url.txt
    public var promotional_text: String? // <lang>/promotional_text.txt

    // Review Information
    public var first_name: String? // review_information/first_name.txt
    public var last_name: String? // review_information/last_name.txt
    public var phone_number: String? // review_information/phone_number.txt
    public var email_address: String? // review_information/email_address.txt
    public var demo_user: String? // review_information/demo_user.txt
    public var demo_password: String? // review_information/demo_password.txt
    public var notes: String? // review_information/notes.txt

    // Locale-specific metadata
    public var localizations: [String: FastlaneAppStoreMetadata]?

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case copyright
        case primary_category
        case secondary_category
        case primary_first_sub_category
        case primary_second_sub_category
        case secondary_first_sub_category
        case secondary_second_sub_category

        case name
        case subtitle
        case privacy_url
        case apple_tv_privacy_policy
        case description
        case keywords
        case release_notes
        case support_url
        case marketing_url
        case promotional_text

        case first_name
        case last_name
        case phone_number
        case email_address
        case demo_user
        case demo_password
        case notes

        case localizations
    }
}

extension FastlaneAppStoreMetadata: FastlaneMetadata {
    public var appTitle: String? { name }
    public var appSubtitle: String? { subtitle }
    public var appDescription: String? { description }
}

/// https://docs.fastlane.tools/actions/supply/
public struct FastlanePlayStoreMetadata: Codable {
    public var title: String? // <lang>/title.txt
    public var short_description: String? // <lang>/short_description.txt
    public var full_description: String? // <lang>/full_description.txt
    public var video: String? // <lang>/video.txt

    // TODO: changelogs (like https://github.com/fastlane/fastlane/tree/master/supply/spec/fixtures/metadata/android/en-US/changelogs)

    // Locale-specific metadata
    public var localizations: [String: FastlanePlayStoreMetadata]?

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case title
        case short_description
        case full_description
        case video

        case localizations
    }
}

extension FastlanePlayStoreMetadata: FastlaneMetadata {
    public var appTitle: String? { title }
    public var appSubtitle: String? { short_description }
    public var appDescription: String? { full_description }
}
