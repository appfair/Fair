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

### Installation

You can install Fairtool locally by running:

```shell
curl -fsSL https://appfair.net/install-fairtool.sh | sh
```

### Running from Source

The run the fairtool from a local build
on a machine with Swift 5.10 or higher:

```shell
git clone https://github.com/appfair/Fair
cd Fair
swift run fairtool --help
```

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


## Fair Swift Modules

The `fairtool` is powered by the `Fair` package, which is a
zero-dependency cross-platform set of modules written in Swift.
There are four top-level modules in the package:

### FairCore

The `FairCore` module is the lowest-level set of data structures and
algorithms shared throughout the package.
It supports macOS 12+, iOS 15+, and Linux (Windows is close,
but needs a fix for missing zlib; Android is TBD).

### FairExpo

The `FairExpo` module provides a cross-platform set of networking
protocols, such as utilities for interacting with a
`GraphQLEndpointService`

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


