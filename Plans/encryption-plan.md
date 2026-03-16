# Plan: Add an Encryption Mode to `ReferenceFileDocument`

## Overview

Add an optional encryption mode to `ReferenceFileDocument` so a document can be saved as an encrypted package rather than plain content.

The proposed approach is:

- package the document contents into an archive
- encrypt the archive with a user-provided password
- store enough metadata to let the app recognise that the file is encrypted
- prompt for a password when the file is opened
- decrypt to a temporary working location before loading the internal contents

This follows the approach discussed earlier:

- the password acts as the secret used to decrypt the archive
- the encrypted file can be self-contained
- the app should bundle its own archive library rather than relying on external `zip` commands

## Goals

- Support an encrypted save mode for `ReferenceFileDocument`
- Keep the feature self-contained inside the app
- Avoid depending on shell tools installed on the system
- Preserve a clear file format that the app can detect and validate
- Allow the app to open, decrypt, edit, and re-save encrypted documents
- Keep the unencrypted mode available for backwards compatibility

## Non-goals

- Multi-user key management
- Public/private key workflows
- Cloud key escrow
- DRM-style prevention of copying after decryption
- Fine-grained per-file encryption inside the package

## Recommended format

Use a custom document package format with two modes:

1. **Plain mode**
   - the existing `ReferenceFileDocument` format

2. **Encrypted mode**
   - a wrapper package that contains:
     - a manifest file with format metadata
     - an encrypted archive containing the real document contents

## Proposed file structure

### Outer package

The outer document should contain only a small set of files:

```text
MyDocument.refdoc
├── manifest.json
└── payload.zip.enc
```

### `manifest.json`

The manifest should be plain text JSON and should not contain sensitive content.

Suggested fields:

```json
{
  "formatVersion": 1,
  "documentType": "ReferenceFileDocument",
  "storageMode": "encryptedZip",
  "encryption": {
    "scheme": "zip-aes-256",
    "kdf": "library-default-or-documented-kdf",
    "payloadFilename": "payload.zip.enc"
  },
  "innerFormat": {
    "kind": "bundle",
    "rootFolder": "DocumentContents"
  }
}
```

### Encrypted payload

`payload.zip.enc` should contain the real internal document structure, for example:

```text
DocumentContents/
├── metadata.json
├── content/
│   ├── file1
│   └── file2
└── previews/
```

The app should decrypt this archive only after the user has entered the password.

## File format decision

There are two implementation options.

### Option A: Standard password-protected ZIP

Store the encrypted payload as a password-protected ZIP archive.

Benefits:

- simpler mental model
- easier to inspect during development
- supported by several existing libraries

Risks:

- some ZIP encryption modes are weak
- library compatibility varies
- you must ensure the chosen library supports strong encryption such as AES, not legacy ZipCrypto

### Option B: App-defined encrypted container using ZIP as the inner archive

Create a normal ZIP archive first, then encrypt the whole ZIP blob using a modern crypto API.

Benefits:

- clearer control over encryption design
- easier to standardise crypto choices across platforms
- avoids ambiguity around older ZIP encryption modes

Risks:

- more implementation work
- you must design the container format and metadata carefully

## Recommendation

Start with **Option A only if** the bundled archive library clearly supports strong AES-based ZIP encryption and reliable password-based decryption.

If that cannot be guaranteed, use **Option B**:

- ZIP the internal contents
- derive a key from the password
- encrypt the ZIP data as a single blob
- store that blob as the payload

This keeps the package model discussed earlier while giving stronger control over the security design.

## Library strategy

Bundle a trusted archive library with the application.

Requirements for the library:

- can create ZIP archives in-process
- can extract ZIP archives in-process
- supports password-protected archives
- preferably supports AES encryption
- is actively maintained
- works on the target Apple platforms

Do not rely on:

- `/usr/bin/zip`
- `/usr/bin/unzip`
- shell scripts
- external command execution

