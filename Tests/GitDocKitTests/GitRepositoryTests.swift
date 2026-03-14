import Foundation
import Testing
@testable import GitDocKit

@Suite("GitRepository Tests")
struct GitRepositoryTests {

    /// Creates a temporary directory with a git repo initialized via `git init`.
    private func makeTempRepo() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitDocKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init", tmp.path]
        process.environment = [
            "GIT_CONFIG_NOSYSTEM": "1",
            "HOME": tmp.path,
            "PATH": "/usr/bin:/bin"
        ]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        // Configure user for commits
        for (key, value) in [("user.name", "Test"), ("user.email", "test@test.com")] {
            let cfg = Process()
            cfg.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            cfg.arguments = ["-C", tmp.path, "config", key, value]
            try cfg.run()
            cfg.waitUntilExit()
        }

        return tmp
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Open a git repository")
    @MainActor
    func openRepository() throws {
        let tmp = try makeTempRepo()
        defer { cleanup(tmp) }

        let repo = try GitRepository(url: tmp)
        #expect(repo.url == tmp)
    }

    @Test("Stage a file and commit")
    @MainActor
    func stageAndCommit() throws {
        let tmp = try makeTempRepo()
        defer { cleanup(tmp) }

        // Write a file into the repo
        let fileURL = tmp.appendingPathComponent("hello.txt")
        try "Hello, GitDocKit!".write(to: fileURL, atomically: true, encoding: .utf8)

        let repo = try GitRepository(url: tmp)
        try repo.stageAll()

        let author = GitSignature(name: "Test", email: "test@test.com")
        let commit = try repo.commit(message: "Initial commit", author: author)

        #expect(commit.message == "Initial commit")
        #expect(commit.author.name == "Test")
        #expect(commit.author.email == "test@test.com")
    }

    @Test("Commit appears in log")
    @MainActor
    func commitAppearsInLog() throws {
        let tmp = try makeTempRepo()
        defer { cleanup(tmp) }

        let fileURL = tmp.appendingPathComponent("hello.txt")
        try "Hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let repo = try GitRepository(url: tmp)
        try repo.stageAll()

        let author = GitSignature(name: "Test", email: "test@test.com")
        try repo.commit(message: "First commit", author: author)

        let log = try repo.log(limit: 10)
        #expect(log.count == 1)
        #expect(log[0].message == "First commit")
    }

    @Test("Multiple commits appear in log in order")
    @MainActor
    func multipleCommits() throws {
        let tmp = try makeTempRepo()
        defer { cleanup(tmp) }

        let repo = try GitRepository(url: tmp)
        let author = GitSignature(name: "Test", email: "test@test.com")

        // First commit
        let f1 = tmp.appendingPathComponent("a.txt")
        try "A".write(to: f1, atomically: true, encoding: .utf8)
        try repo.stageAll()
        try repo.commit(message: "Add a.txt", author: author)

        // Second commit
        let f2 = tmp.appendingPathComponent("b.txt")
        try "B".write(to: f2, atomically: true, encoding: .utf8)
        try repo.stageAll()
        try repo.commit(message: "Add b.txt", author: author)

        let log = try repo.log(limit: 10)
        #expect(log.count == 2)
        #expect(log[0].message == "Add b.txt")
        #expect(log[1].message == "Add a.txt")
    }
}
