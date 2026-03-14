import Foundation
import SwiftGitX
#if canImport(Combine)
import Combine
#endif

/// A main-actor-isolated wrapper around SwiftGitX's `Repository`, providing
/// observable, high-level git operations.
@MainActor
public final class GitRepository: ObservableObject, Sendable {

    // MARK: - Properties

    /// The URL of the repository's working directory.
    public let url: URL

    /// The underlying SwiftGitX repository handle.
    private let repository: Repository

    /// The name of the currently checked-out branch, or nil if HEAD is detached/unborn.
    @Published public var currentBranch: String?

    /// Recent commits from HEAD.
    @Published public var commits: [GitCommit] = []

    /// Current working-directory status entries.
    @Published public var status: [StatusEntry] = []

    /// Names of all local branches.
    @Published public var branches: [String] = []

    // MARK: - Initialization

    /// Opens an existing git repository at the given URL.
    /// - Parameter url: The root directory of the git repository.
    /// - Throws: If the repository cannot be opened.
    public init(url: URL) throws {
        self.url = url
        self.repository = try Repository(at: url)
        try? refresh()
    }

    /// Creates a new git repository at the given URL.
    /// - Parameter url: The directory where the repository should be created.
    /// - Returns: A new `GitRepository` instance.
    @discardableResult
    public static func create(at url: URL) throws -> GitRepository {
        _ = try Repository.create(at: url)
        return try GitRepository(url: url)
    }

    // MARK: - Staging

    /// Stages all changes in the working directory.
    public func stageAll() throws {
        var index = try repository.index
        try index.addAll()
        try index.save()
    }

    // MARK: - Committing

    /// Creates a commit with the staged changes.
    /// - Parameters:
    ///   - message: The commit message.
    ///   - author: The author signature.
    /// - Returns: A `GitCommit` value representing the new commit.
    @discardableResult
    public func commit(message: String, author: GitSignature) throws -> GitCommit {
        let signature = Signature(name: author.name, email: author.email)
        let commit = try repository.commit(message: message, signature: signature)
        try? refresh()
        return GitCommit(from: commit)
    }

    // MARK: - Branches

    /// Checks out the branch with the given name.
    /// - Parameter branch: The branch name to check out.
    public func checkout(branch: String) throws {
        let branchRef = try repository.branch.get(named: branch)
        try repository.checkout(branch: branchRef)
        try? refresh()
    }

    /// Creates a new branch at the current HEAD.
    /// - Parameter name: The name for the new branch.
    public func createBranch(name: String) throws {
        let head = try repository.HEAD
        let commit = try repository.show(head.target.id) as SwiftGitX.Commit
        _ = try repository.branch.create(named: name, target: commit)
        try? refresh()
    }

    // MARK: - Log

    /// Returns the commit log starting from HEAD.
    /// - Parameter limit: Maximum number of commits to return. Defaults to 50.
    /// - Returns: An array of `GitCommit` values.
    public func log(limit: Int = 50) throws -> [GitCommit] {
        let log = try repository.log()
        return Array(log.prefix(limit).map { GitCommit(from: $0) })
    }

    // MARK: - Reset

    /// Resets the repository to HEAD~1 with a mixed reset (undo the last commit,
    /// keeping changes in the working directory).
    public func undoLastCommit() throws {
        let log = try repository.log()
        let commits = Array(log.prefix(2))
        guard commits.count >= 2 else {
            throw GitRepositoryError.noCommitToUndo
        }
        let parentCommit = commits[1]
        try repository.reset(to: parentCommit, type: .mixed)
        try? refresh()
    }

    // MARK: - Refresh

    /// Re-reads branches, commits, and status from the repository on disk.
    public func refresh() throws {
        // Current branch
        currentBranch = try? repository.HEAD.name

        // Branches
        branches = (try? repository.branch.list().map(\.name)) ?? []

        // Status
        status = (try? repository.status()) ?? []

        // Commits
        commits = (try? log(limit: 50)) ?? []
    }

    // MARK: - HEAD

    /// Returns the OID string of the current HEAD commit, or nil if HEAD is unborn.
    public var headOID: String? {
        return try? repository.HEAD.target.id.description
    }
}

// MARK: - Errors

/// Errors specific to `GitRepository` operations.
public enum GitRepositoryError: Error, Sendable {
    case noCommitToUndo
    case repositoryNotFound
}
