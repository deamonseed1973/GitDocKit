import Foundation

/// Manages a per-document temporary directory for decrypted document contents.
///
/// The workspace creates a uniquely-named directory under the system temporary directory
/// and removes it on `close()` or `deinit`.
public final class ReferenceFileTemporaryWorkspace: Sendable {

    /// The URL of the workspace directory.
    public let url: URL

    /// Prefix used for workspace directory names.
    private static let directoryPrefix = "GitDocKit-"

    /// Maximum age (in seconds) for orphaned workspaces before cleanup.
    private static let orphanMaxAge: TimeInterval = 3600

    /// Whether the workspace has been closed.
    private let _closed = LockedState(initialState: false)

    // MARK: - Initialisation

    /// Creates a new workspace reference. Call `open()` to create the directory on disk.
    public init() {
        self.url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.directoryPrefix)\(UUID().uuidString)")
    }

    deinit {
        close()
    }

    // MARK: - Lifecycle

    /// Creates the workspace directory on disk.
    public func open() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Removes the workspace directory. Safe to call multiple times.
    public func close() {
        guard _closed.withLock({ val in
            if val { return false }
            val = true
            return true
        }) else { return }

        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Orphan Cleanup

    /// Removes any `GitDocKit-*` directories in the system temp folder that are older than 1 hour.
    public static func cleanOrphanedWorkspaces() {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory

        guard let contents = try? fm.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let cutoff = Date().addingTimeInterval(-orphanMaxAge)

        for item in contents {
            guard item.lastPathComponent.hasPrefix(directoryPrefix) else { continue }

            guard let values = try? item.resourceValues(forKeys: [.creationDateKey]),
                  let created = values.creationDate,
                  created < cutoff else { continue }

            try? fm.removeItem(at: item)
        }
    }
}

// MARK: - Locked State Helper

/// A minimal thread-safe wrapper for mutable state.
private final class LockedState<Value: Sendable>: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var value: Value

    init(initialState: Value) {
        self.value = initialState
    }

    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
