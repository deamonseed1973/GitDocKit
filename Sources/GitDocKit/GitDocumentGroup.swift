#if canImport(SwiftUI)
import SwiftUI

/// A convenience `Scene` that opens external git repositories as documents using
/// `GitExternalDocument`.
///
/// Usage:
/// ```swift
/// @main
/// struct MyApp: App {
///     var body: some Scene {
///         GitExternalDocumentGroup { document in
///             RepositoryView(document: document)
///         }
///     }
/// }
/// ```
public struct GitExternalDocumentGroup<Content: View>: Scene {

    private let contentBuilder: (GitExternalDocument) -> Content

    public init(@ViewBuilder content: @escaping (GitExternalDocument) -> Content) {
        self.contentBuilder = content
    }

    public var body: some Scene {
        DocumentGroup(viewing: GitExternalDocument.self) { config in
            contentBuilder(config.document)
        }
    }
}

/// A convenience `Scene` that opens `.gitpkg` package documents using
/// `GitPackageDocument`.
///
/// Usage:
/// ```swift
/// @main
/// struct MyApp: App {
///     var body: some Scene {
///         GitPackageDocumentGroup { document in
///             RepositoryView(document: document)
///         }
///     }
/// }
/// ```
public struct GitPackageDocumentGroup<Content: View>: Scene {

    private let contentBuilder: (GitPackageDocument) -> Content

    public init(@ViewBuilder content: @escaping (GitPackageDocument) -> Content) {
        self.contentBuilder = content
    }

    public var body: some Scene {
        DocumentGroup(viewing: GitPackageDocument.self) { config in
            contentBuilder(config.document)
        }
    }
}

/// Backwards-compatible alias for `GitExternalDocumentGroup`.
public typealias GitDocumentGroup = GitExternalDocumentGroup
#endif
