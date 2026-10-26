import SwiftUI
import UniformTypeIdentifiers

struct UserDataBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let backup: UserDataBackup

    init(backup: UserDataBackup) {
        self.backup = backup
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        backup = try UserDataBackup.decodeVerifyingMedia(from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try backup.encodedData())
    }

    static func defaultFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return "WhereCanIGo-Backup-\(formatter.string(from: date))"
    }
}
