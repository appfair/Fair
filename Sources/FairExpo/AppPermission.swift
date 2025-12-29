// Copyright (c) 2022 - 2026 The App Fair Project <info@appfair.org>
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-or-later
import Swift
import Foundation
import FairCore
#if canImport(CoreFoundation)
import CoreFoundation
#endif

/// One of the supported permission types: ``AppEntitlementPermission``, ``AppUsagePermission``, ``AppBackgroundModePermission``, or ``AppUnrecognizedPermission``.
public typealias AppPermission = Either<AppEntitlementPermission>
    .Or<AppUsagePermission>
    .Or<AppBackgroundModePermission>
    .Or<AppUnrecognizedPermission>

/// A permission is a specific entitlement coupled with a description of its usage
public struct AppUsagePermission : Codable, Hashable {
    public enum PermissionType : String, Codable, Hashable { case usage }
    public var type: PermissionType = .usage

    /// The type of the permission, which maps to a `NS**UsageDescription` key in the Info.plist
    public var identifier: UsageDescriptionKey

    /// A description of the reason for needing the permission
    public var usageDescription: String

    public init(usage identifier: UsageDescriptionKey, usageDescription: String) {
        self.identifier = identifier
        self.usageDescription = usageDescription
    }
}

/// A permission is a specific entitlement coupled with a description of its usage
public struct AppBackgroundModePermission : Codable, Hashable {
    public enum PermissionType : String, Codable, Hashable { case backgroundMode = "background-mode" }
    public var type: PermissionType = .backgroundMode

    /// The type of the permission, which maps to a `NS**UsageDescription` key in the Info.plist
    public var identifier: AppBackgroundMode

    /// A description of the reason for needing the permission
    public var usageDescription: String

    public init(backgroundMode identifier: AppBackgroundMode, usageDescription: String) {
        self.identifier = identifier
        self.usageDescription = usageDescription
    }
}

/// An element of the "background-mode" permission type
public struct AppBackgroundMode : RawCodable, Hashable {
    public let rawValue: String

    public init(_ name: String) {
        self.rawValue = name
    }

    public init(rawValue name: String) {
        self.rawValue = name
    }

}

/// A permission with an unrecognized ``type`` property.
public struct AppUnrecognizedPermission : Codable, Hashable {
    /// The type of the permission
    public var type: String

    /// The unknown identifier for the permission
    public var identifier: String?

    /// A description of the reason for needing the permission
    public var usageDescription: String

    public init(type: String, identifier: String?, usageDescription: String) {
        self.type = type
        self.identifier = identifier
        self.usageDescription = usageDescription
    }
}

/// A permission is a specific entitlement coupled with a description of its usage
public struct AppEntitlementPermission : Codable, Hashable {
    public enum PermissionType : String, Codable, Hashable { case entitlement }
    public var type: PermissionType = .entitlement

    /// The type of the permission, which maps to an entitement key
    public var identifier: AppEntitlement

    /// A description of the reason for needing the permission
    public var usageDescription: String

    public init(entitlement identifier: AppEntitlement, usageDescription: String) {
        self.identifier = identifier
        self.usageDescription = usageDescription
    }
}

public struct AppEntitlement : RawCodable, Equatable, Hashable {
    public let rawValue: String

    public init(_ name: String) {
        self.rawValue = name
    }

    public init(rawValue name: String) {
        self.rawValue = name
    }

    /// The key for specifying the permission in an entitlements plist
    public var entitlementKey: String {
        // "com.apple." + rawValue
        rawValue
    }

    /// The class of entitlement
    public enum Category : String, CaseIterable, Hashable {
        /// Required by all apps
        case prerequisite
        /// Low-risk
        case harmless
        /// Access to assets like media
        case assets
        /// Reading files
        case readFile
        /// Writing files
        case writeFile
        /// Network access
        case network
        /// Device access
        case device
        /// Miscellaneous access
        case misc
        /// Personal Information
        case personal_information
        /// Low-level system
        case volatile
    }

