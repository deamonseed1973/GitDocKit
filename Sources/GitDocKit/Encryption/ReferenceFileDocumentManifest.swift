import Foundation

// MARK: - Storage Mode

/// Describes whether a document is stored in plain or encrypted form.
public enum ReferenceFileStorageMode: String, Codable, Sendable {
    /// The document is stored as-is without encryption.
    case plain
    /// The document is stored as an encrypted archive.
    case encrypted
}

// MARK: - Encryption Scheme

/// The encryption scheme used to protect the payload archive.
public enum EncryptionScheme: String, Codable, Sendable {
    /// AES-256 encryption applied directly via a password-protected ZIP archive.
    case zipAES256 = "zip-aes-256"
    /// A plain ZIP archive encrypted as a single blob using CryptoKit AES.GCM
    /// with a key derived from the user's password.
    case customEncryptedArchive = "custom-encrypted-archive"
}

// MARK: - Manifest

/// Metadata describing the format and encryption state of a `ReferenceFileDocument` package.
///
/// The manifest is stored as `manifest.json` inside the outer document package.
/// It is always plain-text JSON and must not contain sensitive content.
public struct ReferenceFileDocumentManifest: Codable, Sendable, Equatable {

    // MARK: Constants

    /// The current format version produced by this library.
    public static let currentFormatVersion = 1

    /// The range of format versions this library can read.
    public static let supportedFormatVersions: ClosedRange<Int> = 1...1

    // MARK: Properties

    /// The format version of the manifest.
    public let formatVersion: Int

    /// The document type identifier.
    public let documentType: String

    /// Whether the document is plain or encrypted.
    public let storageMode: ReferenceFileStorageMode

    /// Encryption-specific metadata. Present only when `storageMode` is `.encrypted`.
    public let encryption: EncryptionMetadata?

    /// Metadata describing the inner document structure.
    public let innerFormat: InnerFormatMetadata?

    // MARK: Nested Types

    /// Encryption metadata stored inside the manifest.
    public struct EncryptionMetadata: Codable, Sendable, Equatable {
        /// The encryption scheme used to protect the payload.
        public let scheme: EncryptionScheme
        /// The key derivation function identifier (informational).
        public let kdf: String
        /// The filename of the encrypted payload inside the package.
        public let payloadFilename: String

        public init(scheme: EncryptionScheme, kdf: String, payloadFilename: String) {
            self.scheme = scheme
            self.kdf = kdf
            self.payloadFilename = payloadFilename
        }
    }

    /// Metadata describing the inner (decrypted) document structure.
    public struct InnerFormatMetadata: Codable, Sendable, Equatable {
        /// The kind of inner content (e.g. "bundle" or "flat").
        public let kind: String
        /// The root folder name inside the archive.
        public let rootFolder: String

        public init(kind: String, rootFolder: String) {
            self.kind = kind
            self.rootFolder = rootFolder
        }
    }

    // MARK: Initialisation

    /// Creates a new manifest.
    public init(
        formatVersion: Int = ReferenceFileDocumentManifest.currentFormatVersion,
        documentType: String = "ReferenceFileDocument",
        storageMode: ReferenceFileStorageMode,
        encryption: EncryptionMetadata? = nil,
        innerFormat: InnerFormatMetadata? = nil
    ) {
        self.formatVersion = formatVersion
        self.documentType = documentType
        self.storageMode = storageMode
        self.encryption = encryption
        self.innerFormat = innerFormat
    }

    // MARK: Factory

    /// Returns a manifest configured for plain (unencrypted) storage.
    public static func plain(documentType: String = "ReferenceFileDocument") -> Self {
        ReferenceFileDocumentManifest(
            storageMode: .plain
        )
    }

    /// Returns a manifest configured for encrypted storage using the custom encrypted archive scheme.
    public static func encrypted(
        payloadFilename: String = "payload.zip.enc",
        rootFolder: String = "DocumentContents"
    ) -> Self {
        ReferenceFileDocumentManifest(
            storageMode: .encrypted,
            encryption: EncryptionMetadata(
                scheme: .customEncryptedArchive,
                kdf: "HKDF-SHA256",
                payloadFilename: payloadFilename
            ),
            innerFormat: InnerFormatMetadata(
                kind: "bundle",
                rootFolder: rootFolder
            )
        )
    }

    // MARK: Validation

    /// Validates that the manifest version is supported by this library.
    /// - Throws: `ReferenceFileManifestError.unsupportedVersion` if the version is out of range.
    public func validateVersion() throws {
        guard Self.supportedFormatVersions.contains(formatVersion) else {
            throw ReferenceFileManifestError.unsupportedVersion(formatVersion)
        }
    }

    // MARK: Encoding / Decoding

    /// Encodes the manifest to JSON `Data`.
    public func encodeJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Decodes a manifest from JSON `Data`.
    /// - Throws: `ReferenceFileManifestError.invalidManifest` if decoding fails.
    public static func decodeJSON(from data: Data) throws -> Self {
        do {
            return try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw ReferenceFileManifestError.invalidManifest(underlying: error)
        }
    }
}

// MARK: - Manifest Errors

/// Errors related to manifest parsing and validation.
public enum ReferenceFileManifestError: Error, Sendable {
    /// The manifest format version is not supported by this library.
    case unsupportedVersion(Int)
    /// The manifest JSON could not be decoded.
    case invalidManifest(underlying: Error)
}
