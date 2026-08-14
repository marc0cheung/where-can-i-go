import Foundation
import UIKit

struct VisaAttachmentStore {
    static func folderURL(for visaID: UUID) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("visa_attachments/\(visaID.uuidString)", isDirectory: true)
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
}
