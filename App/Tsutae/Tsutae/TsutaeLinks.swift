import AppKit
import Foundation

enum TsutaeLinks {
    static let githubRepository = URL(string: "https://github.com/yanfch/tsutae")!

    static func openGitHubRepository() {
        NSWorkspace.shared.open(githubRepository)
    }
}