## User experience

### Creating a new encrypted document

Suggested flow:

1. User chooses **Save as Encrypted Document** or enables encryption in document settings.
2. App prompts for a password.
3. App asks the user to confirm the password.
4. App warns that losing the password means the content may be unrecoverable.
5. App saves the document in encrypted mode.

### Opening an encrypted document

Suggested flow:

1. App reads `manifest.json`.
2. App detects `storageMode: encryptedZip`.
3. App prompts for the password before loading document contents.
4. App decrypts the payload to a temporary working location.
5. App validates the internal structure.
6. App opens the document.

### Re-saving an encrypted document

Suggested flow:

- edits happen against a temporary working copy
- on save, the app rebuilds the archive and re-encrypts it
- temporary decrypted files are removed after successful save or on close

## Password handling rules

- Never store the password in the document.
- Never log the password.
- Keep password values in memory only as long as needed.
- Clear temporary buffers where practical.
- Do not silently downgrade to weaker encryption.
- Give a clear error if the password is wrong or the payload is corrupt.

## Temporary file handling

The biggest practical risk is leaving decrypted content behind on disk.

Rules:

- decrypt only into an app-controlled temporary directory
- mark temporary files clearly as ephemeral
- remove temporary files when the document closes
- remove temporary files if open fails midway
- clean up stale temporary files on app launch
- avoid long-lived cached decrypted copies unless there is a strong reason

## Backwards compatibility

The document reader should support:

- existing unencrypted documents
- newly encrypted documents

The app should:

- detect the mode from the manifest or top-level structure
- avoid breaking existing documents
- offer an upgrade path from plain to encrypted mode
- optionally offer a decrypt-and-save-as-plain operation

## Validation rules

Before opening a file, validate:

- outer package contains a manifest
- manifest version is supported
- manifest document type matches `ReferenceFileDocument`
- encryption scheme is recognised
- payload file exists
- decrypted archive expands into the expected root structure

If any validation fails, show a clear error and do not partially load the document.

## Suggested API changes

## Data model

Add a storage mode concept:

```swift
enum ReferenceFileStorageMode {
    case plain
    case encrypted
}
```

Add configuration for encrypted save operations:

```swift
struct ReferenceFileEncryptionOptions {
    let password: String
    let scheme: EncryptionScheme
}
```

```swift
enum EncryptionScheme {
    case zipAES256
    case customEncryptedArchive
}
```

## Document responsibilities

`ReferenceFileDocument` should be responsible for:

- detecting the document format
- reading the manifest
- coordinating decryption when needed
- loading the decrypted internal contents
- saving either plain or encrypted output

The crypto and archive logic should live in separate helper types or services.

## Suggested components

### `ReferenceFileDocumentManifest`

Responsible for:

- encoding and decoding manifest JSON
- format version checks
- storage mode detection

### `ReferenceFileArchiveService`

Responsible for:

- building the internal archive
- extracting archive contents
- validating internal folder structure

### `ReferenceFileEncryptionService`

Responsible for:

- encrypting archive data
- decrypting archive data
- mapping library errors into app errors

### `ReferenceFileTemporaryWorkspace`

Responsible for:

- creating temporary working directories
- cleaning them up
- tracking in-progress decrypted content

## Implementation phases

## Phase 1: Format design

- define the outer package structure
- define `manifest.json`
- define format versioning rules
- define the expected inner archive structure
- decide whether to use ZIP AES directly or a custom encrypted blob around a ZIP archive

### Deliverables

- format specification
- sample manifests
- example encrypted package layout

## Phase 2: Archive abstraction

- add an archive service abstraction
- integrate the chosen bundled library
- support create and extract operations in tests
- validate basic round-trip behaviour for the internal document contents

### Deliverables

- archive service protocol or concrete type
- unit tests for archive creation and extraction

## Phase 3: Encryption abstraction

