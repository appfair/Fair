
# App Metadata Catalog Details

## Locales

Available fastlane locales (check fastlane_core/lib/fastlane_core/languages.rb):

All: ar-SA ca cs da de-DE el en-AU en-CA en-GB en-US es-ES es-MX fi fr-CA fr-FR he hi hr hu id it ja ko ms nl-NL no pl pt-BR pt-PT ro ru sk sv th tr uk vi zh-Hans zh-Hant

Apple App Store: (2020-08-24 - Available locales are not available as an endpoint in App Store Connect)
  ar-SA ca cs da de-DE el en-AU en-CA en-GB en-US es-ES es-MX fi fr-CA fr-FR he hi hr hu id it ja ko ms nl-NL no pl pt-BR pt-PT ro ru sk sv th tr uk vi zh-Hans zh-Hant
  
Google Play Store: (from supply/lib/supply/languages.rb ; see https://support.google.com/googleplay/android-developer/answer/3125566?hl=en)
  af, am, ar, az_AZ, be, bg, bn_BD, ca, cs_CZ, da_DK, de_DE, el_GR, en_AU, en_CA, en_GB, en_IN, en_SG, en_US, en_ZA, es_419, es_ES, es_US, et, eu_ES, fa, fi_FI, fil, fr_CA, fr_FR, gl_ES, hi_IN, hr, hu_HU, hy_AM, id, is_IS, it_IT, iw_IL, ja_JP, ka_GE, km_KH, kn_IN, ko_KR, ky_KG, lo_LA, lt, lv, mk_MK, ml_IN, mn_MN, mr_IN, ms, ms_MY, my_MM, ne_NP, nl_NL, no_NO, pl_PL, pt_BR, pt_PT, rm, ro, ru_RU, si_LK, sk, sl, sr, sv_SE, sw, ta_IN, te_IN, th, tr_TR, uk, vi, zh_CN, zh_HK, zh_TW, zu

see: spaceship/lib/assets/languageMapping.json


## Categories

There are four different category ontologies supported for the various app distribution channels.

An app's category can be derived from the Info.plist or  .xcconfig for INFOPLIST_KEY_LSApplicationCategoryType like "public.app-category.utilities", as well as the fastlane primary_category.txt, secondary_category.txt files.


### Apple App Store

https://docs.fastlane.tools/actions/deliver/#reference

primary_category, secondary_category
primary_first_sub_category, primary_second_sub_category

(note: probably needs updating)

FOOD_AND_DRINK, BUSINESS, EDUCATION, SOCIAL_NETWORKING, BOOKS, SPORTS, FINANCE, REFERENCE, GRAPHICS_AND_DESIGN, DEVELOPER_TOOLS, HEALTH_AND_FITNESS, MUSIC, WEATHER, TRAVEL, ENTERTAINMENT, STICKERS, GAMES, LIFESTYLE, MEDICAL, MAGAZINES_AND_NEWSPAPERS, UTILITIES, SHOPPING, PRODUCTIVITY, NEWS, PHOTO_AND_VIDEO, NAVIGATION

### AltStore

parse category from Info.plist and map it into https://faq.altstore.io/developers/make-a-source#category-string

developer, entertainment, games, lifestyle, other, photo-video, social, utilities


### Google Play Store

"Example categories""
https://support.google.com/googleplay/android-developer/answer/9859673?hl=en#zippy=%2Capps

Important: You must let us know if your app is a News app by declaring the News apps declaration. Learn more about requirements for news and news-related apps.

App or Game:

  - App: Art and Design, Auto and Vehicles, Beauty, Books and Reference, Business, Comics, Communications, Dating, Education, Entertainment, Events, Finance, Food and Drink, Health and Fitness, House and Home, Libraries and Demo, Lifestyle, Maps and Navigation, Medical, Music and Audio, News and Magazines, Parenting, Personalization, Photography, Productivity, Shopping, Social, Sports, Tools, Travel and Local, Video Players and Editors, Weather


### F-Droid

These are not canonical, but they are the categories listed in the
main f-droid repository (https://f-droid.org/repo/index-v2.json)

Connectivity, Development, Games, Graphics, Internet, Money, Multimedia, Navigation, Phone & SMS, Reading, Science & Education, Security, Sports & Health, System, Theming, Time, Writing




```
sructs:
file: path, size, sha256


- metadata
  - name: i18n
  - summary: i18n
  - description: i18n
  - icon: i18nfile
  - featureGraphic: i18nfile
  - platforms[]
    - name (ios/android)
    - ios
      - bundleID
      - marketplaceID
    - android
      - appid
    - screenshots: [deviceName: i18nfile]
    - summary(override): i18n
    - icon(override): i18nfile
    - versions[]
      - versionString
      - buildNumber
      - releaseNotes: i18n
      - artifacts
        - type (apk/ipa)
        - size
        - checksum (sha256)
        - url
        - requirements
          - ios: minimum/maximum version
          - ios: iPhone/iPad/etc
          - android: app level
        - permissions[]
          - android: permission
          - ios: usageDescriptions for permissions
          - ios: app entitlements
```
