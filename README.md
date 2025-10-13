The `fairtool` is a cross-platform (Linux & macOS) command-line utility for 
managing an ecosystem of apps.
It is powered by the Fair package, which is a zero-dependency 
cross-platform (Linux, macOS, & iOS) set of Swift 5 modules.

The Fair package is used to create and maintain app distribution networks such as 
[appfair.org](https://appfair.org).

## fairtool

The functionality of the `Fair` module can best be illustrated by the
capabilities of the `fairtool`, which is a command-line utility for
macOS (15+) and Linux.

### fairtool artifact info _file_.app

The "app info" command will examine a macOS `.app` folder 
or an unencrypted `.ipa` file or url
and output a JSON representation of the contents of the app's
`Info.plist` along with the entitlements embedded within the 
app's primary executable.

```json5
// fairtool artifact info /System/Applications/Calculator.app
[
  {
    "entitlements" : [
      {
        "com.apple.security.app-sandbox" : true,
        "com.apple.security.files.user-selected.read-write" : true,
        "com.apple.security.network.client" : true,
        "com.apple.security.print" : true
      },
      {
        "com.apple.security.app-sandbox" : true,
        "com.apple.security.files.user-selected.read-write" : true,
        "com.apple.security.network.client" : true,
        "com.apple.security.print" : true
      }
    ],
    "info" : {
      "BuildMachineOSBuild" : "20A241133",
      "CFBundleDevelopmentRegion" : "English",
      "CFBundleExecutable" : "Calculator",
      "CFBundleHelpBookFolder" : "Calculator.help",
      "CFBundleHelpBookName" : "com.apple.Calculator.help",
      "CFBundleIconFile" : "AppIcon",
      "CFBundleIconName" : "AppIcon",
      "CFBundleIdentifier" : "com.apple.calculator",
      "CFBundleInfoDictionaryVersion" : "6.0",
      "CFBundleName" : "Calculator",
      "CFBundlePackageType" : "APPL",
      "CFBundleShortVersionString" : "10.16",
      "CFBundleSignature" : "????",
      "CFBundleSupportedPlatforms" : [
        "MacOSX"
      ],
      "CFBundleVersion" : "223",
      "CTIgnoreUserFonts" : true,
      "DTCompiler" : "com.apple.compilers.llvm.clang.1_0",
      "DTPlatformBuild" : "13E6049a",
      "DTPlatformName" : "macosx",
      "DTPlatformVersion" : "12.4",
      "DTSDKBuild" : "21F64",
      "DTSDKName" : "macosx12.4.internal",
      "DTXcode" : "1330",
      "DTXcodeBuild" : "13E6049a",
      "LSApplicationCategoryType" : "public.app-category.utilities",
      "LSApplicationSecondaryCategoryType" : "public.app-category.productivity",
      "LSHasLocalizedDisplayName" : true,
      "LSMinimumSystemVersion" : "12.4",
      "NSMainNibFile" : "Calculator",
      "NSPrincipalClass" : "NSApplication",
      "NSSupportsSuddenTermination" : true
    },
    "url" : "file:///System/Applications/Calculator.app/"
  }
]
```

The `info` property contains a JSON-ized form of the contents 
if the `Info.plist`.
The `entitlements` array contains the entitlements extracted from
the binary. Note that in the case of multi-architecture binaries 
(such as a "universal binary"), one set of entitlements will be
output for each processor architectures in the Mach-O binary.


### fairtool artifact info _url_.ipa

The fairtool can also output the same information for an unencrypted
iOS .ipa file, either a local file or a remote URL:

```json5
// fairtool artifact info https://github.com/Cloud-Cuckoo/App/releases/latest/download/Cloud-Cuckoo-iOS.ipa
[
  {
    "entitlements": [],
    "info": {
      "CFBundleName": "Cloud Cuckoo",
      "CFBundleIdentifier": "app.Cloud-Cuckoo",
      "CFBundleVersion": "469",
      "CFBundleShortVersionString": "0.9.108",
      "CFBundleExecutable": "Cloud Cuckoo",
      "CFBundleIcons": {
        "CFBundlePrimaryIcon": {
          "CFBundleIconFiles": [
            "AppIcon60x60"
          ],
          "CFBundleIconName": "AppIcon"
        }
      },
      "AppSource": {
        "developerName": "Fair Apps <fairapps@appfair.net>",
        "fundingLinks": [
          {
            "localizedDescription": "Help fund upcoming challenges and new additions to the whimsical and award-winning “Cloud Cuckoo” game. Fun for all ages!",
            "localizedTitle": "Support the development of “Cloud Cuckoo”",
            "platform": "GITHUB",
            "url": "https://github.com/Cloud-Cuckoo"
          }
        ],
        "localizedDescription": "Chase on the Cuckoo around the screen! This is a silly little game for the App Fair.",
        "subtitle": "A whimsical game of excitement and delight",
        "versionDescription": "Bug fixes and performance improvements."
      },
      "BuildMachineOSBuild": "21F79",
      "CFBundleSupportedPlatforms": [
        "iPhoneOS"
      ],
      "DTCompiler": "com.apple.compilers.llvm.clang.1_0",
      "DTPlatformBuild": "19C51",
      "DTPlatformName": "iphoneos",
      "DTPlatformVersion": "15.2",
      "DTSDKBuild": "19C51",
      "DTSDKName": "iphoneos15.2",
      "DTXcode": "1321",
      "DTXcodeBuild": "13C100",
      "ITSAppUsesNonExemptEncryption": false,
      "LSApplicationQueriesSchemes": [
        "appfair"
      ],
      "LSSupportsOpeningDocumentsInPlace": true,
      "NSAppleEventsUsageDescription": "AppleScript can be used by this app.",
      "NSAppleScriptEnabled": true,
      "NSAppTransportSecurity": {
        "NSAllowsArbitraryLoads": true
      },
      "NSHumanReadableCopyright": "GNU Affero General Public License"
    },
    "url": "https://github.com/Cloud-Cuckoo/App/releases/latest/download/Cloud-Cuckoo-iOS.ipa"
  }
]

```

### fairtool JSON output

Most of the fairtool's informational operations will output
well-formed JSON. This is so it can be used in conjunction with
other tools.

One such tools is the popular `jq` utility, which can be used to format,
filter, and re-structure JSON. For example, to examine an app's
"*UsageDescription" properties (which will give insight into which
privacy-sensitive operations the app is capable of performing), you might run:

```
% fairtool artifact info /Applications/Signal.app | jq '.[].info | with_entries(select(.key|match("UsageDescription")))[]'

"This app needs access to Bluetooth"
"This app needs access to the camera"
"This app needs access to the microphone"
```

Another useful application might be to download and check the
version of an online app download. For example:

```
% fairtool artifact info https://github.com/Cloud-Cuckoo/App/releases/latest/download/Cloud-Cuckoo-macOS.zip | jq '.[].info.CFBundleShortVersionString'

downloading from URL: https://github.com/Cloud-Cuckoo/App/releases/latest/download/Cloud-Cuckoo-macOS.zip
extracting info: https://github.com/Cloud-Cuckoo/App/releases/latest/download/Cloud-Cuckoo-macOS.zip

"0.9.95"
```

#### Multi-line JSON output

When the fairtool command outputs JSON, it does it as a single top-level
array with one  element for each command line argument.
This allows the output to be produced as each (potentially slow) resources is
acquired and analyzed.

For example, the following command may take some time to complete:

```
% fairtool artifact info /System/Applications/*.app | jq '.[].info.CFBundleName'

"App Store"
"Automator"
"Books"
…
"TV"
"TextEdit"
"Time Machine"
"VoiceMemos"
```


The end result will not be printed until the command has completed,
since `jq` is waiting for the entire array before it will process
the command.

You can, instead, "promote" the JSON output from an embedded array
to the straight output of raw JSON objects using the `-J` flag,
which will then enable `jq` to process them as they are produced.

Contrast this command with the one above:

```
% fairtool artifact info -J /System/Applications/*.app | jq '.info.CFBundleName'
```

The output will be the same, but the latter command with the `-J`
flag will output each element in turn as it is downloaded.
This can be especially important when checking potentially slow
access to online resources, or when processing may archives at once.


### fairtool source create

The `fairtool source create` command will analyze the information
from `fairtool artifact info` and generate an App Source Catalog JSON blob. 
This catalog format is supported by app installation tools like
[The App Fair](https://appfair.app) on macOS and
[AltStore](https://altstore.io) on iOS.

The tool has the following options:

```
% fairtool source create --help 

OVERVIEW: Create a source from the specified .ipa or .zip.

USAGE: fairtool source create [--verbose] [--quiet] [--promote-json] [--catalog-name <name>] [--catalog-identifier <id>] [--catalog-source-url <url>] [--app-localized-description <desc> ...] [--app-version-description <desc> ...] [--app-subtitle <title> ...] [--app-developer-name <email> ...] [--app-download-url <URL> ...] [<apps> ...]

ARGUMENTS:
  <apps>                  path(s) or url(s) for app folders or ipa archives

OPTIONS:
  -v, --verbose           whether to display verbose messages.
  -q, --quiet             whether to be suppress output.
  -J, --promote-json      exclude root JSON array from output.
  --catalog-name <name>   the name of the catalog.
  --catalog-identifier <id>
                          the identifier of the catalog.
  --catalog-source-url <url>
                          the source URL of the catalog.
  --app-localized-description <desc>
                          the default description(s) for the app(s).
  --app-version-description <desc>
                          the default versionDescription for the app(s).
  --app-subtitle <title>  the default subtitle(s) for the app(s).
  --app-developer-name <email>
                          the default developer name(s) for the app(s).
  --app-download-url <URL>
                          the download URLfor the app(s).
  -h, --help              Show help information.
```

An example of the catalog output is as follows:

```json5
// % fairtool source create https://github.com/Cloud-Cuckoo/App/releases/download/0.9.91/Cloud-Cuckoo-iOS.ipa

{
  "identifier": "CATALOG_IDENTIFIER",
  "name": "CATALOG_NAME",
  "apps": [
    {
      "bundleIdentifier": "app.Cloud-Cuckoo",
      "developerName": "DEVELOPER_NAME",
      "downloadURL": "https://github.com/Cloud-Cuckoo/App/releases/download/0.9.91/Cloud-Cuckoo-iOS.ipa",
      "localizedDescription": "LOCALIZED_DESCRIPTION",
      "name": "Cloud Cuckoo",
      "permissions": [
        {
          "type": "usage",
          "usage": "NSAppleEventsUsageDescription",
          "usageDescription": "AppleScript can be used by this app."
        }
      ],
      "screenshotURLs": [],
      "sha256": "01398e19555b65b7c457d02e68d0e0ca34cf078867a674aee019a7f28da70d64",
      "size": 5118243,
      "subtitle": "SUBTITLE",
      "version": "0.9.91",
      "versionDate": "2022-06-30T20:23:12Z",
      "versionDescription": "VERSION_DESCRIPTION"
    }
  ]
}
```

#### Default properties for source create

Properties such as `subtitle` and `developerName` will be derived from the
app's Info.plist's property named `AppSource`, which is expected to be a dictionary
keyed by the corresponding property names.

An abridged example of an `Info.plist` with the `AppSource` property:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AppSource</key>
    <dict>
        <key>subtitle</key>
        <string>A whimsical game of excitement and delight</string>
        <key>localizedDescription</key>
        <string>Chase on the Cuckoo around the screen! This is a silly little game for the App Fair.</string>
        <key>developerName</key>
        <string>Fair Apps &lt;fairapps@appfair.net&gt;</string>
        <key>versionDescription</key>
        <string>Bug fixes and performance improvements.</string>
        <key>fundingLinks</key>
        <array>
            <dict>
                <key>platform</key>
                <string>GITHUB</string>
                <key>url</key>
                <string>https://github.com/Cloud-Cuckoo</string>
                <key>localizedTitle</key>
                <string>Support the development of “Cloud Cuckoo”</string>
                <key>localizedDescription</key>
                <string>Help fund upcoming challenges and new additions to the whimsical and award-winning “Cloud Cuckoo” game. Fun for all ages!</string>
            </dict>
        </array>
    </dict>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
    <key>CFBundleShortVersionString</key>
    <string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key>
    <string>$(CURRENT_PROJECT_VERSION)</string>
</dict>
</plist>
```

With that metadata embedded in the .ipa, the `fairtool source create` command
will have enough information to generate a more complete catalog entry.

The benefit of this method is that the app artifact alone is sufficient
for the creation of a catalog without requiring any additional
sources of metadata.

```json5
// fairtool source create https://github.com/Cloud-Cuckoo/App/releases/download/0.9.99/Cloud-Cuckoo-iOS.ipa

{
  "identifier": "CATALOG_IDENTIFIER",
  "name": "CATALOG_NAME",
  "apps": [
    {
      "bundleIdentifier": "app.Cloud-Cuckoo",
      "developerName": "Fair Apps <fairapps@appfair.net>",
      "downloadURL": "https://github.com/Cloud-Cuckoo/App/releases/download/0.9.99/Cloud-Cuckoo-iOS.ipa",
      "fundingLinks": [
        {
          "localizedDescription": "Help fund upcoming challenges and new additions to the whimsical and award-winning “Cloud Cuckoo” game. Fun for all ages!",
          "localizedTitle": "Support the development of “Cloud Cuckoo”",
          "platform": "GITHUB",
          "url": "https://github.com/Cloud-Cuckoo"
        }
      ],
      "localizedDescription": "Chase on the Cuckoo around the screen! This is a silly little game for the App Fair.",
      "name": "Cloud Cuckoo",
      "permissions": [
        {
          "type": "usage",
          "usage": "NSAppleEventsUsageDescription",
          "usageDescription": "AppleScript can be used by this app."
        }
      ],
      "screenshotURLs": [],
      "sha256": "8a3903588bece74c00bef1329f9dd6cc9684e78be049b1b4e2325ce07d78e085",
      "size": 5162625,
      "subtitle": "A whimsical game of excitement and delight",
      "version": "0.9.99",
      "versionDate": "2022-07-03T04:51:21Z",
      "versionDescription": "Bug fixes and performance improvements."
    }
  ]
}
```


### fairtool source verify

The `fairtool source verify` can be used to check the validity of the
apps in a JSON catalog.

For example:

```shell
% fairtool source create https://github.com/Cloud-Cuckoo/App/releases/latest/download/Cloud-Cuckoo-iOS.ipa > catalog.json

% fairtool source verify catalog.json

[
  {
    "app": {
      "bundleIdentifier": "app.Cloud-Cuckoo"
      "sha256": "56e748bf053aff8612702ba9f1aa13031ef0c29313cc4047e3176b9ba8526686",
      "size": 5136274
    }
  }
]
```

If, for example, the resource at the `downloadURL` no longer matches the
SHA256 checksum or file size, the catalog's validation errors 
would look like:

```json
[
  {
    "app": {
      "bundleIdentifier": "app.Cloud-Cuckoo"
      "size": 5136274,
      "sha256": "56e748bf053aff8612702ba9f1aa13031ef0c29313cc4047e3176b9ba8526686"
    },
    "failures": [
      {
        "type": "size_mismatch",
        "message": "Download size mismatch (5136274 vs. 5052688) from: https://github.com/Cloud-Cuckoo/App/releases/latest/download/Cloud-Cuckoo-iOS.ipa"
      },
      {
        "type": "checksum_failed",
        "message": "Checksum mismatch (56e748bf053aff8612702ba9f1aa13031ef0c29313cc4047e3176b9ba8526686 vs. 07e74b8db6eed309a6cdc92e40d5f7b7fd00922126f8ff49085516dd052ffa3a) from: https://github.com/Cloud-Cuckoo/App/releases/latest/download/Cloud-Cuckoo-iOS.ipa"
      }
    ]
  }
]
```

## Fair Swift Modules

The `fairtool` is powered by the `Fair` package, which is a
zero-dependency cross-platform set of modules written in Swift.
There are four top-level modules in the package:

### FairCore

The `FairCore` module is the lowest-level set of data structures and
algorithms shared throughout the package.
It supports macOS 12+, iOS 15+, and Linux (Windows is close,
but needs a fix for missing zlib; Android is TBD).

FairCore also contains utilities for 
[zip file handling](https://fair-ground.github.io/Fair/documentation/faircore/ziparchive)
and 
[XML parsing](https://fair-ground.github.io/Fair/documentation/faircore/xmlnode).

### FairExpo

The `FairExpo` module provides a cross-platform set of networking
protocols, such as utilities for interacting with a
[GraphQLEndpointService](https://fair-ground.github.io/Fair/documentation/fairexpo/graphqlendpointservice),
getting metadata from the
[HomebrewAPI](https://fair-ground.github.io/Fair/documentation/fairexpo/homebrewapi/),
and creating and verifying App Source catalogs with the
[https://fair-ground.github.io/Fair/documentation/fairexpo/appcatalogapi](AppCatalogAPI).

 `FairExpo` depends on `FairCore`.
 
## Swift Package Manager

In order to add the Fair module to an existing package named "App",


```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "App",
    platforms: [ .macOS(.v15), .iOS(.v17) ],
    products: [
        .library(name: "App", targets: ["App"]),
    ],
    dependencies: [
        .package(url: "https://github.com/appfair/Fair", "0.9.0"..<"2.0.0"), 
    ],
    targets: [
        .target(name: "App", dependencies: [
            // low-level data structures and utilities
            .product(name: "FairCore", package: "Fair"),
            // optional catalog utilities
            .product(name: "FairExpo", package: "Fair"),
        ]),
        .testTarget(name: "AppTests", dependencies: ["App"]),
    ]
)
```

## Roadmap

Until version 1.0 is achieved, minor and patch releases
can and will break source compatibility.
If this causes problems, pin your dependency to a specific version.
Binary compatibility is never guaranteed.


## License

This software is released under the GNU Affero General Public
License with an exception that permits it to be used
in apps that are distributed through restrictive channels,
such as a commercial App Store. For more details, see
the [`LICENSE.AGPL`](LICENSE.AGPL)
and [`LICENSE_EXCEPTION.FAIR`](LICENSE_EXCEPTION.FAIR)
files.


