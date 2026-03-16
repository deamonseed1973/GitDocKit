#if canImport(Combine)
import Foundation
import Testing
@testable import GitDocKit

@Suite("GitRepository Tests")
struct GitRepositoryTests {

    /// Creates a temporary directory and initializes a git repo via SwiftGitX.
    private func makeTempRepo() throws -> (URL, GitRepository) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitDocKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let repo = try GitRepository.create(at: tmp)
        return (tmp, repo)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Open a git repository")
    @MainActor
    func openRepository() throws {
        let (tmp, _) = try makeTempRepo()
        defer { cleanup(tmp) }

        let repo = try GitRepository(url: tmp)
        #expect(repo.url == tmp)
    }

    @Test("Stage a file and commit")
    @MainActor
    func stageAndCommit() throws {
        let (tmp, repo) = try makeTempRepo()
        defer { cleanup(tmp) }

        let fileURL = tmp.appendingPathComponent("hello.txt")
        try "Hello, GitDocKit!".write(to: fileURL, atomically: true, encoding: .utf8)

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
        let (tmp, repo) = try makeTempRepo()
        defer { cleanup(tmp) }

        let fileURL = tmp.appendingPathComponent("hello.txt")
        try "Hello".write(to: fileURL, atomically: true, encoding: .utf8)

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
        let (tmp, repo) = try makeTempRepo()
        defer { cleanup(tmp) }

        let author = GitSignature(name: "Test", email: "test@test.com")

        let f1 = tmp.appendingPathComponent("a.txt")
        try "A".write(to: f1, atomically: true, encoding: .utf8)
        try repo.stageAll()
        try repo.commit(message: "Add a.txt", author: author)

        let f2 = tmp.appendingPathComponent("b.txt")
        try "B".write(to: f2, atomically: true, encoding: .utf8)
        try repo.stageAll()
        try repo.commit(message: "Add b.txt", author: author)

        let log = try repo.log(limit: 10)
        #expect(log.count == 2)
        #expect(log[0].message == "Add b.txt")
        #expect(log[1].message == "Add a.txt")
    }

    @Test("Branch creation and checkout")
    @MainActor
    func branchCreateAndCheckout() throws {
        let (tmp, repo) = try makeTempRepo()
        defer { cleanup(tmp) }

        let author = GitSignature(name: "Test", email: "test@test.com")

        let f = tmp.appendingPathComponent("init.txt")
        try "init".write(to: f, atomically: true, encoding: .utf8)
        try repo.stageAll()
        try repo.commit(message: "Initial", author: author)

        try repo.createBranch(name: "feature")
        #expect(repo.currentBranch == "feature")
        #expect(repo.branches.contains("feature"))

        let defaultBranch = repo.branches.first { $0 != "feature" } ?? "master"
        try repo.checkout(branch: defaultBranch)
        #expect(repo.currentBranch == defaultBranch)
    }

    @Test("Status shows modified and new files")
    @MainActor
    func statusShowsChanges() throws {
        let (tmp, repo) = try makeTempRepo()
        defer { cleanup(tmp) }

        let author = GitSignature(name: "Test", email: "test@test.com")

        let f = tmp.appendingPathComponent("tracked.txt")
        try "original".write(to: f, atomically: true, encoding: .utf8)
        try repo.stageAll()
        try repo.commit(message: "Initial", author: author)

        try "modified".write(to: f, atomically: true, encoding: .utf8)
        let newFile = tmp.appendingPathComponent("untracked.txt")
        try "new".write(to: newFile, atomically: true, encoding: .utf8)

        try repo.refresh()

        #expect(!repo.status.isEmpty)
        let paths = repo.status.map(\.path)
        #expect(paths.contains("tracked.txt"))
        #expect(paths.contains("untracked.txt"))
    }

    @Test("headOID is a valid hex string")
    @MainActor
    func headOIDIsValidHex() throws {
        let (tmp, repo) = try makeTempRepo()
        defer { cleanup(tmp) }

        let author = GitSignature(name: "Test", email: "test@test.com")

        let f = tmp.appendingPathComponent("file.txt")
        try "data".write(to: f, atomically: true, encoding: .utf8)
        try repo.stageAll()
        try repo.commit(message: "Commit", author: author)

        let oid = repo.headOID
        #expect(oid != nil)
        #expect(oid!.count == 40)
        #expect(oid!.allSatisfy { $0.isHexDigit })
    }

    @Test("Opening non-repo directory throws")
    @MainActor
    func openNonRepoThrows() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitDocKitTests-nonrepo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        #expect(throws: GitRepositoryError.self) {
            _ = try GitRepository(url: tmp)
        }
    }

    @Test("Log limit parameter is respected")
    @MainActor
    func logLimitRespected() throws {
        let (tmp, repo) = try makeTempRepo()
        defer { cleanup(tmp) }

        let author = GitSignature(name: "Test", email: "test@test.com")

        for i in 1...5 {
            let f = tmp.appendingPathComponent("file\(i).txt")
            try "\(i)".write(to: f, atomically: true, encoding: .utf8)
            try repo.stageAll()
            try repo.commit(message: "Commit \(i)", author: author)
        }

        let limited = try repo.log(limit: 3)
        #expect(limited.count == 3)

        let all = try repo.log(limit: 50)
        #expect(all.count == 5)
    }
}
#endif // canImport(Combine)
