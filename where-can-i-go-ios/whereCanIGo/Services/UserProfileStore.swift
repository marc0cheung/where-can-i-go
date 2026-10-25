import Foundation
import Combine
import ImageIO
import UIKit

struct UserProfile: Codable {
    var name = ""
    var photoData: Data?

    var displayName: String {
        name.isEmpty ? String(localized: "Your Profile") : name
    }
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
            let savedProfile = try JSONDecoder().decode(UserProfile.self, from: data)
            if let photoData = savedProfile.photoData, UIImage(data: photoData) == nil {
                throw ProfilePhotoError.invalidImage
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
        let data = try JSONEncoder().encode(savedProfile)
        try data.write(to: fileURL, options: .atomic)
        profile = savedProfile
    }

    nonisolated static func preparePhoto(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512
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
