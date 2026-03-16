import Foundation
#if canImport(CryptoKit)

// MARK: - Reader Errors

/// Errors produced when reading an encrypted document package.
public enum ReferenceFileDocumentReaderError: Error, Sendable {
    /// The package does not contain a `manifest.json` file.
    case missingManifest
    /// The manifest could not be decoded.
    case invalidManifest
    /// The manifest format version is not supported by this library.
    case unsupportedVersion
    /// The encrypted payload file referenced by the manifest is missing.
    case missingPayload
    /// The password was incorrect (decryption authentication failed).
    case wrongPassword
    /// The encrypted payload is corrupt or could not be extracted.
    case corruptPayload
    /// The expected inner structure was not found after extraction.
    case invalidStructure
}

// MARK: - Read Result

/// The result of reading an encrypted document package.
public struct EncryptedDocumentReadResult: Sendable {
    /// The URL pointing at the extracted root folder inside the workspace.
    public let contentURL: URL
    /// The workspace managing the temporary directory. The caller must call `close()` when done.
    public let workspace: ReferenceFileTemporaryWorkspace
}

// MARK: - Reader

/// Reads an encrypted `ReferenceFileDocument` package, decrypts it, and extracts the contents
/// into a temporary workspace.
public struct ReferenceFileEncryptedDocumentReader: Sendable {

    private let archiveService: ZIPFoundationArchiveService
    private let encryptionService: CryptoKitEncryptionService

    public init() {
        self.archiveService = ZIPFoundationArchiveService()
        self.encryptionService = CryptoKitEncryptionService()
    }

    /// Reads and decrypts an encrypted document package.
    ///
    /// - Parameters:
    ///   - packageURL: The URL of the `.refdoc` package directory.
    ///   - password: The password to decrypt with.
    /// - Returns: An ``EncryptedDocumentReadResult`` containing the content URL and workspace.
    /// - Throws: ``ReferenceFileDocumentReaderError`` on failure.
    public func read(packageURL: URL, password: String) throws -> EncryptedDocumentReadResult {
        // 1. Read and decode manifest.
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL)
        } catch {
            throw ReferenceFileDocumentReaderError.missingManifest
        }

        let manifest: ReferenceFileDocumentManifest
        do {
            manifest = try ReferenceFileDocumentManifest.decodeJSON(from: manifestData)
        } catch {
            throw ReferenceFileDocumentReaderError.invalidManifest
        }

        // 2. Validate manifest.
        guard ReferenceFileDocumentManifest.supportedFormatVersions.contains(manifest.formatVersion) else {
            throw ReferenceFileDocumentReaderError.unsupportedVersion
        }
        guard manifest.documentType == "ReferenceFileDocument",
              manifest.storageMode == .encrypted,
              let encryption = manifest.encryption,
              let innerFormat = manifest.innerFormat else {
            throw ReferenceFileDocumentReaderError.invalidManifest
        }

        // Check payload file exists.
        let payloadURL = packageURL.appendingPathComponent(encryption.payloadFilename)
        guard FileManager.default.fileExists(atPath: payloadURL.path) else {
            throw ReferenceFileDocumentReaderError.missingPayload
        }

        // 3. Create workspace.
        let workspace = ReferenceFileTemporaryWorkspace()
        do {
            try workspace.open()
        } catch {
            workspace.close()
            throw ReferenceFileDocumentReaderError.corruptPayload
        }

        do {
            // 4. Read payload.
            let payloadData = try Data(contentsOf: payloadURL)

            // 5. Decrypt.
            let archiveData: Data
            do {
                archiveData = try encryptionService.decrypt(data: payloadData, password: password)
            } catch let error as ReferenceFileEncryptionError {
                switch error {
                case .wrongPassword:
                    throw ReferenceFileDocumentReaderError.wrongPassword
                default:
                    throw ReferenceFileDocumentReaderError.corruptPayload
                }
            }

            // 6. Extract archive.
            do {
                try archiveService.extractArchive(archiveData, to: workspace.url)
            } catch {
                throw ReferenceFileDocumentReaderError.corruptPayload
            }

            // 7. Validate root folder exists.
            let rootFolderURL = workspace.url.appendingPathComponent(innerFormat.rootFolder)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: rootFolderURL.path, isDirectory: &isDir),
                  isDir.boolValue else {
                throw ReferenceFileDocumentReaderError.invalidStructure
            }

            return EncryptedDocumentReadResult(
                contentURL: rootFolderURL,
                workspace: workspace
            )
        } catch let error as ReferenceFileDocumentReaderError {
            workspace.close()
            throw error
        } catch {
            workspace.close()
            throw ReferenceFileDocumentReaderError.corruptPayload
        }
    }
}

#endif // canImport(CryptoKit)
