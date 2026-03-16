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
        let repo = try GitRepository.create(at: tempDir)

        let filePath = tempDir.appendingPathComponent("hello.txt")
        try "Hello, GitDocKit!".write(to: filePath, atomically: true, encoding: .utf8)

        try repo.stageAll()
        let commit = try repo.commit(message: "Initial commit", author: testAuthor)

        XCTAssertEqual(commit.message, "Initial commit")
        XCTAssertEqual(commit.author.name, "Test")
        XCTAssertEqual(commit.author.email, "test@example.com")
        XCTAssertFalse(commit.id.isEmpty)
    }

    @MainActor
    func testLogShowsCommit() throws {
        let repo = try GitRepository.create(at: tempDir)

        let filePath = tempDir.appendingPathComponent("file.txt")
        try "content".write(to: filePath, atomically: true, encoding: .utf8)

        try repo.stageAll()
        try repo.commit(message: "First commit", author: testAuthor)

        let log = try repo.log()
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log.first?.message, "First commit")
    }

    @MainActor
    func testUndoLastCommit() throws {
        let repo = try GitRepository.create(at: tempDir)

        let file1 = tempDir.appendingPathComponent("file1.txt")
        try "first".write(to: file1, atomically: true, encoding: .utf8)
        try repo.stageAll()
        try repo.commit(message: "First commit", author: testAuthor)

        let file2 = tempDir.appendingPathComponent("file2.txt")
        try "second".write(to: file2, atomically: true, encoding: .utf8)
        try repo.stageAll()
        try repo.commit(message: "Second commit", author: testAuthor)

        var log = try repo.log()
        XCTAssertEqual(log.count, 2)

        try repo.undoLastCommit()

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
