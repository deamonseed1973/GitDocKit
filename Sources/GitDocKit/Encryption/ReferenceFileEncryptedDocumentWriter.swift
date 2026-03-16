import Foundation
#if canImport(CryptoKit)

// MARK: - Writer Errors

/// Errors produced when writing an encrypted document package.
public enum ReferenceFileDocumentWriterError: Error, Sendable {
    /// The source directory does not exist or is not a directory.
    case sourceNotFound
    /// The archive could not be created from the source contents.
    case archiveFailed(underlying: Error)
    /// Encryption of the archive data failed.
    case encryptionFailed(underlying: Error)
    /// Writing the output package to disk failed.
    case writeFailed(underlying: Error)
}

// MARK: - Writer

/// Writes document contents into an encrypted `.refdoc` package.
public struct ReferenceFileEncryptedDocumentWriter: Sendable {

    private let archiveService: ZIPFoundationArchiveService
    private let encryptionService: CryptoKitEncryptionService

    public init() {
        self.archiveService = ZIPFoundationArchiveService()
        self.encryptionService = CryptoKitEncryptionService()
    }

    /// Writes an encrypted document package.
    ///
    /// - Parameters:
    ///   - sourceDirectory: The directory containing the document contents to encrypt.
    ///   - destinationURL: The URL where the `.refdoc` package will be written.
    ///   - password: The password to encrypt with.
    ///   - rootFolder: The name of the root folder inside the archive (default: `"DocumentContents"`).
    public func write(
        sourceDirectory: URL,
        destinationURL: URL,
        password: String,
        rootFolder: String = "DocumentContents"
    ) throws {
        let fm = FileManager.default

        // Validate source.
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourceDirectory.path, isDirectory: &isDir), isDir.boolValue else {
            throw ReferenceFileDocumentWriterError.sourceNotFound
        }

        // 1. Create staging directory with rootFolder subdirectory.
        let stagingDir = fm.temporaryDirectory
            .appendingPathComponent("GitDocKit-staging-\(UUID().uuidString)")
        let rootFolderDir = stagingDir.appendingPathComponent(rootFolder)
        defer { try? fm.removeItem(at: stagingDir) }

        do {
            try fm.createDirectory(at: rootFolderDir, withIntermediateDirectories: true)
        } catch {
            throw ReferenceFileDocumentWriterError.writeFailed(underlying: error)
        }

        // Copy source files into rootFolder.
        do {
            let items = try fm.contentsOfDirectory(
                at: sourceDirectory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            for item in items {
                let dest = rootFolderDir.appendingPathComponent(item.lastPathComponent)
                try fm.copyItem(at: item, to: dest)
            }
        } catch {
            throw ReferenceFileDocumentWriterError.writeFailed(underlying: error)
        }

        // 2. Archive the root folder directory so that the archive root is the rootFolder name.
        let archiveData: Data
        do {
            archiveData = try archiveService.createArchive(from: rootFolderDir)
        } catch {
            throw ReferenceFileDocumentWriterError.archiveFailed(underlying: error)
        }

        // 3. Encrypt the archive.
        let encryptedData: Data
        do {
            encryptedData = try encryptionService.encrypt(data: archiveData, password: password)
        } catch {
            throw ReferenceFileDocumentWriterError.encryptionFailed(underlying: error)
        }

        // 4. Build manifest.
        let manifest = ReferenceFileDocumentManifest.encrypted(
            payloadFilename: "payload.zip.enc",
            rootFolder: rootFolder
        )

        // 5. Write to a temporary output package.
        let tempOutputDir = fm.temporaryDirectory
            .appendingPathComponent("GitDocKit-output-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tempOutputDir) }

        do {
            try fm.createDirectory(at: tempOutputDir, withIntermediateDirectories: true)
            let manifestData = try manifest.encodeJSON()
            try manifestData.write(to: tempOutputDir.appendingPathComponent("manifest.json"))
            try encryptedData.write(to: tempOutputDir.appendingPathComponent("payload.zip.enc"))
        } catch {
            throw ReferenceFileDocumentWriterError.writeFailed(underlying: error)
        }

        // 6. Atomically replace destination.
        do {
            if fm.fileExists(atPath: destinationURL.path) {
                _ = try fm.replaceItemAt(destinationURL, withItemAt: tempOutputDir)
            } else {
                try fm.moveItem(at: tempOutputDir, to: destinationURL)
            }
        } catch {
            throw ReferenceFileDocumentWriterError.writeFailed(underlying: error)
        }
    }
}

#endif // canImport(CryptoKit)