    public var categories: Set<Category> {
        switch self {
        case .app_sandbox:
            return [.prerequisite, .harmless]
        case .cs_allow_jit:
            return [.harmless]

        case .teamIdentifier:
            return [.harmless]
        case .application_identifier:
            return [.harmless]

        case .cs_debugger:
            return [.volatile]
        case .cs_allow_unsigned_executable_memory:
            return [.volatile]
        case .cs_allow_dyld_environment_variables:
            return [.volatile]
        case .cs_disable_library_validation:
            return [.harmless] // [.volatile] // needs to be harmless because ad-hoc-signed executables would not otherwise be able to link to other ad-hoc-signed frameworks
        case .cs_disable_executable_page_protection:
            return [.volatile]

        case .network_client:
            return [.network]
        case .network_server:
            return [.network]

        case .files_all:
            return [.readFile, .writeFile]
        case .files_user_selected_read_write:
            return [.readFile, .writeFile]
        case .files_user_selected_read_only:
            return [.readFile]
        case .files_user_selected_executable:
            return [.readFile, .writeFile]

        case .print:
            return [.device]
        case .scripting_targets:
            return [.harmless]
        case .application_groups:
            return [.harmless]

        case .files_downloads_read_only:
            return [.readFile]
        case .files_downloads_read_write:
            return [.readFile, .writeFile]
        case .files_bookmarks_app_scope:
            return [.harmless]
        case .files_bookmarks_document_scope:
            return [.harmless]
        case .files_home_relative_path_read_only:
            return [.readFile]
        case .files_home_relative_path_read_write:
            return [.readFile, .writeFile]
        case .files_absolute_path_read_only:
            return [.readFile]
        case .files_absolute_path_read_write:
            return [.readFile, .writeFile]

        case .assets_pictures_read_only:
            return [.assets, .readFile, .writeFile]
        case .assets_pictures_read_write:
            return [.assets, .readFile, .writeFile]
        case .assets_music_read_only:
            return [.assets, .readFile, .writeFile]
        case .assets_music_read_write:
            return [.assets, .readFile, .writeFile]
        case .assets_movies_read_only:
            return [.assets, .readFile, .writeFile]
        case .assets_movies_read_write:
            return [.assets, .readFile, .writeFile]

        case .personal_information_location:
            return [.personal_information]
        case .personal_information_addressbook:
            return [.personal_information]
        case .personal_information_calendars:
            return [.personal_information]

        case .device_camera:
            return [.device]
        case .device_microphone:
            return [.device]
        case .device_usb:
            return [.device]
        case .device_serial:
            return [.device]
        case .device_firewire:
            return [.device]
        case .device_bluetooth:
            return [.device]
        case .device_audio_input:
            return [.device]
        case .device_audio_video_bridging:
            return [.device]

        case .apple_events:
            return [.misc]
        case .audio_unit_host:
            return [.misc]
        case .iokit_user_client_class:
            return [.misc]
        case .mach_lookup_global_name:
            return [.misc]
        case .mach_register_global_name:
            return [.misc]

        case .shared_preference_read_only:
            return [.readFile, .writeFile]
        case .shared_preference_read_write:
            return [.readFile, .writeFile]

        default:
            return []
        }
    }

