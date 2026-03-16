# GitDocKit — Agent Guidelines

## ⚠️ Hard Rules

### No `Process` or subprocess spawning
**NEVER use `Foundation.Process`, `ProcessInfo`, or any shell/subprocess calls** to complete tasks in this project.

All git operations MUST go through the libgit2 library directly — via **SwiftGitX** (the project's declared Swift Package dependency), which wraps libgit2 without shelling out.

Rationale: The project was created specifically to replace a fragile `git` CLI subprocess layer. Reintroducing `Process`-based calls defeats the entire purpose.

**Forbidden patterns:**
```swift
// ❌ NEVER do this
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
// ...

// ❌ NEVER do this
try process.run()
```

**Required pattern:**
```swift
// ✅ Use SwiftGitX (libgit2 directly)
import SwiftGitX
let repo = try Repository(at: url)
try repo.index.addAll()
try repo.commit(message: "...", author: signature, committer: signature)
```

### Swift 6 strict concurrency
All code must compile with Swift 6 strict concurrency. Use `@MainActor`, `Sendable`, and `async/await` as appropriate.

### Branch policy
Never commit directly to `main`. Always create a feature branch and open a PR.

### Git identity for commits (when using gh CLI or git itself for repo management)
```
git config user.name "Bot"
git config user.email "bot@richardstelling.com"
```
