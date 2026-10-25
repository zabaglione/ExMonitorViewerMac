import Foundation

enum UpdateConfigurationError: Error {
    case invalidFeedURL
    case invalidPublicKey
}

struct UpdateConfiguration {
    let feedURL: URL

    init(feed: String?, publicKey: String?) throws {
        guard let feed, let url = URL(string: feed), let host = url.host,
              url.user == nil, url.password == nil, url.fragment == nil else {
            throw UpdateConfigurationError.invalidFeedURL
        }
        var allowed = url.scheme == "https" && !host.isEmpty
        #if UPDATER_TESTING
        // ローカル配信試験だけで使用し、配布用ビルドには含めない。
        allowed = allowed || (url.scheme == "http" && ["127.0.0.1", "localhost"].contains(host))
        #endif
        guard allowed else { throw UpdateConfigurationError.invalidFeedURL }
        guard let publicKey, Data(base64Encoded: publicKey)?.count == 32 else {
            throw UpdateConfigurationError.invalidPublicKey
        }
        feedURL = url
    }
}
