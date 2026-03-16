import Foundation
import ZIPFoundation

// MARK: - Protocol

/// A service that creates and extracts archive files from directory contents.
public protocol ReferenceFileArchiveService: Sendable {
    /// Creates an archive from the contents of a directory.
    /// - Parameters:
    ///   - sourceDirectory: The directory whose contents should be archived.
    /// - Returns: The raw archive data.
    func createArchive(from sourceDirectory: URL) throws -> Data

    /// Extracts an archive into a destination directory.
    /// - Parameters:
    ///   - archiveData: The raw archive data.
    ///   - destinationDirectory: The directory to extract into.
    func extractArchive(_ archiveData: Data, to destinationDirectory: URL) throws
}

// MARK: - Archive Errors

/// Errors produced by archive operations.
public enum ReferenceFileArchiveError: Error, Sendable {
    /// The source directory does not exist or is not a directory.
    case sourceNotFound(URL)
    /// The archive data could not be read or is corrupt.
    case corruptArchive(underlying: Error)
    /// An I/O error occurred during archive creation or extraction.
    case ioError(underlying: Error)
}

// MARK: - ZIPFoundation Implementation

/// An archive service backed by ZIPFoundation.
public struct ZIPFoundationArchiveService: ReferenceFileArchiveService {

    public init() {}

    public func createArchive(from sourceDirectory: URL) throws -> Data {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourceDirectory.path, isDirectory: &isDir), isDir.boolValue else {
            throw ReferenceFileArchiveError.sourceNotFound(sourceDirectory)
        }

        // Write to a temporary file, then read back the data.
        let tempURL = fm.temporaryDirectory
            .appendingPathComponent("archive-\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: tempURL) }

        do {
            try fm.zipItem(at: sourceDirectory, to: tempURL)
        } catch {
            throw ReferenceFileArchiveError.ioError(underlying: error)
        }

        do {
            return try Data(contentsOf: tempURL)
        } catch {
            throw ReferenceFileArchiveError.ioError(underlying: error)
        }
    }

    public func extractArchive(_ archiveData: Data, to destinationDirectory: URL) throws {
        let fm = FileManager.default

        // Write data to a temporary ZIP file, then extract.
        let tempURL = fm.temporaryDirectory
            .appendingPathComponent("archive-\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: tempURL) }

        do {
            try archiveData.write(to: tempURL)
        } catch {
            throw ReferenceFileArchiveError.ioError(underlying: error)
        }

        do {
            try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            try fm.unzipItem(at: tempURL, to: destinationDirectory)
        } catch {
            throw ReferenceFileArchiveError.corruptArchive(underlying: error)
        }
    }
}
