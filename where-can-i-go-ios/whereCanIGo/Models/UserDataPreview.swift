//
//  UserDataPreview.swift
//  whereCanIGo
//
//  Created by Marco on 26/10/2026.
//

import Foundation

// MARK: - Display-only mappings for UI (no business logic)

/// Read-only info about a backup file, for the import preview screen.
struct UserDataBackupPreviewDetails: Equatable {
    var exportedAt: Date
    var appVersion: String          // "" when unknown
    var passportCode: String        // "" when not included
    var personalVisaCount: Int
    var visitCount: Int
    var wishlistCount: Int
    var includesProfilePhoto: Bool
    var includesVisaAttachments: Bool
    /// nil = the file has no friends section.
    var friendCount: Int?
    var includesSharingIdentity: Bool
}

extension UserDataBackup {
    var previewDetails: UserDataBackupPreviewDetails {
        UserDataBackupPreviewDetails(
            exportedAt: exportedAt,
            appVersion: app?.version ?? "",
            passportCode: passport?.code ?? "",
            personalVisaCount: personalVisas.count,
            visitCount: visits.count,
            wishlistCount: wishlist.count,
            includesProfilePhoto: profile?.photo != nil,
            // true if the file carries the attachments section for any visa (even if empty)
            includesVisaAttachments: personalVisas.contains { $0.attachments != nil },
            friendCount: friends?.count,
            includesSharingIdentity: sharingIdentity != nil
        )
    }
}

/// Added / skipped counts for the import preview and result screens.
/// For `.replace`, "added" means "imported" and "skipped" is always 0.
struct UserDataRestorePreviewCounts: Equatable {
    var personalVisasAdded: Int
    var personalVisasSkipped: Int
    var visitsAdded: Int
    var visitsSkipped: Int
    var wishlistAdded: Int
    var wishlistSkipped: Int
}

extension UserDataRestoreSummary {
    var previewCounts: UserDataRestorePreviewCounts {
        UserDataRestorePreviewCounts(
            personalVisasAdded: personalVisasAdded,
            personalVisasSkipped: personalVisasSkipped,
            visitsAdded: visitsAdded,
            visitsSkipped: visitsSkipped,
            wishlistAdded: wishlistAdded,
            wishlistSkipped: wishlistSkipped
        )
    }
}
