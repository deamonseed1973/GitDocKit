import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(Security)
import Security
#endif

// MARK: - Encryption Errors

/// Errors produced by encryption or decryption operations.
public enum ReferenceFileEncryptionError: Error, Sendable {
    /// The provided password was incorrect (decryption authentication failed).
    case wrongPassword
    /// The encrypted payload format is not supported.
    case unsupportedFormat
    /// The encrypted payload data is corrupt or truncated.
    case corruptPayload
    /// The manifest format version is not supported.
    case unsupportedVersion
}

// MARK: - Protocol

/// A service that encrypts and decrypts data using a password.
public protocol ReferenceFileEncryptionService: Sendable {
    /// Encrypts raw data with the given password.
    /// - Parameters:
    ///   - data: The plaintext data to encrypt.
    ///   - password: The user-provided password.
    /// - Returns: The encrypted data blob (including any necessary metadata such as salt and nonce).
    func encrypt(data: Data, password: String) throws -> Data

    /// Decrypts an encrypted data blob with the given password.
    /// - Parameters:
    ///   - data: The encrypted data blob.
    ///   - password: The user-provided password.
    /// - Returns: The decrypted plaintext data.
    func decrypt(data: Data, password: String) throws -> Data
}

// MARK: - CryptoKit AES-GCM Implementation

#if canImport(CryptoKit)

/// Encrypts and decrypts data using AES-256-GCM with a key derived from a password via HKDF-SHA256.
///
/// **Wire format** (all fields concatenated):
/// ```
/// [salt: 32 bytes] [nonce: 12 bytes] [ciphertext + GCM tag]
/// ```
///
/// Key derivation:
/// 1. Generate a random 32-byte salt.
/// 2. Derive a 256-bit symmetric key using HKDF-SHA256 with the salt and password encoded as UTF-8.
public struct CryptoKitEncryptionService: ReferenceFileEncryptionService {

    /// Length of the random salt used for key derivation.
    private static let saltLength = 32

    /// Info string used in HKDF expansion.
    private static let hkdfInfo = Data("GitDocKit-Encryption".utf8)

    public init() {}

    public func encrypt(data: Data, password: String) throws -> Data {
        let salt = generateSalt()
        let key = deriveKey(password: password, salt: salt)

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.seal(data, using: key)
        } catch {
            throw ReferenceFileEncryptionError.corruptPayload
        }

        guard let combined = sealedBox.combined else {
            throw ReferenceFileEncryptionError.corruptPayload
        }

        // combined = nonce (12) + ciphertext + tag (16)
        var output = Data()
        output.append(salt)
        output.append(combined)
        return output
    }

    public func decrypt(data: Data, password: String) throws -> Data {
        // Minimum: salt (32) + nonce (12) + tag (16) = 60 bytes with 0 plaintext
        let minimumLength = Self.saltLength + 12 + 16
        guard data.count >= minimumLength else {
            throw ReferenceFileEncryptionError.corruptPayload
        }

        let salt = data.prefix(Self.saltLength)
        let combined = data.dropFirst(Self.saltLength)
        let key = deriveKey(password: password, salt: salt)

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: combined)
        } catch {
            throw ReferenceFileEncryptionError.corruptPayload
        }

        do {
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            // GCM authentication failure almost always means wrong password.
            throw ReferenceFileEncryptionError.wrongPassword
        }
    }

    // MARK: - Private

    private func generateSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: Self.saltLength)
        _ = SecRandomCopyBuffer(&bytes)
        return Data(bytes)
    }

    private func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let inputKey = SymmetricKey(data: Data(password.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: Self.hkdfInfo,
            outputByteCount: 32
        )
    }
}

/// Generates cryptographically secure random bytes into the provided buffer.
private func SecRandomCopyBuffer(_ buffer: inout [UInt8]) {
    #if canImport(Security)
    _ = SecRandomCopyBytes(kSecRandomKey, buffer.count, &buffer)
    #else
    // Fallback for platforms without Security framework.
    for i in buffer.indices {
        buffer[i] = UInt8.random(in: 0...255)
    }
    #endif
}

#endif // canImport(CryptoKit)