    /// The Info.plist properties that are used to explain to end-users the reason for the requested entitlement.
    /// In order to pass integration, each entitlement added to the `sandbox-*.entitlements` files must have a corresponding usage description in the `Info.plist`'s `FairUsage` dictionary that explains in plain language the reason the app will need to request that permission.
    ///
    /// An empty returned array indicates that the entitlement may be used without needing any description (such as `cs_allow_jit`).
    /// A `nil` return value indicates that the property is always forbidden altogether (such as `files_all`)
    public var usageDescriptionProperties: [String]? {
        switch self {
        case .files_all:
            return nil // never allowed; use files_user_selected_read_write instead
        case .cs_allow_unsigned_executable_memory:
            return nil // never allowed
        case .cs_allow_dyld_environment_variables:
            return nil // never allowed
        case .cs_disable_executable_page_protection:
            return nil // never allowed

        case .cs_disable_library_validation:
            return [] // always allowed (and required in order to support loading embedded frameworks for an ad-hoc signed app)

        case .app_sandbox:
            return [] // no description required; ["CSAllowJITUsageDescription"]

        case .cs_allow_jit:
            return [] // permitted, with no description required

        default:
            // all other entitlements require that their usage description is included in the Info.plist's FairUsage section
            return [entitlementKey]
        }

        // TODO: also permit using the system-defined `*UsageDescription` properties when they apply, such as "NSDesktopFolderUsageDescription", "NSDocumentsFolderUsageDescription", and "NSLocalNetworkUsageDescription"
    }
}

extension AppEntitlement : CaseIterable {
    public static let allCases: Set<Self> = developerEntitlements.union(securityEntitlements)
}


/// Top-level entitlement keys
public extension AppEntitlement {
    static let application_identifier = AppEntitlement("application-identifier")

    static let informationalEntitlements = Set<Self>([
        .application_identifier,
    ])
}



/// secutiry-specific keys
public extension AppEntitlement {

    /// The key begins with "secutiry."
    var isSecurityEntitlement: Bool {
        entitlementKey.hasPrefix("com.apple.security.")
    }

    /// All the known security-related entitlements (typically for macOS)
    static let securityEntitlements = Set<Self>([
        .app_sandbox,
        .get_task_allow,
        .network_client,
        .network_server,
        .device_camera,
        .device_microphone,
        .device_usb,
        .print,
        .device_bluetooth,
        .device_audio_video_bridging,
        .device_firewire,
        .device_serial,
        .device_audio_input,
        .personal_information_addressbook,
        .personal_information_location,
        .personal_information_calendars,
        .files_user_selected_read_only,
        .files_user_selected_read_write,
        .files_user_selected_executable,
        .files_downloads_read_only,
        .files_downloads_read_write,
        .assets_pictures_read_only,
        .assets_pictures_read_write,
        .assets_music_read_only,
        .assets_music_read_write,
        .assets_movies_read_only,
        .assets_movies_read_write,
        .files_all,
        .cs_allow_jit,
        .cs_debugger,
        .cs_allow_unsigned_executable_memory,
        .cs_allow_dyld_environment_variables,
        .cs_disable_library_validation,
        .cs_disable_executable_page_protection,
        .scripting_targets,
        .application_groups,
        .files_bookmarks_app_scope,
        .files_bookmarks_document_scope,
        .files_home_relative_path_read_only,
        .files_home_relative_path_read_write,
        .files_absolute_path_read_only,
        .files_absolute_path_read_write,
        .apple_events,
        .audio_unit_host,
        .iokit_user_client_class,
        .mach_lookup_global_name,
        .mach_register_global_name,
        .shared_preference_read_only,
        .shared_preference_read_write,
    ])


    // MARK: Essentials

    /// A Boolean value that indicates whether the app may use access control technology to contain damage to the system and user data if an app is compromised.
    static let app_sandbox = AppEntitlement("com.apple.security.app-sandbox")

    static let get_task_allow = AppEntitlement("com.apple.security.get-task-allow")

    // MARK: Network

    /// A Boolean value indicating whether your app may open outgoing network connections.
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_network_client
    static let network_client = AppEntitlement("com.apple.security.network.client")

    /// A Boolean value indicating whether your app may listen for incoming network connections.
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_network_server
    static let network_server = AppEntitlement("com.apple.security.network.server")

    // MARK: Hardware

    /// A Boolean value that indicates whether the app may interact with the built-in and external cameras, and capture movies and still images.
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_device_camera
    static let device_camera = AppEntitlement("com.apple.security.device.camera")

    /// A Boolean value that indicates whether the app may use the microphone.
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_device_microphone
    static let device_microphone = AppEntitlement("com.apple.security.device.microphone")

