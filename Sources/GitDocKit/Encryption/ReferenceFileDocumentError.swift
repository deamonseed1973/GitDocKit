import Foundation

/// User-facing errors for encrypted document operations.
///
/// This enum wraps lower-level reader, writer, and workspace errors into
/// human-readable messages suitable for display in UI alerts.
public enum ReferenceFileDocumentError: Error, Sendable, LocalizedError {
    /// The password entered was incorrect.
    case wrongPassword
    /// The document uses an unsupported encryption format.
    case unsupportedFormat
    /// The document was created with a newer, unsupported version.
    case unsupportedVersion
    /// The document is damaged or corrupt.
    case corruptDocument
    /// The document is incomplete or missing required files.
    case missingContent
    /// Saving the document failed.
    case saveFailed(underlying: Error)
    /// Temporary file cleanup failed.
    case cleanupFailed

    public var errorDescription: String? {
        switch self {
        case .wrongPassword:
            return "The password you entered is incorrect. Please try again."
        case .unsupportedFormat:
            return "This document uses an unsupported encryption format and cannot be opened."
        case .unsupportedVersion:
            return "This document was created with a newer version of the app and cannot be opened."
        case .corruptDocument:
            return "The document appears to be damaged and could not be opened."
        case .missingContent:
            return "The document is incomplete or missing required files."
        case .saveFailed(let underlying):
            return "The document could not be saved. \(underlying.localizedDescription)"
        case .cleanupFailed:
            return "Temporary files could not be removed. Please check your disk."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .wrongPassword:
            return "Check your password and try again."
        case .unsupportedFormat:
            return "Update the app to the latest version or contact support."
        case .unsupportedVersion:
            return "Update the app to the latest version to open this document."
        case .corruptDocument:
            return "Try opening a backup copy of the document."
        case .missingContent:
            return "The document may have been partially deleted. Try restoring from a backup."
        case .saveFailed:
            return "Check that you have write permissions and sufficient disk space."
        case .cleanupFailed:
            return "Check available disk space and permissions on the temporary directory."
        }
    }
}
