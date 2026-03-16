import Foundation
import SwiftGitX
#if canImport(Combine)
import Combine
#endif

/// A status entry representing a file's status in the working directory.
public struct GitStatusEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let path: String
    public let status: String
}

#if canImport(Combine)
/// A main-actor-isolated wrapper providing observable, high-level git operations
/// via SwiftGitX (libgit2 directly).
@MainActor
public final class GitRepository: ObservableObject, Sendable {

    // MARK: - Properties

    /// The URL of the repository's working directory.
    public let url: URL

    /// The name of the currently checked-out branch, or nil if HEAD is detached/unborn.
    @Published public var currentBranch: String?

    /// Recent commits from HEAD.
    @Published public var commits: [GitCommit] = []

    /// Current working-directory status entries.
    @Published public var status: [GitStatusEntry] = []

    /// Names of all local branches.
    @Published public var branches: [String] = []

    // MARK: - Internal

    /// The underlying SwiftGitX repository handle.
    private let repo: Repository

    // MARK: - Initialization

    /// Opens an existing git repository at the given URL.
    /// - Parameter url: The root directory of the git repository.
    /// - Throws: If the repository cannot be opened.
    public init(url: URL) throws {
        self.url = url
        do {
            self.repo = try Repository.open(at: url)
        } catch {
            throw GitRepositoryError.repositoryNotFound
        }
        try? refresh()
    }

    /// Internal initializer that accepts a pre-opened SwiftGitX Repository.
    internal init(url: URL, repo: Repository) {
        self.url = url
        self.repo = repo
        try? refresh()
    }

    /// Creates a new git repository at the given URL.
    /// - Parameter url: The directory where the repository should be created.
    /// - Returns: A new `GitRepository` instance.
    @discardableResult
    public static func create(at url: URL) throws -> GitRepository {
        let repo: Repository
        do {
            repo = try Repository.create(at: url)
        } catch {
            throw GitRepositoryError.gitCommandFailed(error.localizedDescription)
        }
        return GitRepository(url: url, repo: repo)
    }

    // MARK: - Staging

    /// Stages all changes in the working directory.
    public func stageAll() throws {
        let statusEntries = try repo.status()
        var paths: [String] = []
        for entry in statusEntries {
            if let delta = entry.workingTree {
                paths.append(delta.newFile.path)
            }
            if let delta = entry.index {
                paths.append(delta.newFile.path)
            }
        }
        let uniquePaths = Array(Set(paths))
        if !uniquePaths.isEmpty {
            try repo.add(paths: uniquePaths)
        }
    }

    // MARK: - Committing

    /// Creates a commit with the staged changes.
    /// - Parameters:
    ///   - message: The commit message.
    ///   - author: The author signature.
    /// - Returns: A `GitCommit` value representing the new commit.
    @discardableResult
    public func commit(message: String, author: GitSignature) throws -> GitCommit {
        // Set author/committer in repo config
        try repo.config.set("user.name", to: author.name)
        try repo.config.set("user.email", to: author.email)

        let swiftGitXCommit = try repo.commit(message: message)

        let parentIDs = swiftGitXCommit.parents.map { $0.id.hex }

        try? refresh()

        return GitCommit(
            id: swiftGitXCommit.id.hex,
            message: message,
            author: author,
            date: swiftGitXCommit.date,
            parentIDs: parentIDs
        )
    }

    // MARK: - Branches

    /// Checks out the branch with the given name.
    /// - Parameter branch: The branch name to check out.
    public func checkout(branch: String) throws {
        let branchRef = try repo.branch.get(named: branch)
        try repo.switch(to: branchRef)
        try? refresh()
    }

    /// Creates a new branch at the current HEAD.
    /// - Parameter name: The name for the new branch.
    public func createBranch(name: String) throws {
        let headRef = try repo.HEAD
        guard let headCommit = headRef.target as? SwiftGitX.Commit else {
            throw GitRepositoryError.gitCommandFailed("HEAD does not point to a commit")
        }
        let newBranch = try repo.branch.create(named: name, target: headCommit)
        try repo.switch(to: newBranch)
        try? refresh()
    }