- add an encryption service abstraction
- support password-based encrypt and decrypt
- return domain-specific errors for bad password, unsupported format, and corrupt payload

### Deliverables

- encryption service
- round-trip encryption tests
- error mapping tests

## Phase 4: Document read path

- detect encrypted documents from the manifest
- prompt for password through the app layer
- decrypt to a temporary workspace
- load the inner document model from decrypted contents
- clean up on failure

### Deliverables

- encrypted open flow
- wrong-password behaviour
- corrupt-payload behaviour

## Phase 5: Document save path

- add save support for encrypted mode
- rebuild the archive from current document state
- encrypt and write the payload
- write the manifest
- replace existing file safely

### Deliverables

- encrypted save flow
- overwrite-safe save logic
- save tests

## Phase 6: UX and recovery

- add password entry UI
- add password confirmation UI
- add mode switching between plain and encrypted
- add recovery messaging and warnings
- decide whether password changes are supported in v1

### Deliverables

- save/open UI updates
- human-readable error messages
- recovery guidance copy

## Error handling

Define clear user-facing errors for:

- wrong password
- unsupported encryption mode
- unsupported file version
- corrupt archive
- missing payload
- invalid manifest
- failed cleanup of temporary files

Avoid vague messages such as "open failed".

## Security considerations

### Strength of encryption

Do not use legacy ZIP encryption if a stronger AES mode is available.

### Password quality

Encourage strong passwords. At minimum:

- require a non-empty password
- warn on very short passwords
- consider a strength indicator

### Sensitive metadata

Do not place document secrets in the manifest.

### Memory exposure

Assume decrypted data may exist briefly in memory while editing. Reduce exposure where practical, but focus first on preventing unnecessary disk persistence.

### Tampering

Consider whether you need payload integrity checking in addition to encryption. If the chosen library or encryption approach does not provide clear tamper detection, add this to the design.

## Open questions

- Should encrypted mode be optional per document or mandatory for certain document types?
- Do we need a visible badge in the UI showing that the document is encrypted?
- Should the app remember the password for the current session only?
- Should password change be supported in the first release?
- Should autosave be enabled for encrypted documents, and if so, how will temporary decrypted state be handled?
- Do we need integrity verification separate from decryption?
- Is cross-platform compatibility required for the encrypted file format?

## Testing plan

## Unit tests

- manifest encode/decode
- archive round-trip
- encryption round-trip
- wrong password handling
- corrupt payload handling
- unsupported version handling

## Integration tests

- create plain document, convert to encrypted, reopen successfully
- create encrypted document, edit, save, reopen successfully
- open encrypted document with wrong password
- open malformed encrypted package
- interrupted save does not destroy the existing valid file

## Manual tests

- send encrypted document to another macOS user and confirm it opens with the password
- confirm the extracted package contents remain unreadable without decryption
- confirm temporary decrypted files are removed after close
- confirm file association and document open flows still work in Finder

## Rollout plan

1. Ship behind a development flag.
2. Test with sample documents of different sizes.
3. Review failure cases and recovery messages.
4. Enable for internal users.
5. Promote to general availability once the format is stable.

## Suggested acceptance criteria

- A user can save a `ReferenceFileDocument` in encrypted mode.
- The saved document contains manifest metadata plus an encrypted payload.
- Opening the document requires a password.
- A wrong password does not reveal any content.
- The decrypted contents are only stored in a temporary workspace.
- Closing the document removes temporary decrypted files.
- Existing plain documents still open normally.
- The implementation does not rely on external shell tools.

## Summary

The cleanest approach is to treat encrypted `ReferenceFileDocument` files as a wrapper package:

- a small clear-text manifest
- one encrypted payload archive
- app-controlled decryption into a temporary workspace
- bundled archive support inside the application

This keeps the format understandable, supports password-based protection without distributing private keys, and gives a realistic path to adding encryption without replacing the whole document model.

