#if canImport(SwiftUI)
import SwiftUI

/// A convenience `Scene` that opens git repositories as documents using
/// `GitReferenceFileDocument`.
///
/// Usage:
/// ```swift
/// @main
/// struct MyApp: App {
///     var body: some Scene {
///         GitDocumentGroup { document in
///             RepositoryView(document: document)
///         }
///     }
/// }
/// ```
public struct GitDocumentGroup<Content: View>: Scene {

    private let contentBuilder: (GitReferenceFileDocument) -> Content

    public init(@ViewBuilder content: @escaping (GitReferenceFileDocument) -> Content) {
        self.contentBuilder = content
    }

    public var body: some Scene {
        DocumentGroup(viewing: GitReferenceFileDocument.self) { config in
            contentBuilder(config.document)
        }
    }
}
#endif
