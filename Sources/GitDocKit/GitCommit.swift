import Foundation
import SwiftGitX

/// An immutable, sendable signature for commit authors and committers.
public struct GitSignature: Hashable, Sendable {
    public let name: String
    public let email: String

    public init(name: String, email: String) {
        self.name = name
        self.email = email
    }
}

/// An immutable value type representing a git commit.
public struct GitCommit: Sendable, Identifiable, Hashable {

    /// The commit's object ID as a hex string.
    public let id: String

    /// The commit message.
    public let message: String

    /// The commit author.
    public let author: GitSignature

    /// The date the commit was authored.
    public let date: Date

    /// The OID hex strings of parent commits.
    public let parentIDs: [String]

    /// Creates a `GitCommit` from a SwiftGitX `Commit`.
    init(from commit: SwiftGitX.Commit) {
        self.id = commit.id.description
        self.message = commit.message
        self.author = GitSignature(name: commit.author.name, email: commit.author.email)
        self.date = commit.author.date
        self.parentIDs = commit.parents.map { $0.id.description }
    }

    /// Creates a `GitCommit` with explicit values (useful for testing).
    public init(id: String, message: String, author: GitSignature, date: Date, parentIDs: [String] = []) {
        self.id = id
        self.message = message
        self.author = author
        self.date = date
        self.parentIDs = parentIDs
    }

    public static func == (lhs: GitCommit, rhs: GitCommit) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
