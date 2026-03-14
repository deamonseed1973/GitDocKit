# GitDocKit

A Swift Package providing `ReferenceFileDocument`-conforming base classes backed by a libgit2 repository. A chimera combining the best ideas from three projects:

- **[SwiftGitX](https://github.com/ibrahimcetin/SwiftGitX)** — Swift 6 libgit2 wrapper (the git backend)
- **[AsyncSwiftGit](https://github.com/bdewey/AsyncSwiftGit)** — async/await concurrency patterns for libgit2
- **[Xit](https://github.com/Uncommon/Xit)** — NSDocument pattern for git repositories (the document model)

GitDocKit fuses these approaches into a single package: your SwiftUI document *is* a git repository, with undo powered by `git reset`, staging and commits exposed as simple Swift API calls, and everything built for Swift 6 strict concurrency.

## Platforms

- macOS 13+
- iOS 16+

## Installation

Add GitDocKit to your project via Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/deamonseed1973/GitDocKit.git", from: "1.0.0"),
]
```

Then add `GitDocKit` to your target's dependencies:

```swift
.target(name: "MyApp", dependencies: ["GitDocKit"])
```

## Usage

### Open a Repository

```swift
import GitDocKit

let repo = try GitRepository(url: URL(fileURLWithPath: "/path/to/repo"))
let log = try repo.log()
for commit in log {
    print("\(commit.id.prefix(7)) \(commit.message)")
}
```

### Stage and Commit

```swift
let repo = try GitRepository(url: repoURL)

// Stage everything
try repo.stageAll()

// Commit
let author = GitSignature(name: "Jane Dev", email: "jane@example.com")
let commit = try repo.commit(message: "Add new feature", author: author)
print("Created commit: \(commit.id)")
```

### Undo a Commit

```swift
// Reset to HEAD~1 (undo the last commit, keeps changes in working dir)
try repo.undoLastCommit()
```

### Use GitDocumentGroup in SwiftUI

```swift
import SwiftUI
import GitDocKit

@main
struct MyApp: App {
    var body: some Scene {
        GitDocumentGroup { document in
            ContentView(document: document)
        }
    }
}
```

## Architecture

### Layer 1: Git Backend (`GitRepository`, `GitCommit`)

The foundation layer wraps SwiftGitX's synchronous libgit2 API in `@MainActor`-isolated classes with clean Swift interfaces. `GitRepository` provides staging, committing, log, reset, and status operations. `GitCommit` is an immutable value type representing a commit.

### Layer 2: Document Model (`GitReferenceFileDocument`, `GitDocumentGroup`, `GitHookObserver`)

The document layer builds on Layer 1 to provide SwiftUI integration:

- **`GitReferenceFileDocument`** — A `ReferenceFileDocument` subclass where the document *is* a git repository directory. Reads open the repo from a `FileWrapper`; writes serialize back. Undo support is built in via `git reset`.
- **`GitDocumentGroup`** — A SwiftUI `Scene` wrapper that creates a `DocumentGroup` pre-configured for git repository documents.
- **`GitHookObserver`** — Watches `.git/hooks/` using `DispatchSource` and publishes change events, enabling reactive UI updates when hooks are modified.

## Credits

GitDocKit is a chimera built on the shoulders of:

- **[SwiftGitX](https://github.com/ibrahimcetin/SwiftGitX)** by Ibrahim Cetin — Swift 6, libgit2 wrapper, MIT license
- **[AsyncSwiftGit](https://github.com/bdewey/AsyncSwiftGit)** by Brian Dewey — async/await patterns for libgit2
- **[Xit](https://github.com/Uncommon/Xit)** by Uncommon — NSDocument pattern for git repositories

## License

MIT
