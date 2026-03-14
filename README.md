# GitDocKit

A Swift Package that marries Apple's `ReferenceFileDocument` with [libgit2](https://libgit2.org) — giving you a document-based app where **git is the persistence layer**.

GitDocKit is a *chimera* combining ideas from three projects:

| Source | What it contributes |
|---|---|
| [SwiftGitX](https://github.com/ibrahimcetin/SwiftGitX) | Swift 6, libgit2 wrapper (MIT) — the git backend |
| [AsyncSwiftGit](https://github.com/bdewey/AsyncSwiftGit) | async/await libgit2 patterns — the concurrency model |
| [Xit](https://github.com/Uncommon/Xit) | NSDocument pattern for git repos — the document model |

## Installation

Add GitDocKit via Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/ArcticForge/GitDocKit.git", from: "1.0.0"),
]
```

Then add `"GitDocKit"` as a dependency of your target.

## Usage

### Open a repository

```swift
import GitDocKit

let repo = try GitRepository(url: URL(fileURLWithPath: "/path/to/repo"))
print(repo.currentBranch ?? "HEAD detached")
print(repo.branches)
```

### Stage and commit

```swift
let author = GitSignature(name: "Ada Lovelace", email: "ada@example.com")

try repo.stageAll()
let commit = try repo.commit(message: "Add analytical engine notes", author: author)
print("Created commit \(commit.id)")
```

### Undo a commit

```swift
// Using the document model (registers with UndoManager):
document.registerCommitUndo(message: "Add analytical engine notes")

// Or directly:
try repo.undoLastCommit()  // git reset HEAD~1 --mixed
```

### Use GitDocumentGroup in a SwiftUI app

```swift
import SwiftUI
import GitDocKit

@main
struct MyApp: App {
    var body: some Scene {
        GitDocumentGroup { document in
            if let repo = document.repository {
                RepositoryView(repo: repo)
            } else {
                Text("Not a git repository")
            }
        }
    }
}
```

## Architecture

GitDocKit is organized in two layers:

### Layer 1 — Git Core

- **`GitRepository`** — `@MainActor` observable wrapper around SwiftGitX's `Repository`. Exposes staging, committing, branching, log, and status as `@Published` properties.
- **`GitCommit`** / **`GitSignature`** — Lightweight, `Sendable` value types for commits and author info.
- **`GitHookObserver`** — Watches `.git/hooks/` via GCD dispatch sources and publishes installed hooks.

### Layer 2 — Document Integration

- **`GitReferenceFileDocument`** — A `ReferenceFileDocument` that opens a directory as a git repo. Snapshot is `Void` because the git repository on disk *is* the source of truth. Supports undo via `UndoManager` (each commit registers a reset-to-HEAD~1 undo action).
- **`GitDocumentGroup`** — A SwiftUI `Scene` convenience that wraps `DocumentGroup(viewing:)` for git repositories.

## Requirements

- Swift 6.0+
- macOS 13+ / iOS 16+

## Credits

- [SwiftGitX](https://github.com/ibrahimcetin/SwiftGitX) by Ibrahim Cetin — the libgit2 Swift wrapper powering the git backend.
- [AsyncSwiftGit](https://github.com/bdewey/AsyncSwiftGit) by Brian Dewey — inspiration for the async/await concurrency patterns.
- [Xit](https://github.com/Uncommon/Xit) — inspiration for the NSDocument/ReferenceFileDocument integration pattern.

## License

MIT
