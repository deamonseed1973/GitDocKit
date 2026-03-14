# GitDocKit — Build Task

Build a Swift Package called GitDocKit. This is a chimera combining:

1. ibrahimcetin/SwiftGitX (Swift 6, libgit2 wrapper, MIT) — the git backend
2. bdewey/AsyncSwiftGit (async/await libgit2 patterns) — the concurrency model
3. Uncommon/Xit (NSDocument pattern for git repos) — the document model

## What to build

A Swift Package providing `ReferenceFileDocument`-conforming base classes backed by a libgit2 repository. Platform: iOS 16+, macOS 13+.

## Package structure

### Package.swift
- Name: GitDocKit
- Swift tools version: 6.0
- Platforms: .macOS(.v13), .iOS(.v16)
- Dependencies:
  - SwiftGitX: https://github.com/ibrahimcetin/SwiftGitX.git (from: "1.0.0")
- Targets:
  - GitDocKit (library)
  - GitDocKitTests

### Sources/GitDocKit/

**GitRepository.swift** — Main actor wrapping SwiftGitX's Repository

```swift
@MainActor
public final class GitRepository: ObservableObject {
    public let url: URL
    private var repository: Repository  // SwiftGitX
    
    @Published public var currentBranch: String?
    @Published public var commits: [GitCommit] = []
    @Published public var status: [StatusEntry] = []
    @Published public var branches: [String] = []
    
    public init(url: URL) throws
    public func stageAll() throws
    public func commit(message: String, author: GitSignature) throws
    public func checkout(branch: String) throws
    public func createBranch(name: String) throws
    public func log(limit: Int) throws -> [GitCommit]
    public func refresh() throws  // re-reads branches/commits/status
}
```

**GitCommit.swift** — Value type for commits

```swift
public struct GitCommit: Identifiable, Hashable, Sendable {
    public let id: String  // OID hex
    public let message: String
    public let author: GitSignature
    public let date: Date
    public let parentIDs: [String]
}

public struct GitSignature: Hashable, Sendable {
    public let name: String
    public let email: String
}
```

**GitReferenceFileDocument.swift** — The key chimera piece

```swift
@MainActor
public final class GitReferenceFileDocument: ReferenceFileDocument {
    // UTType for a directory containing a .git folder
    public static let readableContentTypes: [UTType] = [.folder]
    
    public var repository: GitRepository?
    private var _undoManager: UndoManager?
    
    // Required init for ReferenceFileDocument
    public required init(configuration: ReadConfiguration) throws
    // Opens the directory as a git repo
    
    // Snapshot type = void (we never serialize - git IS the persistence)
    public typealias Snapshot = Void
    
    public func snapshot(contentType: UTType) throws -> Void { () }
    
    // Never writes - the git repo on disk is the source of truth
    public func fileWrapper(snapshot: Void, configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(directoryWithFileWrappers: [:])
    }
    
    // Git-backed undo: each commit registers an undo action
    public func registerCommitUndo(message: String)
    // Registers with undoManager: undo = git reset HEAD~1 --mixed
}
```

**GitDocumentGroup.swift** — SwiftUI convenience

```swift
public struct GitDocumentGroup<Content: View>: Scene {
    let contentBuilder: (GitReferenceFileDocument) -> Content
    
    public init(@ViewBuilder content: @escaping (GitReferenceFileDocument) -> Content)
    
    public var body: some Scene {
        DocumentGroup(viewing: GitReferenceFileDocument.self) { config in
            contentBuilder(config.document)
        }
    }
}
```

**GitHookObserver.swift** — Watches .git/hooks/ for changes

```swift
public final class GitHookObserver: ObservableObject {
    public let repositoryURL: URL
    @Published public var installedHooks: [GitHook] = []
    
    private var dirSource: DispatchSourceFileSystemObject?
    
    public init(repositoryURL: URL)
    public func startObserving()
    public func stopObserving()
}

public struct GitHook: Identifiable, Hashable {
    public let id: String  // hook name e.g. "pre-commit"
    public let url: URL
    public let isExecutable: Bool
}
```

## Implementation notes

- SwiftGitX uses a synchronous API - wrap calls with @MainActor / Task where needed
- The undo manager integration: when commit() is called, register undo that calls reset to HEAD~1 mixed
- GitReferenceFileDocument init: get the URL from configuration and open the git repo there
- For iOS: UTType .folder is the right type. The document picker will let users select a folder.
- Make everything compile with Swift 6 strict concurrency (Sendable, @MainActor where needed)
- If SwiftGitX doesn't have a reset method, use Process to run `git reset HEAD~1 --mixed` as a fallback

## README.md
Write a good README explaining:
- What it is and the chimera concept  
- Installation (SPM)
- Basic usage (4 code examples: open repo, commit, undo a commit, use GitDocumentGroup)
- Architecture section (Layer 1 + Layer 2)
- Credits (SwiftGitX, AsyncSwiftGit, Xit)

## Tests
Write basic tests in GitDocKitTests:
- Create a temp git repo using Foundation (git init via Process)
- Open it with GitRepository
- Stage a file and commit
- Verify the commit appears in log

## .github/VOUCHED.td
Create .github/VOUCHED.td with content:
```
# Vouched contributors
rjstelling
```

## .github/workflows/swift.yml
Standard Swift CI that builds and tests on ubuntu-latest with Swift 6.

## .github/workflows/vouch.yml
Vouch workflow with:
- on: pull_request (opened/reopened/synchronize) and issues (opened/reopened)
- check-pr job: uses mitchellh/vouch/action/check-pr@v1
- check-issue job: uses mitchellh/vouch/action/check-issue@v1

## Commit and push
After building everything:
1. git add -A
2. git commit -m "Initial chimera: GitDocKit — ReferenceFileDocument + libgit2"
3. git push origin main

The git remote already has credentials configured. Just run git push.

When completely finished, run:
openclaw system event --text "Done: GitDocKit initial chimera built and pushed" --mode now
