import XCTest
@testable import GitDocKit
import Foundation

final class GitDocKitTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitDocKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func runGit(_ args: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        process.environment = [
            "GIT_AUTHOR_NAME": "Test",
            "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test",
            "GIT_COMMITTER_EMAIL": "test@example.com",
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "GitDocKitTests", code: Int(process.terminationStatus))
        }
    }

    private var testAuthor: GitSignature {
        GitSignature(name: "Test", email: "test@example.com")
    }

    // MARK: - Tests

    @MainActor
    func testCreateAndOpenRepository() throws {
        let repo = try GitRepository.create(at: tempDir)
        XCTAssertNotNil(repo)
        XCTAssertEqual(repo.url, tempDir)
    }

    @MainActor
    func testStageAndCommit() throws {
        // Initialize repo with git CLI
        try runGit(["init"], in: tempDir)

        // Create a file
        let filePath = tempDir.appendingPathComponent("hello.txt")
        try "Hello, GitDocKit!".write(to: filePath, atomically: true, encoding: .utf8)

        // Open with GitRepository
        let repo = try GitRepository(url: tempDir)

        // Stage and commit
        try repo.stageAll()
        let commit = try repo.commit(message: "Initial commit", author: testAuthor)

        XCTAssertEqual(commit.message, "Initial commit")
        XCTAssertEqual(commit.author.name, "Test")
        XCTAssertEqual(commit.author.email, "test@example.com")
        XCTAssertFalse(commit.id.isEmpty)
    }

    @MainActor
    func testLogShowsCommit() throws {
        try runGit(["init"], in: tempDir)

        let filePath = tempDir.appendingPathComponent("file.txt")
        try "content".write(to: filePath, atomically: true, encoding: .utf8)

        let repo = try GitRepository(url: tempDir)
        try repo.stageAll()
        try repo.commit(message: "First commit", author: testAuthor)

        let log = try repo.log()
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log.first?.message, "First commit")
    }

    @MainActor
    func testUndoLastCommit() throws {
        try runGit(["init"], in: tempDir)

        // Create and commit first file
        let file1 = tempDir.appendingPathComponent("file1.txt")
        try "first".write(to: file1, atomically: true, encoding: .utf8)

        let repo = try GitRepository(url: tempDir)
        try repo.stageAll()
        try repo.commit(message: "First commit", author: testAuthor)

        // Create and commit second file
        let file2 = tempDir.appendingPathComponent("file2.txt")
        try "second".write(to: file2, atomically: true, encoding: .utf8)
        try repo.stageAll()
        try repo.commit(message: "Second commit", author: testAuthor)

        // Verify two commits exist
        var log = try repo.log()
        XCTAssertEqual(log.count, 2)

        // Undo last commit
        try repo.undoLastCommit()

        // Verify only one commit remains
        log = try repo.log()
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log.first?.message, "First commit")
    }

    func testGitCommitEquality() {
        let date = Date()
        let author = GitSignature(name: "A", email: "a@b.c")
        let a = GitCommit(id: "abc123", message: "msg", author: author, date: date)
        let b = GitCommit(id: "abc123", message: "msg", author: author, date: date)
        let c = GitCommit(id: "def456", message: "msg", author: author, date: date)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
