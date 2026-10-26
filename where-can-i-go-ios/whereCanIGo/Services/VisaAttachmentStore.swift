import Foundation
import OSLog

struct VisaAttachmentStore {
    private static var rootURL: URL {
        URL.documentsDirectory.appendingPathComponent("visa_attachments", isDirectory: true)
    }

    private static let logger = Logger(subsystem: "com.marcocheung.whereCanIGo", category: "AttachmentRestore")

    static func folderURL(for visaID: UUID) -> URL {
        rootURL.appendingPathComponent(visaID.uuidString, isDirectory: true)
    }

    static func fileURL(fileName: String, visaID: UUID) -> URL {
        folderURL(for: visaID).appendingPathComponent(fileName)
    }

    static func save(data: Data, fileExtension ext: String, for visaID: UUID) throws -> String {
        let folder = folderURL(for: visaID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString).\(ext.lowercased())"
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        return name
    }

    static func delete(fileName: String, for visaID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(fileName: fileName, visaID: visaID))
    }

    static func deleteFolder(for visaID: UUID) {
        try? FileManager.default.removeItem(at: folderURL(for: visaID))
    }

    static func exportAttachmentFiles(for visa: PersonalVisa) throws -> [BackupFile] {
        var files: [BackupFile] = []
        for fileName in visa.attachmentFileNames {
            try validateFileName(fileName)
            do {
                let data = try Data(contentsOf: fileURL(fileName: fileName, visaID: visa.id))
                files.append(BackupFile(fileName: fileName, data: data))
            } catch CocoaError.fileReadNoSuchFile {
                continue
            }
        }
        return files
    }

    static func makeRestoreWorkspace() throws -> (staging: URL, backup: URL) {
        let workspace = rootURL
            .appendingPathComponent(".restore-tmp", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staging = workspace.appendingPathComponent("staging", isDirectory: true)
        let backup = workspace.appendingPathComponent("backup", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
            return (staging, backup)
        } catch {
            cleanup(workspace)
            throw error
        }
    }

    static func stage(_ media: [BackupMedia], for visaID: UUID, in stagingRoot: URL) throws {
        let folder = stagingRoot.appendingPathComponent(visaID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var fileNames: Set<String> = []
        for file in media {
            try file.validateIntegrity()
            guard file.isSupported(for: .attachment) else {
                throw RestoreError.unsupportedMedia
            }
            try validateFileName(file.fileName)
            guard fileNames.insert(file.fileName).inserted else {
                throw RestoreError.duplicateFileName
            }
            try file.data.write(to: folder.appendingPathComponent(file.fileName), options: .atomic)
        }
    }

    static func commitStaged(from stagingRoot: URL, visaIDs: Set<UUID>, backupRoot: URL) throws {
        let manager = FileManager.default
        let orderedIDs = visaIDs.sorted { $0.uuidString < $1.uuidString }
        for id in orderedIDs {
            var isDirectory: ObjCBool = false
            let staged = stagingRoot.appendingPathComponent(id.uuidString, isDirectory: true)
            guard manager.fileExists(atPath: staged.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  !manager.fileExists(atPath: backupRoot.appendingPathComponent(id.uuidString).path) else {
                throw RestoreError.invalidWorkspace
            }
        }

        var processed: Set<UUID> = []
        do {
            for id in orderedIDs {
                let destination = folderURL(for: id)
                if manager.fileExists(atPath: destination.path) {
                    try manager.moveItem(at: destination, to: backupRoot.appendingPathComponent(id.uuidString))
                }
                // Only roll back an ID after its original folder has been safely moved.
                processed.insert(id)
                try manager.moveItem(
                    at: stagingRoot.appendingPathComponent(id.uuidString),
                    to: destination
                )
            }
        } catch {
            let originalError = error
            do {
                try rollbackCommitted(visaIDs: processed, backupRoot: backupRoot)
            } catch {
                throw CommitRecoveryError(
                    originalError: originalError,
                    rollbackError: error,
                    recoveryDirectory: backupRoot.deletingLastPathComponent()
                )
            }
            throw originalError
        }
    }

    static func rollbackCommitted(visaIDs: Set<UUID>, backupRoot: URL) throws {
        let manager = FileManager.default
        var failures: [String] = []
        for id in visaIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            do {
                let destination = folderURL(for: id)
                if manager.fileExists(atPath: destination.path) {
                    try manager.removeItem(at: destination)
                }
                let original = backupRoot.appendingPathComponent(id.uuidString)
                if manager.fileExists(atPath: original.path) {
                    try manager.moveItem(at: original, to: destination)
                }
            } catch {
                failures.append("\(id.uuidString): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            throw RollbackError(details: failures.joined(separator: "\n"))
        }
    }

    static func cleanup(_ url: URL) {
        let workspace = ["staging", "backup"].contains(url.lastPathComponent)
            ? url.deletingLastPathComponent() : url
        let restoreRoot = rootURL.appendingPathComponent(".restore-tmp", isDirectory: true)
        guard UUID(uuidString: workspace.lastPathComponent) != nil,
              workspace.deletingLastPathComponent().standardizedFileURL == restoreRoot.standardizedFileURL else {
            logger.error("Refusing to clean an invalid attachment restore workspace.")
            return
        }
        do {
            try FileManager.default.removeItem(at: workspace)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            logger.error("Unable to clean attachment restore workspace: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func validateFileName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"), !name.contains("\0") else {
            throw RestoreError.invalidFileName
        }
    }

    private enum RestoreError: LocalizedError {
        case invalidFileName, duplicateFileName, unsupportedMedia, invalidWorkspace

        var errorDescription: String? {
            switch self {
            case .invalidFileName:
                String(localized: "The backup contains an invalid attachment file name.")
            case .duplicateFileName:
                String(localized: "The backup contains duplicate attachment file names.")
            case .unsupportedMedia:
                String(localized: "The backup contains an unsupported attachment.")
            case .invalidWorkspace:
                String(localized: "The attachment restore workspace is incomplete or already in use.")
            }
        }
    }

    private struct RollbackError: LocalizedError {
        let details: String

        var errorDescription: String? {
            String(localized: "Some attachments could not be restored.") + "\n" + details
        }
    }

    struct CommitRecoveryError: LocalizedError {
        let originalError: Error
        let rollbackError: Error
        let recoveryDirectory: URL

        var errorDescription: String? {
            [
                String(localized: "Restore failed and rollback could not be completed. Recovery files have been retained at:"),
                recoveryDirectory.path,
                originalError.localizedDescription,
                rollbackError.localizedDescription
            ].joined(separator: "\n")
        }
    }
}