    /// A Boolean value indicating whether your app may interact with USB devices.
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_device_usb
    static let device_usb = AppEntitlement("com.apple.security.device.usb")

    /// A Boolean value indicating whether your app may print a document.
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_print
    static let print = AppEntitlement("com.apple.security.print")

    /// A Boolean value indicating whether your app may interact with Bluetooth devices.
    /// see: https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html#//apple_ref/doc/uid/TP40011195-CH4-SW21
    static let device_bluetooth = AppEntitlement("com.apple.security.device.bluetooth")

    /// Interaction with AVB devices by using the Audio Video Bridging framework
    /// see: https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html#//apple_ref/doc/uid/TP40011195-CH4-SW21
    static let device_audio_video_bridging = AppEntitlement("com.apple.security.device.audio-video-bridging")

    /// Interaction with FireWire devices (currently, does not support interaction with audio/video devices such as DV cameras)
    /// see: https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html#//apple_ref/doc/uid/TP40011195-CH4-SW21
    static let device_firewire = AppEntitlement("com.apple.security.device.firewire")

    /// Interaction with serial devices
    /// see: https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html#//apple_ref/doc/uid/TP40011195-CH4-SW21
    static let device_serial = AppEntitlement("com.apple.security.device.serial")

    /// Recording of audio using the built-in microphone, if available, along with access to audio input using any Core Audio API that supports audio input
    static let device_audio_input = AppEntitlement("com.apple.security.device.audio-input")

    // MARK: App Data

    /// A Boolean value that indicates whether the app may have read-write access to contacts in the user's address book.
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_personal-information_addressbook
    static let personal_information_addressbook = AppEntitlement("com.apple.security.personal-information.addressbook")
    /// A Boolean value that indicates whether the app may access location information from Location Services.
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_personal-information_location
    static let personal_information_location = AppEntitlement("com.apple.security.personal-information.location")

    /// A Boolean value that indicates whether the app may have read-write access to the user's calendar.
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_personal-information_calendars
    static let personal_information_calendars = AppEntitlement("com.apple.security.personal-information.calendars")

    // MARK: File Access

    /// A Boolean value that indicates whether the app may have read-only access to files the user has selected using an Open or Save dialog.
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_files_user-selected_read-only
    static let files_user_selected_read_only = AppEntitlement("com.apple.security.files.user-selected.read-only")

    /// A Boolean value that indicates whether the app may have read-write access to files the user has selected using an Open or Save dialog.
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_files_user-selected_read-write
    static let files_user_selected_read_write = AppEntitlement("com.apple.security.files.user-selected.read-write")

    /// Allows apps to write executable files
    /// - See: https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html#//apple_ref/doc/uid/TP40011195-CH4-SW6
    static let files_user_selected_executable = AppEntitlement("com.apple.security.files.user-selected.executable")

    /// A Boolean value that indicates whether the app may have read-only access to the Downloads folder.
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_files_downloads_read-only
    static let files_downloads_read_only = AppEntitlement("com.apple.security.files.downloads.read-only")

    /// A Boolean value that indicates whether the app may have read-write access to the Downloads folder.
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_files_downloads_read-write
    static let files_downloads_read_write = AppEntitlement("com.apple.security.files.downloads.read-write")

    /// A Boolean value that indicates whether the app may have read-only access to the Pictures folder.
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_assets_pictures_read-only
    static let assets_pictures_read_only = AppEntitlement("com.apple.security.assets.pictures.read-only")

    /// A Boolean value that indicates whether the app may have read-write access to the Pictures folder.
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_assets_pictures_read-write
    static let assets_pictures_read_write = AppEntitlement("com.apple.security.assets.pictures.read-write")

    /// A Boolean value that indicates whether the app may have read-only access to the Music folder.
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_assets_music_read-only
    static let assets_music_read_only = AppEntitlement("com.apple.security.assets.music.read-only")

