import Foundation
import Combine
import CryptoKit

@MainActor
final class UserDataTransferService: ObservableObject {
    nonisolated struct ExportOptions: Sendable {
        var includeProfilePhoto = false
        var includeVisaAttachments = false
        var includeSharingIdentity = false
        var includeFriends = false
    }

    private let appState: AppState
    private let profileStore: UserProfileStore
    private let friendStore: FriendStore

    init(appState: AppState, profileStore: UserProfileStore, friendStore: FriendStore) {
        self.appState = appState
        self.profileStore = profileStore
        self.friendStore = friendStore
    }

    var friendCount: Int { friendStore.friends.count }

    func makeBackup(options: ExportOptions = ExportOptions()) throws -> UserDataExportResult {
        guard !profileStore.loadFailed else {
            throw TransferError.profileUnavailable
        }
        let data = appState.exportSnapshot()
        let bundledDefaults = appState.bundledDefaultVisas(for: data.passportCode)
        let attachmentLoader: ((PersonalVisa) throws -> [BackupFile])? = options.includeVisaAttachments
            ? { try VisaAttachmentStore.exportAttachmentFiles(for: $0) } : nil
        let photo = options.includeProfilePhoto ? try profileStore.exportPhotoFile() : nil
        var identity: SharingIdentityRecord?
        if options.includeSharingIdentity, let key = try SharingIdentity.currentKey() {
            identity = SharingIdentityRecord(privateKey: key.rawRepresentation,
                                             lastRevision: try SharingIdentity.lastRevision())
        }
        if options.includeFriends, friendStore.loadError != nil {
            throw TransferError.friendsUnavailable
        }
        return try UserDataBackup.make(
            from: data,
            displayName: profileStore.exportDisplayName,
            profilePhoto: photo,
            attachmentLoader: attachmentLoader,
            bundledDefaults: bundledDefaults,
            sharingIdentity: identity,
            friends: options.includeFriends ? friendStore.snapshot() : nil
        )
    }

