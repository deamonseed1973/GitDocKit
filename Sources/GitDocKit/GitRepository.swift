import Foundation
#if canImport(Combine)
import Combine
#endif

/// A status entry from `git status --porcelain`.
public struct GitStatusEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let path: String
    public let status: String
}

/// A main-actor-isolated wrapper providing observable, high-level git operations
/// via the `git` CLI.
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

    // MARK: - Git CLI Helper

    @discardableResult
    private func run(_ args: [String], env: [String: String]? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = url
        var environment = ProcessInfo.processInfo.environment
        if let env { environment.merge(env) { _, new in new } }
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? ""
            throw GitRepositoryError.gitCommandFailed(errMsg)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Initialization

    /// Opens an existing git repository at the given URL.
    /// - Parameter url: The root directory of the git repository.
    /// - Throws: If the repository cannot be opened.
    public init(url: URL) throws {
        self.url = url
        // Verify this is a git repository
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--git-dir"]
        process.currentDirectoryURL = url
        process.environment = ProcessInfo.processInfo.environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitRepositoryError.repositoryNotFound
        }
        try? refresh()
    }

    /// Creates a new git repository at the given URL.
    /// - Parameter url: The directory where the repository should be created.
    /// - Returns: A new `GitRepository` instance.
    @discardableResult
    public static func create(at url: URL) throws -> GitRepository {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init", url.path]
        process.environment = ProcessInfo.processInfo.environment
        let errPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? ""
            throw GitRepositoryError.gitCommandFailed(errMsg)
        }
        return try GitRepository(url: url)
    }

    // MARK: - Staging

    /// Stages all changes in the working directory.
    public func stageAll() throws {
        try run(["add", "-A"])
    }

    // MARK: - Committing

    /// Creates a commit with the staged changes.
    /// - Parameters:
    ///   - message: The commit message.
    ///   - author: The author signature.
    /// - Returns: A `GitCommit` value representing the new commit.
    @discardableResult
    public func commit(message: String, author: GitSignature) throws -> GitCommit {
        try run([
            "-c", "user.name=\(author.name)",
            "-c", "user.email=\(author.email)",
            "commit", "-m", message,
        ])

        let oid = try run(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)

        let dateStr = try run(["log", "-1", "--format=%aI"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: dateStr) ?? Date()

        let parentLine = try run(["log", "-1", "--format=%P"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let parentIDs = parentLine.isEmpty ? [] : parentLine.split(separator: " ").map(String.init)

        try? refresh()

        return GitCommit(
            id: oid,
            message: message,
            author: author,
            date: date,
            parentIDs: parentIDs
        )
    }

    // MARK: - Branches

    /// Checks out the branch with the given name.
    /// - Parameter branch: The branch name to check out.
    public func checkout(branch: String) throws {
        try run(["checkout", branch])
        try? refresh()
    }

    /// Creates a new branch at the current HEAD.
    /// - Parameter name: The name for the new branch.
    public func createBranch(name: String) throws {
        try run(["checkout", "-b", name])
        try? refresh()
    }

    // MARK: - Log

    /// Returns the commit log starting from HEAD.
    /// - Parameter limit: Maximum number of commits to return. Defaults to 50.
    /// - Returns: An array of `GitCommit` values.
    public func log(limit: Int = 50) throws -> [GitCommit] {
        let output = try run(["log", "-n", "\(limit)", "--format=%H|%s|%an|%ae|%aI|%P"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !output.isEmpty else { return [] }

        let formatter = ISO8601DateFormatter()

        return output.split(separator: "\n", omittingEmptySubsequences: true).map { line ->  GitCommit in
            let parts = line.split(separator: "|", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
            let oid = parts.count > 0 ? parts[0] : ""
            let message = parts.count > 1 ? parts[1] : ""
            let authorName = parts.count > 2 ? parts[2] : ""
            let authorEmail = parts.count > 3 ? parts[3] : ""
            let dateStr = parts.count > 4 ? parts[4] : ""
            let parentStr = parts.count > 5 ? parts[5] : ""
            let parentIDs = parentStr.isEmpty ? [] : parentStr.split(separator: " ").map(String.init)
            let date = formatter.date(from: dateStr) ?? Date()

            return GitCommit(
                id: oid,
                message: message,
                author: GitSignature(name: authorName, email: authorEmail),
                date: date,
                parentIDs: parentIDs
            )
        }
    }

    // MARK: - Reset

    /// Resets the repository to HEAD~1 with a mixed reset (undo the last commit,
    /// keeping changes in the working directory).
    public func undoLastCommit() throws {
        try run(["reset", "--mixed", "HEAD~1"])
        try? refresh()
    }

    // MARK: - Refresh

    /// Re-reads branches, commits, and status from the repository on disk.
    public func refresh() throws {
        // Current branch
        if let branchOutput = try? run(["symbolic-ref", "--short", "HEAD"]) {
            currentBranch = branchOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentBranch?.isEmpty == true { currentBranch = nil }
        } else {
            currentBranch = nil
        }

        // Branches
        if let branchList = try? run(["branch", "--format=%(refname:short)"]) {
            branches = branchList
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init)
        } else {
            branches = []
        }

        // Status
        if let statusOutput = try? run(["status", "--porcelain"]) {
            let lines = statusOutput.split(separator: "\n", omittingEmptySubsequences: true)
            status = lines.map { line ->  GitStatusEntry in
                let lineStr = String(line)
                let statusCode = String(lineStr.prefix(2)).trimmingCharacters(in: .whitespaces)
                let path = String(lineStr.dropFirst(3))
                return GitStatusEntry(id: path, path: path, status: statusCode)
            }
        } else {
            status = []
        }

        // Commits
        commits = (try? log(limit: 50)) ?? []
    }

    // MARK: - HEAD

    /// Returns the OID string of the current HEAD commit, or nil if HEAD is unborn.
    public var headOID: String? {
        guard let output = try? run(["rev-parse", "HEAD"]) else { return nil }
        let oid = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return oid.isEmpty ? nil : oid
    }
}

// MARK: - Errors

/// Errors specific to `GitRepository` operations.
public enum GitRepositoryError: Error, Sendable {
    case noCommitToUndo
    case repositoryNotFound
    case gitCommandFailed(String)
}
