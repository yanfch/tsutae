import AppKit
import Foundation

enum TsutaeLinks {
    static let githubRepository = URL(string: "https://github.com/yanfch/tsutae")!
    static let githubIssue = URL(string: "https://github.com/yanfch/tsutae/issues/new")!

    static func openGitHubRepository() {
        NSWorkspace.shared.open(githubRepository)
    }

    static func openGitHubIssue() {
        NSWorkspace.shared.open(githubIssue)
    }
}
