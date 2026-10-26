//
//  UserDataRestore.swift
//  whereCanIGo
//
//  Created by Marco on 26/10/2026.
//

import Foundation

/// How an imported backup is applied to local data.
enum UserDataImportMode: String, Codable, CaseIterable, Identifiable {
    /// Overwrite this device's data with the file.
    case replace
    /// Keep this device's data; only add records whose IDs don't exist yet.
    case merge

    var id: String { rawValue }
}

/// Result of an import. For `.replace`, "added" means "imported".
struct UserDataRestoreSummary: Equatable {
    var mode: UserDataImportMode
    var personalVisasAdded: Int = 0
    var personalVisasSkipped: Int = 0
    var visitsAdded: Int = 0
    var visitsSkipped: Int = 0
    var wishlistAdded: Int = 0
    var wishlistSkipped: Int = 0
    /// Wishlist items removed because the same ID already exists as a Visit.
    var wishlistResolvedAsVisited: Int = 0
    var attachmentsRestored: Int = 0
    /// Attachments / profile photo skipped because this app version doesn't support their type or size.
    var mediaSkipped: Int = 0
    var passportChanged: Bool = false
    /// Custom entry-policy edits (overrides + removals) applied.
    var entryPolicyEdits: Int = 0
    /// Entry-policy overrides skipped because their category is unknown to this app version.
    var entryPoliciesSkipped: Int = 0
    var profileUpdated: Bool = false
    var restoredAt: Date = Date()
}

enum UserDataRestoreError: LocalizedError {
    case restoreInProgress
    case invalidPassportCode(String)
    case persistenceFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .restoreInProgress:
            return String(localized: "restore.error.inProgress")
        case .invalidPassportCode(let code):
            return String(localized: "restore.error.invalidPassport \(code)")
        case .persistenceFailed:
            return String(localized: "restore.error.saveFailed")
        }
    }
}

extension Notification.Name {
    /// Posted on the main actor after a restore fully succeeds.
    /// userInfo["summary"] contains the UserDataRestoreSummary.
    static let userDataDidRestore = Notification.Name("UserDataDidRestore")
}