    /// A Boolean value that indicates whether the app may have read-write access to the Music folder.
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_assets_music_read-write
    static let assets_music_read_write = AppEntitlement("com.apple.security.assets.music.read-write")

    /// A Boolean value that indicates whether the app may have read-only access to the Movies folder.
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_assets_movies_read-only
    static let assets_movies_read_only = AppEntitlement("com.apple.security.assets.movies.read-only")

    /// A Boolean value that indicates whether the app may have read-write access to the Movies folder.
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_assets_movies_read-write
    static let assets_movies_read_write = AppEntitlement("com.apple.security.assets.movies.read-write")

    /// A Boolean value that indicates whether the app may have access to all files
    /// - See: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_files_all
    static let files_all = AppEntitlement("com.apple.security.files.all")

    // MARK: Other

    /// Allow Execution of JIT-compiled Code Entitlement
    static let cs_allow_jit = AppEntitlement("com.apple.security.cs.allow-jit")
    /// Debugging Tool Entitlement
    static let cs_debugger = AppEntitlement("com.apple.security.cs.debugger")

    /// Allow Unsigned Executable Memory Entitlement (Forbidden)
    static let cs_allow_unsigned_executable_memory = AppEntitlement("com.apple.security.cs.allow-unsigned-executable-memory")

    /// Allow DYLD Environment Variables Entitlement (Forbidden)
    static let cs_allow_dyld_environment_variables = AppEntitlement("com.apple.security.cs.allow-dyld-environment-variables")

    /// A Boolean value that indicates whether the app loads arbitrary plug-ins or frameworks, without requiring code signing.
    /// https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_cs_disable-library-validation
    static let cs_disable_library_validation = AppEntitlement("com.apple.security.cs.disable-library-validation")

    /// Disable Executable Memory Protection Entitlement (Forbidden)
    static let cs_disable_executable_page_protection = AppEntitlement("com.apple.security.cs.disable-executable-page-protection")


    /// Ability to use specific AppleScript scripting access groups within a specific scriptable app
    /// - See: https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html#//apple_ref/doc/uid/TP40011195-CH4-SW25
    static let scripting_targets = AppEntitlement("com.apple.security.scripting-targets")

    /// Allows access to group containers that are shared among multiple apps produced by a single development team, and allows certain additional interprocess communication between the apps
    static let application_groups = AppEntitlement("com.apple.security.application-groups")

    static let files_bookmarks_app_scope = AppEntitlement("com.apple.security.files.bookmarks.app-scope")
    static let files_bookmarks_document_scope = AppEntitlement("com.apple.security.files.bookmarks.document-scope")

    // MARK: Temporary Exceptions

    /// This is an array of paths relative to the user-directory, but must begin with a slash
    static let files_home_relative_path_read_only = AppEntitlement("com.apple.security.temporary-exception.files.home-relative-path.read-only")
    /// This is an array of paths relative to the user-directory, but must begin with a slash
    static let files_home_relative_path_read_write = AppEntitlement("com.apple.security.temporary-exception.files.home-relative-path.read-write")
    /// This is an array of absolute paths beginning with a slash
    static let files_absolute_path_read_only = AppEntitlement("com.apple.security.temporary-exception.files.absolute-path.read-only")
    /// This is an array of absolute paths beginning with a slash
    static let files_absolute_path_read_write = AppEntitlement("com.apple.security.temporary-exception.files.absolute-path.read-write")

    static let apple_events = AppEntitlement("com.apple.security.temporary-exception.apple-events")
    static let audio_unit_host = AppEntitlement("com.apple.security.temporary-exception.audio-unit-host")
    static let iokit_user_client_class = AppEntitlement("com.apple.security.temporary-exception.iokit-user-client-class")
    static let mach_lookup_global_name = AppEntitlement("com.apple.security.temporary-exception.mach-lookup.global-name")
    static let mach_register_global_name = AppEntitlement("com.apple.security.temporary-exception.mach-register.global-name")
    static let shared_preference_read_only = AppEntitlement("com.apple.security.temporary-exception.shared-preference.read-only")
    static let shared_preference_read_write = AppEntitlement("com.apple.security.temporary-exception.shared-preference.read-write")
}

