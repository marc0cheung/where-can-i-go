import Foundation
import Combine
import ImageIO
import UIKit
import UniformTypeIdentifiers

struct UserProfile: Codable {
    var name = ""
    var photoData: Data?
    /// Uncropped photo and crop position, kept locally so the avatar can be re-cropped.
    var photoSourceData: Data?
    var photoCrop: ProfilePhotoCrop?

    var displayName: String {
        name.isEmpty ? String(localized: "Your Profile") : name
    }
}

struct ProfilePhotoCrop: Codable, Equatable {
    var zoom: Double
    var offsetX: Double
    var offsetY: Double
}

@MainActor
final class UserProfileStore: ObservableObject {
    @Published private(set) var profile = UserProfile()
    @Published private(set) var loadFailed = false
    @Published var loadError: String?

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.documentsDirectory.appendingPathComponent("user_profile.json")
        load()
    }

    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            var savedProfile = try JSONDecoder().decode(UserProfile.self, from: data)
            if let photoData = savedProfile.photoData, UIImage(data: photoData) == nil {
                throw ProfilePhotoError.invalidImage
            }
            if savedProfile.photoData == nil
                || savedProfile.photoSourceData.flatMap(UIImage.init(data:)) == nil {
                savedProfile.photoSourceData = nil
                savedProfile.photoCrop = nil
            }
            profile = savedProfile
            loadFailed = false
            loadError = nil
        } catch CocoaError.fileReadNoSuchFile {
            profile = UserProfile()
            loadFailed = false
            loadError = nil
        } catch {
            loadFailed = true
            loadError = error.localizedDescription
        }
    }

    func save(_ draft: UserProfile) throws {
        var savedProfile = draft
        savedProfile.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        try persist(savedProfile)
    }

    private func persist(_ savedProfile: UserProfile) throws {
        let data = try JSONEncoder().encode(savedProfile)
        try data.write(to: fileURL, options: .atomic)
        profile = savedProfile
        loadFailed = false
        loadError = nil
    }

    var exportDisplayName: String? {
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    func exportPhotoFile() throws -> BackupFile? {
        guard let data = profile.photoData else { return nil }
        guard let ext = Self.photoExtension(for: data) else {
            throw ProfilePhotoError.invalidImage
        }
        return BackupFile(fileName: "avatar.\(ext)", data: data)
    }

    struct ProfileSnapshot: Codable {
        let name: String
        let photoData: Data?
        let photoFileExtension: String?
        var photoSourceData: Data?
        var photoCrop: ProfilePhotoCrop?
    }

    func snapshot() -> ProfileSnapshot {
        ProfileSnapshot(
            name: profile.name,
            photoData: profile.photoData,
            photoFileExtension: profile.photoData.flatMap { Self.photoExtension(for: $0) },
            photoSourceData: profile.photoSourceData,
            photoCrop: profile.photoCrop
        )
    }

    func restoreSnapshot(_ snapshot: ProfileSnapshot) throws {
        try persist(UserProfile(
            name: snapshot.name,
            photoData: snapshot.photoData,
            photoSourceData: snapshot.photoSourceData,
            photoCrop: snapshot.photoCrop))
    }

    func restore(_ importedProfile: UserDataBackup.Profile?, mode: UserDataImportMode) throws -> Bool {
        guard let importedProfile else { return false }
        var updated = profile
        switch mode {
        case .replace:
            updated.name = importedProfile.displayName ?? ""
        case .merge:
            if exportDisplayName == nil {
                updated.name = importedProfile.displayName ?? ""
            }
        }
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldRestorePhoto: Bool
        switch mode {
        case .replace: shouldRestorePhoto = true
        case .merge: shouldRestorePhoto = profile.photoData == nil
        }
        if shouldRestorePhoto, let photo = importedProfile.photo {
            try photo.validateIntegrity()
            guard photo.isSupported(for: .profilePhoto),
                  UIImage(data: photo.data) != nil else {
                throw ProfilePhotoError.invalidImage
            }
            updated.photoData = photo.data
            updated.photoSourceData = nil
            updated.photoCrop = nil
        }
        guard updated.name != profile.name || updated.photoData != profile.photoData else {
            return false
        }
        try persist(updated)
        return true
    }

    private nonisolated static func photoExtension(for data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else {
            return nil
        }
        return UTType(type as String)?.preferredFilenameExtension
    }

    nonisolated static func preparePhoto(_ data: Data, maximumPixelSize: Int = 512) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
              ] as CFDictionary),
              let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85) else {
            throw ProfilePhotoError.invalidImage
        }
        return jpeg
    }
}

enum ProfilePhotoError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        String(localized: "The selected photo could not be opened. Please choose another photo.")
    }
}
