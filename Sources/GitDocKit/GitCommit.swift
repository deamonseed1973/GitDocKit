import Foundation

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

    /// Creates a `GitCommit` with explicit values.
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