/// developer-specific keys
/// https://developer.apple.com/documentation/bundleresources/entitlements
public extension AppEntitlement {
    /// The key begins with "developer."
    var isDeveloperEntitlement: Bool {
        entitlementKey.hasPrefix("com.apple.developer.")
    }

    /// All the known developer-related entitlements (typically for iOS)
    static let developerEntitlements = Set<Self>([
        .mailClient,
        .webBrowser,
        .autofillCredentialProvider,
        .signWithApple,
        .contacts,
        .classKit,
        .automaticAssesmentConfiguration,
        .gameCenter,
        .healthKit,
        .healthKitCapabilities,
        .homeKit,
        .iCloudDevelopmentContainersIdentifiers,
        .iCloudContainersEnvironment,
        .iCloudContainerIdentifiers,
        .iCloudServices,
        .iCloudKeyValueStore,
        .interAppAudio,
        .networkExtensions,
        .personalVPN,
        .apsEnvironment,
        .keychainAccessGroups,
        .dataProtection,
        .siri,
        .passTypeIDs,
        .merchantIDs,
        .wifiInfo,
        .externalAccessoryConfiguration,
        .multipath,
        .hotspotConfiguration,
        .nfcTagReaderSessionFormats,
        .associatedDomains,
        .maps,
        .driverKit,
    ])

    static let teamIdentifier = AppEntitlement("com.apple.developer.team-identifier")

    /// https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_developer_mail-client
    static let mailClient = AppEntitlement("com.apple.developer.mail-client")

    /// https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_developer_web-browser
    static let webBrowser = AppEntitlement("com.apple.developer.web-browser")

    static let autofillCredentialProvider = AppEntitlement("com.apple.developer.authentication-services.autofill-credential-provider")
    static let signWithApple = AppEntitlement("com.apple.developer.applesignin")
    static let contacts = AppEntitlement("com.apple.developer.contacts.notes")
    static let classKit = AppEntitlement("com.apple.developer.ClassKit-environment")
    static let automaticAssesmentConfiguration = AppEntitlement("com.apple.developer.automatic-assessment-configuration")
    static let gameCenter = AppEntitlement("com.apple.developer.game-center")
    static let healthKit = AppEntitlement("com.apple.developer.healthkit")
    static let healthKitCapabilities = AppEntitlement("com.apple.developer.healthkit.access")
    static let homeKit = AppEntitlement("com.apple.developer.homekit")
    static let iCloudDevelopmentContainersIdentifiers = AppEntitlement("com.apple.developer.icloud-container-development-container-identifiers")
    static let iCloudContainersEnvironment = AppEntitlement("com.apple.developer.icloud-container-environment")
    static let iCloudContainerIdentifiers = AppEntitlement("com.apple.developer.icloud-container-identifiers")
    static let iCloudServices = AppEntitlement("com.apple.developer.icloud-services")
    static let iCloudKeyValueStore = AppEntitlement("com.apple.developer.ubiquity-kvstore-identifier")
    /// Deprecated: Inter-App Audio is deprecated in iOS 13 and is unavailable when running iPad apps in macOS.
    static let interAppAudio = AppEntitlement("inter-app-audio")
    static let networkExtensions = AppEntitlement("com.apple.developer.networking.networkextension")
    static let personalVPN = AppEntitlement("com.apple.developer.networking.vpn.api")
    static let apsEnvironment = AppEntitlement("aps-environment")
    static let keychainAccessGroups = AppEntitlement("keychain-access-groups")
    static let dataProtection = AppEntitlement("com.apple.developer.default-data-protection")
    static let siri = AppEntitlement("com.apple.developer.siri")
    static let passTypeIDs = AppEntitlement("com.apple.developer.pass-type-identifiers")
    static let merchantIDs = AppEntitlement("com.apple.developer.in-app-payments")
    static let wifiInfo = AppEntitlement("com.apple.developer.networking.wifi-info")
    static let externalAccessoryConfiguration = AppEntitlement("com.apple.external-accessory.wireless-configuration")
    static let multipath = AppEntitlement("com.apple.developer.networking.multipath")
    static let hotspotConfiguration = AppEntitlement("com.apple.developer.networking.HotspotConfiguration")
    static let nfcTagReaderSessionFormats = AppEntitlement("com.apple.developer.nfc.readersession.formats")
    static let associatedDomains = AppEntitlement("com.apple.developer.associated-domains")
    /// Deprecated: Using Maps no longer requires an entitlement.
    static let maps = AppEntitlement("com.apple.developer.maps")
    static let driverKit = AppEntitlement("com.apple.developer.driverkit.transport.pci")
}


