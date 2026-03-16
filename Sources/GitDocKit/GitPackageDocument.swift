#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
import SwiftGitX

/// A self-contained git package document.
///
/// The entire git repository is embedded inside the document as a directory
/// package with the `.gitpkg` extension. Internal structure:
/// ```
/// MyDocument.gitpkg/
///   repo/   <-- actual git repository lives here
/// ```
@MainActor
public final class GitPackageDocument: ReferenceFileDocument {

    // MARK: - UTType

    /// The custom UTType for `.gitpkg` packages.
    public static let contentType = UTType(exportedAs: "com.gitdockit.package")

    // MARK: - Content Types

    public static let readableContentTypes: [UTType] = [GitPackageDocument.contentType]
    public static let writableContentTypes: [UTType] = [GitPackageDocument.contentType]

    // MARK: - Properties

    /// The git repository backing this document.
    public var repository: GitRepository?

    /// The URL of the package directory on disk (the .gitpkg directory).
    public var packageURL: URL?

    /// The undo manager provided by SwiftUI's document infrastructure.
    public var undoManager: UndoManager?

    // MARK: - Snapshot

    public typealias Snapshot = Void

    public func snapshot(contentType: UTType) throws -> Void {
        ()
    }

    /// Returns a file wrapper representing the package directory containing the repo subdirectory.
    public func fileWrapper(snapshot: Void, configuration: WriteConfiguration) throws -> FileWrapper {
        guard let packageURL else {
            return FileWrapper(directoryWithFileWrappers: [:])
        }

        let repoURL = packageURL.appendingPathComponent("repo")
        guard FileManager.default.fileExists(atPath: repoURL.path) else {
            return FileWrapper(directoryWithFileWrappers: [:])
        }

        let repoWrapper = try FileWrapper(url: repoURL, options: .immediate)
        repoWrapper.preferredFilename = "repo"
        return FileWrapper(directoryWithFileWrappers: ["repo": repoWrapper])
    }

    // MARK: - Initialization

    /// Opens a `.gitpkg` package from the given read configuration.
    public required init(configuration: ReadConfiguration) throws {
        guard let repoWrapper = configuration.file.fileWrappers?["repo"] else {
            return
        }

        if let packageFilename = configuration.file.preferredFilename {
            let pkgURL = URL(fileURLWithPath: packageFilename)
            self.packageURL = pkgURL
            let repoURL = pkgURL.appendingPathComponent("repo")
            if FileManager.default.fileExists(atPath: repoURL.path) {
                self.repository = try? GitRepository(url: repoURL)
            }
        }
    }

    /// Creates an empty document (no repository attached).
    public init() {
        self.repository = nil
        self.packageURL = nil
    }

    // MARK: - Factory

    /// Creates a new `.gitpkg` package at the given URL.
    ///
    /// This factory method:
    /// 1. Creates the `.gitpkg` directory at `url`
    /// 2. Creates a `repo/` subdirectory inside it
    /// 3. Initializes a new git repository there
    /// 4. Returns the document
    ///
    /// - Parameter url: The URL where the `.gitpkg` directory should be created.
    /// - Returns: A configured `GitPackageDocument`.
    public static func create(at url: URL) throws -> GitPackageDocument {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)

        let repoURL = url.appendingPathComponent("repo")
        try fm.createDirectory(at: repoURL, withIntermediateDirectories: true)

        let repo = try GitRepository.create(at: repoURL)

        let doc = GitPackageDocument()
        doc.packageURL = url
        doc.repository = repo
        return doc
    }

    // MARK: - Undo Integration

    /// Registers an undo action that resets the repository to HEAD~1 (mixed).
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
