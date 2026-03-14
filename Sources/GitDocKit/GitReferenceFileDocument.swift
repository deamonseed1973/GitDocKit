#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers

/// A `ReferenceFileDocument` backed by a git repository on disk.
///
/// The git repository _is_ the persistence layer — the document never serializes
/// its own data. Each commit can optionally register an undo action that resets
/// the repo to HEAD~1 (mixed).
@MainActor
public final class GitReferenceFileDocument: ReferenceFileDocument {

    // MARK: - Content Types

    /// Opens directories (which may contain a `.git` folder).
    public static let readableContentTypes: [UTType] = [.folder]

    // MARK: - Properties

    /// The git repository backing this document, if successfully opened.
    public var repository: GitRepository?

    /// The undo manager provided by SwiftUI's document infrastructure.
    public var undoManager: UndoManager?

    // MARK: - Snapshot

    /// Snapshot is `Void` — the git repo on disk is the source of truth.
    public typealias Snapshot = Void

    public func snapshot(contentType: UTType) throws -> Void {
        ()
    }

    /// Returns an empty directory wrapper — we never write back to the document
    /// because the git repository already persists on disk.
    public func fileWrapper(snapshot: Void, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(directoryWithFileWrappers: [:])
    }

    // MARK: - Initialization

    /// Opens the directory at the given file URL as a git repository.
    public required init(configuration: ReadConfiguration) throws {
        // ReferenceFileDocument provides the file wrapper for the directory.
        // We need the URL, which is available via the file wrapper's filename
        // and the expectation that the system passes the directory URL.
        if let url = configuration.file.preferredFilename.flatMap({ URL(fileURLWithPath: $0) }) {
            self.repository = try? GitRepository(url: url)
        }
    }

    /// Creates an empty document (no repository attached).
    public init() {
        self.repository = nil
    }

    // MARK: - Undo Integration

    /// Registers an undo action that resets the repository to HEAD~1 (mixed).
    ///
    /// Call this after each commit to enable Edit > Undo in your app.
    /// - Parameter message: A human-readable description for the undo action.
    public func registerCommitUndo(message: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                try? self.repository?.undoLastCommit()
            }
        }
        undoManager.setActionName("Undo: \(message)")
    }
}
#endif