public struct UsageDescriptionKey : RawRepresentable, Codable, Hashable {
    public let rawValue: String

    public init(_ name: String) {
        self.rawValue = name
    }

    public init(rawValue name: String) {
        self.rawValue = name
    }
}

public extension UsageDescriptionKey {

    // MARK: tracking
    static let NSUserTrackingUsageDescription = UsageDescriptionKey("NSUserTrackingUsageDescription")


    // MARK: location

    static let NSLocationUsageDescription = UsageDescriptionKey("NSLocationUsageDescription")

    static let NSLocationDefaultAccuracyReduced = UsageDescriptionKey("NSLocationDefaultAccuracyReduced")

    static let NSLocationAlwaysUsageDescription = UsageDescriptionKey("NSLocationAlwaysUsageDescription")

    static let NSLocationTemporaryUsageDescriptionDictionary = UsageDescriptionKey("NSLocationTemporaryUsageDescriptionDictionary")

    static let NSLocationWhenInUseUsageDescription = UsageDescriptionKey("NSLocationWhenInUseUsageDescription")

    static let NSLocationAlwaysAndWhenInUseUsageDescription = UsageDescriptionKey("NSLocationAlwaysAndWhenInUseUsageDescription")

    static let NSWidgetWantsLocation = UsageDescriptionKey("NSWidgetWantsLocation")


    // MARK: network

    static let NSVoIPUsageDescription = UsageDescriptionKey("NSVoIPUsageDescription")

    static let NSNearbyInteractionUsageDescription = UsageDescriptionKey("NSNearbyInteractionUsageDescription")

    static let NSNearbyInteractionAllowOnceUsageDescription = UsageDescriptionKey("NSNearbyInteractionAllowOnceUsageDescription")


    // MARK: voice

    static let NSSiriUsageDescription = UsageDescriptionKey("NSSiriUsageDescription")

    static let NSSpeechRecognitionUsageDescription = UsageDescriptionKey("NSSpeechRecognitionUsageDescription")


    // MARK: hardware

    static let NSSensorKitUsageDescription = UsageDescriptionKey("NSSensorKitUsageDescription")

    static let NSMicrophoneUsageDescription = UsageDescriptionKey("NSMicrophoneUsageDescription")

    static let NSCameraUsageDescription = UsageDescriptionKey("NSCameraUsageDescription")

    static let NSBluetoothUsageDescription = UsageDescriptionKey("NSBluetoothUsageDescription")

    static let NSBluetoothAlwaysUsageDescription = UsageDescriptionKey("NSBluetoothAlwaysUsageDescription")

    static let NSBluetoothPeripheralUsageDescription = UsageDescriptionKey("NSBluetoothPeripheralUsageDescription")

    static let NSBluetoothWhileInUseUsageDescription = UsageDescriptionKey("NSBluetoothWhileInUseUsageDescription")


    static let NFCReaderUsageDescription = UsageDescriptionKey("NFCReaderUsageDescription")


    // MARK: motion

    static let NSMotionUsageDescription = UsageDescriptionKey("NSMotionUsageDescription")

