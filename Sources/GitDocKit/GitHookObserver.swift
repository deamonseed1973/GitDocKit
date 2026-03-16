import Foundation
#if canImport(Combine) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS))
import Combine

/// An identifiable representation of a git hook script.
public struct GitHook: Identifiable, Hashable, Sendable {
    /// The hook name (e.g. "pre-commit", "post-merge").
    public let id: String
    /// The full URL to the hook file on disk.
    public let url: URL
    /// Whether the hook file has its executable bit set.
    public let isExecutable: Bool
}

/// Observes the `.git/hooks/` directory for changes using a GCD dispatch source
/// and publishes the list of installed hooks.
@MainActor
public final class GitHookObserver: ObservableObject {

    /// The root URL of the git repository.
    public let repositoryURL: URL

    /// The currently installed hooks.
    @Published public var installedHooks: [GitHook] = []

    private let hooksURL: URL
    private var dirSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    public init(repositoryURL: URL) {
        self.repositoryURL = repositoryURL
        self.hooksURL = repositoryURL.appendingPathComponent(".git/hooks")
        scanHooks()
    }

    deinit {
        stopObserving()
    }

    /// Starts watching `.git/hooks/` for filesystem events.
    public func startObserving() {
        stopObserving()

        let fd = open(hooksURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.scanHooks()
        }

        source.setCancelHandler { [fd = fd] in
            close(fd)
        }

        source.resume()
        dirSource = source
    }

    /// Stops watching the hooks directory.
    public func stopObserving() {
        dirSource?.cancel()
        dirSource = nil
        fileDescriptor = -1
    }

    // MARK: - Private

    private func scanHooks() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: hooksURL, includingPropertiesForKeys: [.isExecutableKey]) else {
            installedHooks = []
            return
        }

        installedHooks = entries.compactMap { url -> GitHook? in
            // Skip .sample files that ship with git init
            guard !url.lastPathComponent.hasSuffix(".sample") else { return nil }
            let isExec = (try? url.resourceValues(forKeys: [.isExecutableKey]).isExecutable) ?? false
            return GitHook(id: url.lastPathComponent, url: url, isExecutable: isExec)
        }
    }
}
#endif // canImport(Combine) && Apple platforms