    // MARK: - Log

    /// Returns the commit log starting from HEAD.
    /// - Parameter limit: Maximum number of commits to return. Defaults to 50.
    /// - Returns: An array of `GitCommit` values.
    public func log(limit: Int = 50) throws -> [GitCommit] {
        let commitSequence = try repo.log()
        var result: [GitCommit] = []
        for swiftGitXCommit in commitSequence {
            if result.count >= limit { break }
            let parentIDs = swiftGitXCommit.parents.map { $0.id.hex }
            result.append(GitCommit(
                id: swiftGitXCommit.id.hex,
                message: swiftGitXCommit.message,
                author: GitSignature(
                    name: swiftGitXCommit.author.name,
                    email: swiftGitXCommit.author.email
                ),
                date: swiftGitXCommit.date,
                parentIDs: parentIDs
            ))
        }
        return result
    }

    // MARK: - Reset

    /// Resets the repository to HEAD~1 with a mixed reset (undo the last commit,
    /// keeping changes in the working directory).
    public func undoLastCommit() throws {
        let headRef = try repo.HEAD
        guard let headCommit = headRef.target as? SwiftGitX.Commit else {
            throw GitRepositoryError.noCommitToUndo
        }
        let parents = headCommit.parents
        guard let parentCommit = parents.first else {
            throw GitRepositoryError.noCommitToUndo
        }
        try repo.reset(to: parentCommit, mode: .mixed)
        try? refresh()
    }

    // MARK: - Refresh

    /// Re-reads branches, commits, and status from the repository on disk.
    public func refresh() throws {
        // Current branch
        if let headRef = try? repo.HEAD, let branch = headRef as? Branch {
            currentBranch = branch.name
        } else {
            currentBranch = nil
        }

        // Branches
        if let branchList = try? repo.branch.list(.local) {
            branches = branchList.map(\.name)
        } else {
            branches = []
        }

        // Status
        if let statusEntries = try? repo.status() {
            var entries: [GitStatusEntry] = []
            for entry in statusEntries {
                let path: String
                let statusCode: String
                if let delta = entry.workingTree {
                    path = delta.newFile.path
                    statusCode = statusString(for: entry.status)
                } else if let delta = entry.index {
                    path = delta.newFile.path
                    statusCode = statusString(for: entry.status)
                } else {
                    continue
                }
                entries.append(GitStatusEntry(id: path, path: path, status: statusCode))
            }
            status = entries
        } else {
            status = []
        }

        // Commits
        commits = (try? log(limit: 50)) ?? []
    }

    // MARK: - HEAD

    /// Returns the OID string of the current HEAD commit, or nil if HEAD is unborn.
    public var headOID: String? {
        guard let headRef = try? repo.HEAD,
              let commit = headRef.target as? SwiftGitX.Commit else {
            return nil
        }
        let hex = commit.id.hex
        return hex.isEmpty ? nil : hex
    }

    // MARK: - Private

    private func statusString(for statuses: [StatusEntry.Status]) -> String {
        if statuses.contains(.indexNew) { return "A" }
        if statuses.contains(.indexModified) { return "M" }
        if statuses.contains(.indexDeleted) { return "D" }
        if statuses.contains(.indexRenamed) { return "R" }
        if statuses.contains(.workingTreeNew) { return "?" }
        if statuses.contains(.workingTreeModified) { return "M" }
        if statuses.contains(.workingTreeDeleted) { return "D" }
        return "?"
    }
}
#endif // canImport(Combine)

// MARK: - Errors

/// Errors specific to `GitRepository` operations.
public enum GitRepositoryError: Error, Sendable {
    case noCommitToUndo
    case repositoryNotFound
    case gitCommandFailed(String)
}