    static let NSFallDetectionUsageDescription = UsageDescriptionKey("NSFallDetectionUsageDescription")


    // MARK: databases

    static let NSRemindersUsageDescription = UsageDescriptionKey("NSRemindersUsageDescription")

    static let NSContactsUsageDescription = UsageDescriptionKey("NSContactsUsageDescription")

    static let NSCalendarsUsageDescription = UsageDescriptionKey("NSCalendarsUsageDescription")

    static let NSPhotoLibraryAddUsageDescription = UsageDescriptionKey("NSPhotoLibraryAddUsageDescription")

    static let NSPhotoLibraryUsageDescription = UsageDescriptionKey("NSPhotoLibraryUsageDescription")


    // MARK: services

    static let NSAppleMusicUsageDescription = UsageDescriptionKey("NSAppleMusicUsageDescription")

    static let NSHomeKitUsageDescription = UsageDescriptionKey("NSHomeKitUsageDescription")

    static let NSVideoSubscriberAccountUsageDescription = UsageDescriptionKey("NSVideoSubscriberAccountUsageDescription")


    // MARK: games

    static let NSGKFriendListUsageDescription = UsageDescriptionKey("NSGKFriendListUsageDescription")


    // MARK: health

    static let NSHealthShareUsageDescription = UsageDescriptionKey("NSHealthShareUsageDescription")

    static let NSHealthUpdateUsageDescription = UsageDescriptionKey("NSHealthUpdateUsageDescription")

    static let NSHealthClinicalHealthRecordsShareUsageDescription = UsageDescriptionKey("NSHealthClinicalHealthRecordsShareUsageDescription")


    // MARK: misc

    static let NSAppleEventsUsageDescription = UsageDescriptionKey("NSAppleEventsUsageDescription")

    static let NSFocusStatusUsageDescription = UsageDescriptionKey("NSFocusStatusUsageDescription")

    static let NSLocalNetworkUsageDescription = UsageDescriptionKey("NSLocalNetworkUsageDescription")

    static let NSFaceIDUsageDescription = UsageDescriptionKey("NSFaceIDUsageDescription")


    // MARK: standard locations (macOS)
    static let NSDesktopFolderUsageDescription = UsageDescriptionKey("NSDesktopFolderUsageDescription")

    static let NSDocumentsFolderUsageDescription = UsageDescriptionKey("NSDocumentsFolderUsageDescription")

    static let NSDownloadsFolderUsageDescription = UsageDescriptionKey("NSDownloadsFolderUsageDescription")


    // MARK: misc (macOS)
    static let NSSystemExtensionUsageDescription = UsageDescriptionKey("NSSystemExtensionUsageDescription")

    static let NSSystemAdministrationUsageDescription = UsageDescriptionKey("NSSystemAdministrationUsageDescription")

    static let NSFileProviderDomainUsageDescription = UsageDescriptionKey("NSFileProviderDomainUsageDescription")

    static let NSFileProviderPresenceUsageDescription = UsageDescriptionKey("NSFileProviderPresenceUsageDescription")

    static let NSNetworkVolumesUsageDescription = UsageDescriptionKey("NSNetworkVolumesUsageDescription")

    static let NSRemovableVolumesUsageDescription = UsageDescriptionKey("NSRemovableVolumesUsageDescription")

}

public struct AppEntitlements {
    static let empty: AppEntitlements = AppEntitlements([:])

    public var values: [String: Any]

    init(_ values: [String: Any]) {
        self.values = values
    }

    public var count: Int {
        values.count
    }

    /// Returns the entitlement values as a codable JSON struct.
    public func json() throws -> JSON {
        try Plist(rawValue: values as NSDictionary).json()
    }

    public func value(forKey key: AppEntitlement) -> Any? {
        values[key.rawValue]
    }

    static func readEntitlements(from data: Data) -> AppEntitlements {
        guard let rawValues = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return .empty
        }
        return AppEntitlements(rawValues)
    }
}
