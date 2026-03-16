#if canImport(CryptoKit)
import XCTest
@testable import GitDocKit
import Foundation

final class EncryptionTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EncryptionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - Manifest Tests

    func testManifestEncodeDecodeRoundTrip() throws {
        let manifest = ReferenceFileDocumentManifest.encrypted()

        let data = try manifest.encodeJSON()
        let decoded = try ReferenceFileDocumentManifest.decodeJSON(from: data)

        XCTAssertEqual(manifest, decoded)
        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(decoded.storageMode, .encrypted)
        XCTAssertEqual(decoded.encryption?.scheme, .customEncryptedArchive)
        XCTAssertEqual(decoded.encryption?.kdf, "HKDF-SHA256")
        XCTAssertEqual(decoded.encryption?.payloadFilename, "payload.zip.enc")
        XCTAssertEqual(decoded.innerFormat?.kind, "bundle")
        XCTAssertEqual(decoded.innerFormat?.rootFolder, "DocumentContents")
    }

    func testPlainManifestRoundTrip() throws {
        let manifest = ReferenceFileDocumentManifest.plain()

        let data = try manifest.encodeJSON()
        let decoded = try ReferenceFileDocumentManifest.decodeJSON(from: data)

        XCTAssertEqual(manifest, decoded)
        XCTAssertEqual(decoded.storageMode, .plain)
        XCTAssertNil(decoded.encryption)
    }

    func testManifestVersionValidation() throws {
        let supported = ReferenceFileDocumentManifest(
            formatVersion: 1,
            storageMode: .plain
        )
        XCTAssertNoThrow(try supported.validateVersion())

        let unsupported = ReferenceFileDocumentManifest(
            formatVersion: 99,
            storageMode: .plain
        )
        XCTAssertThrowsError(try unsupported.validateVersion()) { error in
            guard case ReferenceFileManifestError.unsupportedVersion(99) = error else {
                XCTFail("Expected unsupportedVersion(99), got \(error)")
                return
            }
        }
    }

    func testManifestInvalidJSON() {
        let garbage = Data("not json".utf8)
        XCTAssertThrowsError(try ReferenceFileDocumentManifest.decodeJSON(from: garbage)) { error in
            guard case ReferenceFileManifestError.invalidManifest = error else {
                XCTFail("Expected invalidManifest, got \(error)")
                return
            }
        }
    }

    // MARK: - Archive Tests

    func testArchiveCreateExtractRoundTrip() throws {
        let service = ZIPFoundationArchiveService()

        // Create sample directory structure.
        let sourceDir = tempDir.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let subDir = sourceDir.appendingPathComponent("content")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try "Hello, World!".write(
            to: sourceDir.appendingPathComponent("readme.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "nested file".write(
            to: subDir.appendingPathComponent("nested.txt"),
            atomically: true,
            encoding: .utf8
        )

        // Round-trip.
        let archiveData = try service.createArchive(from: sourceDir)
        XCTAssertFalse(archiveData.isEmpty)

        let extractDir = tempDir.appendingPathComponent("extracted")
        try service.extractArchive(archiveData, to: extractDir)

        // ZIPFoundation extracts with the source directory name as root.
        let rootName = sourceDir.lastPathComponent
        let extractedRoot = extractDir.appendingPathComponent(rootName)

        let readmeContent = try String(
            contentsOf: extractedRoot.appendingPathComponent("readme.txt"),
            encoding: .utf8
        )
        XCTAssertEqual(readmeContent, "Hello, World!")

        let nestedContent = try String(
            contentsOf: extractedRoot.appendingPathComponent("content/nested.txt"),
            encoding: .utf8
        )
        XCTAssertEqual(nestedContent, "nested file")
    }

    func testArchiveSourceNotFound() {
        let service = ZIPFoundationArchiveService()
        let missing = tempDir.appendingPathComponent("does-not-exist")

        XCTAssertThrowsError(try service.createArchive(from: missing)) { error in
            guard case ReferenceFileArchiveError.sourceNotFound = error else {
                XCTFail("Expected sourceNotFound, got \(error)")
                return
            }
        }
    }

    // MARK: - Encryption Tests

    func testEncryptDecryptRoundTrip() throws {
        let service = CryptoKitEncryptionService()
        let plaintext = Data("Secret document content for testing.".utf8)
        let password = "correct-horse-battery-staple"

        let encrypted = try service.encrypt(data: plaintext, password: password)
        XCTAssertNotEqual(encrypted, plaintext)

        let decrypted = try service.decrypt(data: encrypted, password: password)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptDecryptEmptyData() throws {
        let service = CryptoKitEncryptionService()
        let plaintext = Data()
        let password = "pass"

        let encrypted = try service.encrypt(data: plaintext, password: password)
        let decrypted = try service.decrypt(data: encrypted, password: password)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testWrongPasswordThrows() throws {
        let service = CryptoKitEncryptionService()
        let plaintext = Data("Top secret".utf8)

        let encrypted = try service.encrypt(data: plaintext, password: "right-password")

        XCTAssertThrowsError(try service.decrypt(data: encrypted, password: "wrong-password")) { error in
            guard case ReferenceFileEncryptionError.wrongPassword = error else {
                XCTFail("Expected wrongPassword, got \(error)")
                return
            }
        }
    }

    func testCorruptPayloadThrows() {
        let service = CryptoKitEncryptionService()
        let tooShort = Data([0x00, 0x01, 0x02])

        XCTAssertThrowsError(try service.decrypt(data: tooShort, password: "any")) { error in
            guard case ReferenceFileEncryptionError.corruptPayload = error else {
                XCTFail("Expected corruptPayload, got \(error)")
                return
            }
        }
    }

    // MARK: - Temporary Workspace Tests

    func testTemporaryWorkspaceCleanup() throws {
        let workspace = ReferenceFileTemporaryWorkspace()
        try workspace.open()

        let workspaceURL = workspace.url
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceURL.path))

        workspace.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspaceURL.path))

        // Safe to call close again.
        workspace.close()
    }

    // MARK: - Encrypted Document Reader Tests

    func testEncryptedDocumentReaderRoundTrip() throws {
        let writer = ReferenceFileEncryptedDocumentWriter()
        let reader = ReferenceFileEncryptedDocumentReader()
        let password = "test-read-write-password"

        // Create source content.
        let sourceDir = tempDir.appendingPathComponent("reader-source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try "hello reader".write(
            to: sourceDir.appendingPathComponent("note.txt"),
            atomically: true,
            encoding: .utf8
        )
        let subDir = sourceDir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try "nested content".write(
            to: subDir.appendingPathComponent("deep.txt"),
            atomically: true,
            encoding: .utf8
        )

        // Write the encrypted package.
        let packageURL = tempDir.appendingPathComponent("Test.refdoc")
        try writer.write(
            sourceDirectory: sourceDir,
            destinationURL: packageURL,
            password: password
        )

        // Read it back.
        let result = try reader.read(packageURL: packageURL, password: password)
        defer { result.workspace.close() }

        let noteContent = try String(
            contentsOf: result.contentURL.appendingPathComponent("note.txt"),
            encoding: .utf8
        )
        XCTAssertEqual(noteContent, "hello reader")

        let deepContent = try String(
            contentsOf: result.contentURL.appendingPathComponent("sub/deep.txt"),
            encoding: .utf8
        )
        XCTAssertEqual(deepContent, "nested content")
    }

    func testEncryptedDocumentReaderWrongPassword() throws {
        let writer = ReferenceFileEncryptedDocumentWriter()
        let reader = ReferenceFileEncryptedDocumentReader()

        let sourceDir = tempDir.appendingPathComponent("wrong-pw-source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try "secret".write(
            to: sourceDir.appendingPathComponent("file.txt"),
            atomically: true,
            encoding: .utf8
        )

        let packageURL = tempDir.appendingPathComponent("WrongPW.refdoc")
        try writer.write(
            sourceDirectory: sourceDir,
            destinationURL: packageURL,
            password: "correct-password"
        )

        XCTAssertThrowsError(try reader.read(packageURL: packageURL, password: "wrong-password")) { error in
            guard case ReferenceFileDocumentReaderError.wrongPassword = error else {
                XCTFail("Expected wrongPassword, got \(error)")
                return
            }
        }
    }

    func testEncryptedDocumentReaderMissingManifest() throws {
        let reader = ReferenceFileEncryptedDocumentReader()

        // Create a package directory without manifest.json.
        let packageURL = tempDir.appendingPathComponent("NoManifest.refdoc")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try reader.read(packageURL: packageURL, password: "any")) { error in
            guard case ReferenceFileDocumentReaderError.missingManifest = error else {
                XCTFail("Expected missingManifest, got \(error)")
                return
            }
        }
    }

    func testEncryptedDocumentReaderMissingPayload() throws {
        let reader = ReferenceFileEncryptedDocumentReader()

        // Create a package with manifest but no payload.
        let packageURL = tempDir.appendingPathComponent("NoPayload.refdoc")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)

        let manifest = ReferenceFileDocumentManifest.encrypted()
        let manifestData = try manifest.encodeJSON()
        try manifestData.write(to: packageURL.appendingPathComponent("manifest.json"))

        XCTAssertThrowsError(try reader.read(packageURL: packageURL, password: "any")) { error in
            guard case ReferenceFileDocumentReaderError.missingPayload = error else {
                XCTFail("Expected missingPayload, got \(error)")
                return
            }
        }
    }

    // MARK: - Encrypted Document Writer Tests

    func testEncryptedDocumentWriterCreatesValidPackage() throws {
        let writer = ReferenceFileEncryptedDocumentWriter()

        let sourceDir = tempDir.appendingPathComponent("writer-source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try "content".write(
            to: sourceDir.appendingPathComponent("data.txt"),
            atomically: true,
            encoding: .utf8
        )

        let packageURL = tempDir.appendingPathComponent("Valid.refdoc")
        try writer.write(
            sourceDirectory: sourceDir,
            destinationURL: packageURL,
            password: "pw"
        )

        // Verify package structure.
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        let payloadURL = packageURL.appendingPathComponent("payload.zip.enc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: payloadURL.path))

        // Verify manifest is valid.
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try ReferenceFileDocumentManifest.decodeJSON(from: manifestData)
        XCTAssertEqual(manifest.storageMode, .encrypted)
        XCTAssertEqual(manifest.encryption?.payloadFilename, "payload.zip.enc")
    }

    func testEncryptedDocumentWriterOverwriteSafe() throws {
        let writer = ReferenceFileEncryptedDocumentWriter()

        let sourceDir = tempDir.appendingPathComponent("overwrite-source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try "original".write(
            to: sourceDir.appendingPathComponent("file.txt"),
            atomically: true,
            encoding: .utf8
        )

        let packageURL = tempDir.appendingPathComponent("Overwrite.refdoc")

        // Create a dummy file at the destination.
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try "dummy".write(
            to: packageURL.appendingPathComponent("dummy.txt"),
            atomically: true,
            encoding: .utf8
        )

        // Write should succeed, replacing the existing destination.
        try writer.write(
            sourceDirectory: sourceDir,
            destinationURL: packageURL,
            password: "pw"
        )

        // Verify new package structure exists.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: packageURL.appendingPathComponent("manifest.json").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: packageURL.appendingPathComponent("payload.zip.enc").path
        ))
    }

    // MARK: - Document Error Tests

    func testDocumentErrorDescriptions() {
        let cases: [ReferenceFileDocumentError] = [
            .wrongPassword,
            .unsupportedFormat,
            .unsupportedVersion,
            .corruptDocument,
            .missingContent,
            .saveFailed(underlying: NSError(domain: "test", code: 1)),
            .cleanupFailed,
        ]

        for error in cases {
            let description = error.errorDescription
            XCTAssertNotNil(description, "Missing errorDescription for \(error)")
            XCTAssertFalse(description?.isEmpty ?? true, "Empty errorDescription for \(error)")

            let suggestion = error.recoverySuggestion
            XCTAssertNotNil(suggestion, "Missing recoverySuggestion for \(error)")
            XCTAssertFalse(suggestion?.isEmpty ?? true, "Empty recoverySuggestion for \(error)")
        }
    }

    // MARK: - Full Pipeline Test

    func testFullArchiveThenEncryptRoundTrip() throws {
        let archiveService = ZIPFoundationArchiveService()
        let encryptionService = CryptoKitEncryptionService()
        let password = "test-password-123"

        // Create source content.
        let sourceDir = tempDir.appendingPathComponent("doc-contents")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try "document body".write(
            to: sourceDir.appendingPathComponent("body.txt"),
            atomically: true,
            encoding: .utf8
        )

        // Archive -> Encrypt.
        let archiveData = try archiveService.createArchive(from: sourceDir)
        let encrypted = try encryptionService.encrypt(data: archiveData, password: password)

        // Decrypt -> Extract.
        let decrypted = try encryptionService.decrypt(data: encrypted, password: password)
        XCTAssertEqual(decrypted, archiveData)

        let extractDir = tempDir.appendingPathComponent("restored")
        try archiveService.extractArchive(decrypted, to: extractDir)

        let rootName = sourceDir.lastPathComponent
        let body = try String(
            contentsOf: extractDir.appendingPathComponent(rootName).appendingPathComponent("body.txt"),
            encoding: .utf8
        )
        XCTAssertEqual(body, "document body")
    }
}
#endif // canImport(CryptoKit)
