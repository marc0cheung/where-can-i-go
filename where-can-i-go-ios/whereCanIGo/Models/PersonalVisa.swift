import Foundation

struct PersonalVisa: Codable, Identifiable, Hashable {
    let id: UUID
    let countryCode: String   // ISO3
    let visaType: String
    let duration: String
    let expiryDate: Date
    let notes: String?
    let attachmentFileNames: [String]

    init(id: UUID = UUID(),
         countryCode: String,
         visaType: String,
         duration: String,
         expiryDate: Date,
         notes: String? = nil,
         attachmentFileNames: [String] = []) {
        self.id = id
        self.countryCode = countryCode
        self.visaType = visaType
        self.duration = duration
        self.expiryDate = expiryDate
        self.notes = notes
        self.attachmentFileNames = attachmentFileNames
    }
}