    func readBackup(from url: URL) async throws -> UserDataBackup {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }
        try Task.checkCancellation()
        let limit = UserDataBackup.maxFileByteCount
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size >= 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard size <= limit else {
            throw UserDataBackupError.fileTooLarge
        }
        let reader = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= limit else {
                throw UserDataBackupError.fileTooLarge
            }
            try Task.checkCancellation()
            let backup = try UserDataBackup.decodeVerifyingMedia(from: data)
            try Task.checkCancellation()
            return backup
        }
        let backup = try await withTaskCancellationHandler {
            try await reader.value
        } onCancel: {
            reader.cancel()
        }
        try Task.checkCancellation()
        try backup.validate(checkMediaChecksums: false)
        return backup
    }

    func preview(_ backup: UserDataBackup, mode: UserDataImportMode) throws -> UserDataRestoreSummary {
        try backup.makeImportPlan(
            mode: mode,
            local: appState.exportSnapshot(),
            bundledDefaults: appState.bundledDefaultVisas(for:)
        ).summary
    }

    func importBackup(_ backup: UserDataBackup, mode: UserDataImportMode) async throws -> UserDataRestoreSummary {
        try Task.checkCancellation()
        guard !profileStore.loadFailed else {
            throw TransferError.profileUnavailable
        }
        if backup.friends != nil, friendStore.loadError != nil {
            throw TransferError.friendsUnavailable
        }
        try appState.beginRestore()
        defer { appState.endRestore() }

        let oldData = appState.exportSnapshot()
        let oldProfile = profileStore.snapshot()
        let oldFriends = friendStore.snapshot()
        let plan = try backup.makeImportPlan(
            mode: mode,
            local: oldData,
            bundledDefaults: appState.bundledDefaultVisas(for:)
        )
        let workspace = try VisaAttachmentStore.makeRestoreWorkspace()
        var shouldCleanupWorkspace = true
        defer {
            if shouldCleanupWorkspace { VisaAttachmentStore.cleanup(workspace.staging) }
        }

        // Keep durable originals as well as attachment folders if rollback itself fails.
        try DataStore(directory: workspace.backup).saveAppData(oldData)
        try JSONEncoder().encode(oldProfile).write(
            to: workspace.backup.appendingPathComponent("user_profile.json"),
            options: [.atomic, .completeFileProtection]
        )
        let stagedIDs = Set(plan.attachmentsToStage.keys)
        for (id, media) in plan.attachmentsToStage.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            try VisaAttachmentStore.stage(media, for: id, in: workspace.staging)
        }
        try Task.checkCancellation()
        let removedIDs = try appState.commitRestoredData(plan.data)
        do {
            try VisaAttachmentStore.commitStaged(
                from: workspace.staging,
                visaIDs: stagedIDs,
                backupRoot: workspace.backup
            )
        } catch {
            let originalError = error
            shouldCleanupWorkspace = !(originalError is VisaAttachmentStore.CommitRecoveryError)
            do {
                _ = try appState.commitRestoredData(oldData)
            } catch {
                shouldCleanupWorkspace = false
                throw RecoveryError(
                    originalError: originalError,
                    rollbackErrors: [error],
                    recoveryDirectory: workspace.backup.deletingLastPathComponent()
                )
            }
            throw originalError
        }

        let profileUpdated: Bool
        var friendsRestored = 0
        var identityResult = IdentityRestore.none
        do {
            profileUpdated = try profileStore.restore(plan.profile, mode: mode)
            if let friends = plan.friends {
                switch mode {
                case .replace:
                    try friendStore.replaceAll(with: friends)
                    friendsRestored = friends.count
                case .merge:
                    friendsRestored = try friendStore.merge(friends)
                }
            }
            // Last step: a Keychain write has no rollback here.
            if let identity = plan.sharingIdentity {
                identityResult = try restoreIdentity(identity, mode: mode)
            }
        } catch {
            let originalError = error
            var rollbackErrors: [Error] = []
            do {
                _ = try appState.commitRestoredData(oldData)
            } catch {
                rollbackErrors.append(error)
            }
            do {
                try VisaAttachmentStore.rollbackCommitted(visaIDs: stagedIDs, backupRoot: workspace.backup)
            } catch {
                rollbackErrors.append(error)
            }
            do {
                try profileStore.restoreSnapshot(oldProfile)
            } catch {
                rollbackErrors.append(error)
            }
            if friendStore.snapshot() != oldFriends {
                do {
                    try friendStore.replaceAll(with: oldFriends)
                } catch {
                    rollbackErrors.append(error)
                }
            }
            if !rollbackErrors.isEmpty {
                shouldCleanupWorkspace = false
                throw RecoveryError(
                    originalError: originalError,
                    rollbackErrors: rollbackErrors,
                    recoveryDirectory: workspace.backup.deletingLastPathComponent()
                )
            }
            throw originalError
        }

        for id in removedIDs {
            VisaAttachmentStore.deleteFolder(for: id)
        }
        VisaAttachmentStore.cleanup(workspace.staging)
        shouldCleanupWorkspace = false
        var summary = plan.summary
        summary.profileUpdated = profileUpdated
        summary.friendsRestored = friendsRestored
        summary.sharingIdentityRestored = identityResult == .installed
        summary.sharingIdentityKept = identityResult == .kept
        appState.publishRestoreSummary(summary)
        return summary
    }

    private enum IdentityRestore { case none, installed, kept }

    /// Replace installs the file's key. Merge installs it only when this device
    /// has no key yet, or already has the same key.
    private func restoreIdentity(_ record: SharingIdentityRecord, mode: UserDataImportMode) throws -> IdentityRestore {
        let current = try SharingIdentity.currentKey()?.rawRepresentation
        if mode == .merge, let current, current != record.privateKey {
            return .kept
        }
        try SharingIdentity.install(privateKey: record.privateKey, lastRevision: record.lastRevision)
        return current == record.privateKey ? .none : .installed
    }

    private enum TransferError: LocalizedError {
        case profileUnavailable
        case friendsUnavailable

        var errorDescription: String? {
            switch self {
            case .profileUnavailable:
                String(localized: "Your profile could not be loaded. Retry loading it before transferring data.")
            case .friendsUnavailable:
                String(localized: "Your friends could not be loaded. Retry loading them in Travels before transferring data.")
            }
        }
    }

    private struct RecoveryError: LocalizedError {
        let originalError: Error
        let rollbackErrors: [Error]
        let recoveryDirectory: URL

        var errorDescription: String? {
            ([
                String(localized: "Restore failed and rollback could not be completed. Recovery files have been retained at:"),
                recoveryDirectory.path,
                originalError.localizedDescription
            ] + rollbackErrors.map(\.localizedDescription)).joined(separator: "\n")
        }
    }
}
