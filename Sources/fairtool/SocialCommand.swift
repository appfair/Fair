import Foundation
import FairCore
import FairExpo
import ArgumentParser

//public struct SocialCommand : AsyncParsableCommand {
//    public static let experimental = true
//    public static var configuration = CommandConfiguration(commandName: "social",
//                                                           abstract: "Social media utilities.",
//                                                           shouldDisplay: !experimental,
//                                                           subcommands: [
//                                                            TweetCommand.self,
//                                                           ])
//
//    public init() {
//    }
//
//    public struct TweetCommand: FairStructuredCommand {
//        public static let experimental = false
//
//        public typealias Output = Tweeter.PostResponse
//
//        public static var configuration = CommandConfiguration(commandName: "tweet",
//                                                               abstract: "Post a tweet.",
//                                                               shouldDisplay: !experimental)
//
//        @OptionGroup public var tweetOptions: TweetOptions
//        @OptionGroup public var msgOptions: MsgOptions
//        @OptionGroup public var delayOptions: DelayOptions
//
//        @Flag(name: [.long], help: ArgumentHelp("Whether tweets should be grouped into a single conversation."))
//        public var conversation: Bool = false
//
//        @Argument(help: ArgumentHelp("The contents of the tweet", valueName: "body", visibility: .default))
//        public var body: [String]
//
//        public init() { }
//
//        public func executeCommand() -> AsyncThrowingStream<Tweeter.PostResponse, Error> {
//            warnExperimental(Self.experimental)
//            var initialTweetID: Tweeter.TweetID? = nil
//
//            return executeSeries(body, initialValue: nil) { body, prev in
//                msg(.info, "tweeting body:", body)
//                let auth = try tweetOptions.createAuth()
//
//                if let prev = prev {
//                    initialTweetID = initialTweetID ?? prev.response?.data.id // remember just the initial tweet id
//                    if conversation {
//                        msg(.info, "conversation tweet id: \(initialTweetID?.rawValue ?? "")")
//                    }
//                    // wait in between success postings
//                    try await delayOptions.sleepTask() {
//                        msg(.info, "pausing between tweets for: \($0) seconds")
//                    }
//                }
//
//                return try await Tweeter.post(text: body, in_reply_to_tweet_id: conversation ? initialTweetID : nil, auth: auth)
//            }
//        }
//    }
//}


/// Authentication options for Twitter CLI
//public struct TweetOptions: ParsableArguments {
//    @Option(name: [.long], help: ArgumentHelp("Oauth consumer key for sending tweets.", valueName: "key"))
//    public var twitterConsumerKey: String?
//
//    @Option(name: [.long], help: ArgumentHelp("Oauth consumer secret for sending tweets.", valueName: "secret"))
//    public var twitterConsumerSecret: String?
//
//    @Option(name: [.long], help: ArgumentHelp("Oauth token for sending tweets.", valueName: "token"))
//    public var twitterToken: String?
//
//    @Option(name: [.long], help: ArgumentHelp("Oauth token secret for sending tweets.", valueName: "secret"))
//    public var twitterTokenSecret: String?
//
//    public init() { }
//
//    private func check(_ propValue: String?, env: String, option: String) throws -> String {
//        if let propValue = propValue { return propValue }
//        if let envValue = ProcessInfo.processInfo.environment[env] { return envValue }
//        throw AppError(String(format: NSLocalizedString("Must specify either option --%@ or environment variable: $@", bundle: .module, comment: "error message"), arguments: [option, env]))
//    }
//
//    func createAuth(parameters: [String : String] = [:]) throws -> OAuth1.Info {
//        try OAuth1.Info(consumerKey: check(twitterConsumerKey, env: "FAIRTOOL_TWITTER_CONSUMER_KEY", option: "twitter-consumer-key"),
//                        consumerSecret: check(twitterConsumerSecret, env: "FAIRTOOL_TWITTER_CONSUMER_SECRET", option: "twitter-consumer-secret"),
//                        oauthToken: check(twitterToken, env: "FAIRTOOL_TWITTER_TOKEN", option: "twitter-token"),
//                        oauthTokenSecret: check(twitterTokenSecret, env: "FAIRTOOL_TWITTER_TOKEN_SECRET", option: "twitter-token-secret"),
//                        oauthTimestamp: nil,
//                        oauthNonce: nil)
//    }
//}
